#if DEBUG
import SwiftUI

/// The single DEBUG entry on Home: a draggable DEV dot that snaps to the left
/// or right edge. Tapping expands a grouped, searchable command panel; picking
/// a command collapses the panel so the scene keeps running. A status strip
/// explains the last result, ↻ replays it, and a long press offers reset /
/// exit-all. Empty areas pass touches through to the forest.
struct HomeDebugDock: View {
    let status: String
    let onRun: (String) -> String
    let onExitAll: () -> Void

    @State private var preferences = HomeDebugDockPreferences.load()
    @State private var expanded = false
    @State private var query = ""
    @State private var dragOffset: CGSize = .zero
    @State private var lastResult = ""
    @State private var lastCommand: String?
    @State private var statusCollapsed = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dotY = min(max(80, size.height * preferences.verticalFraction), size.height - 80)
            let dotX = preferences.onRightEdge ? size.width - 30 : 30
            ZStack(alignment: .topLeading) {
                if expanded {
                    panel(width: min(360, size.width - 24))
                        .frame(maxWidth: .infinity, maxHeight: size.height * 0.62, alignment: .top)
                        .padding(.top, 60)
                        .transition(.opacity)
                }
                if !lastResult.isEmpty || !status.isEmpty {
                    statusStrip
                        // Beside the dot and pushed toward the edge so it never
                        // covers Pibo's face in the middle of the stage.
                        .position(
                            x: preferences.onRightEdge ? size.width - 136 : 136,
                            y: dotY + 42
                        )
                }
                dot
                    .position(x: dotX + dragOffset.width, y: dotY + dragOffset.height)
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { value in
                                let x = dotX + value.translation.width
                                let y = dotY + value.translation.height
                                preferences.onRightEdge = x > size.width / 2
                                preferences.verticalFraction = Double(min(max(0.1, y / max(1, size.height)), 0.9))
                                preferences.save()
                                dragOffset = .zero
                            }
                    )
            }
        }
    }

    private var dot: some View {
        Text("DEV")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.black.opacity(0.62)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .contentShape(Circle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } }
            .contextMenu {
                if let lastCommand {
                    Button("重播上次操作") { run(lastCommand) }
                }
                Button("重置当前") { if let lastCommand { run(lastCommand) } }
                Button("退出全部调试", role: .destructive) {
                    onExitAll()
                    lastResult = "已退出全部调试"
                    lastCommand = nil
                }
            }
            .accessibilityLabel("开发调试面板")
    }

    private var statusStrip: some View {
        HStack(spacing: 6) {
            if !statusCollapsed {
                Text(lastResult.isEmpty ? status : lastResult)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            if lastCommand != nil {
                Button { if let lastCommand { run(lastCommand) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            Button { statusCollapsed.toggle() } label: {
                Image(systemName: statusCollapsed ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .frame(maxWidth: 260)
    }

    private func panel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索调试工具", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HomeDebugToolCatalog.groups, id: \.self) { group in
                        Button(group) {
                            preferences.lastGroup = group
                            preferences.save()
                            query = ""
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(preferences.lastGroup == group && query.isEmpty
                            ? Color.green.opacity(0.85) : Color.gray.opacity(0.18)))
                        .foregroundStyle(preferences.lastGroup == group && query.isEmpty ? .white : .primary)
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(HomeDebugToolCatalog.filter(
                        group: preferences.lastGroup, query: query, recents: preferences.recents
                    )) { tool in
                        Button { run(tool.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(.system(size: 14, weight: .medium))
                                Text(tool.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
    }

    private func run(_ id: String) {
        preferences.noteUsed(id)
        preferences.save()
        lastCommand = id
        withAnimation(.easeOut(duration: 0.15)) { expanded = false }
        let result = onRun(id)
        lastResult = result.isEmpty ? (HomeDebugToolCatalog.tool(id)?.title ?? id) : result
    }
}
#endif
