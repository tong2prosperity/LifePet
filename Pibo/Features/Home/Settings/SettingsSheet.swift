import SwiftUI

/// Settings, behind the home gear (Figma headers 76:6662 / 245:1742): pick a
/// 关于毛的主题 and start over. Reset lives here now (it used to hang directly
/// off the gear button).
struct SettingsSheet: View {
    @Environment(PetStateStore.self) private var store
    @Environment(MembershipService.self) private var membership
    @Environment(\.dismiss) private var dismiss

    /// Performs the actual reset (store wipe + onboarding flag) — owned by
    /// `HomeView` because the onboarding flag lives there.
    var onReset: () -> Void
    /// DEBUG-only: run the full 拍餐识别 path with a synthetic photo (the
    /// simulator has no camera). Owned by `HomeView` (holds recognizer + history).
    var onSimulateMeal: (MealType) -> Void = { _ in }

    @State private var showResetConfirm = false
    @State private var showMembership = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                header
                themeSection
                membershipSection
                dangerSection
                #if DEBUG
                debugSection
                #endif
            }
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showMembership) {
            MembershipSheet()
        }
        .confirmationDialog(
            AppLocalization.text("重置后会回到首启流程"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("重新开始"), role: .destructive) {
                onReset()
                dismiss()
            }
            Button(AppLocalization.text("取消"), role: .cancel) {}
        }
    }

    private var header: some View {
        Text(AppLocalization.text("设置"))
            .lpText(LP.Typography.uiH4)
            .foregroundStyle(LP.Content.primary)
            .padding(.top, LP.Spacing.s)
    }

    // MARK: 主题

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("关于毛的主题"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            VStack(spacing: 0) {
                ForEach(Array(PiboTheme.selectable.enumerated()), id: \.element.id) { index, theme in
                    themeRow(theme)
                    if index < PiboTheme.selectable.count - 1 {
                        Divider().overlay(LP.Separator.primary)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    private func themeRow(_ theme: PiboTheme) -> some View {
        let isSelected = store.currentTheme.id == theme.id
        return Button {
            LPHaptics.tap()
            store.selectedThemeID = theme.id
        } label: {
            HStack(spacing: LP.Spacing.m) {
                themeThumbnail(theme)
                Text(themeName(theme))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LP.Fill.foundationAccent)
                }
            }
            .padding(.horizontal, LP.Spacing.m)
            .padding(.vertical, LP.Spacing.s + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func themeName(_ theme: PiboTheme) -> String {
        theme.displayName.isEmpty ? AppLocalization.text("魔丸（默认）") : AppLocalization.text(theme.displayName)
    }

    /// A slice of the theme's backdrop as the row thumbnail (procedural themes
    /// fall back to their scene colors).
    private func themeThumbnail(_ theme: PiboTheme) -> some View {
        Group {
            if let bg = theme.scene.backgroundImage {
                Image(bg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [theme.scene.skyBottom, theme.scene.ground],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .strokeBorder(LP.Border.primary, lineWidth: LP.BorderWidth.hair)
        )
    }

    // MARK: 会员

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("会员"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            Button {
                LPHaptics.tap()
                showMembership = true
            } label: {
                HStack(spacing: LP.Spacing.m) {
                    Text(AppLocalization.text("Pibo 会员"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Spacer(minLength: 0)
                    Text(membership.isMember ? AppLocalization.text("已开通") : AppLocalization.text("未开通"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(membership.isMember ? LP.Fill.foundationAccent : LP.Content.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LP.Content.quarternary)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    // MARK: 重置

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("其他"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Text(AppLocalization.text("重新开始"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Fill.foundationError)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    // MARK: Debug (sprout-flow rehearsal)

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text("DEV")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            VStack(spacing: 0) {
                Button {
                    store.debugInjectWorkout()
                    dismiss()
                } label: {
                    debugRow("模拟运动完成（发芽流程）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    store.growthStage = .mystery
                } label: {
                    debugRow("回到未发芽（「?」卷芽）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    onSimulateMeal(.lunch)
                    dismiss()
                } label: {
                    debugRow("模拟拍一张午餐（走后台 Kimi 识别）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                weatherDebugRow
            }
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    /// 天气切换 — 驱动首页场景下雨三件套(雨幕 / 地面水花 / 滴在 Pibo 上)。
    /// 接入 WeatherKit 前用它演示;选中即写 `store.weather` → 场景实时响应。
    private var weatherDebugRow: some View {
        HStack(spacing: LP.Spacing.s) {
            Text("天气")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            ForEach([PiboWeather.clear, .rain, .thunderstorm, .snow], id: \.self) { w in
                let on = store.weather == w
                Button {
                    LPHaptics.tap()
                    store.weather = w
                } label: {
                    Text(w.displayName)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(on ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                        .padding(.horizontal, LP.Spacing.s)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(on ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
    }

    private func debugRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
        .contentShape(Rectangle())
    }
    #endif
}

#Preview {
    SettingsSheet(onReset: {})
        .environment(PetStateStore(demoMode: true))
        .environment(MembershipService())
}
