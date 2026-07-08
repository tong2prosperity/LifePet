import SwiftUI

/// DEV page for proving the recommended water workflow:
/// static illustration + stream mask + Metal shader animation. The current
/// source art is `water_lab_scene`, generated from
/// `tmp/generated/pibo_forest_with_flowing_stream.png`.
struct WaterLabView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var speed: Double = 0.62
    @State private var rippleStrength: Double = 0.70
    @State private var highlightStrength: Double = 0.78
    @State private var showMask = false
    @State private var isPaused = false
    @State private var controlsExpanded = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LP.Fill.bgSurface.ignoresSafeArea()

                WaterLabScene(
                    containerSize: geo.size,
                    speed: speed,
                    rippleStrength: rippleStrength,
                    highlightStrength: highlightStrength,
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
                        Text("Metal 流水实验")
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
                Text("背景图保持静态，只在溪流遮罩内做折射、滚动高光和水纹。")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                controlSlider("流速", value: $speed, range: 0.15...1.40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("折射", value: $rippleStrength, range: 0.00...1.25)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                controlSlider("高光", value: $highlightStrength, range: 0.00...1.30)
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
    var showMask: Bool
    var isPaused: Bool

    private let imageSize = CGSize(width: 1320, height: 1760)

    var body: some View {
        let fitted = aspectFillRect(image: imageSize, in: containerSize)
        ZStack {
            Image("water_lab_scene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()

            TimelineView(.animation(paused: isPaused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 120)
                Image("water_lab_scene")
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .layerEffect(
                        ShaderLibrary.flowingStream(
                            .float2(fitted.size),
                            .float(Float(t)),
                            .float(Float(speed)),
                            .float(Float(rippleStrength)),
                            .float(Float(highlightStrength))
                        ),
                        maxSampleOffset: CGSize(width: 18, height: 18)
                    )
                    .frame(width: fitted.width, height: fitted.height)
                    .allowsHitTesting(false)
            }

            if showMask {
                Image("water_lab_scene")
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .colorEffect(ShaderLibrary.streamMaskPreview(.float2(fitted.size)))
                    .frame(width: fitted.width, height: fitted.height)
                    .allowsHitTesting(false)
                    .blendMode(.plusLighter)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
    }

    private func aspectFillRect(image: CGSize, in container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0,
              container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = max(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

#Preview {
    WaterLabView()
}
