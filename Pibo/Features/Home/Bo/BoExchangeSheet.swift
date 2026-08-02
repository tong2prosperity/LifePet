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

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            balanceBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: LP.Spacing.m) {
                    ForEach(ornaments) { ornament in
                        ornamentStep(ornament)
                    }

                    HStack(spacing: LP.Spacing.m) {
                        timelineDot(reached: false)
                        Text(AppLocalization.text("更多道具上线中......"))
                            .lpText(LP.Typography.uiH3)
                            .foregroundStyle(LP.Content.quarternary)
                    }
                    .padding(.bottom, LP.Spacing.xxl)
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.top, LP.Spacing.xl)
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
                .lpText(LP.Typography.uiH3)
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
        .padding(.horizontal, LP.Spacing.s)
        .padding(.top, LP.Spacing.s)
    }

    private var balanceBar: some View {
        HStack {
            Text(AppLocalization.text("当前bo数"))
                .lpText(LP.Typography.uiH3)
                .foregroundStyle(LP.Content.secondary)
            Spacer()
            HStack(spacing: LP.Spacing.s) {
                PiboBoGlyph()
                    .frame(width: 26, height: 36)
                Text(AppLocalization.format("%d bo", ledger.balance))
                    .lpText(LP.Typography.uiH3)
                    .foregroundStyle(LP.Content.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 93)
        .background(LP.Fill.bgContainer)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LP.Border.secondary).frame(height: LP.BorderWidth.hair)
        }
    }

    private func ornamentStep(_ ornament: PiboOrnament) -> some View {
        let unlocked = unlocks.isUnlocked(ornament.id)
        let canUnlock = unlocks.canUnlock(ornament.id, balance: ledger.balance)
        let isExpanded = expanded == ornament.id

        return HStack(alignment: .top, spacing: LP.Spacing.m) {
            timelineDot(reached: unlocked || canUnlock)
                .padding(.top, isExpanded ? LP.Spacing.l : 41)

            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                if isExpanded {
                    expandedArtwork(ornament, locked: !unlocked)

                    Text(ornament.localizedName)
                        .lpText(LP.Typography.uiH3)
                        .foregroundStyle(LP.Colorful.teal600)

                    Text(ornament.localizedEntry)
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(LP.Content.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: LP.Spacing.m) {
                        OrnamentThumbnail(ornament: ornament, isLocked: !unlocked)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ornament.localizedName)
                                .lpText(LP.Typography.uiH3)
                                .foregroundStyle(LP.Colorful.teal600)
                            Text(AppLocalization.format("%d bo", ornament.cost))
                                .lpText(LP.Typography.uiH3)
                                .foregroundStyle(LP.Content.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            expanded = isExpanded ? nil : ornament.id
                        }
                    } label: {
                        Label(
                            AppLocalization.text(isExpanded ? "收起" : "查看"),
                            systemImage: isExpanded ? "chevron.up" : "chevron.down"
                        )
                        .labelStyle(.titleAndIcon)
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Colorful.teal500)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                    statusControl(ornament, unlocked: unlocked, canUnlock: canUnlock)
                }
            }
            .padding(LP.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.xxl, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.xxl, style: .continuous)
                    .strokeBorder(LP.Border.secondary, lineWidth: LP.BorderWidth.hair)
            )
        }
    }

    private func expandedArtwork(_ ornament: PiboOrnament, locked: Bool) -> some View {
        OrnamentThumbnail(ornament: ornament, isLocked: locked)
            .frame(width: 224, height: 168)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [LP.Colorful.green500.opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
            )
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
                guard ledger.spend(ornament.cost) else { return }
                unlocks.markUnlocked(ornament.id)
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
            .frame(width: 24)
    }
}

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
                    .opacity(isLocked ? 0.3 : 1)
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: 24))
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(width: 64, height: 64)
    }
}

#Preview {
    NavigationStack {
        BoUnlockPage()
            .environment(BoLedgerStore())
            .environment(OrnamentUnlockStore())
    }
}
