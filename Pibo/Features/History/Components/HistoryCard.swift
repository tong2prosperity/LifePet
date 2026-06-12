import SwiftUI

/// Base card chrome for the 历史数据页 cards (Figma `activity card` 1193:1508):
/// a rounded-24 surface with a 2px white@8% inner border, soft elevation-1 shadow,
/// and a title header (b3Medium) at the top-left. The fill varies per card — plain
/// container, a tinted gradient (活动 / 今日脚步), dark grey-850 (睡眠), or paper
/// grey-200 (今日记录) — supplied by the `background` builder so each card keeps its
/// own surface while sharing the frame, border, and shadow.
struct HistoryCard<Background: View, Content: View>: View {
    let title: String
    /// Dark surface (睡眠) → header uses the inverted ink ramp.
    var dark: Bool = false
    @ViewBuilder var background: () -> Background
    @ViewBuilder var content: () -> Content

    /// Figma radius/xl-24. `LP.Radius` skips 24, so it lives here as the card's
    /// house radius rather than polluting the token enum.
    static var radius: CGFloat { 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryCardHeader(title: title, dark: dark)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { background() }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 2)
        )
        .lpShadow(LP.Shadow.elevation1)
    }
}

/// Card title row — `pt16 / pb8 / px20`, b3Medium (Figma `card header` 1374:855).
struct HistoryCardHeader: View {
    let title: String
    var dark: Bool = false

    var body: some View {
        Text(AppLocalization.text(title))
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(dark ? LP.Content.invertSecondary : LP.Content.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.s)
            .padding(.horizontal, LP.Spacing.xl)
    }
}

/// One labelled metric column (卡路里 · 785 · kcal) — Figma `daily activities
/// data` 1374:495. Label (c2 quarternary) over value (uiH4) + unit (b3).
struct HistoryStatColumn: View {
    let label: String
    let value: String
    let unit: String
    var dark: Bool = false

    var body: some View {
        VStack(spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(dark ? LP.Content.invertQuarternary : LP.Content.quarternary)
            HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
                Text(value)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(dark ? LP.Content.invertPrimary : LP.Content.primary)
                Text(unit)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(dark ? LP.Content.invertPrimary : LP.Content.primary)
                    .padding(.vertical, LP.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
