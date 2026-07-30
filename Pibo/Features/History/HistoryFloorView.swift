import SwiftUI

// MARK: - 二楼内容容器 + 底部 tab bar
//
// Full-screen 足迹 content. 首发只上「原版」`PiboHistoryView`（带云朵睡眠卡）——
// 新版 `PiboFootprintsView` 和自定义形象页 `CustomPiboPage` 都还在，只是入口收在
// `PiboReleaseScope` 里（`footprintsHistory` / `customizePibo`）。
//
// 开关全关时**不套 `TabView`**：只剩一页却挂一条 iOS 26 悬浮 tab bar 很怪，而且
// 白占一块底部安全区。打开 `-PiboEnableFootprints` 后回到两 tab 并排评估的形态，
// 用系统 `TabView` + `Tab`（而不是手搓 bar）是为了让 Liquid Glass 的材质、形状、
// 滚动边缘行为和安全区内边距都自动来。页面各自保留顶部内边距以让开关闭按钮。

struct HistoryFloorView: View {
    /// Deep-link target. Resolved to a tab **in `init`** rather than in
    /// `onAppear`, so a routed open never flashes the default tab first.
    var focus: HistoryFocus?

    @State private var selection: FloorTab

    private enum FloorTab: Hashable { case footprints, classic }

    init(focus: HistoryFocus? = nil) {
        self.focus = focus
        _selection = State(initialValue: focus == .stress ? .classic : .footprints)
    }

    var body: some View {
        if PiboReleaseScope.footprintsHistory {
            TabView(selection: $selection) {
                Tab("足迹", systemImage: "sparkles", value: FloorTab.footprints) {
                    PiboFootprintsView()
                }
                Tab("原版", systemImage: "chart.bar.xaxis", value: FloorTab.classic) {
                    PiboHistoryView(focus: focus)
                }
            }
        } else {
            // 单页形态。`focus` 直接透传，压力卡深链不再需要先切 tab。
            PiboHistoryView(focus: focus)
        }
    }
}

#Preview {
    HistoryFloorView()
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(HistoryPreviewData.store)
}
