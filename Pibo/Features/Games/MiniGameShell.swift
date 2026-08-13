import Foundation
import SwiftUI

struct MiniGameCountdownClock {
    let duration: TimeInterval

    private(set) var isRunning: Bool
    private var elapsedBeforeRun: TimeInterval
    private var runStartedAt: TimeInterval

    init(duration: TimeInterval, startsRunning: Bool = false) {
        self.duration = duration
        self.isRunning = startsRunning
        self.elapsedBeforeRun = 0
        self.runStartedAt = ProcessInfo.processInfo.systemUptime
    }

    mutating func reset(startsRunning: Bool = false) {
        elapsedBeforeRun = 0
        runStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = startsRunning
    }

    mutating func pause(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRunning else { return }
        elapsedBeforeRun = elapsed(at: now)
        runStartedAt = now
        isRunning = false
    }

    mutating func resume(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !isRunning, elapsedBeforeRun < duration else { return }
        runStartedAt = now
        isRunning = true
    }

    func elapsed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        min(
            duration,
            elapsedBeforeRun + (isRunning ? max(0, now - runStartedAt) : 0)
        )
    }

    func secondsLeft(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        max(0, Int(ceil(duration - elapsed(at: now))))
    }
}

struct MiniGameShell<Stage: View, BottomBar: View, Overlay: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isAccessibilityOverlayPresented = false

    let kind: MiniGameKind
    var scoreText: String? = nil
    var detailText: String? = nil
    var onClose: () -> Void
    @ViewBuilder var stage: () -> Stage
    @ViewBuilder var bottomBar: () -> BottomBar
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack {
            MiniGameStageBackground(tint: kind.tint)
                .ignoresSafeArea()

            GeometryReader { proxy in
                if proxy.size.width > proxy.size.height * 1.15 {
                    landscapeLayout(width: proxy.size.width)
                } else {
                    portraitLayout(height: proxy.size.height)
                }
            }
        }
        .accessibilityHidden(isAccessibilityOverlayPresented)
        .overlay {
            overlay()
        }
        .onPreferenceChange(MiniGameAccessibilityOverlayPreferenceKey.self) { isPresented in
            isAccessibilityOverlayPresented = isPresented
        }
        .lpDynamicTypeScaling()
        .preferredColorScheme(.light)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("miniGame.\(kind.rawValue)")
    }

    private func portraitLayout(height: CGFloat) -> some View {
        VStack(spacing: LP.Spacing.m) {
            hud
                .padding(.horizontal, LP.Spacing.l)
                .padding(.top, LP.Spacing.s)

            gameStage
                .padding(.horizontal, LP.Spacing.l)

            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(showsIndicators: false) {
                    controls
                        .padding(.horizontal, LP.Spacing.l)
                        .padding(.bottom, LP.Spacing.s)
                }
                .frame(maxHeight: max(150, height * 0.38))
            } else {
                controls
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, LP.Spacing.s)
            }
        }
    }

    private func landscapeLayout(width: CGFloat) -> some View {
        HStack(spacing: LP.Spacing.m) {
            VStack(spacing: LP.Spacing.m) {
                hud

                ScrollView(showsIndicators: false) {
                    controls
                        .padding(.bottom, LP.Spacing.s)
                }
            }
            .frame(width: min(360, max(270, width * 0.38)))

            gameStage
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.vertical, LP.Spacing.s)
    }

    private var hud: some View {
        MiniGameHUDBar(
            title: kind.title,
            subtitle: detailText ?? kind.tag,
            scoreText: scoreText,
            tint: kind.tint,
            onClose: onClose
        )
        .accessibilityIdentifier("miniGame.\(kind.rawValue).hud")
    }

    private var gameStage: some View {
        stage()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("miniGame.\(kind.rawValue).stage")
    }

    private var controls: some View {
        bottomBar()
            .accessibilityIdentifier("miniGame.\(kind.rawValue).controls")
    }
}

extension MiniGameShell where BottomBar == EmptyView, Overlay == EmptyView {
    init(
        kind: MiniGameKind,
        scoreText: String? = nil,
        detailText: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder stage: @escaping () -> Stage
    ) {
        self.kind = kind
        self.scoreText = scoreText
        self.detailText = detailText
        self.onClose = onClose
        self.stage = stage
        self.bottomBar = { EmptyView() }
        self.overlay = { EmptyView() }
    }
}

extension MiniGameShell where Overlay == EmptyView {
    init(
        kind: MiniGameKind,
        scoreText: String? = nil,
        detailText: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder stage: @escaping () -> Stage,
        @ViewBuilder bottomBar: @escaping () -> BottomBar
    ) {
        self.kind = kind
        self.scoreText = scoreText
        self.detailText = detailText
        self.onClose = onClose
        self.stage = stage
        self.bottomBar = bottomBar
        self.overlay = { EmptyView() }
    }
}

struct MiniGameStageBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            LP.Fill.bgSurfaceSecondary
            LinearGradient(
                colors: [
                    tint.opacity(0.18),
                    LP.Fill.bgSurfaceSecondary.opacity(0.3),
                    LP.Fill.bgSurface.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                Path { path in
                    path.move(to: CGPoint(x: -20, y: height * 0.74))
                    path.addCurve(
                        to: CGPoint(x: width + 20, y: height * 0.68),
                        control1: CGPoint(x: width * 0.25, y: height * 0.60),
                        control2: CGPoint(x: width * 0.62, y: height * 0.84)
                    )
                    path.addLine(to: CGPoint(x: width + 20, y: height + 20))
                    path.addLine(to: CGPoint(x: -20, y: height + 20))
                    path.closeSubpath()
                }
                .fill(LP.Fill.bgContainer.opacity(0.52))
            }
        }
    }
}

struct MiniGameHUDBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let scoreText: String?
    let tint: Color
    let onClose: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    HStack(spacing: LP.Spacing.s) {
                        MiniGameCircleButton(
                            system: "xmark",
                            label: AppLocalization.text("关闭"),
                            action: onClose
                        )
                        Spacer(minLength: 0)
                        scoreBadge
                    }
                    titleBlock
                }
            } else {
                HStack(spacing: LP.Spacing.s) {
                    MiniGameCircleButton(
                        system: "xmark",
                        label: AppLocalization.text("关闭"),
                        action: onClose
                    )
                    titleBlock
                    Spacer(minLength: 0)
                    scoreBadge
                }
            }
        }
        .padding(LP.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
        )
        .lpShadow(LP.Shadow.elevation1)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            Text(AppLocalization.text(subtitle))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.tertiary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let scoreText {
            Text(scoreText)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s)
                .frame(minHeight: 36)
                .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.92)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: LP.BorderWidth.hair))
        }
    }
}

struct MiniGameCircleButton: View {
    let system: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LP.Fill.bgContainer))
                .overlay(Circle().strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MiniGameStageCaption: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let text: String
    let textStyle: LP.TextStyle
    let foreground: Color
    let fill: Color

    init(
        _ text: String,
        textStyle: LP.TextStyle = LP.Typography.c1Medium,
        foreground: Color = LP.Content.secondary,
        fill: Color = LP.Fill.bgContainer.opacity(0.9)
    ) {
        self.text = text
        self.textStyle = textStyle
        self.foreground = foreground
        self.fill = fill
    }

    var body: some View {
        Text(AppLocalization.text(text))
            .lpText(textStyle)
            .foregroundStyle(foreground)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.m)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? LP.Spacing.xs : 0)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(fill)
            )
    }
}

struct MiniGameActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Variant {
        case primary
        case secondary
        case danger
    }

    let title: String
    let system: String
    var variant: Variant = .secondary
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.body.weight(.semibold))
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.b3Medium)
            }
            .foregroundStyle(foreground)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.s)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? LP.Spacing.s : 0)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: LP.BorderWidth.hair))
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("miniGame.action.\(title)")
    }

    private var foreground: Color {
        switch variant {
        case .primary, .danger: return LP.Fill.foundationOnAccent
        case .secondary: return LP.Content.secondary
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return LP.Fill.foundationAccent
        case .danger: return LP.Fill.foundationError
        case .secondary: return LP.Fill.bgContainer
        }
    }

    private var stroke: Color {
        switch variant {
        case .primary, .danger: return .clear
        case .secondary: return LP.Border.primary
        }
    }
}

struct MiniGameControlBar<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LP.Spacing.s) {
                    content()
                }
            } else {
                HStack(spacing: LP.Spacing.s) {
                    content()
                }
            }
        }
        .padding(LP.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
        )
        .lpShadow(LP.Shadow.elevation1)
    }
}

struct MiniGameResultOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var resultTitleFocused: Bool

    let isPresented: Bool
    let title: String
    let message: String
    let primaryTitle: String
    let primarySystem: String
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondarySystem: String = "xmark"
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        if isPresented {
            ZStack {
                LP.Fill.maskModal.ignoresSafeArea()
                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: LP.Spacing.l) {
                            Text(AppLocalization.text(title))
                                .lpText(LP.Typography.uiH4)
                                .foregroundStyle(LP.Content.primary)
                                .multilineTextAlignment(.center)
                                .accessibilityFocused($resultTitleFocused)
                            Text(AppLocalization.text(message))
                                .lpText(LP.Typography.handMid)
                                .foregroundStyle(LP.Content.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: LP.Spacing.s) {
                                    resultButtons
                                }
                            } else {
                                HStack(spacing: LP.Spacing.s) {
                                    resultButtons
                                }
                            }
                        }
                        .padding(LP.Spacing.xxl)
                        .frame(maxWidth: 340)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgPop)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                        )
                        .lpShadow(LP.Shadow.elevation3)
                        .padding(LP.Spacing.xxl)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                }
            }
            .transition(reduceMotion ? .identity : .opacity)
            .preference(key: MiniGameAccessibilityOverlayPreferenceKey.self, value: true)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                dismiss()
            }
            .onAppear {
                resultTitleFocused = true
            }
            .onDisappear {
                resultTitleFocused = false
            }
        }
    }

    @ViewBuilder
    private var resultButtons: some View {
        MiniGameActionButton(
            title: secondaryTitle ?? "离开",
            system: secondaryAction == nil ? "xmark" : secondarySystem,
            variant: .secondary,
            action: secondaryAction ?? { dismiss() }
        )
        MiniGameActionButton(
            title: primaryTitle,
            system: primarySystem,
            variant: .primary,
            action: primaryAction
        )
    }
}

private struct MiniGameAccessibilityOverlayPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct MiniGameSegmentedPicker<Option: CaseIterable & Identifiable & Hashable>: View where Option.AllCases: RandomAccessCollection {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LP.Spacing.xs) {
                    options
                }
            } else {
                HStack(spacing: LP.Spacing.xs) {
                    options
                }
            }
        }
    }

    @ViewBuilder
    private var options: some View {
            ForEach(Array(Option.allCases)) { option in
                Button {
                    LPHaptics.tap()
                    selection = option
                } label: {
                    Text(AppLocalization.text(title(option)))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(selection == option ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? LP.Spacing.s : 0)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            Capsule().fill(selection == option ? LP.Fill.foundationAccent : LP.Fill.bgContainer.opacity(0.72))
                        )
                        .overlay(
                            Capsule().strokeBorder(selection == option ? .clear : LP.Border.tertiary,
                                                   lineWidth: LP.BorderWidth.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text(title(option)))
                .accessibilityIdentifier("miniGame.segment.\(title(option))")
            }
    }
}
