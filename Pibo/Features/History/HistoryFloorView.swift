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
    var body: some View {
        TabView {
            Tab("足迹", systemImage: "sparkles") {
                PiboFootprintsView()
            }
            Tab("原版", systemImage: "chart.bar.xaxis") {
                PiboHistoryView()
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
