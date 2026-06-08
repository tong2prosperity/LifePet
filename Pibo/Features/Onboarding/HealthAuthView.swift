import SwiftUI
import os

/// First-launch screen (魔丸态). Introduces Pibo — a tsundere flower-sprite that
/// just fell to Earth — and asks to read (never write) HealthKit so the flower
/// on its head can grow. Auth round-trip lives in
/// `HealthDataService.requestAuthorization()`; this is presentation + copy.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store
    @State private var petNameDraft: String = ""

    /// Called by `RootView` when the gate should close — auth granted, demo
    /// accepted, or "later".
    let onContinue: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                hero
                why
                naming
                Spacer(minLength: LP.Spacing.l)
                actions
            }
            .padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .onAppear { if petNameDraft.isEmpty { petNameDraft = store.petName } }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            OnboardingPiboHero()
                .frame(maxWidth: .infinity)
                .padding(.vertical, LP.Spacing.m)
            Text(lp: "PIBO · 魔丸态")
                .lpText(LP.Typography.c1Medium)
                .tracking(2)
                .foregroundStyle(LP.Content.tertiary)
            Text(lp: "它刚掉到\n这颗星球。")
                .lpText(LP.Typography.uiH1)
                .foregroundStyle(LP.Content.primary)
            Text(lp: "Pibo 是只种花的小精灵，听不懂人话，只在乎头上那株花。花要靠你身上的能量才能开——所以它赖上了你，却死不承认。")
                .lpText(LP.Typography.b2Regular)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(lp: "Pibo 会读取（不写入）")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
            VStack(spacing: LP.Spacing.m) {
                row(icon: "figure.walk", title: "步数 / 运动", subtitle: "让花有活力，颜色更鲜艳")
                row(icon: "moon.zzz.fill", title: "睡眠 · 深睡 · REM", subtitle: "让花有精神，挺得起头")
                row(icon: "heart.fill", title: "心率 / HRV", subtitle: "感知你今天的状态")
                row(icon: "camera", title: "拍照", subtitle: "帮 Pibo 认识地球")
            }
            .padding(LP.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Separator.primary, lineWidth: 1)
            )
            .lpShadow(LP.Shadow.elevation1)
        }
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(lp: "给这只 Pibo 起名")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
            TextField("PIBO", text: $petNameDraft)
                .lpText(LP.Typography.b1Medium)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(LP.Content.primary)
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .fill(LP.Fill.bgContainer)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .strokeBorder(LP.Separator.primary, lineWidth: 1.5)
                )
            Text(lp: "前两周它只会喊你「人」。第 15 天起，它会试着喊你的名字。")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: LP.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LP.Fill.foundationAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(lp: title)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(lp: subtitle)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            switch health.authState {
            case .unavailable:
                VStack(spacing: LP.Spacing.m) {
                    Text(lp: "当前设备不支持 HealthKit · 仅 Demo 模式可用")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .multilineTextAlignment(.center)
                    primaryButton("用 Demo 数据继续", action: continueWithDemo)
                }
            case .requesting:
                HStack(spacing: LP.Spacing.m) {
                    ProgressView()
                    Text(lp: "等你授权…")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            default:
                VStack(spacing: LP.Spacing.m) {
                    primaryButton("连接 HealthKit", action: connect)
                    secondaryButton("用 Demo 数据继续", action: continueWithDemo)
                    ghostButton("以后再说", action: deferAuth)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Fill.foundationOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LP.Spacing.l)
                .background(Capsule().fill(LP.Fill.foundationAccent))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LP.Spacing.l)
                .background(Capsule().fill(LP.Fill.bgContainer))
                .overlay(Capsule().strokeBorder(LP.Separator.primary, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LP.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func connect() {
        LPLog.onboarding.notice("User chose: connect HealthKit")
        commitName()
        Task {
            await health.requestAuthorization()
            store.demoMode = health.authState != .granted
            LPLog.onboarding.notice("Onboarding finished (auth=\(String(describing: health.authState), privacy: .public))")
            onContinue()
        }
    }

    private func continueWithDemo() {
        LPLog.onboarding.notice("User chose: demo mode")
        commitName()
        store.demoMode = true
        onContinue()
    }

    private func deferAuth() {
        LPLog.onboarding.notice("User chose: maybe later")
        commitName()
        store.demoMode = true
        onContinue()
    }

    private func commitName() {
        let trimmed = petNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.petName = trimmed.isEmpty ? "PIBO" : String(trimmed.prefix(16))
    }
}

/// 魔丸态 Pibo hero: a soft blob with the mystery head (黑洞 + 绿色 ?), in a
/// dashed-ring spotlight.
private struct OnboardingPiboHero: View {
    var body: some View {
        ZStack {
            Circle().fill(LP.Fill.bgContainer)
                .frame(width: 172, height: 172)
                .overlay(Circle().strokeBorder(LP.Separator.primary, lineWidth: 1))
                .lpShadow(LP.Shadow.elevation2)
            Circle()
                .strokeBorder(LP.Content.quarternary,
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .frame(width: 140, height: 140)
            VStack(spacing: -8) {
                PiboHeadItemView(item: .mystery, size: 30)
                blob
            }
            .offset(y: 6)
        }
        .accessibilityHidden(true)
    }

    private var blob: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.white)
                .frame(width: 78, height: 90)
                .overlay(Capsule(style: .continuous).strokeBorder(Color(hex: 0xDADADA), lineWidth: 2))
            HStack(spacing: 16) {
                eye; eye
            }
            .offset(y: 4)
        }
    }

    private var eye: some View {
        Ellipse().fill(Color(hex: 0x1F1F1F)).frame(width: 7, height: 9)
    }
}

#Preview {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
}
