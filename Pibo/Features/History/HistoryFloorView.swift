import SwiftUI

// MARK: - 二楼内容容器 + 底部 tab bar
//
// Full-screen 足迹 content. During redesign evaluation a native `TabView` keeps
// the new 足迹 page and the untouched original data page side by side. Pibo
// customization remains implemented, but its release entry is temporarily hidden.
//
// Using the system `TabView` + `Tab` API (rather than a hand-rolled bar) is what
// lets iOS 26 render its Liquid Glass floating tab bar automatically — material,
// shape, scroll-edge behavior and safe-area insets all come for free. The pages
// keep their own top padding to clear the drawer's close band; the bottom inset
// for the tab bar is handled by the system.

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
        TabView(selection: $selection) {
            Tab("足迹", systemImage: "sparkles", value: FloorTab.footprints) {
                PiboFootprintsView()
            }
            Tab("原版", systemImage: "chart.bar.xaxis", value: FloorTab.classic) {
                PiboHistoryView(focus: focus)
            }
            // 「自定义」tab（`CustomPiboPage`）在首发范围外，入口暂时收起。页面本身
            // 原样保留 —— 恢复时加回一个 `.custom` case 和这里的 `Tab` 即可。
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
