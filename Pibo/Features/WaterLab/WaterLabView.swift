import SwiftUI
#if DEBUG
import SpriteKit

/// DEV controls for the exact SpriteKit river used by production Home. This
/// intentionally owns no second renderer: sliders update the production water
/// shaders and reflection projection on `PiboStageScene` directly.
struct WaterLabView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var speed: Double = 0.62
    @State private var rippleStrength: Double = 0.70
    @State private var highlightStrength: Double = 0.78
    @State private var reflectionIntensity: Double = 1.00
    @State private var reflectionCompression: Double = 0.52
    @State private var reflectionTipScale: Double = 0.72
    @State private var showMask = false
    @State private var isPaused = false
    @State private var controlsExpanded = true

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let argument = arguments.first(where: {
            $0.hasPrefix("-PiboWaterReflectionIntensity=")
        }) {
            let value = argument.dropFirst("-PiboWaterReflectionIntensity=".count)
            if let intensity = Double(value) {
                _reflectionIntensity = State(initialValue: min(max(intensity, 0), 1.6))
            }
        }

        // Deterministic screenshot preset used to compare reflection-on and
        // reflection-off renders. It is intentionally DEBUG-only with this view.
        if arguments.contains("-PiboWaterLabCapture") {
            _isPaused = State(initialValue: true)
            _controlsExpanded = State(initialValue: false)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LP.Fill.bgSurface.ignoresSafeArea()

                WaterLabScene(
                    containerSize: geo.size,
                    speed: speed,
                    rippleStrength: rippleStrength,
                    highlightStrength: highlightStrength,
                    reflectionIntensity: reflectionIntensity,
                    reflectionCompression: reflectionCompression,
                    reflectionTipScale: reflectionTipScale,
                    showMask: showMask,
                    isPaused: isPaused
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    toolbar
                    Spacer()
                    controls
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.top, LP.Spacing.s)
                .padding(.bottom, LP.Spacing.m)
            }
        }
        .preferredColorScheme(.light)
        .statusBarHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: LP.Spacing.s) {
            Button {
                LPHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LP.Content.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LP.Fill.bgContainer.opacity(0.88)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭流水实验")

            Spacer(minLength: 0)

            Toggle(isOn: $showMask) {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .semibold))
            }
            .toggleStyle(.button)
            .tint(LP.Fill.foundationAccent)
            .accessibilityLabel("显示水区遮罩")

            Button {
                LPHaptics.tap()
                isPaused.toggle()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LP.Content.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LP.Fill.bgContainer.opacity(0.88)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "播放水流" : "暂停水流")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Button {
                LPHaptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    controlsExpanded.toggle()
                }
            } label: {
                HStack(spacing: LP.Spacing.s) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("生产流水实验")
                            .lpText(LP.Typography.uiH4)
                            .foregroundStyle(LP.Content.primary)
                        if !controlsExpanded {
                            Text("流速 \(speed, format: .number.precision(.fractionLength(2))) · 折射 \(rippleStrength, format: .number.precision(.fractionLength(2))) · 高光 \(highlightStrength, format: .number.precision(.fractionLength(2)))")
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LP.Content.secondary)
                        .rotationEffect(.degrees(controlsExpanded ? 0 : 180))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(LP.Fill.bgSurfaceSecondary.opacity(0.75)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controlsExpanded ? "折叠调节面板" : "展开调节面板")

            if controlsExpanded {
                Text("首页同一套分层素材；倒影网格与水面高光都限制在溪流 alpha 遮罩内。")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                controlSlider("流速", value: $speed, range: 0.15...1.40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("折射", value: $rippleStrength, range: 0.00...1.25)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("高光", value: $highlightStrength, range: 0.00...1.30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("倒影强度", value: $reflectionIntensity, range: 0.00...1.60)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("纵向压缩", value: $reflectionCompression, range: 0.25...0.85)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("远端宽度", value: $reflectionTipScale, range: 0.45...1.00)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(LP.Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: LP.BorderWidth.hair)
        )
    }

    private func controlSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(LP.Fill.foundationAccent)
        }
    }
}

private struct WaterLabScene: View {
    var containerSize: CGSize
    var speed: Double
    var rippleStrength: Double
    var highlightStrength: Double
    var reflectionIntensity: Double
    var reflectionCompression: Double
    var reflectionTipScale: Double
    var showMask: Bool
    var isPaused: Bool

    @State private var scene = PiboStageScene(size: CGSize(width: 390, height: 760))

    var body: some View {
        PiboStageRenderView(scene: scene, preferredFramesPerSecond: isPaused ? 1 : 60)
            .frame(width: containerSize.width, height: containerSize.height)
            .clipped()
            .onAppear { configureScene() }
            .onChange(of: containerSize) { _, _ in configureScene() }
            .onChange(of: speed) { _, _ in updateWater() }
            .onChange(of: rippleStrength) { _, _ in updateWater() }
            .onChange(of: highlightStrength) { _, _ in updateWater() }
            .onChange(of: reflectionIntensity) { _, _ in updateWater() }
            .onChange(of: reflectionCompression) { _, _ in updateWater() }
            .onChange(of: reflectionTipScale) { _, _ in updateWater() }
            .onChange(of: showMask) { _, _ in updateWater() }
            .onChange(of: isPaused) { _, paused in
                scene.isPaused = paused
            }
    }

    private func configureScene() {
        if containerSize.width > 1, containerSize.height > 1 { scene.size = containerSize }
        scene.apply(theme: .forest, state: .idle, growth: .sprouted)
        scene.setEnvironment(.daylight)
        scene.setLowPowerMode(false)
        scene.isPaused = isPaused
        updateWater()
    }

    private func updateWater() {
        scene.setWaterDebugTuning(
            speed: speed,
            rippleStrength: rippleStrength,
            highlightStrength: highlightStrength,
            reflectionIntensity: reflectionIntensity,
            reflectionCompression: reflectionCompression,
            reflectionTipScale: reflectionTipScale,
            showMask: showMask
        )
    }
}

#Preview {
    WaterLabView()
}
#endif
