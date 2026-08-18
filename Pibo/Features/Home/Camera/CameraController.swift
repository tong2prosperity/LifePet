@preconcurrency import AVFoundation
import Observation
import UIKit
import os

/// Thin `AVCaptureSession` wrapper. Session setup / start / stop run on a private
/// serial queue; observed readiness/capture state flips on the main actor. The
/// session runs only while the viewfinder is visible and stays unavailable on a
/// simulator or denied device.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    enum Availability: Equatable {
        case idle
        case requestingPermission
        case ready
        case permissionDenied
        case restricted
        case deviceUnavailable
        case configurationFailed
        case captureFailed
    }

    private enum SessionSetupResult: Sendable {
        case ready
        case deviceUnavailable
        case configurationFailed
    }
    /// AVFoundation owns its own synchronization; all mutations still go
    /// through `queue`, while SwiftUI reads `session` only to attach a preview.
    @ObservationIgnored nonisolated(unsafe) let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "fun.tiebao.co.Pibo.camera.session")
    @ObservationIgnored private var pending: CheckedContinuation<UIImage?, Never>?
    @ObservationIgnored private var pendingCaptureID: Int64?
    @ObservationIgnored private var captureTimeout: Task<Void, Never>?
    @ObservationIgnored private var lifecycleGeneration: UInt = 0

    private(set) var availability: Availability = .idle
    /// The capture session remains alive after a single shutter failure. Keeping
    /// that live context lets the next shutter act as the retry instead of
    /// replacing the preview with an unrelated error screen.
    var hasLivePreview: Bool {
        availability == .ready || availability == .captureFailed
    }
    /// Backwards-compatible capture readiness used by existing callers.
    var isReady: Bool { hasLivePreview }
    /// Prevents a second shutter from replacing the first capture continuation.
    private(set) var isCapturing = false

    override init() { super.init() }

    func start() async {
        guard !isReady else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        availability = .requestingPermission
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied:
            availability = .permissionDenied
            return
        case .restricted:
            availability = .restricted
            return
        @unknown default:
            availability = .configurationFailed
            return
        }
        guard granted else {
            LPLog.camera.notice("camera access not granted")
            availability = AVCaptureDevice.authorizationStatus(for: .video) == .restricted
                ? .restricted
                : .permissionDenied
            return
        }
        // A back action may happen while the system authorization sheet or
        // hardware setup is in flight. A stale request must not revive the
        // session after the viewfinder has gone away.
        guard generation == lifecycleGeneration else { return }
        let setup = await withCheckedContinuation { (cont: CheckedContinuation<SessionSetupResult, Never>) in
            queue.async {
                let configured = !self.session.inputs.isEmpty
                    && self.session.outputs.contains { $0 === self.output }
                let result = configured ? SessionSetupResult.ready : self.buildSession()
                if case .ready = result {
                    if !self.session.isRunning { self.session.startRunning() }
                    LPLog.camera.notice("capture session ready")
                } else {
                    LPLog.camera.error("capture session build failed — no usable camera input")
                }
                let resolved: SessionSetupResult = if case .ready = result, !self.session.isRunning {
                    .configurationFailed
                } else {
                    result
                }
                cont.resume(returning: resolved)
            }
        }
        guard generation == lifecycleGeneration else { return }
        switch setup {
        case .ready: availability = .ready
        case .deviceUnavailable: availability = .deviceUnavailable
        case .configurationFailed: availability = .configurationFailed
        }
    }

    /// Runs on `queue`. Returns whether a camera input + photo output were wired up.
    private nonisolated func buildSession() -> SessionSetupResult {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) ?? AVCaptureDevice.default(for: .video) else {
            return .deviceUnavailable
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            return .configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
        return .ready
    }

    func capturePhoto() async -> UIImage? {
        guard isReady, !isCapturing else {
            LPLog.camera.info("capturePhoto skipped — session not ready")
            return nil
        }
        // Clear the previous attempt's inline error while this retry is running.
        availability = .ready
        isCapturing = true
        LPLog.camera.debug("capturePhoto requested")
        let settings = AVCapturePhotoSettings()
        let captureID = settings.uniqueID
        return await withCheckedContinuation { cont in
            pending = cont
            pendingCaptureID = captureID
            captureTimeout?.cancel()
            captureTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                LPLog.camera.error("photo capture timed out")
                self?.completeCapture(id: captureID, image: nil)
            }
            queue.async {
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func stop() {
        lifecycleGeneration &+= 1
        availability = .idle
        isCapturing = false
        captureTimeout?.cancel()
        captureTimeout = nil
        pendingCaptureID = nil
        if let pending {
            self.pending = nil
            pending.resume(returning: nil)
        }
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        if let error {
            LPLog.camera.error("photo capture failed: \(error.localizedDescription, privacy: .public)")
        } else if let image {
            LPLog.camera.info("photo captured \(Int(image.size.width), privacy: .public)×\(Int(image.size.height), privacy: .public)@\(Double(image.scale), format: .fixed(precision: 1), privacy: .public)x")
        } else {
            LPLog.camera.error("photo captured but image decode failed (no fileDataRepresentation)")
        }
        let captureID = photo.resolvedSettings.uniqueID
        Task { @MainActor in
            self.completeCapture(id: captureID, image: image)
        }
    }

    /// A stopped capture can still deliver its delegate callback after a new
    /// viewfinder session has started. Match AVFoundation's capture ID so that
    /// stale callback can never resume the newer shutter's continuation.
    private func completeCapture(id: Int64, image: UIImage?) {
        guard pendingCaptureID == id else { return }
        captureTimeout?.cancel()
        captureTimeout = nil
        pendingCaptureID = nil
        let continuation = pending
        pending = nil
        isCapturing = false
        if image == nil, availability == .ready {
            availability = .captureFailed
        }
        continuation?.resume(returning: image)
    }
}
