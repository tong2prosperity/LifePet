import SwiftUI

/// The persistent top and bottom controls on Home. Speech and DEBUG overlays
/// remain sibling layers so their existing z-order stays explicit in Home.
struct HomePrimaryChrome: View {
    let presentation: HomePresentationState
    var balanceChip: AnyView? = nil
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let dismissSpeech: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader(
                presentation: presentation,
                balanceChip: balanceChip,
                cameraEnabled: cameraEnabled,
                walkDoodleEnabled: walkDoodleEnabled,
                dismissSpeech: dismissSpeech
            )
            Spacer()
            HomeBottomControls(
                dismissSpeech: dismissSpeech,
                onOpenHistory: onOpenHistory
            )
        }
        .padding(.horizontal, LP.Spacing.l)
    }
}

/// Top-row Home chrome. Decision 048: the left shows only collected,
/// spendable `bo`; ripe energy still on Pibo's head is not counted.
struct HomeHeader: View {
    let presentation: HomePresentationState
    var balanceChip: AnyView? = nil
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let dismissSpeech: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            if let balanceChip { balanceChip }
            Spacer(minLength: 0)

            HomeCornerActions(
                cameraEnabled: cameraEnabled,
                walkDoodleEnabled: walkDoodleEnabled,
                dismissSpeech: dismissSpeech,
                onOpenCamera: {
                    Analytics.track(
                        .cameraOpen,
                        screen: "home",
                        ["meal": .string("none")]
                    )
                    presentation.activeSheet = .mealCaptureSelection
                },
                onOpenWalkDoodle: {
                    presentation.showWalkDoodle = true
                },
                onOpenSettings: {
                    Analytics.track(.settingsOpen, screen: "home")
                    presentation.showSettings = true
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
                    label: "散步涂鸦",
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
        let isCamera = systemImage == "camera.fill"
        return Button {
            LPHaptics.tap()
            dismissSpeech()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isCamera
                                 ? PiboMoss.Color.foundationTeal
                                 : LP.Content.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(isCamera
                              ? PiboMoss.Color.sheetMoss.opacity(0.94)
                              : LP.Fill.bgContainer.opacity(0.90))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .strokeBorder(
                            isCamera
                                ? PiboMoss.Color.hairline.opacity(0.72)
                                : .white.opacity(0.55),
                            lineWidth: LP.BorderWidth.hair
                        )
                )
                .shadow(
                    color: isCamera ? Color(hex: 0x17342B, alpha: 0.18) : .clear,
                    radius: isCamera ? 8 : 0,
                    y: isCamera ? 3 : 0
                )
                .lpShadow(LP.Shadow.elevation1)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(label))
    }
}

struct HomeBottomControls: View {
    let dismissSpeech: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            historyButton
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

}


/// Always-visible collected balance with the short collection hint to its right.
struct HomeBoBalanceChip: View {
    let balance: Int
    let hint: String?
    let onTap: () -> Void
    let onCenterChange: (CGPoint) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LP.Spacing.s) {
            Button(action: onTap) {
                HStack(spacing: 7) {
                    PiboBoGlyph()
                        .frame(width: 15, height: 24)
                        .accessibilityHidden(true)
                    Text(AppLocalization.format("%d bo", balance))
                        .font(.system(size: 17, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0x24 / 255, green: 0x53 / 255, blue: 0x43 / 255))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(Color(red: 0xF4 / 255, green: 0xEB / 255, blue: 0xDD / 255).opacity(0.93))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.format("已收取 %d bo", balance))
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { onCenterChange($0) }

            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0x34 / 255, green: 0x5D / 255, blue: 0x49 / 255))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0xE8 / 255, green: 0xF1 / 255, blue: 0xE3 / 255).opacity(0.91))
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150, alignment: .leading)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}
