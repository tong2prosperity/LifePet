import Foundation
import SwiftUI

/// Figma 6444:41862 的独立物品解锁页。
///
/// 三件物品严格沿「吊床 → 补梦风铃 → 铃兰灯」顺序开放。价格继续取自
/// `PiboOrnament`，页面不复制数值规则。
struct BoUnlockPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BoLedgerStore.self) private var ledger
    @Environment(OrnamentUnlockStore.self) private var unlocks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded: PiboOrnament.ID?

    private var ornaments: [PiboOrnament] { PiboOrnament.ordered }

    /// Component geometry from the linked Figma states. The 24pt card radius is
    /// also the house radius on the history surface; keeping it local avoids
    /// changing the global `xxl` token, which is 36pt in the newer UI-kit ramp.
    private enum Layout {
        static let cardRadius: CGFloat = 24
        static let timelineLeading: CGFloat = 27
        static let timelineWidth: CGFloat = 24
        static let timelineGap: CGFloat = 10
        static let railWidth: CGFloat = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            balanceBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: LP.Spacing.l) {
                    ForEach(ornaments) { ornament in
                        ornamentStep(ornament)
                    }

                    HStack(spacing: Layout.timelineGap) {
                        timelineDot(reached: false)
                        Text(AppLocalization.text("更多道具上线中......"))
                            .lpText(LP.Typography.b1Medium)
                            .foregroundStyle(LP.Content.quarternary)
                    }
                    .padding(.top, LP.Spacing.xxl4)
                    .padding(.bottom, LP.Spacing.xxl)
                }
                .background(alignment: .topLeading) {
                    Capsule()
                        .fill(LP.Neutral.grey250.opacity(0.72))
                        .frame(width: Layout.railWidth)
                        .padding(.leading, (Layout.timelineWidth - Layout.railWidth) / 2)
                        .padding(.top, 49)
                }
                .padding(.leading, Layout.timelineLeading)
                .padding(.trailing, LP.Spacing.xl)
                .padding(.top, LP.Spacing.xxl)
            }
        }
        .background(LP.Fill.bgSurfaceSecondary.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            unlocks.markUnlockGuideSeen()
            if expanded == nil {
                expanded = unlocks.nextLocked?.id ?? ornaments.last?.id
            }
        }
    }

    private var pageHeader: some View {
        ZStack {
            Text(AppLocalization.text("兑换道具"))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.secondary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LP.Content.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("返回"))
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, LP.Spacing.m)
        .padding(.top, LP.Spacing.s)
    }

    private var balanceBar: some View {
        HStack {
            Text(AppLocalization.text("当前bo数"))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer()
            HStack(spacing: LP.Spacing.xs) {
                PiboBoGlyph()
                    .frame(width: 26, height: 36)
                Text(AppLocalization.format("%d bo", ledger.balance))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Colorful.teal600)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, LP.Spacing.m)
            .frame(height: 36)
            .background(Capsule().fill(LP.Fill.bgContainer))
        }
        .padding(.leading, 30)
        .padding(.trailing, LP.Spacing.xl)
        .padding(.top, LP.Spacing.xl)
    }

    private func ornamentStep(_ ornament: PiboOrnament) -> some View {
        let unlocked = unlocks.isUnlocked(ornament.id)
        let canUnlock = unlocks.canUnlock(ornament.id, balance: ledger.balance)
        let isExpanded = expanded == ornament.id

        return HStack(alignment: .top, spacing: Layout.timelineGap) {
            timelineDot(reached: unlocked || ledger.balance >= ornament.cost)
                .padding(.top, 41)

            Group {
                if isExpanded {
                    expandedCard(
                        ornament,
                        unlocked: unlocked,
                        canUnlock: canUnlock
                    )
                } else {
                    collapsedCard(
                        ornament,
                        unlocked: unlocked,
                        canUnlock: canUnlock
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .strokeBorder(LP.Border.secondary, lineWidth: LP.BorderWidth.hair)
            )
        }
    }

    private func expandedCard(
        _ ornament: PiboOrnament,
        unlocked: Bool,
        canUnlock: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            ZStack(alignment: .topTrailing) {
                expandedArtwork(ornament, locked: !unlocked)
                statusControl(ornament, unlocked: unlocked, canUnlock: canUnlock)
                    .padding(.top, LP.Spacing.s)
                    .padding(.trailing, LP.Spacing.s)
            }

            Text(ornament.localizedName)
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Colorful.teal600)

            Text(compactEntry(ornament.localizedEntry))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expanded = nil
                }
            } label: {
                Label(AppLocalization.text("收起"), systemImage: "chevron.up")
                    .labelStyle(.titleAndIcon)
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Colorful.teal500)
            }
            .buttonStyle(.plain)
        }
        .padding(LP.Spacing.l)
    }

    private func collapsedCard(
        _ ornament: PiboOrnament,
        unlocked: Bool,
        canUnlock: Bool
    ) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expanded = ornament.id
                }
            } label: {
                HStack(spacing: LP.Spacing.l) {
                    OrnamentThumbnail(ornament: ornament, isLocked: !unlocked)
                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        Text(ornament.localizedName)
                            .lpText(LP.Typography.b1Medium)
                            .foregroundStyle(LP.Colorful.teal600)
                        Text(AppLocalization.format("%d bo", ornament.cost))
                            .lpText(LP.Typography.b1Medium)
                            .foregroundStyle(LP.Content.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppLocalization.text("查看"))

            statusControl(ornament, unlocked: unlocked, canUnlock: canUnlock)
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.vertical, LP.Spacing.l)
        .frame(minHeight: 98)
    }

    private func compactEntry(_ text: String) -> String {
        text.replacingOccurrences(of: "\n\n", with: "\n")
    }

    private func expandedArtwork(_ ornament: PiboOrnament, locked: Bool) -> some View {
        OrnamentThumbnail(
            ornament: ornament,
            isLocked: locked,
            size: CGSize(width: 224, height: 168)
        )
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusControl(
        _ ornament: PiboOrnament,
        unlocked: Bool,
        canUnlock: Bool
    ) -> some View {
        if unlocked {
            statusPill("已解锁", foreground: LP.Colorful.teal600,
                       background: LP.Colorful.green500.opacity(0.1))
        } else if canUnlock {
            Button {
                guard unlocks.purchase(ornament.id, using: ledger) == .purchased else { return }
                LPHaptics.success()
                Analytics.track(.boUnlock, screen: "bo_unlock",
                                ["ornament": .string(ornament.id.rawValue),
                                 "cost": .int(ornament.cost)])
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expanded = unlocks.nextLocked?.id ?? ornament.id
                }
            } label: {
                statusPill("解锁", foreground: LP.Fill.foundationOnAccent,
                           background: LP.Fill.foundationAccent)
            }
            .buttonStyle(.plain)
        } else {
            statusPill("待解锁", foreground: LP.Neutral.grey500,
                       background: Color.black.opacity(0.05))
        }
    }

    private func statusPill(
        _ text: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Text(AppLocalization.text(text))
            .lpText(LP.Typography.b4Medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
    }

    private func timelineDot(reached: Bool) -> some View {
        Circle()
            .fill(reached ? LP.Fill.foundationAccent : LP.Content.quarternary)
            .frame(width: 16, height: 16)
            .frame(width: Layout.timelineWidth)
    }
}

private struct OrnamentThumbnail: View {
    let ornament: PiboOrnament
    let isLocked: Bool
    let size: CGSize

    init(
        ornament: PiboOrnament,
        isLocked: Bool,
        size: CGSize = CGSize(width: 64, height: 64)
    ) {
        self.ornament = ornament
        self.isLocked = isLocked
        self.size = size
    }

    var body: some View {
        Group {
            if let image = UIImage(named: ornament.thumbnailImage) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .saturation(isLocked ? 0.15 : 1)
                    .opacity(isLocked ? 0.3 : 1)
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: min(size.width, size.height) > 64 ? 40 : 24))
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        BoUnlockPage()
            .environment(BoLedgerStore())
            .environment(OrnamentUnlockStore())
    }
}
