import SwiftUI
import UIKit

struct TodayPiboShareSheet: View {
    let snapshot: TodayPiboShareSnapshot
    /// Home's current bo container fill, so the exported portrait matches the
    /// stage instead of always drawing the empty shell.
    var boFillProgress: Double = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedScene: PiboFlatWorldScene
    @State private var characterImage: UIImage?
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var errorText: String?

    private var pixel: Bool { PiboReleaseScope.pixelShare }

    init(snapshot: TodayPiboShareSnapshot, boFillProgress: Double = 0) {
        self.snapshot = snapshot
        self.boFillProgress = boFillProgress
        _selectedScene = State(initialValue: PiboFlatWorldScene.recommended(petName: snapshot.petName))
    }

    var body: some View {
        Group {
            if pixel { pixelSheet } else { legacySheet }
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL { PiboSystemShareSheet(url: exportURL) }
        }
    }

    // MARK: Pixel sheet (HarmonyPibo `TodayPiboShareSheet.ets`)

    private var pixelSheet: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.text("分享今天的我"))
                        .font(PixelFont.font(20))
                        .foregroundStyle(PixelUIColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(AppLocalization.text("每日推荐一景，也可以自己选择"))
                        .font(.system(size: 13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .frame(width: 44, height: 44)
                        .background(PixelUIColor.paperDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("关闭分享预览"))
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    shareCard

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedScene.localizedTitle)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(PixelUIColor.ink)
                                Text(pixelSceneAtmosphere(selectedScene))
                                    .font(.system(size: 13))
                                    .foregroundStyle(PixelUIColor.inkSoft)
                            }
                            Spacer(minLength: 0)
                            Text(AppLocalization.text("左右滑动换景 · 今日真实记录"))
                                .font(.system(size: 10))
                                .foregroundStyle(PixelUIColor.inkSoft)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(PiboFlatWorldScene.allCases, id: \.self) { scene in
                                    sceneChoice(scene)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(PixelUIColor.paper)
                    .overlay {
                        Rectangle().stroke(PixelUIColor.border, lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(PixelUIColor.inkSoft)
            }

            PixelButton(label: isExporting ? AppLocalization.text("正在生成…")
                                          : AppLocalization.text("分享这张图片"),
                        active: !isExporting) {
                export()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelUIColor.paper.ignoresSafeArea())
        .task {
            if characterImage == nil && !pixel {
                characterImage = PiboShareCharacterRenderer.image(
                    stateID: snapshot.assetStateID,
                    boFillProgress: CGFloat(boFillProgress)
                )
            }
            AccessibilityNotification.ScreenChanged(AppLocalization.text("今天的 Pibo")).post()
            #if DEBUG
            // `-PiboShareExport` runs the export once, so the offscreen render of the pixel
            // card can be checked in the simulator.
            if ProcessInfo.processInfo.arguments.contains("-PiboShareExport") {
                try? await Task.sleep(for: .seconds(1))
                export()
            }
            #endif
        }
    }

    private func sceneChoice(_ scene: PiboFlatWorldScene) -> some View {
        let selected = scene == selectedScene
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selectedScene = scene }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    PixelPortraitView(scene: scene)
                        .frame(width: 48, height: 60)
                    if selected {
                        Circle()
                            .fill(Color(pixelHex: 0x1C332D).opacity(0.9))
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 60)
                .clipped()
                .overlay {
                    Rectangle().stroke(selected ? scene.pixelAccent : PixelUIColor.border,
                                       lineWidth: selected ? 2 : 1)
                }
                Text(scene.localizedTitle)
                    .font(.system(size: 9, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? PixelUIColor.ink : PixelUIColor.inkSoft)
                    .lineLimit(1)
                    .frame(width: 55)
            }
            .frame(width: 55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scene.localizedTitle)
        .accessibilityValue(selected ? AppLocalization.text("当前分享场景") : "")
    }

    private var shareCard: some View {
        TodayPiboShareCard(snapshot: snapshot, scene: selectedScene,
                           characterImage: characterImage, pixel: pixel)
            .shadow(color: .black.opacity(pixel ? 0 : 0.16), radius: pixel ? 0 : 16, y: pixel ? 0 : 8)
    }

    // MARK: Legacy sheet

    private var legacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LP.Spacing.l) {
                    ViewThatFits(in: .horizontal) {
                        shareCard
                        shareCard
                            .scaleEffect(0.84)
                            .frame(width: 269, height: 359)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LP.Spacing.m) {
                            ForEach(PiboFlatWorldScene.allCases, id: \.self) { scene in
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                        selectedScene = scene
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(scene.resourceName)
                                            .resizable().scaledToFill()
                                            .frame(width: 48, height: 60).clipped()
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(scene == selectedScene ? LP.Fill.foundationAccent : LP.Separator.primary, lineWidth: scene == selectedScene ? 3 : 1)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(scene.localizedTitle)
                                            .lpText(LP.Typography.c1Regular)
                                            .foregroundStyle(LP.Content.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(scene.localizedTitle)
                                .accessibilityValue(scene == selectedScene ? "已选择" : "")
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText).lpText(LP.Typography.c1Regular).foregroundStyle(LP.Fill.foundationError)
                    }

                    Button {
                        export()
                    } label: {
                        HStack {
                            if isExporting { ProgressView().tint(LP.Fill.foundationOnAccent) }
                            Text(isExporting ? "正在准备" : "分享图片")
                                .lpText(LP.Typography.b2Medium)
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .background(LP.Fill.foundationAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                }
                .padding(LP.Spacing.l)
            }
            .background(LP.Fill.bgSurface.ignoresSafeArea())
            .navigationTitle("今天的 Pibo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            characterImage = PiboShareCharacterRenderer.image(
                stateID: snapshot.assetStateID,
                boFillProgress: CGFloat(boFillProgress)
            )
            if characterImage == nil {
                errorText = "Pibo 形象暂时无法生成，请重试。"
                AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
            }
            AccessibilityNotification.ScreenChanged("今天的 Pibo").post()
        }
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        errorText = nil
        if !pixel {
            let image = characterImage ?? PiboShareCharacterRenderer.image(
                stateID: snapshot.assetStateID,
                boFillProgress: CGFloat(boFillProgress)
            )
            guard let image else {
                errorText = "Pibo 形象暂时无法生成，请重试。"
                AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
                isExporting = false
                return
            }
            characterImage = image
        }
        do {
            exportURL = try TodayPiboShareService.export(
                snapshot: snapshot,
                scene: selectedScene,
                characterImage: characterImage,
                pixel: pixel
            )
        } catch {
            errorText = AppLocalization.text("图片暂时无法生成，请重试。")
            AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
        }
        isExporting = false
    }
}

/// A one-line weather note per scene, matching the ArkTS `atmosphere` strings.
func pixelSceneAtmosphere(_ scene: PiboFlatWorldScene) -> String {
    switch scene {
    case .nightClouds: AppLocalization.text("夜云低垂，星星在树梢上")
    case .dawnCreek: AppLocalization.text("晨雾未散，溪水很凉")
    case .riverValley: AppLocalization.text("晴日河谷，风把草压弯")
    case .rainGorge: AppLocalization.text("雨下得很密，峡谷有回声")
    case .coralDusk: AppLocalization.text("暮色落在珊瑚色的岸边")
    }
}

extension PiboFlatWorldScene {
    /// The chip's selected border, one per scene (ArkTS `TodayPiboShareScene.accent`).
    var pixelAccent: Color {
        switch self {
        case .nightClouds: Color(pixelHex: 0x8DABF4)
        case .dawnCreek: Color(pixelHex: 0xE8B9A0)
        case .riverValley: Color(pixelHex: 0x7FB069)
        case .rainGorge: Color(pixelHex: 0x7C93A8)
        case .coralDusk: Color(pixelHex: 0xE58C7B)
        }
    }
}
