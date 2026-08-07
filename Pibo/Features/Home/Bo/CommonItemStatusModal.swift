import SwiftUI

struct CommonItemStatusModal: View {
    @Environment(\.dismiss) private var dismiss

    let ornamentID: PiboOrnament.ID
    let title: String
    let status: String
    let message: String

    var body: some View {
        VStack(spacing: LP.Spacing.l) {
            Capsule()
                .fill(LP.Border.primary)
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            if let ornament = PiboOrnament.ornament(ornamentID) {
                OrnamentArtwork(ornament: ornament, locked: false)
                    .frame(width: 112, height: 126)
                    .accessibilityHidden(true)
            }

            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                    .accessibilityAddTraits(.isHeader)

                Label(AppLocalization.text(status), systemImage: "hourglass")
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.accent)

                Text(AppLocalization.text(message))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                dismiss()
            } label: {
                Text(AppLocalization.text("回到森林"))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LP.Fill.foundationAccent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.s)
        .padding(.bottom, LP.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(LP.Fill.bgSurface)
        .lpDynamicTypeScaling()
        .accessibilityAddTraits(.isModal)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
