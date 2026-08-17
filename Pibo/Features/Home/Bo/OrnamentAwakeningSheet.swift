import PiboCore
import SwiftUI

/// One forest object, reached by tapping that object's grey in-world form.
/// This is deliberately not a catalogue or a separate progress surface.
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
        NavigationStack {
            Group {
                if let ornament {
                    VStack(alignment: .leading, spacing: LP.Spacing.l) {
                        HStack(alignment: .center, spacing: LP.Spacing.l) {
                            OrnamentArtwork(ornament: ornament, locked: true)
                                .frame(width: 104, height: 116)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                                Text(AppLocalization.format("%@（未唤醒）", ornament.localizedName))
                                    .lpText(LP.Typography.uiH5)
                                    .foregroundStyle(LP.Content.primary)
                                    .accessibilityAddTraits(.isHeader)
                                Text(capability(for: ornament.id))
                                    .lpText(LP.Typography.b3Regular)
                                    .foregroundStyle(LP.Content.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text(AppLocalization.format(
                            "需要 %d bo · 当前 %d bo",
                            ornament.cost,
                            ledger.balance
                        ))
                        .lpText(LP.Typography.b1Medium)
                        .foregroundStyle(LP.Content.accent)
                        .monospacedDigit()

                        if let failureMessage {
                            Label(failureMessage, systemImage: "exclamationmark.circle")
                                .lpText(LP.Typography.b4Medium)
                                .foregroundStyle(LP.Content.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Button(action: awaken) {
                            Text(primaryButtonLabel(for: ornament))
                                .lpText(LP.Typography.b1Medium)
                                .foregroundStyle(canAwaken(ornament) ? LP.Fill.foundationOnAccent : LP.Content.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                                        .fill(canAwaken(ornament)
                                              ? LP.Fill.foundationAccent
                                              : LP.Fill.bgContainer)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAwaken(ornament))
                    }
                    .padding(.horizontal, LP.Spacing.xl)
                    .padding(.top, LP.Spacing.m)
                    .padding(.bottom, LP.Spacing.l)
                } else {
                    ContentUnavailableView(
                        AppLocalization.text("物件不可用"),
                        systemImage: "leaf"
                    )
                }
            }
            .background(LP.Fill.bgSurface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.text("关闭")) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func canAwaken(_ ornament: PiboOrnament) -> Bool {
        unlocks.state(ornament.id, balance: ledger.balance) == .purchasable
    }

    private func primaryButtonLabel(for ornament: PiboOrnament) -> String {
        switch unlocks.state(ornament.id, balance: ledger.balance) {
        case .purchasable:
            AppLocalization.format("唤醒%@", ornament.localizedName)
        case .owned:
            AppLocalization.text("已经唤醒")
        case .eligible:
            AppLocalization.format("还需要 %d bo", max(0, ornament.cost - ledger.balance))
        case .unavailable:
            AppLocalization.text("暂时不能唤醒")
        }
    }

    private func awaken() {
        guard let ornament, unlocks.nextLocked?.id == ornament.id else { return }
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
        case .hammock:
            AppLocalization.text("唤醒后，Pibo 睡觉或疲惫时可以使用吊床。")
        case .chime:
            AppLocalization.text("唤醒后，可以把一次步行留成 Walk Doodle。")
        case .statusObserver:
            AppLocalization.text("唤醒后，可以查看由真实健康记录校准的恢复状态。")
        case .lantern:
            AppLocalization.text("唤醒后，可以亲手点亮森林里的铃兰灯。")
        }
    }
}
