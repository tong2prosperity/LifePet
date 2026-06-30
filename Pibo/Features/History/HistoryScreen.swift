import SwiftUI

// MARK: - 历史页全屏容器
//
// The 历史数据页 is now reached by tapping the home's hand-drawn 「足迹」 icon
// (see `HomeView`) — it presents as a full-screen cover instead of riding the old
// 上滑数据二楼 drawer. This wrapper hosts `HistoryFloorView` (数据 / 自定义 tabs)
// over the #E8EEF1 surface + a close affordance. `floorIsOpen` defaults to `true`,
// so the history page's `WaterSurface` animates whenever this cover is on screen.

struct HistoryScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LP.Fill.bgSurfaceSecondary.ignoresSafeArea()

            HistoryFloorView()

            Button {
                LPHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LP.Content.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LP.Fill.bgContainer))
                    .lpShadow(LP.Shadow.elevation1)
            }
            .buttonStyle(.plain)
            .padding(.trailing, LP.Spacing.xl)
            .padding(.top, LP.Spacing.l)
            .accessibilityLabel(AppLocalization.text("关闭"))
        }
    }
}

#Preview {
    HistoryScreen()
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}
