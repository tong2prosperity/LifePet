import SwiftUI

struct CommonItemStatusModal: View {
    @Environment(\.dismiss) private var dismiss

    let ornamentID: PiboOrnament.ID
    let title: String
    let status: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            PiboMossSheetHandle()
                .frame(maxWidth: .infinity)

            HStack(spacing: LP.Spacing.l) {
                if let ornament = PiboOrnament.ornament(ornamentID) {
                    OrnamentArtwork(ornament: ornament, locked: false)
                        .frame(width: 96, height: 108)
                        .padding(LP.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: PiboMoss.Radius.media)
                                .fill(PiboMoss.Color.raisedNeutral.opacity(0.54))
                        )
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Text(AppLocalization.text(title))
                        .lpText(LP.Typography.uiH4)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                        .accessibilityAddTraits(.isHeader)

                    Label(AppLocalization.text(status), systemImage: "hourglass")
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }
            }

            Text(AppLocalization.text(message))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(integrityNote)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
                .padding(LP.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                        .fill(PiboMoss.Color.raisedNeutral.opacity(0.52))
                )

            PiboMossPrimaryButton(
                title: AppLocalization.text("回到森林"),
                action: { dismiss() }
            )
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.m)
        .padding(.bottom, LP.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isModal)
        .piboMossSheet(detents: [.medium])
    }

    private var integrityNote: String {
        switch ornamentID {
        case .hammock:
            AppLocalization.text("收到可用的睡眠记录后会自动更新；没有记录不会影响 bo。")
        case .statusObserver:
            AppLocalization.text("数据不足时会继续等待，不会生成恢复分数，也不会影响 bo。")
        case .chime, .lantern:
            AppLocalization.text("当前状态会保留，不会因为缺少数据影响 bo。")
        }
    }
}
