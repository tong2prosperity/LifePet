import SwiftUI

/// 兑换道具面板。
///
/// 存量第一次有了去处 —— 这是整个闭环里「累积 → 变化」的那一环。左边一条进度轨表示
/// 「离下一件还有多远」，右边逐件列出：已解锁 / 可解锁 / 还没够（罩一层雾）。
///
/// 点一件展开它的图注。图注不是商品说明，是 Pibo 那本词典里的条目 —— 它承担的是
/// 「这个东西对任务没用，但值得留着」的那部分表达（决定 014）。
struct BoExchangeSheet: View {
    @Environment(BoLedgerStore.self) private var ledger
    @Environment(OrnamentUnlockStore.self) private var unlocks

    @State private var expanded: PiboOrnament.ID?

    private var ornaments: [PiboOrnament] { PiboOrnament.ordered }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                HStack(alignment: .top, spacing: LP.Spacing.m) {
                    CostRail(
                        costs: ornaments.map(\.cost),
                        balance: ledger.balance
                    )
                    .frame(width: 28)

                    VStack(spacing: LP.Spacing.s) {
                        ForEach(ornaments) { ornament in
                            row(ornament)
                        }
                    }
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.bottom, LP.Spacing.xxl)
            }
        }
        .background(LP.Fill.bgSurfaceSecondary)
        // 只有三件物品，`.medium` 就够；展开图注时用户可以自己拖到 `.large`。
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 头

    private var header: some View {
        HStack(alignment: .center) {
            Text(AppLocalization.text("兑换道具"))
                .lpText(LP.Typography.uiH3)
                .foregroundStyle(LP.Content.primary)

            Spacer(minLength: 0)

            HStack(spacing: LP.Spacing.xs) {
                PiboBoGlyph().frame(width: 14, height: 19)
                Text(AppLocalization.format("%d bo", ledger.balance))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
            }
            .padding(.horizontal, LP.Spacing.s)
            .padding(.vertical, 5)
            .background(Capsule().fill(LP.Fill.bgContainer))
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.top, LP.Spacing.l)
        .padding(.bottom, LP.Spacing.m)
    }

    // MARK: 单件

    @ViewBuilder
    private func row(_ ornament: PiboOrnament) -> some View {
        let unlocked = unlocks.isUnlocked(ornament.id)
        let affordable = ledger.balance >= ornament.cost
        let isExpanded = expanded == ornament.id

        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(spacing: LP.Spacing.m) {
                OrnamentThumbnail(ornament: ornament, isLocked: !unlocked)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ornament.localizedName)
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    HStack(spacing: 4) {
                        PiboBoGlyph(isDimmed: !unlocked && !affordable)
                            .frame(width: 10, height: 14)
                        Text(AppLocalization.format("%d bo", ornament.cost))
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                }

                Spacer(minLength: 0)

                statusControl(ornament, unlocked: unlocked, affordable: affordable)
            }

            if isExpanded {
                Text(ornament.localizedEntry)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(LP.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(
                    affordable && !unlocked ? LP.Fill.foundationAccent : LP.Border.tertiary,
                    lineWidth: affordable && !unlocked ? 1.5 : LP.BorderWidth.hair
                )
        )
        // 还没够的那些罩一层雾：看得见轮廓和价格，看不清细节。
        .overlay {
            if !unlocked && !affordable {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.55))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.22)) {
                expanded = isExpanded ? nil : ornament.id
            }
        }
    }

    @ViewBuilder
    private func statusControl(
        _ ornament: PiboOrnament,
        unlocked: Bool,
        affordable: Bool
    ) -> some View {
        if unlocked {
            Text(AppLocalization.text("已解锁"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
                .padding(.horizontal, LP.Spacing.s)
                .padding(.vertical, 5)
                .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
        } else if affordable {
            Button {
                unlock(ornament)
            } label: {
                Text(AppLocalization.text("解锁"))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LP.Fill.foundationAccent))
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(LP.Content.quarternary)
                .frame(width: 28, height: 28)
        }
    }

    private func unlock(_ ornament: PiboOrnament) {
        // 先扣费再记解锁。反过来的话，一次余额不足的解锁会留下一件白给的物件。
        guard ledger.spend(ornament.cost) else { return }
        LPHaptics.success()
        unlocks.markUnlocked(ornament.id)
        Analytics.track(.boUnlock, screen: "bo_exchange",
                        ["ornament": .string(ornament.id.rawValue),
                         "cost": .int(ornament.cost)])
        withAnimation(.easeOut(duration: 0.22)) { expanded = ornament.id }
    }
}

// MARK: - 进度轨

/// 左侧那条竖轨：刻度是各件的价格，填充到当前余额所在的位置。
///
/// 刻度**均匀排布**而不是按价格线性排 —— 1 / 8 / 20 这种不均匀定价按数值排会把前
/// 两档挤成一团。均匀排也和每行卡片一一对齐，读起来是「第几件」而不是「第几块钱」。
private struct CostRail: View {
    /// 已按价格升序。
    let costs: [Int]
    let balance: Int

    /// 第 i 档刻度的纵向位置（0 = 顶部 = 最便宜）。方向与设计稿一致：
    /// 从上往下价格递增，填充从顶部向下延伸。
    private func y(atIndex index: Int, in height: CGFloat) -> CGFloat {
        guard costs.count > 1 else { return height / 2 }
        return height * CGFloat(index) / CGFloat(costs.count - 1)
    }

    /// 余额落在轨上的位置 —— 在相邻两档之间线性插值，所以「离下一件还有多远」
    /// 是看得出来的，而不是只在跨档时跳一下。
    private func fillHeight(in height: CGFloat) -> CGFloat {
        guard let first = costs.first, !costs.isEmpty else { return 0 }
        if balance < first { return 0 }
        for index in costs.indices.dropLast() where balance < costs[index + 1] {
            let span = CGFloat(costs[index + 1] - costs[index])
            let progress = span > 0 ? CGFloat(balance - costs[index]) / span : 0
            return y(atIndex: index, in: height)
                + (y(atIndex: index + 1, in: height) - y(atIndex: index, in: height)) * progress
        }
        return height
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LP.Content.quarternary.opacity(0.25))
                    .frame(width: 3, height: height)
                    .offset(x: 6)

                Capsule()
                    .fill(LP.Fill.foundationAccent)
                    .frame(width: 3, height: fillHeight(in: height))
                    .offset(x: 6)

                ForEach(Array(costs.enumerated()), id: \.offset) { index, cost in
                    let reached = balance >= cost
                    HStack(spacing: 3) {
                        Circle()
                            .fill(reached ? LP.Fill.foundationAccent : LP.Content.quarternary)
                            .frame(width: 7, height: 7)
                        Text("\(cost)")
                            .lpText(LP.Typography.c2Medium)
                            .foregroundStyle(reached ? LP.Content.secondary : LP.Content.quarternary)
                    }
                    .offset(x: 4, y: y(atIndex: index, in: height) - 3.5)
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: balance)
    }
}

// MARK: - 缩略图

/// 缩略图。资产缺失时退化成一个**看得见**的占位 —— 悄悄留一块空白比画错更糟，
/// 排查时根本注意不到。
private struct OrnamentThumbnail: View {
    let ornament: PiboOrnament
    let isLocked: Bool

    var body: some View {
        Group {
            if let image = UIImage(named: ornament.thumbnailImage) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .saturation(isLocked ? 0.15 : 1)
                    .opacity(isLocked ? 0.55 : 1)
            } else {
                RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                    .fill(LP.Content.quarternary.opacity(0.22))
                    .overlay(
                        Image(systemName: "leaf")
                            .font(.system(size: 18))
                            .foregroundStyle(LP.Content.tertiary)
                    )
            }
        }
        .frame(width: 52, height: 52)
    }
}

#Preview {
    BoExchangeSheet()
        .environment(BoLedgerStore())
        .environment(OrnamentUnlockStore())
}
