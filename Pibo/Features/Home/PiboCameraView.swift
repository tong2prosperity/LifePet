import SwiftUI
import Observation
import AVFoundation
import UIKit

/// 拍照页 / 记录饮食 (Figma `488:1337` §拍照页). Opened from the home 露珠相机 button.
///
/// Flow: live camera viewfinder → tap the shutter (the capture area flashes once
/// with a 20% white scrim) → 拍立得 polaroid preview (random −5°…5° tilt, with a
/// timestamp + pibo mark) → 重拍 / 保存. Save persists the shot (it becomes the
/// viewfinder thumbnail next time) and raises 认知能量 via `onPhotoSaved`.
///
/// Capture is a real `AVCaptureSession`. On a device without a camera (simulator)
/// or when access is denied, it falls back to a synthesized placeholder frame so
/// the whole flow still demos.
struct PiboCameraView: View {
    @Environment(\.dismiss) private var dismiss
    var onPhotoSaved: () -> Void = {}

    @State private var camera = CameraController()
    private enum Stage { case viewfinder, preview }
    @State private var stage: Stage = .viewfinder
    @State private var shot: UIImage? = nil
    @State private var lastThumb: UIImage? = PiboPhotoStore.loadLatest()
    @State private var capturedAt = Date()
    @State private var flash = false
    @State private var aspect: CaptureAspect = .fourThree
    @State private var tilt: Double = 0

    var body: some View {
        ZStack {
            LP.Fill.bgSurface.ignoresSafeArea()
            switch stage {
            case .viewfinder: viewfinder
            case .preview:    preview
            }
        }
        .task { await camera.configure() }
        .onDisappear { camera.stop() }
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

    /// 记录饮食 — centered title + subtitle (Figma `509:2732`), back chevron top-left.
    private var captureHeader: some View {
        ZStack(alignment: .top) {
            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text("记录饮食"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
                Text(AppLocalization.text("pibo想知道你吃了什么"))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
            }
            .frame(maxWidth: .infinity)
            HStack {
                backButton(action: { dismiss() })
                Spacer(minLength: 0)
            }
        }
        .padding(LP.Spacing.xl)
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
                Text(AppLocalization.text("相机不可用 · 用示意画面继续"))
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
        LPHaptics.tap()
        capturedAt = Date()
        tilt = Double.random(in: -5...5)
        withAnimation(.linear(duration: 0.06)) { flash = true }
        Task {
            let img = await camera.capturePhoto()
            try? await Task.sleep(for: .milliseconds(90))
            shot = img
            withAnimation(.easeOut(duration: 0.18)) { flash = false }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { stage = .preview }
        }
    }

    private func retake() {
        shot = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { stage = .viewfinder }
    }

    private func save() {
        LPHaptics.tap()
        if let shot {
            PiboPhotoStore.saveLatest(shot)
            lastThumb = shot
        }
        onPhotoSaved()
        dismiss()
    }

    private var timestampLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/dd  hh:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: capturedAt)
    }

    /// 通用弹幕池 — Pibo's after-save reaction is raised on the *home* (spec §4.3),
    /// so this pool stays here for `HomeView.handlePhotoSaved` to draw from.
    static let genericComments = [
        "…这个…能吃？", "…地球的…食物…好奇怪…", "…#@!%…闻起来…", "…花…不吃…这个…",
        "…人的能量…从这儿来…？", "…Pibo…只能…光合作用…", "…看起来…比土壤…好吃…",
        "…颜色…没…见过…", "…形状…不像…花…", "…地球…东西…都…能吃？",
    ]
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
/// serial queue; `isReady` (observed) flips on the main actor once a real capture
/// device is wired up — it stays `false` on the simulator so the UI shows the
/// placeholder frame.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "fun.tiebao.co.Pibo.camera.session")
    @ObservationIgnored private var pending: CheckedContinuation<UIImage?, Never>?

    /// True once a usable back camera is running (false on simulator / when denied).
    var isReady = false

    override init() { super.init() }

    func configure() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default:             granted = false
        }
        guard granted else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let ok = self.buildSession()
                if ok { self.session.startRunning() }
                Task { @MainActor in self.isReady = ok }
                cont.resume()
            }
        }
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
        guard isReady else { return nil }
        return await withCheckedContinuation { cont in
            pending = cont
            queue.async {
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        Task { @MainActor in
            self.pending?.resume(returning: image)
            self.pending = nil
        }
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
enum PiboPhotoStore {
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
