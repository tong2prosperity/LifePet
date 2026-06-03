import SwiftUI
import os

/// First-launch screen. Asks the user to share HealthKit reads, then hands
/// control back to `RootView`. The actual auth round-trip lives in
/// `HealthDataService.requestAuthorization()`; this view is just the
/// presentation + copy.
///
/// We surface three buttons:
/// - **Connect** — primary; runs the system dialog.
/// - **Demo only** — proceeds with hard-coded demo data (`DemoMode = true`).
/// - **Maybe later** — closes the gate without touching HK; the home shows
///   the demo defaults until the user opens this screen again.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store
    @State private var petNameDraft: String = ""

    /// Called by `RootView` when the gate should close — either auth was
    /// granted, the user accepted demo mode, or they tapped "later".
    let onContinue: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.s5) {
                hero
                why
                naming
                Spacer(minLength: LP.Spacing.s5)
                actions
            }
            .padding(LP.Spacing.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lpPaper(.app)
        .onAppear {
            if petNameDraft.isEmpty {
                petNameDraft = store.petName
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            StarShellHero()
                .frame(maxWidth: .infinity)
                .padding(.bottom, LP.Spacing.s2)
            Text(lp: "PIBO · 契约唤醒")
                .lpText(LP.Typography.monoLabel)
                .foregroundStyle(LP.Colors.coral)
            Text(lp: "用你的星光\n叫醒 Pibo。")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
                .lineSpacing(4)
            Text(lp: "运动会变成活力星光，睡眠会变成静息星光。Pibo 会因为这些光保持清醒。")
                .lpText(LP.Typography.serifItalic)
                .foregroundStyle(LP.Colors.muted)
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s3) {
            Text(lp: "Pibo 会读取（不写入）")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
            VStack(alignment: .leading, spacing: LP.Spacing.s2) {
                row(icon: "figure.walk", title: "步数 / 运动 / 卡路里", subtitle: "→ 活力星光")
                row(icon: "moon.zzz.fill", title: "睡眠 · 深睡 · REM", subtitle: "→ 静息星光")
                row(icon: "heart.fill", title: "HRV / 心率 / 冥想", subtitle: "→ 心绪回声（后台）")
                row(icon: "sparkles", title: "已完成的运动", subtitle: "→ 星光落下，Pibo 会回应")
            }
            .lpStampedCard(fill: LP.Colors.paperCard)
        }
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            Text(lp: "给这只 Pibo 起名")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
            TextField("PIBO", text: $petNameDraft)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(LP.Colors.ink)
                .padding(.horizontal, LP.Spacing.s3)
                .padding(.vertical, LP.Spacing.s3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LP.Colors.paperCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: 1.5)
                )
            Text(lp: "名字可以以后再改。MVP 里它仍然是同一种契约生命：Pibo。")
                .lpText(LP.Typography.caption)
                .foregroundStyle(LP.Colors.muted)
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LP.Colors.coral)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(lp: title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(lp: subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            switch health.authState {
            case .unavailable:
                VStack(spacing: LP.Spacing.s3) {
                    Text(lp: "当前设备不支持 HealthKit · 仅 Demo 模式可用")
                        .lpText(LP.Typography.caption)
                        .foregroundStyle(LP.Colors.muted)
                        .multilineTextAlignment(.center)
                    LPButton(AppLocalization.text("用临时星光继续"), variant: .primary, action: continueWithDemo)
                }
            case .requesting:
                HStack(spacing: LP.Spacing.s3) {
                    ProgressView()
                    Text(lp: "等你授权…")
                        .lpText(LP.Typography.caption)
                        .foregroundStyle(LP.Colors.muted)
                }
            default:
                VStack(spacing: LP.Spacing.s3) {
                    LPButton(AppLocalization.text("签订契约并连接 HealthKit"), variant: .primary, action: connect)
                    LPButton(AppLocalization.text("用临时星光继续"), variant: .secondary, action: continueWithDemo)
                    LPButton(AppLocalization.text("以后再说"), variant: .ghost, action: deferAuth)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

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

private struct StarShellHero: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LP.Colors.paperWarm)
                .frame(width: 156, height: 156)
                .overlay(Circle().strokeBorder(LP.Colors.ink, lineWidth: 2))
            Circle()
                .strokeBorder(LP.Colors.coral.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .frame(width: 126, height: 126)
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LP.Colors.coral)
                .offset(x: -44, y: -38)
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LP.Colors.sage)
                .offset(x: 44, y: 36)
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(LP.Colors.ink)
                .opacity(0.9)
            Text("PIBO")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(LP.Colors.paperCard)
                .offset(y: 2)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
}
