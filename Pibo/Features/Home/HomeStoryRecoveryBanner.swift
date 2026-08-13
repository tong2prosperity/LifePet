import SwiftUI

enum HomeStoryRecoveryPolicy {
    static func shouldShow(
        featureEnabled: Bool,
        needsRecovery: Bool,
        dismissed: Bool,
        scheduleAllowsPresentation: () -> Bool
    ) -> Bool {
        guard featureEnabled, needsRecovery, !dismissed else { return false }
        return scheduleAllowsPresentation()
    }
}

struct HomeStoryRecoveryBanner: View {
    let messageKey: String
    let actionKey: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: LP.Spacing.m) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.narrative(messageKey))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.primary)
                    Text(AppLocalization.narrative(actionKey))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Fill.foundationAccent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LP.Content.tertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.narrative("onboarding.close"))
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s)
        .background(LP.Fill.bgContainer.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .lpShadow(LP.Shadow.elevation2)
    }
}
