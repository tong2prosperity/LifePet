import SwiftUI

enum ShadowFriendHomeEntryState: Equatable {
    case empty
    case attention
    case connected
}

struct ShadowFriendHomeEntry: View {
    let state: ShadowFriendHomeEntryState
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Button(action: action) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "person.2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PiboMoss.Color.forestInk)
                        .frame(width: 44, height: 44)
                        .background(PiboMoss.Color.raisedNeutral.opacity(0.9), in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
                        .shadow(color: SwiftUI.Color(hex: 0x0C3028, alpha: 0.15), radius: 8, y: 3)

                    if state != .empty {
                        Circle()
                            .fill(state == .attention
                                ? SwiftUI.Color(hex: 0xD4A447)
                                : PiboMoss.Color.foundationTeal)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(.white.opacity(0.92), lineWidth: 1.5) }
                    }
                }
            }
            .buttonStyle(.plain)
            // Harmony's frozen design coordinates use a top-left position of
            // (326, 408) for the 44 pt control on a 393×852 artboard.
            .position(
                x: proxy.size.width * 348 / 393,
                y: proxy.size.height * 430 / 852
            )
            .accessibilityLabel("好友 Pibo")
            .accessibilityHint("邀请好友、查看好友 Pibo 或管理连接")
        }
        .allowsHitTesting(true)
    }
}

struct ShadowFriendLightBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(SwiftUI.Color(hex: 0xD4A447))
            Text(text)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)
        }
        .padding(.horizontal, LP.Spacing.l)
        .frame(minHeight: 48)
        .background(PiboMoss.Color.sheetMoss.opacity(0.95), in: Capsule())
        .overlay { Capsule().strokeBorder(PiboMoss.Color.hairline.opacity(0.72)) }
        .shadow(color: SwiftUI.Color(hex: 0x17342B, alpha: 0.17), radius: 10, y: 4)
        .accessibilityLabel(text)
    }
}
