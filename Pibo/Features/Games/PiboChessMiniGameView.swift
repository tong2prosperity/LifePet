import PiboChessUI
import SwiftUI

struct PiboChessMiniGameView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PiboChessGameView()
            .overlay(alignment: .topTrailing) {
                Button {
                    LPHaptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LP.Content.secondary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, LP.Spacing.s)
                .padding(.trailing, LP.Spacing.l)
                .accessibilityLabel(AppLocalization.text("关闭国际象棋"))
                .accessibilityIdentifier("chess.close")
            }
            .preferredColorScheme(.light)
    }
}
