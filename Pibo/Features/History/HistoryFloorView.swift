import SwiftUI

// MARK: - 二楼内容容器 + 底部 tab bar
//
// The pull-up 数据二楼's content. Hosts a bottom tab bar that switches between
// the 历史数据页 (`PiboHistoryView`) and the 自定义 Pibo 页 (`CustomPiboPage`).
// Lives between `HomeView`'s `FloorContainer` drawer and the two pages, so the
// pull-up choreography (and its top close band) is untouched — only the content
// gains a tab bar.
//
// The bar is attached via `.safeAreaInset(.bottom)`, so each page's `ScrollView`
// automatically clears it (and stays above the home indicator).

/// The two 二楼 destinations.
enum FloorTab: String, CaseIterable, Identifiable {
    case data, custom
    var id: String { rawValue }
    var title: String { self == .data ? "数据" : "自定义" }
    var icon: String { self == .data ? "chart.bar.xaxis" : "wand.and.stars" }
}

struct HistoryFloorView: View {
    @State private var tab: FloorTab = .custom

    var body: some View {
        Group {
            switch tab {
            case .data:   PiboHistoryView()
            case .custom: CustomPiboPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PiboFloorTabBar(selection: $tab)
        }
    }
}

/// The bottom tab bar — two items, the selected one inked, the fill bleeding to
/// the screen bottom while the labels sit above the home indicator.
struct PiboFloorTabBar: View {
    @Binding var selection: FloorTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FloorTab.allCases) { t in
                let selected = selection == t
                Button {
                    guard selection != t else { return }
                    LPHaptics.tap()
                    withAnimation(.easeInOut(duration: 0.2)) { selection = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .regular))
                        Text(t.title).lpText(LP.Typography.c2Medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? LP.Content.primary : LP.Content.quarternary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .background {
            LP.Fill.bgContainer.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(LP.Separator.primary).frame(height: 0.5)
        }
    }
}

#Preview {
    HistoryFloorView()
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}
