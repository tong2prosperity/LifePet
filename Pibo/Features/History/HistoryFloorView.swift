import SwiftUI

// MARK: - 二楼内容容器 + 底部 tab bar
//
// Full-screen 足迹 content. During redesign evaluation a native `TabView` keeps
// the new 足迹 page, the untouched original data page, and Pibo customization
// side by side. Once the redesign is approved the 原版 comparison tab can be
// removed without deleting `PiboHistoryView` itself.
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

    private enum FloorTab: Hashable { case footprints, classic, custom }

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
            Tab("自定义", systemImage: "wand.and.stars", value: FloorTab.custom) {
                CustomPiboPage()
            }
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
