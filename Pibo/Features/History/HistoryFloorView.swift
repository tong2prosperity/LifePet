import SwiftUI

// MARK: - 二楼内容容器 + 底部 tab bar
//
// The pull-up 数据二楼's content. A **native `TabView`** switches between the
// 历史数据页 (`PiboHistoryView`) and the 自定义 Pibo 页 (`CustomPiboPage`).
//
// Using the system `TabView` + `Tab` API (rather than a hand-rolled bar) is what
// lets iOS 26 render its Liquid Glass floating tab bar automatically — material,
// shape, scroll-edge behavior and safe-area insets all come for free. The pages
// keep their own top padding to clear the drawer's close band; the bottom inset
// for the tab bar is handled by the system.

struct HistoryFloorView: View {
    var body: some View {
        TabView {
            Tab("数据", systemImage: "chart.bar.xaxis") {
                PiboHistoryView()
            }
            Tab("自定义", systemImage: "wand.and.stars") {
                CustomPiboPage()
            }
        }
    }
}

#Preview {
    HistoryFloorView()
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}
