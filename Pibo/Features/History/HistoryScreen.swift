import SwiftUI

/// A deep-link target inside the history surface — the contract between the
/// notification layer and the tabs beneath it. A notification knows *what it is
/// about*, not which tab currently happens to render it, so it names the card
/// and `HistoryFloorView` decides where that lives.
enum HistoryFocus: Hashable {
    /// The 压力卡. Lives inline on the 原版 tab (the 足迹 tab only reaches it
    /// through a detail sheet, which is a worse landing).
    case stress
}


// MARK: - 历史页全屏容器
//
// The 历史数据页 is now reached by tapping the home's hand-drawn 「足迹」 icon
// (see `HomeView`) — it presents as a full-screen cover instead of riding the old
// 上滑数据二楼 drawer. This wrapper hosts `HistoryFloorView` (首发只有「原版」页；
// 新版足迹页的入口收在 `PiboReleaseScope.footprintsHistory`) over the page surface
// + a close affordance. `floorIsOpen` defaults to `true`, so the history page's
// `WaterSurface` animates whenever this cover is on screen.

struct HistoryScreen: View {
    @Environment(\.dismiss) private var dismiss

    /// Where to land when the surface opens. `nil` = the normal 足迹 entry.
    var focus: HistoryFocus?
    var initialDate: Date?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PixelUIColor.paperDim.ignoresSafeArea()

            HistoryFloorView(focus: focus, initialDate: initialDate)

            Button {
                LPHaptics.tap()
                dismiss()
            } label: {
                Text("×")
                    .font(PixelFont.font(18))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(width: 44, height: 44)
                    .background(PixelUIColor.paper)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    .background { Rectangle().fill(PixelUIColor.shadow).offset(x: 2, y: 2) }
            }
            .buttonStyle(.plain)
            .padding(.trailing, LP.Spacing.xl)
            .padding(.top, LP.Spacing.s)
            .accessibilityLabel(AppLocalization.text("关闭"))
            .accessibilityIdentifier("pibo.history.close")
        }
    }
}

#Preview {
    HistoryScreen()
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(HistoryPreviewData.store)
}
