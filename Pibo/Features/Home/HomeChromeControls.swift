import SwiftUI

/// Top-row Home chrome. It keeps the established `bo` and corner-entry wiring
/// beside the controls that emit those actions, while Home owns presentation.
struct HomeHeader: View {
    @Environment(PetStateStore.self) private var store
    @Environment(BoProgressFeedbackStore.self) private var boProgressFeedback
    @Environment(BoLedgerStore.self) private var boLedger
    @Environment(OrnamentUnlockStore.self) private var ornamentUnlocks

    let featurePresentation: HomeFeaturePresentationState
    @Binding var showBoUnlockPage: Bool
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let feedbackEnabled: Bool
    let dismissSpeech: () -> Void
    let collectAction: () -> Bool

    private var feedbackRequest: BoCounterFeedbackRequest? {
        BoCounterFeedbackRequest(
            feedID: store.feedToken,
            milestoneID: boProgressFeedback.pending?.id
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                BoCounterView(
                    balance: boLedger.balance,
                    growthProgress: boLedger.growthProgress,
                    hasRipeBo: boLedger.hasRipeBo,
                    highlightsExchange: ornamentUnlocks.shouldHighlightUnlockGuide(
                        balance: boLedger.balance
                    ),
                    feedbackRequest: feedbackRequest,
                    feedbackEnabled: feedbackEnabled,
                    feedbackCompleted: { request in
                        if store.feedToken == request.feedID {
                            store.feedToken = nil
                        }
                        if let milestoneID = request.milestoneID {
                            boProgressFeedback.consume(id: milestoneID)
                        }
                    },
                    collectAction: {
                        dismissSpeech()
                        return collectAction()
                    }
                ) {
                    dismissSpeech()
                    Analytics.track(.boPanelOpen, screen: "home",
                                    ["balance": .int(boLedger.balance)])
                    showBoUnlockPage = true
                }
            }

            Spacer(minLength: 0)

            HomeCornerActions(
                cameraEnabled: cameraEnabled,
                walkDoodleEnabled: walkDoodleEnabled,
                dismissSpeech: dismissSpeech,
                onOpenCamera: {
                    HomeCameraPresentationCoordinator.open(
                        meal: nil,
                        presentation: featurePresentation
                    )
                },
                onOpenWalkDoodle: {
                    featurePresentation.showWalkDoodle = true
                },
                onOpenSettings: {
                    Analytics.track(.settingsOpen, screen: "home")
                    featurePresentation.showSettings = true
                }
            )
        }
        .padding(.top, LP.Spacing.s)
    }
}

struct HomeCornerActions: View {
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let dismissSpeech: () -> Void
    let onOpenCamera: () -> Void
    let onOpenWalkDoodle: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: LP.Spacing.s) {
            if cameraEnabled {
                cornerButton(
                    systemImage: "camera.fill",
                    label: "餐食相机",
                    rotation: -2,
                    size: 36,
                    action: onOpenCamera
                )
            }
            if walkDoodleEnabled {
                cornerButton(
                    systemImage: "map.fill",
                    label: "Walk Doodle",
                    rotation: 1,
                    size: 36,
                    action: onOpenWalkDoodle
                )
            }
            cornerButton(
                systemImage: "gearshape",
                label: "设置",
                rotation: 0,
                size: 36,
                action: onOpenSettings
            )
        }
    }

    private func cornerButton(
        systemImage: String,
        label: String,
        rotation: Double,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.90))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                )
                .lpShadow(LP.Shadow.elevation1)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(label))
    }
}

struct HomeBottomControls: View {
    let hasRipeBo: Bool
    let dismissSpeech: () -> Void
    let onOpenHistory: () -> Void
    let onPluck: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if hasRipeBo {
                pluckButton
            }
            HStack {
                Spacer(minLength: 0)
                historyButton
            }
        }
        .padding(.bottom, LP.Spacing.l)
    }

    private var historyButton: some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            onOpenHistory()
        } label: {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: 0x006650))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LP.Colorful.teal500)
                    .frame(height: 64)
                Image(systemName: "list.bullet")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.white)
                    .padding(.top, 16)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("足迹"))
    }

    private var pluckButton: some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            onPluck()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 12))
                Text(AppLocalization.text("收下长好的毛"))
                    .lpText(LP.Typography.b3Medium)
            }
            .foregroundStyle(LP.Fill.foundationOnAccent)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.s)
            .background(Capsule().fill(LP.Fill.foundationAccent))
            .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
    }
}
