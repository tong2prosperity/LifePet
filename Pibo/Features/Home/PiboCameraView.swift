import SwiftUI
import Observation
@preconcurrency import AVFoundation
import UIKit
import os

/// 餐食相机 / 记录饮食 (Figma `488:1337` §拍照页).
///
/// Flow: choose 早/中/晚 → live camera viewfinder → 拍立得 preview → 重拍 / 保存. A recapture
/// launched from meal detail can inject its meal and enter the viewfinder directly.
///
/// Capture is a real `AVCaptureSession`. Missing permission or hardware is shown
/// honestly and cannot create a synthetic meal record.
struct PiboCameraView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called on 保存 with a real captured frame, its best-effort 识图 label, and
    /// the selected meal. Camera-less or denied devices cannot reach this callback.
    var onPhotoSaved: (UIImage?, String?, MealType?) -> Void

    @State private var camera = CameraController()
    private enum Stage: Hashable { case meal, viewfinder, preview }
    @State private var stage: Stage
    @State private var selectedMeal: MealType?
    private let startsWithMeal: Bool
    @State private var shot: UIImage? = nil
    /// Last saved shot's thumbnail. Loaded lazily off-main in `.task` (a disk read
    /// + JPEG decode) so presenting the camera doesn't hitch on the main thread.
    @State private var lastThumb: UIImage? = nil
    @State private var capturedAt = Date()
    @State private var flash = false
    @State private var aspect: CaptureAspect = .fourThree
    @State private var tilt: Double = 0
    /// 识图 — fills in asynchronously after the shutter; shown on the polaroid.
    @State private var subjectLabel: String? = nil

    init(
        initialMeal: MealType? = nil,
        onPhotoSaved: @escaping (UIImage?, String?, MealType?) -> Void = { _, _, _ in }
    ) {
        self.onPhotoSaved = onPhotoSaved
        self.startsWithMeal = initialMeal != nil
        _selectedMeal = State(initialValue: initialMeal)
        _stage = State(initialValue: initialMeal == nil ? .meal : .viewfinder)
    }

    var body: some View {
        ZStack {
            LP.Fill.bgSurface.ignoresSafeArea()
            switch stage {
            case .meal:       mealSelection
            case .viewfinder: viewfinder
            case .preview:    preview
            }
        }
        .task(id: stage) {
            if stage == .viewfinder {
                await camera.start()
            } else {
                camera.stop()
            }
        }
        .task {
            // Off-main disk read + JPEG decode of the last shot's thumbnail.
            if lastThumb == nil {
                lastThumb = await Task.detached { PiboPhotoStore.loadLatest() }.value
            }
        }
        .onDisappear { camera.stop() }
    }

    private var mealSelection: some View {
        VStack(spacing: 0) {
            selectionHeader(
                title: "餐食相机",
                subtitle: "选择这张照片属于哪一餐",
                backAction: { dismiss() }
            )

            VStack(spacing: LP.Spacing.s) {
                ForEach(MealType.allCases) { meal in
                    mealButton(meal)
                }
            }
            .padding(.horizontal, LP.Spacing.xl)

            Spacer(minLength: LP.Spacing.xl)
        }
    }

    private func selectionHeader(
        title: String,
        subtitle: String,
        backAction: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.text(subtitle))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack {
                backButton(action: backAction)
                Spacer(minLength: 0)
            }
        }
        .padding(LP.Spacing.xl)
    }

    private func mealButton(_ meal: MealType) -> some View {
        Button {
            LPHaptics.tap()
            selectedMeal = meal
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                stage = .viewfinder
            }
        } label: {
            HStack(spacing: LP.Spacing.l) {
                Image(systemName: meal.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(LP.Fill.foundationAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LP.Fill.foundationAccent.opacity(0.12)))

                Text(AppLocalization.text(meal.title))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Content.primary)

                Spacer(minLength: LP.Spacing.s)
                Text(AppLocalization.text(meal.shortLabel))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LP.Content.quarternary)
            }
            .padding(.horizontal, LP.Spacing.l)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(meal.title))
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        VStack(spacing: 0) {
            captureHeader
            Spacer(minLength: LP.Spacing.l)
            frame
            Spacer(minLength: LP.Spacing.l)
            shutterBar
                .padding(.bottom, LP.Spacing.s)
        }
    }

    /// Selected capture purpose — centered title + subtitle, back chevron top-left.
    private var captureHeader: some View {
        ZStack(alignment: .top) {
            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text(captureTitle))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
                Text(AppLocalization.text(captureSubtitle))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
            }
            .frame(maxWidth: .infinity)
            HStack {
                backButton(action: leaveViewfinder)
                Spacer(minLength: 0)
            }
        }
        .padding(LP.Spacing.xl)
    }

    private var captureTitle: String {
        selectedMeal.map { "记录\($0.title)" } ?? "餐食相机"
    }

    private var captureSubtitle: String {
        selectedMeal == nil ? "请选择餐次" : "pibo想知道你吃了什么"
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 28, height: 28)
                .padding(LP.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("返回"))
    }

    /// Full-width capture frame, masked to the chosen aspect — live feed, or a
    /// placeholder on a camera-less device. The 20% white capture flash lives here.
    private var frame: some View {
        ZStack {
            Color.black
            if camera.isReady {
                CameraPreview(session: camera.session)
            } else {
                placeholderFrame
            }
            if flash { Color.white.opacity(0.2) }
        }
        .aspectRatio(aspect.ratio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var placeholderFrame: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x17171A)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: LP.Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30, weight: .regular))
                Text(AppLocalization.text("相机不可用，请检查权限或设备"))
                    .lpText(LP.Typography.c1Regular)
            }
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Bottom bar — last-shot thumbnail · shutter · 画幅 toggle (Figma `512:1886`).
    private var shutterBar: some View {
        HStack {
            thumbnail
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            aspectToggle
        }
        .padding(.horizontal, LP.Spacing.xl)
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
            .fill(Color.black)
            .frame(width: 58, height: 58)
            .overlay {
                if let lastThumb {
                    Image(uiImage: lastThumb).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Concentric-circle shutter (Figma `510:1067`).
    private var shutterButton: some View {
        Button(action: shutter) {
            ZStack {
                Circle().strokeBorder(LP.Neutral.grey400, lineWidth: 5).frame(width: 76, height: 76)
                Circle().fill(LP.Neutral.grey550).frame(width: 54, height: 54)
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(.plain)
        .disabled(!camera.isReady || camera.isCapturing)
        .opacity(camera.isReady && !camera.isCapturing ? 1 : 0.44)
        .accessibilityLabel(AppLocalization.text("拍摄"))
    }

    /// 画幅 toggle — a 30×40 bordered box labeled 4:3 / 1:1 (Figma `512:1889`).
    private var aspectToggle: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { aspect = aspect.next } } label: {
            Text(aspect.label)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 30, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .strokeBorder(LP.Content.secondary, lineWidth: LP.BorderWidth.heavy)
                )
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("画幅比例"))
    }

    // MARK: - Preview (polaroid)

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                backButton(action: retake)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.l)

            Spacer(minLength: LP.Spacing.l)
            polaroid
                .rotationEffect(.degrees(tilt))
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            Spacer(minLength: LP.Spacing.l)

            previewActions
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.bottom, LP.Spacing.l)
        }
    }

    /// 拍立得 paper — grey-300 card, photo + pibo mark + timestamp (Figma `510:1129`).
    private var polaroid: some View {
        VStack(alignment: .leading, spacing: 41) {   // 41 = Figma photo→label gap
            photoArea
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: "hurricane")   // stand-in for the pibo spiral mark
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(LP.Content.secondary)
                Text(timestampLabel)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                if let subjectLabel {
                    // 识图 tag — best-effort, so it reads as Pibo's guess.
                    Text(subjectLabel)
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.secondary)
                        .padding(.horizontal, LP.Spacing.s)
                        .padding(.vertical, LP.Spacing.xs)
                        .background(Capsule().fill(.white.opacity(0.6)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .padding(LP.Spacing.l)
        .frame(width: 288)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Neutral.grey300)   // #D7E0E5 — Figma "container-paperlike"
        )
        // Figma drop-shadow: offset (1.86, 3.71), blur 1.86, 12% black.
        .shadow(color: .black.opacity(0.12), radius: 2, x: 2, y: 4)
    }

    private var photoArea: some View {
        ZStack {
            if let shot {
                Image(uiImage: shot).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0xC9D6C2), Color(hex: 0xE7DCC6), Color(hex: 0xCBB79A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .aspectRatio(aspect.ratio, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var previewActions: some View {
        VStack(spacing: LP.Spacing.s) {
            Button(action: retake) {
                actionLabel(icon: "arrow.counterclockwise", title: "重拍", tint: LP.Content.secondary)
                    .background(Capsule().fill(LP.Neutral.grey200))   // #E8EEF1
            }
            .buttonStyle(.plain)
            Button(action: save) {
                actionLabel(icon: "square.and.arrow.down", title: "保存", tint: LP.Fill.foundationOnAccent)
                    .background(Capsule().fill(LP.Neutral.grey700))   // #56616C
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            Text(AppLocalization.text(title)).lpText(LP.Typography.b1Medium)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }

    // MARK: - Actions

    private func shutter() {
        guard camera.isReady, !camera.isCapturing else { return }
        LPHaptics.tap()
        LPLog.camera.notice("shutter tapped (aspect=\(aspect.label, privacy: .public))")
        capturedAt = Date()
        tilt = Double.random(in: -5...5)
        withAnimation(.linear(duration: 0.06)) { flash = true }
        Task {
            let img = await camera.capturePhoto()
            try? await Task.sleep(for: .milliseconds(90))
            guard let img else {
                withAnimation(.easeOut(duration: 0.18)) { flash = false }
                return
            }
            shot = img
            withAnimation(.easeOut(duration: 0.18)) { flash = false }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { stage = .preview }
            classify(img)
        }
    }

    /// 识图 — runs off-main after the shutter; the tag pops onto the polaroid
    /// once Vision answers. Best-effort: a nil result simply shows no tag.
    private func classify(_ image: UIImage?) {
        subjectLabel = nil
        guard let image else {
            LPLog.classify.info("识图 skipped — no captured image (placeholder device)")
            return
        }
        Task {
            let label = await Task.detached { SubjectClassifier.classify(image) }.value
            // Drop a stale answer if the user already retook the shot.
            guard stage == .preview, shot === image else {
                LPLog.classify.debug("识图 result dropped — shot changed before classify returned")
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { subjectLabel = label }
        }
    }

    private func retake() {
        shot = nil
        subjectLabel = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { stage = .viewfinder }
    }

    private func leaveViewfinder() {
        if startsWithMeal {
            dismiss()
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            stage = .meal
        }
    }

    private func save() {
        guard let shot, let selectedMeal else { return }
        LPHaptics.tap()
        LPLog.camera.notice("保存 meal photo label=\(subjectLabel ?? "—", privacy: .public)")
        PiboPhotoStore.saveLatest(shot)
        lastThumb = shot
        onPhotoSaved(shot, subjectLabel, selectedMeal)
        dismiss()
    }

    private var timestampLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/dd  hh:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: capturedAt)
    }

}

/// 4:3 (default) ↔ 1:1 framing. `ratio` is width∶height for display (portrait).
private enum CaptureAspect {
    case fourThree, oneOne
    var ratio: CGFloat { self == .fourThree ? 3.0 / 4.0 : 1 }
    var label: String { self == .fourThree ? "4:3" : "1:1" }
    var next: CaptureAspect { self == .fourThree ? .oneOne : .fourThree }
}

// MARK: - Camera session

/// Thin `AVCaptureSession` wrapper. Session setup / start / stop run on a private
/// serial queue; observed readiness/capture state flips on the main actor. The
/// session runs only while the viewfinder is visible and stays unavailable on a
/// simulator or denied device.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    /// AVFoundation owns its own synchronization; all mutations still go
    /// through `queue`, while SwiftUI reads `session` only to attach a preview.
    @ObservationIgnored nonisolated(unsafe) let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "fun.tiebao.co.Pibo.camera.session")
    @ObservationIgnored private var pending: CheckedContinuation<UIImage?, Never>?
    @ObservationIgnored private var pendingCaptureID: Int64?
    @ObservationIgnored private var captureTimeout: Task<Void, Never>?
    @ObservationIgnored private var lifecycleGeneration: UInt = 0

    /// True once a usable back camera is running (false on simulator / when denied).
    var isReady = false
    /// Prevents a second shutter from replacing the first capture continuation.
    private(set) var isCapturing = false

    override init() { super.init() }

    func start() async {
        guard !isReady else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default:             granted = false
        }
        guard granted else {
            LPLog.camera.notice("camera access not granted")
            return
        }
        // A back action may happen while the system authorization sheet or
        // hardware setup is in flight. A stale request must not revive the
        // session after the viewfinder has gone away.
        guard generation == lifecycleGeneration else { return }
        let ready = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async {
                let configured = !self.session.inputs.isEmpty
                    && self.session.outputs.contains { $0 === self.output }
                let ok = configured || self.buildSession()
                if ok {
                    if !self.session.isRunning { self.session.startRunning() }
                    LPLog.camera.notice("capture session ready")
                } else {
                    LPLog.camera.error("capture session build failed — no usable camera input")
                }
                cont.resume(returning: ok && self.session.isRunning)
            }
        }
        guard generation == lifecycleGeneration else { return }
        isReady = ready
    }

    /// Runs on `queue`. Returns whether a camera input + photo output were wired up.
    private nonisolated func buildSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output)
        else { return false }
        session.addInput(input)
        session.addOutput(output)
        return true
    }

    func capturePhoto() async -> UIImage? {
        guard isReady, !isCapturing else {
            LPLog.camera.info("capturePhoto skipped — session not ready")
            return nil
        }
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
        isReady = false
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
        continuation?.resume(returning: image)
    }
}

/// SwiftUI host for the live `AVCaptureVideoPreviewLayer`.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The most recent saved photo — persisted to a single file so the viewfinder
/// thumbnail survives across launches.
nonisolated enum PiboPhotoStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pibo_last_photo.jpg")
    }

    static func saveLatest(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func loadLatest() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    PiboCameraView()
}
