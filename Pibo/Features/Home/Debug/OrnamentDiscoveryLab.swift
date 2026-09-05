#if DEBUG
import SwiftUI

/// A side-effect-free rehearsal surface for the common-item discovery motion.
/// It intentionally never calls `unlock`, touches the bo ledger, or advances the
/// persisted discovery checkpoint.
@MainActor
struct OrnamentDiscoveryLab: View {
    private enum MotionMode: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case full = "完整动画"
        case reduce = "减少动态"

        var id: String { rawValue }
    }

    @Environment(OrnamentUnlockStore.self) private var unlocks
    @Environment(\.dismiss) private var dismiss

    @State private var selection = "next"
    @State private var motionMode: MotionMode = .system
    @State private var opacity = 0.42
    @State private var scale: CGFloat = 1
    @State private var glow = 0.0
    @State private var animationTask: Task<Void, Never>?

    private var selectedOrnament: PiboOrnament {
        if selection == "next" {
            return unlocks.nextLocked ?? PiboOrnament.ordered.last!
        }
        return PiboOrnament.ordered.first { $0.id.rawValue == selection }
            ?? PiboOrnament.ordered[0]
    }

    private var reducesMotion: Bool {
        switch motionMode {
        case .system: UIAccessibility.isReduceMotionEnabled
        case .full: false
        case .reduce: true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: LP.Spacing.xl) {
                Spacer(minLength: LP.Spacing.xl)

                preview

                VStack(spacing: LP.Spacing.m) {
                    Picker("物件", selection: $selection) {
                        Text("下一件：\(unlocks.nextLocked?.name ?? "链尾")")
                            .tag("next")
                        ForEach(PiboOrnament.ordered) { ornament in
                            Text(ornament.name).tag(ornament.id.rawValue)
                        }
                    }

                    Picker("动态", selection: $motionMode) {
                        ForEach(MotionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: LP.Spacing.m) {
                    Button("静默显现") { playSilentReveal() }
                        .buttonStyle(.bordered)
                    Button("2.4 秒解锁波") { playUnlockWave() }
                        .buttonStyle(.borderedProminent)
                        .tint(LP.Fill.foundationAccent)
                }

                Text("只预演视觉，不写入物件、bo 或发现进度。")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)

                Spacer(minLength: LP.Spacing.xl)
            }
            .padding(LP.Spacing.xl)
            .background(LP.Fill.bgSurface.ignoresSafeArea())
            .navigationTitle("共同物件发现")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: selection) { _, _ in resetPreview() }
            .onChange(of: motionMode) { _, _ in resetPreview() }
            .onDisappear { animationTask?.cancel() }
        }
    }

    private var preview: some View {
        ZStack {
            Circle()
                .fill(LP.Fill.foundationAccent.opacity(0.16 * glow))
                .frame(width: 250, height: 250)
                .scaleEffect(0.8 + 0.35 * glow)

            Image(selectedOrnament.thumbnailImage)
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .saturation(0.15 + 0.85 * opacity)
                .colorMultiply(Color(red: 0.78, green: 0.94, blue: 0.88))
                .opacity(opacity)
                .scaleEffect(scale)
                .accessibilityLabel(selectedOrnament.name)
        }
        .frame(height: 280)
    }

    private func resetPreview() {
        animationTask?.cancel()
        animationTask = nil
        opacity = 0.42
        scale = 1
        glow = 0
    }

    private func playSilentReveal() {
        animationTask?.cancel()
        opacity = 0
        scale = 0.94
        glow = 0
        guard !reducesMotion else {
            opacity = 0.42
            scale = 1
            return
        }
        withAnimation(.easeOut(duration: 0.72)) {
            opacity = 0.42
            scale = 1
        }
    }

    private func playUnlockWave() {
        animationTask?.cancel()
        opacity = reducesMotion ? 1 : 0
        scale = reducesMotion ? 1 : 0.94
        glow = 0
        guard !reducesMotion else { return }

        animationTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 1
                scale = 1.08
                glow = 1
            }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                scale = 0.98
                glow = 0.3
            }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1
                glow = 0
            }
        }
    }
}
#endif
