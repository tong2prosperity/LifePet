import PiboCore
import SwiftUI

/// One forest object, reached by tapping that object's grey in-world form. The
/// sheet explains the object and its actual entitlement; it is not a catalogue
/// or a second unlock-progress window.
struct OrnamentAwakeningSheet: View {
    let ornamentID: PiboOrnament.ID

    @Environment(BoLedgerStore.self) private var ledger
    @Environment(OrnamentUnlockStore.self) private var unlocks
    @Environment(\.dismiss) private var dismiss
    @State private var failureMessage: String?

    private var ornament: PiboOrnament? {
        PiboOrnament.ornament(ornamentID)
    }

    var body: some View {
        ScrollView {
            if let ornament {
                VStack(spacing: LP.Spacing.l) {
                    PiboMossSheetHandle()
                    objectHeader(ornament)
                    behaviorList(ornament)

                    Text(permissionNote(for: ornament.id))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    costRow(ornament)

                    if let failureMessage {
                        Label(failureMessage, systemImage: "exclamationmark.circle")
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(PiboMoss.Color.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: LP.Spacing.s) {
                        PiboMossPrimaryButton(
                            title: AppLocalization.format("唤醒%@", ornament.localizedName),
                            disabledReason: disabledReason(for: ornament),
                            isEnabled: canAwaken(ornament),
                            action: awaken
                        )
                        PiboMossSecondaryButton(
                            title: AppLocalization.text("关闭"),
                            action: { dismiss() }
                        )
                    }
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.top, LP.Spacing.m)
                .padding(.bottom, LP.Spacing.xxl)
            } else {
                ContentUnavailableView(
                    AppLocalization.text("物件不可用"),
                    systemImage: "leaf"
                )
                .padding(LP.Spacing.xl)
            }
        }
        .foregroundStyle(PiboMoss.Color.forestInk)
        .piboMossSheet(detents: [.fraction(0.72), .large])
    }

    private func objectHeader(_ ornament: PiboOrnament) -> some View {
        HStack(alignment: .center, spacing: LP.Spacing.l) {
            OrnamentArtwork(
                ornament: ornament,
                locked: !unlocks.isUnlocked(ornament.id)
            )
            .frame(width: 104, height: 116)
            .padding(LP.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .fill(PiboMoss.Color.raisedNeutral.opacity(0.54))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .strokeBorder(PiboMoss.Color.hairline.opacity(0.55), lineWidth: 1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text(AppLocalization.text(
                    unlocks.isUnlocked(ornament.id)
                        ? "共同物件"
                        : "共同物件 · 未唤醒"
                ))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(PiboMoss.Color.secondaryInk)

                Text(ornament.localizedName)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .accessibilityAddTraits(.isHeader)

                Text(capability(for: ornament.id))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func behaviorList(_ ornament: PiboOrnament) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(behaviorDetails(for: ornament.id).enumerated()), id: \.offset) { index, detail in
                HStack(alignment: .top, spacing: LP.Spacing.m) {
                    Text(AppLocalization.text(index == 0 ? "新行为" : "同时开放"))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                        .frame(width: 68, alignment: .leading)

                    Text(detail)
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, LP.Spacing.m)
                .overlay(alignment: .bottom) {
                    if index < behaviorDetails(for: ornament.id).count - 1 {
                        Rectangle()
                            .fill(PiboMoss.Color.hairline.opacity(0.48))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func costRow(_ ornament: PiboOrnament) -> some View {
        HStack(spacing: LP.Spacing.s) {
            PiboBoGlyph()
                .frame(width: 18, height: 26)
                .accessibilityHidden(true)

            Text(costLine(for: ornament))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(canAwaken(ornament)
                                 ? PiboMoss.Color.stepsGreen
                                 : PiboMoss.Color.secondaryInk)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func canAwaken(_ ornament: PiboOrnament) -> Bool {
        unlocks.state(ornament.id, balance: ledger.balance) == .purchasable
    }

    private func costLine(for ornament: PiboOrnament) -> String {
        if unlocks.isUnlocked(ornament.id) {
            return AppLocalization.text("已经在森林中")
        }
        if let prerequisite = prerequisite(for: ornament),
           !unlocks.isUnlocked(prerequisite.id) {
            return AppLocalization.format("需要先唤醒%@", prerequisite.localizedName)
        }
        let missing = max(0, ornament.cost - ledger.balance)
        if missing > 0 {
            return AppLocalization.format(
                "还需要 %d bo · 当前 %d bo",
                missing,
                ledger.balance
            )
        }
        return AppLocalization.format(
            "需要 %d bo · 当前 %d bo",
            ornament.cost,
            ledger.balance
        )
    }

    private func disabledReason(for ornament: PiboOrnament) -> String? {
        if unlocks.isUnlocked(ornament.id) { return AppLocalization.text("已经唤醒") }
        if let prerequisite = prerequisite(for: ornament),
           !unlocks.isUnlocked(prerequisite.id) {
            return AppLocalization.format("先唤醒%@", prerequisite.localizedName)
        }
        let missing = max(0, ornament.cost - ledger.balance)
        if missing > 0 { return AppLocalization.format("还需要 %d bo", missing) }
        return AppLocalization.text("暂时不能唤醒")
    }

    private func prerequisite(for ornament: PiboOrnament) -> PiboOrnament? {
        guard let coreID = PiboOrnament.coreDefinition(ornament.id).prerequisiteID,
              let id = PiboOrnament.ID.allCases.first(where: { $0.coreID == coreID }) else {
            return nil
        }
        return PiboOrnament.ornament(id)
    }

    private func awaken() {
        guard let ornament, canAwaken(ornament) else { return }
        Analytics.track(.boUnlockAttempt, screen: "home_ornament", [
            "item": .string(ornament.id.rawValue),
            "balance": .int(ledger.balance),
        ])
        switch unlocks.purchase(ornament.id, using: ledger) {
        case .purchased:
            unlocks.markUnlockGuideSeen()
            LPHaptics.success()
            Analytics.track(.boUnlock, screen: "home_ornament", [
                "item": .string(ornament.id.rawValue),
                "balance": .int(ledger.balance),
            ])
            dismiss()
        case .insufficientBalance:
            failureMessage = AppLocalization.text("bo 数量不足，成熟后再回来。")
        case .prerequisiteMissing:
            failureMessage = AppLocalization.text("需要先唤醒前一件共同物件。")
        case .unavailable:
            failureMessage = AppLocalization.text("这件物件暂时还不能唤醒。")
        case .alreadyOwned:
            dismiss()
        }
    }

    private func capability(for id: PiboOrnament.ID) -> String {
        switch id {
        case .hammock: AppLocalization.text("睡眠回顾与睡醒通知")
        case .chime: AppLocalization.text("把一次步行留成 Walk Doodle")
        case .statusObserver: AppLocalization.text("查看由真实健康记录校准的恢复状态")
        case .lantern: AppLocalization.text("亲手点亮森林里的铃兰灯")
        }
    }

    private func behaviorDetails(for id: PiboOrnament.ID) -> [String] {
        switch id {
        case .hammock:
            [
                AppLocalization.text("睡眠回顾：在 App 内查看最近一次睡眠"),
                AppLocalization.text("睡醒通知：每天睡醒后提醒你查看"),
            ]
        case .chime:
            [AppLocalization.text("Walk Doodle：记录一次步行，把路线留成地图上的线条")]
        case .statusObserver:
            [AppLocalization.text("恢复状态：依据已授权的原始记录等待数据或校准")]
        case .lantern:
            [AppLocalization.text("魔法点灯：亲手点亮森林里的铃兰灯")]
        }
    }

    private func permissionNote(for id: PiboOrnament.ID) -> String {
        switch id {
        case .hammock:
            AppLocalization.text("需要已授权的睡眠记录。拒绝通知权限仍可在 App 内查看睡眠回顾。")
        case .chime:
            AppLocalization.text("精确定位权限只会在使用 Walk Doodle 时请求。")
        case .statusObserver:
            AppLocalization.text("只使用已授权的原始健康记录；数据不足时不会生成恢复分数。")
        case .lantern:
            AppLocalization.text("无需新增权限。")
        }
    }
}
