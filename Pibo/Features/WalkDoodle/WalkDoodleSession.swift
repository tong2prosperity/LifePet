import Foundation
import CoreLocation
import MapKit
import Observation
import os
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives one walk-doodle recording: owns a `CLLocationManager`, accepts GPS
/// fixes (accuracy- + jitter-filtered), keeps the live stroke + metrics the
/// `WalkDoodleView` map reads, and (when permitted) keeps recording while
/// backgrounded plus mirrors progress to a Live Activity. `@Observable @MainActor`,
/// the same shape as `HealthDataService` — an observable store wrapping a system
/// manager, with the `CLLocationManagerDelegate` split into a standalone shim.
@MainActor
@Observable
final class WalkDoodleSession {

    enum Phase: Equatable { case idle, recording, finished }

    private(set) var phase: Phase = .idle
    private(set) var authStatus: CLAuthorizationStatus
    /// Accepted points, in capture order — bound straight to the map's `MapPolyline`.
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private(set) var distanceMeters: Double = 0
    private(set) var areaSquareMeters: Double = 0
    private(set) var elapsed: TimeInterval = 0
    /// Raised when the Live Activity 结束 button fires — the intent writes a
    /// cross-process flag that the ticker polls. `WalkDoodleView` observes this and
    /// finalizes the doodle (shows the preview on next foreground).
    private(set) var stopRequested = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let delegate = WalkLocationDelegate()
    @ObservationIgnored private var rawLocations: [CLLocation] = []
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Drop fixes worse than this (m) — keeps GPS scatter out of the stroke.
    private static let accuracyCeiling: CLLocationAccuracy = 30
    /// Ignore points closer than this (m) to the last accepted one — thins jitter
    /// so a stationary user doesn't inflate distance / crinkle the line.
    private static let minPointSpacing: CLLocationDistance = 3

    /// `allowsBackgroundLocationUpdates = true` throws unless the app declares the
    /// `location` background mode — gate on the actual Info.plist so a missing key
    /// degrades to foreground-only instead of crashing.
    private static var backgroundModeEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?
            .contains("location") ?? false
    }

    init() {
        authStatus = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = Self.minPointSpacing
        // Don't let iOS auto-pause mid-walk; show the blue pill when we keep
        // recording in the background.
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        delegate.onAuth = { [weak self] status in self?.authStatus = status }
        delegate.onLocations = { [weak self] locs in self?.ingest(locs) }
        manager.delegate = delegate
    }

    // MARK: Authorization

    var isAuthorized: Bool {
        authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authStatus == .denied || authStatus == .restricted
    }

    func requestAuthorization() {
        guard authStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    // MARK: Recording

    func start() {
        guard phase != .recording else { return }
        if authStatus == .notDetermined { requestAuthorization() }
        rawLocations.removeAll(keepingCapacity: true)
        coordinates.removeAll(keepingCapacity: true)
        distanceMeters = 0
        areaSquareMeters = 0
        elapsed = 0
        stopRequested = false
        let started = Date()
        startedAt = started
        phase = .recording
        // Keep recording while backgrounded / locked. When-in-use auth + the blue
        // status indicator is enough — no Always authorization required.
        if Self.backgroundModeEnabled { manager.allowsBackgroundLocationUpdates = true }
        manager.startUpdatingLocation()
        clearStopSignal()
        startLiveActivity(startedAt: started)
        startTicking()
        LPLog.app.notice("walk-doodle recording started (bg=\(Self.backgroundModeEnabled, privacy: .public))")
    }

    /// Stop recording and hand back the traced doodle.
    @discardableResult
    func finish() -> WalkDoodleResult {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        phase = .finished
        endLiveActivity()
        let result = WalkDoodleResult(
            coordinates: rawLocations.map(DoodleCoordinate.init),
            distanceMeters: distanceMeters,
            areaSquareMeters: areaSquareMeters,
            duration: elapsed,
            title: nil)
        LPLog.app.notice("walk-doodle finished: \(self.coordinates.count, privacy: .public) pts, \(Int(self.distanceMeters), privacy: .public)m, \(Int(self.areaSquareMeters), privacy: .public)m²")
        return result
    }

    /// Throw the recording away and return to idle (重走 / discard).
    func reset() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        endLiveActivity()
        rawLocations.removeAll(keepingCapacity: true)
        coordinates.removeAll(keepingCapacity: true)
        distanceMeters = 0
        areaSquareMeters = 0
        elapsed = 0
        startedAt = nil
        stopRequested = false
        phase = .idle
    }

    /// A region framing the current stroke (for the finish camera fit).
    var strokeRegion: MKCoordinateRegion? {
        DoodleGeometry.boundingRegion(coordinates)
    }

    // MARK: Ingest

    private func ingest(_ locations: [CLLocation]) {
        guard phase == .recording else { return }
        for loc in locations {
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= Self.accuracyCeiling else { continue }
            if let last = rawLocations.last {
                let step = loc.distance(from: last)
                guard step >= Self.minPointSpacing else { continue }
                distanceMeters += step
            }
            rawLocations.append(loc)
            coordinates.append(loc.coordinate)
        }
        areaSquareMeters = DoodleGeometry.enclosedArea(coordinates)
    }

    private func startTicking() {
        ticker = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .recording, let started = self.startedAt else { continue }
                self.elapsed = Date().timeIntervalSince(started)
                tick += 1
                // The Live Activity 结束 button raises a cross-process flag — poll it.
                if self.isStopSignalRaised(since: started) {
                    self.stopRequested = true
                    return
                }
                // Throttle LA pushes (~every 5s); the timer field counts client-side.
                if tick % 5 == 0 { self.updateLiveActivity(startedAt: started) }
            }
        }
    }

    // MARK: Live Activity + cross-process stop signal

    #if canImport(ActivityKit)
    private func startLiveActivity(startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for activity in Activity<WalkDoodleActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let state = WalkDoodleActivityAttributes.ContentState(
            distanceMeters: 0, areaSquareMeters: 0, startedAt: startedAt, pointCount: 0)
        do {
            _ = try Activity.request(
                attributes: WalkDoodleActivityAttributes(petName: "Pibo"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
        } catch {
            LPLog.app.error("walk-doodle LA start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateLiveActivity(startedAt: Date) {
        let state = WalkDoodleActivityAttributes.ContentState(
            distanceMeters: distanceMeters, areaSquareMeters: areaSquareMeters,
            startedAt: startedAt, pointCount: coordinates.count)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<WalkDoodleActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    private func endLiveActivity() {
        for activity in Activity<WalkDoodleActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func clearStopSignal() { WalkDoodleStopSignal.clear() }

    private func isStopSignalRaised(since baseline: Date) -> Bool {
        WalkDoodleStopSignal.isStopRequested(since: baseline)
    }
    #else
    private func startLiveActivity(startedAt: Date) {}
    private func updateLiveActivity(startedAt: Date) {}
    private func endLiveActivity() {}
    private func clearStopSignal() {}
    private func isStopSignalRaised(since baseline: Date) -> Bool { false }
    #endif
}

/// Forwards `CLLocationManager` callbacks (delivered on the main run loop) into the
/// `@MainActor` session. Standalone (not the `@Observable` session itself) so the
/// NSObject + delegate-protocol conformance never tangles with the Observation
/// macro or the default `MainActor` isolation. Callbacks hop to the main actor via
/// `Task { @MainActor in }`.
private final class WalkLocationDelegate: NSObject, CLLocationManagerDelegate {
    nonisolated(unsafe) var onLocations: (@MainActor ([CLLocation]) -> Void)?
    nonisolated(unsafe) var onAuth: (@MainActor (CLAuthorizationStatus) -> Void)?

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let callback = onLocations
        Task { @MainActor in callback?(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let callback = onAuth
        Task { @MainActor in callback?(status) }
    }
}
