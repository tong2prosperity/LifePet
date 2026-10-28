import SwiftUI

/// One skippable invitation after meeting Pibo, plus a permanent Settings entry.
struct AccountInvitationCard: View {
    let onLogin: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.text("也可以先登录 Pibo"))
                .font(PixelFont.font(17))
            Text(AppLocalization.text("账号用于餐食识别。你也可以先开始相处，之后在设置里登录。"))
                .font(.system(size: 14))
                .foregroundStyle(PixelUIColor.inkSoft)
            HStack(spacing: 10) {
                PixelButton(label: AppLocalization.text("登录 Pibo"), buttonID: "account-invitation-login", onTap: onLogin)
                PixelButton(label: AppLocalization.text("先开始相处"), primary: false,
                            buttonID: "account-invitation-skip", onTap: onSkip)
            }
        }
        .foregroundStyle(PixelUIColor.ink)
        .padding(16)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .accessibilityIdentifier("account-invitation")
    }
}
