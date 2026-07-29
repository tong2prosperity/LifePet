#if DEBUG
import SpriteKit
import SwiftUI

/// Character Lab 的外壳。启动参数 `-PiboCharacterLab` 直接进来。
///
/// 免点击取证：
/// ```
/// xcrun simctl launch <dev> fun.tiebao.co.Pibo -PiboCharacterLab \
///     -PiboLabState muscle -PiboLabZoom 2
/// xcrun simctl io <dev> screenshot /tmp/lab.png
/// ```
struct CharacterLabView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var scene = CharacterLabScene(size: CGSize(width: 393, height: 852))
    @State private var stateID = "default"
    @State private var zoom: Double = 1
    @State private var warpProbe = true
    @State private var autoCycle = false

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                SpriteView(
                    scene: scene,
                    preferredFramesPerSecond: 60,
                    debugOptions: [.showsFPS, .showsDrawCount, .showsNodeCount]
                )
                .onChange(of: geometry.size, initial: true) { _, size in
                    scene.size = size
                }
            }
            .ignoresSafeArea()

            controls
        }
        .onAppear(perform: applyLaunchArguments)
        .onChange(of: stateID) { _, value in scene.request(stateID: value) }
        .onChange(of: zoom) { _, value in scene.zoom = value }
        .onChange(of: warpProbe) { _, value in scene.warpProbe = value }
        .onChange(of: autoCycle) { _, value in scene.autoCycle = value }
        .preferredColorScheme(.light)
    }

    private func applyLaunchArguments() {
        if let raw = Self.argument("-PiboLabZoom"), let value = Double(raw) {
            zoom = min(max(value, 0.5), 4)
        }
        scene.zoom = zoom
        if ProcessInfo.processInfo.arguments.contains("-PiboLabNoWarp") { warpProbe = false }
        scene.warpProbe = warpProbe
        if ProcessInfo.processInfo.arguments.contains("-PiboLabCycle") { autoCycle = true }
        scene.autoCycle = autoCycle
        if ProcessInfo.processInfo.arguments.contains("-PiboLabReflection") {
            scene.showReflectionProxy = true
        }
        if ProcessInfo.processInfo.arguments.contains("-PiboLabCelebrate") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                scene.playWorkoutCelebration()
            }
        }
        // 状态请求必须在场景 didMove 之后 —— 那时 stateIDs 才建好。
        if let raw = Self.argument("-PiboLabState") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                stateID = raw
                scene.request(stateID: raw)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Character Lab").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }

            Picker("状态", selection: $stateID) {
                ForEach(scene.stateIDs, id: \.self) { id in
                    Text(id.replacingOccurrences(of: "sleep-", with: "s")).tag(id)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 2) {
                Text("放大（真实重建）  \(zoom, specifier: "%.2f")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Slider(value: $zoom, in: 0.5 ... 4)
            }

            HStack(spacing: 16) {
                Toggle("warp 探针", isOn: $warpProbe).fixedSize()
                Toggle("自动巡演", isOn: $autoCycle).fixedSize()
                Button("运动完成") { scene.playWorkoutCelebration() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .font(.footnote)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)
    }
}
#endif
