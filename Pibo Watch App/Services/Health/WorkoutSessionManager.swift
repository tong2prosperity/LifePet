import Foundation
import HealthKit

enum WorkoutSessionError: Error {
    case healthDataUnavailable
    case workoutSharingDenied
}

@MainActor
final class WorkoutSessionManager: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    let stream: VitalsStream
    private(set) var current: VitalSession?

    init(stream: VitalsStream = VitalsStream()) {
        self.stream = stream
        super.init()
    }

    private static let readTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.oxygenSaturation),
        // Beat-to-beat series → post-session authoritative RMSSD (CRC trainer).
        HKSeriesType.heartbeat(),
    ]
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKCategoryType(.mindfulSession),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutSessionError.healthDataUnavailable
        }
        try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)

        if healthStore.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized {
            throw WorkoutSessionError.workoutSharingDenied
        }
    }

    func start() async throws -> VitalSession {
        try await requestAuthorization()

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        builder.delegate = stream
        session.delegate = self

        self.session = session
        self.builder = builder

        let startDate = Date()
        do {
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
        } catch {
            session.end()
            try? await builder.endCollection(at: Date())
            self.session = nil
            self.builder = nil
            current = nil
            throw error
        }

        let vs = VitalSession(startedAt: startDate)
        current = vs
        return vs
    }

    func stop() async throws -> VitalSession? {
        guard let session, let builder, var vs = current else { return nil }
        session.end()
        try await builder.endCollection(at: Date())
        _ = try await builder.finishWorkout()

        vs.endedAt = Date()
        current = vs
        self.session = nil
        self.builder = nil
        return vs
    }

    func cancel() async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: Date())
        current = nil
        self.session = nil
        self.builder = nil
    }

    /// Authoritative RMSSD (ms) over the session window, from the real
    /// heartbeat series the watch recorded — the post-session companion to the
    /// live RSA estimate. `nil` when no usable series was captured.
    func sessionRMSSD(start: Date, end: Date) async -> Double? {
        await CRCHeartbeatSeriesReader.sessionRMSSD(store: healthStore, start: start, end: end)
    }

    /// Best-effort log of the completed breathing session as Apple Health mindful minutes.
    /// Silently no-ops if the user didn't grant mindful-session sharing.
    func saveMindfulSession(start: Date, end: Date) async {
        guard end > start else { return }
        let type = HKCategoryType(.mindfulSession)
        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )
        try? await healthStore.save(sample)
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("[Pibo watch] workout state: \(fromState.rawValue) -> \(toState.rawValue)")
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[Pibo watch] workout error: \(error)")
    }
}
