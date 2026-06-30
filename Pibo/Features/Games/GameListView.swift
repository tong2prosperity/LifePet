import SwiftUI

// MARK: - 健康小游戏列表 (游戏场)
//
// The 游戏场 zone entrance content. Every game here is **健康相关** (the worldview
// is "你的身体就是宠物的食物") — they nudge the user to actually move, and the
// result feeds Pibo's 运动能量. The first shipped game is 地图涂鸦 (walk doodle):
// 出门走一幅画、圈一块花田. More body-driven games slot in as more cards.
//
// Presented as a full-screen cover from `HomeView` when the user taps into the
// 游戏场 zone (`PiboStageScene.onEnterGames`). Each playable game presents itself
// over this list; results bubble up via the supplied closures.

struct GameListView: View {
    @Environment(\.dismiss) private var dismiss

    /// A finished walk doodle — `HomeView` persists it + grants 运动能量 + lets
    /// Pibo grumble a line (same handler the old home task card used).
    var onWalkDoodleSaved: (WalkDoodleResult) -> Void

    @State private var showWalkDoodle = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LP.Fill.bgSurfaceSecondary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LP.Spacing.l) {
                    header
                    walkDoodleCard
                    comingSoonCard
                    Color.clear.frame(height: LP.Spacing.xxl)
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.top, 72)
            }

            closeButton
        }
        .fullScreenCover(isPresented: $showWalkDoodle) {
            // WalkDoodleView dismisses itself after 保存/返回; onSaved fires first.
            WalkDoodleView(onSaved: onWalkDoodleSaved)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("游戏场"))
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.text("陪 Pibo 动一动"))
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.secondary)
            // Garbled 魔丸 voice — raw, like the rest of the speech pools.
            Text("...动一动...花...才会开...啵")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cards

    private var walkDoodleCard: some View {
        Button {
            LPHaptics.tap()
            showWalkDoodle = true
        } label: {
            gameCard(
                glyph: "scribble.variable",
                accent: true,
                tag: AppLocalization.text("运动能量"),
                title: AppLocalization.text("地图涂鸦"),
                subtitle: AppLocalization.text("出门走一幅画 · 圈一块花田"),
                playable: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("地图涂鸦：出门走一幅画"))
    }

    private var comingSoonCard: some View {
        gameCard(
            glyph: "figure.run",
            accent: false,
            tag: AppLocalization.text("敬请期待"),
            title: AppLocalization.text("更多健康小游戏"),
            subtitle: AppLocalization.text("都和身体活动有关 · 正在路上"),
            playable: false
        )
        .opacity(0.6)
    }

    private func gameCard(glyph: String, accent: Bool, tag: String, title: String,
                          subtitle: String, playable: Bool) -> some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: glyph)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent ? LP.Fill.foundationOnAccent : LP.Content.tertiary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(accent ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary))
                .overlay(Circle().strokeBorder(LP.Border.tertiary, lineWidth: accent ? 0 : LP.BorderWidth.hair))

            VStack(alignment: .leading, spacing: 3) {
                Text(tag)
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text(title)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(subtitle)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if playable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LP.Content.quarternary)
            }
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer))
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair))
        .lpShadow(LP.Shadow.elevation2)
    }

    // MARK: Close

    private var closeButton: some View {
        Button {
            LPHaptics.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(LP.Fill.bgContainer))
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .padding(.trailing, LP.Spacing.xl)
        .padding(.top, LP.Spacing.l)
        .accessibilityLabel(AppLocalization.text("关闭"))
    }
}

#Preview {
    GameListView(onWalkDoodleSaved: { _ in })
}
