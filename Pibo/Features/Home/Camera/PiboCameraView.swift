import SwiftUI
import PhotosUI
@preconcurrency import AVFoundation
import UIKit
import os

/// Full-screen meal camera. Meal selection happens in a forest-backed
/// Half-sheet before this view is presented. The view stays in its capture
/// context until the backend confirms that food is present; only then does it
/// dismiss to the forest observation and write formal history.
struct PiboCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onPhotoSaved: (
        UIImage?,
        String?,
        MealType?
    ) async -> HomePhotoSaveCoordinator.Outcome

    @State private var camera = CameraController()
    @State private var lastThumb: UIImage?
    @State private var galleryItem: PhotosPickerItem?
    @State private var flash = false
    @State private var isSaving = false
    @State private var gateMessage: String?
    @State private var saveTask: Task<Void, Never>?
    private let meal: MealType

    init(
        initialMeal: MealType? = nil,
        onPhotoSaved: @escaping (
            UIImage?,
            String?,
            MealType?
        ) async -> HomePhotoSaveCoordinator.Outcome = { _, _, _ in .saved }
    ) {
        self.meal = initialMeal ?? Self.suggestedMeal()
        self.onPhotoSaved = onPhotoSaved
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                captureContext

                if camera.hasLivePreview {
                    framingGuide(in: proxy.size)
                }

                VStack(spacing: 0) {
                    cameraHeader
                        .padding(.top, proxy.safeAreaInsets.top + LP.Spacing.s)

                    if camera.hasLivePreview {
                        instructionPill
                    }

                    if camera.availability == .captureFailed {
                        captureFailureNotice
                            .padding(.top, LP.Spacing.m)
                    }

                    if let gateMessage {
                        gateNotice(gateMessage)
                            .padding(.top, LP.Spacing.m)
                    }

                    Spacer(minLength: LP.Spacing.l)

                    if !camera.hasLivePreview,
                       camera.availability != .requestingPermission,
                       camera.availability != .idle {
                        unavailablePanel
                            .padding(.horizontal, LP.Spacing.xl)
                    }

                    Spacer(minLength: LP.Spacing.l)

                    controlDeck(bottomInset: proxy.safeAreaInsets.bottom)
                }

                if flash {
                    Color.white.opacity(0.22)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .task {
            async let cameraStart: Void = camera.start()
            async let thumbnail = Task.detached { PiboPhotoStore.loadLatest() }.value
            lastThumb = await thumbnail
            await cameraStart
        }
        .onChange(of: galleryItem) { _, item in
            guard let item else { return }
            loadGalleryItem(item)
        }
        .onDisappear {
            saveTask?.cancel()
            camera.stop()
        }
        .preferredColorScheme(.dark)
    }

    private var captureContext: some View {
        ZStack {
            if camera.hasLivePreview {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Image("onboarding_forest_empty")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(PiboMoss.Color.forestVeil.opacity(0.92))
            }
        }
    }

    private var cameraHeader: some View {
        ZStack {
            Text(AppLocalization.format("记录%@", AppLocalization.text(meal.title)))
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(PiboMoss.Color.onDarkPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PiboMoss.Color.onDarkPrimary)
                        .frame(width: PiboMoss.Control.minimumHit, height: PiboMoss.Control.minimumHit)
                        .background(Circle().fill(PiboMoss.Color.cameraControl))
                        .overlay(Circle().strokeBorder(PiboMoss.Color.cameraHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("返回森林"))

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
    }

    private var instructionPill: some View {
        Text(AppLocalization.text("把整份餐食放进框内"))
            .lpText(LP.Typography.b4Medium)
            .foregroundStyle(PiboMoss.Color.onDarkPrimary)
            .padding(.horizontal, LP.Spacing.m)
            .frame(minHeight: 36)
            .background(Capsule().fill(Color.black.opacity(0.42)))
            .padding(.top, LP.Spacing.s)
    }

    private func framingGuide(in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
            .strokeBorder(PiboMoss.Color.foundationTeal.opacity(0.88), lineWidth: 2)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(width: max(0, size.width - 40))
            .position(x: size.width / 2, y: size.height * 0.49)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var captureFailureNotice: some View {
        Label(
            AppLocalization.text("这次拍摄没有完成，请保持当前取景并重试。"),
            systemImage: "exclamationmark.circle"
        )
        .lpText(LP.Typography.c1Medium)
        .foregroundStyle(PiboMoss.Color.onDarkPrimary)
        .padding(.horizontal, LP.Spacing.m)
        .frame(minHeight: 40)
        .background(Capsule().fill(Color.black.opacity(0.54)))
        .padding(.horizontal, LP.Spacing.xl)
    }

    private func gateNotice(_ message: String) -> some View {
        Label(AppLocalization.text(message), systemImage: "viewfinder.circle")
            .lpText(LP.Typography.c1Medium)
            .foregroundStyle(PiboMoss.Color.onDarkPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, LP.Spacing.m)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .padding(.horizontal, LP.Spacing.xl)
            .accessibilityAddTraits(.isStaticText)
    }

    private var unavailablePanel: some View {
        VStack(spacing: LP.Spacing.l) {
            Image(systemName: unavailableIcon)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(PiboMoss.Color.onDarkSecondary)
                .accessibilityHidden(true)

            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text(unavailableTitle))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(PiboMoss.Color.onDarkPrimary)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.text(unavailableDetail))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.onDarkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if camera.availability == .permissionDenied {
                PiboMossPrimaryButton(
                    title: AppLocalization.text("前往设置"),
                    action: openSettings
                )
            } else {
                galleryActionButton
            }

            PiboMossSecondaryButton(
                title: AppLocalization.text("返回森林"),
                onDark: true,
                action: { dismiss() }
            )
        }
        .padding(LP.Spacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PiboMoss.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: PiboMoss.Radius.card)
                .strokeBorder(PiboMoss.Color.cameraHairline, lineWidth: 1)
        }
    }

    private var unavailableIcon: String {
        switch camera.availability {
        case .permissionDenied, .restricted: "camera.fill.badge.ellipsis"
        case .configurationFailed: "exclamationmark.camera.fill"
        default: "camera.fill"
        }
    }

    private var unavailableTitle: String {
        switch camera.availability {
        case .permissionDenied: "还没有相机权限"
        case .restricted: "这台设备限制了相机访问"
        case .configurationFailed: "相机暂时没有准备好"
        default: "这台设备暂时没有可用相机"
        }
    }

    private var unavailableDetail: String {
        switch camera.availability {
        case .permissionDenied: "前往设置允许相机访问后，可以继续拍摄餐食。"
        case .restricted: "你仍然可以从相册选择一张餐食照片。"
        case .configurationFailed: "你仍然可以从相册选择，稍后再尝试相机。"
        default: "你仍然可以从相册选择一张餐食照片。"
        }
    }

    private var galleryActionButton: some View {
        PhotosPicker(selection: $galleryItem, matching: .images) {
            Text(AppLocalization.text("从相册选择"))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: PiboMoss.Control.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .fill(PiboMoss.Color.foundationTeal)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("从相册选择餐食照片"))
    }

    private func controlDeck(bottomInset: CGFloat) -> some View {
        HStack {
            galleryThumbnail

            Spacer(minLength: 0)

            VStack(spacing: LP.Spacing.xs) {
                shutterButton
                if !camera.hasLivePreview {
                    Text(AppLocalization.text("相机不可用"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.onDarkSecondary)
                }
            }

            Spacer(minLength: 0)

            Text("4:3")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(PiboMoss.Color.onDarkPrimary)
                .frame(width: 58, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .strokeBorder(PiboMoss.Color.cameraHairline, lineWidth: 1)
                }
                .accessibilityLabel(AppLocalization.text("画幅比例 4 比 3"))
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.l)
        .padding(.bottom, bottomInset + LP.Spacing.m)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(PiboMoss.Color.cameraHairline).frame(height: 1)
        }
    }

    private var galleryThumbnail: some View {
        PhotosPicker(selection: $galleryItem, matching: .images) {
            RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                .fill(Color.black.opacity(0.58))
                .frame(width: 58, height: 58)
                .overlay {
                    if let lastThumb {
                        Image(uiImage: lastThumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(PiboMoss.Color.onDarkSecondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .strokeBorder(PiboMoss.Color.cameraHairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("从相册选择餐食照片"))
    }

    private var shutterButton: some View {
        Button(action: shutter) {
            ZStack {
                Circle()
                    .fill(PiboMoss.Color.cameraControl)
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(PiboMoss.Color.cameraHairline, lineWidth: 4)
                    .frame(width: PiboMoss.Control.shutterDiameter, height: PiboMoss.Control.shutterDiameter)
                Circle()
                    .fill(Color.white.opacity(camera.hasLivePreview ? 0.96 : 0.24))
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.hasLivePreview || camera.isCapturing || isSaving)
        .accessibilityLabel(AppLocalization.text("拍摄餐食"))
        .accessibilityHint(camera.hasLivePreview ? "" : AppLocalization.text("相机不可用，请从相册选择"))
    }

    private var savingOverlay: some View {
        VStack(spacing: LP.Spacing.m) {
            ProgressView().tint(.white)
            Text(AppLocalization.text("正在确认照片里有餐食"))
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(PiboMoss.Color.onDarkPrimary)
            Button(AppLocalization.text("取消识别")) {
                saveTask?.cancel()
                saveTask = nil
                isSaving = false
            }
            .buttonStyle(.plain)
            .lpText(LP.Typography.c1Medium)
            .foregroundStyle(PiboMoss.Color.onDarkSecondary)
        }
        .padding(LP.Spacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PiboMoss.Radius.media))
        .accessibilityElement(children: .combine)
    }

    private func shutter() {
        guard camera.hasLivePreview, !camera.isCapturing, !isSaving else { return }
        gateMessage = nil
        LPHaptics.tap()
        LPLog.camera.notice("meal shutter tapped (aspect=4:3)")
        if !reduceMotion {
            withAnimation(.linear(duration: 0.06)) { flash = true }
        }
        saveTask?.cancel()
        saveTask = Task {
            defer { saveTask = nil }
            let image = await camera.capturePhoto()
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.16)) { flash = false }
            }
            guard let image, !Task.isCancelled else { return }
            await saveAndExit(image)
        }
    }

    private func loadGalleryItem(_ item: PhotosPickerItem) {
        guard !isSaving else { return }
        gateMessage = nil
        isSaving = true
        saveTask?.cancel()
        saveTask = Task {
            defer { saveTask = nil }
            defer {
                galleryItem = nil
                if !Task.isCancelled { isSaving = false }
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data), !Task.isCancelled else {
                return
            }
            await saveAndExit(image)
        }
    }

    private func saveAndExit(_ image: UIImage) async {
        isSaving = true
        let outcome = await onPhotoSaved(image, nil, meal)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .saved:
            await Task.detached { PiboPhotoStore.saveLatest(image) }.value
            lastThumb = image
            LPHaptics.success()
            dismiss()
        case .notFood:
            gateMessage = AppLocalization.text("照片里没有识别到餐食，请调整取景后重拍。")
            isSaving = false
        case .failed:
            gateMessage = AppLocalization.text("餐食识别没有完成，请检查网络后重试。")
            isSaving = false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private static func suggestedMeal(now: Date = .now) -> MealType {
        switch Calendar.current.component(.hour, from: now) {
        case ..<10: .breakfast
        case 10..<16: .lunch
        default: .dinner
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

/// The most recent saved photo — persisted to one file so the gallery control
/// has a truthful thumbnail across launches.
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
    PiboCameraView(initialMeal: .lunch)
}
