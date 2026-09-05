import SwiftUI
import UIKit

struct TodayPiboShareSheet: View {
    let snapshot: TodayPiboShareSnapshot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedScene: PiboFlatWorldScene
    @State private var characterImage: UIImage?
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var errorText: String?

    init(snapshot: TodayPiboShareSnapshot) {
        self.snapshot = snapshot
        _selectedScene = State(initialValue: PiboFlatWorldScene.recommended(petName: snapshot.petName))
    }

    var body: some View {
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
            characterImage = PiboShareCharacterRenderer.image(stateID: snapshot.assetStateID)
            if characterImage == nil {
                errorText = "Pibo 形象暂时无法生成，请重试。"
                AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
            }
            AccessibilityNotification.ScreenChanged("今天的 Pibo").post()
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL { PiboSystemShareSheet(url: exportURL) }
        }
    }

    private var shareCard: some View {
        TodayPiboShareCard(
            snapshot: snapshot,
            scene: selectedScene,
            characterImage: characterImage
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        errorText = nil
        let image = characterImage ?? PiboShareCharacterRenderer.image(
            stateID: snapshot.assetStateID
        )
        guard let image else {
            errorText = "Pibo 形象暂时无法生成，请重试。"
            AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
            isExporting = false
            return
        }
        characterImage = image
        do {
            exportURL = try TodayPiboShareService.export(
                snapshot: snapshot,
                scene: selectedScene,
                characterImage: image
            )
        } catch {
            errorText = "图片暂时无法生成，请重试。"
            AccessibilityNotification.Announcement(errorText ?? "图片生成失败").post()
        }
        isExporting = false
    }
}
