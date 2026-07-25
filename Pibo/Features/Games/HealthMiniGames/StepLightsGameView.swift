import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import Vision

// MARK: - 原地踏步点灯
private enum StepInputMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动计步"
        case .manual: return "手动交替"
        }
    }
}

struct StepLightsGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionInput = MotionGameInput()
    @State private var inputMode = StepInputMode.automatic
    @State private var isRunning = false
    @State private var timeLeft = 45
    @State private var steps = 0
    @State private var laneSide = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var countdown = MiniGameCountdownClock(duration: 45)

    var body: some View {
        MiniGameShell(
            kind: .stepLights,
            scoreText: miniGameScoreText(for: .stepLights, score: steps),
            detailText: "\(timeLeft)s · \(inputStatusText)",
            onClose: { dismiss() }
        ) {
            GeometryReader { proxy in
                VStack(spacing: LP.Spacing.m) {
                    VStack(spacing: LP.Spacing.xs) {
                        HStack {
                            Text(AppLocalization.text("第 \(currentLap) 圈"))
                            Spacer()
                            Text(AppLocalization.text("\(lapSteps)/20 步"))
                        }
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.secondary)

                        ProgressView(value: Double(lapSteps), total: 20)
                            .tint(MiniGameKind.stepLights.tint)
                    }
                    .padding(.horizontal, LP.Spacing.m)

                    if proxy.size.width > proxy.size.height {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(visibleTrail, id: \.self) { index in
                                trailLamp(index: index)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visibleTrail.reversed(), id: \.self) { index in
                                HStack {
                                    if index.isMultiple(of: 2) {
                                        trailLamp(index: index)
                                        Spacer(minLength: 58)
                                    } else {
                                        Spacer(minLength: 58)
                                        trailLamp(index: index)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isManualInput {
                        HStack(spacing: LP.Spacing.l) {
                            footButton(title: "左", side: false)
                            footButton(title: "右", side: true)
                        }
                    } else {
                        Label(AppLocalization.text("手机随身携带，原地自然踏步"), systemImage: "figure.walk.motion")
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(LP.Content.secondary)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.m)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                MiniGameSegmentedPicker(selection: $inputMode) { $0.title }
                    .disabled(isRunning)
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: isRunning ? "暂停" : (timeLeft < 45 ? "继续" : "开始"),
                        system: isRunning ? "pause.fill" : "play.fill",
                        variant: .primary,
                        disabled: showResult
                    ) {
                        if timeLeft == 0 { reset() }
                        isRunning.toggle()
                    }
                    MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "踏亮了 \(steps) 步",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled, isRunning, !showResult {
                let nextTimeLeft = countdown.secondsLeft()
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: isRunning) { _, running in
            if running {
                countdown.resume()
                if inputMode == .automatic {
                    motionInput.startPedometer()
                } else {
                    motionInput.useManualSteps()
                }
            } else {
                countdown.pause()
                motionInput.stopPedometer()
            }
        }
        .onChange(of: motionInput.stepPulse) { oldValue, newValue in
            guard isRunning, inputMode == .automatic, newValue > oldValue else { return }
            let newSteps = newValue - oldValue
            for offset in 0..<newSteps {
                registerStep(haptic: offset == newSteps - 1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning, !showResult {
                isRunning = false
            }
        }
        .onDisappear {
            motionInput.stopPedometer()
        }
    }

    private var isManualInput: Bool {
        inputMode == .manual || motionInput.requiresManualStepInput
    }

    private var inputStatusText: String {
        if isManualInput {
            return motionInput.requiresManualStepInput ? "自动不可用 · 手动左右脚" : "手动左右脚"
        }
        return motionInput.statusText
    }

    private var visibleTrail: [Int] {
        let start = max(0, steps - 5)
        return Array(start..<(start + 12))
    }

    private var currentLap: Int {
        (max(1, steps) - 1) / 20 + 1
    }

    private var lapSteps: Int {
        steps == 0 ? 0 : (steps - 1) % 20 + 1
    }

    private func trailLamp(index: Int) -> some View {
        let isLit = index < steps
        let isNext = index == steps

        return HStack(spacing: LP.Spacing.s) {
            Circle()
                .fill(isLit ? LP.Colorful.yellow400 : LP.Fill.bgContainer.opacity(0.74))
                .frame(width: isNext ? 38 : 30, height: isNext ? 38 : 30)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isNext ? LP.Fill.foundationAccent : (isLit ? LP.Colorful.yellow700.opacity(0.35) : LP.Border.tertiary),
                            lineWidth: isNext ? 3 : 1
                        )
                )
                .shadow(color: isLit ? LP.Colorful.yellow400.opacity(0.5) : .clear, radius: 10)
            Text("\(index + 1)")
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(isNext ? LP.Content.primary : LP.Content.tertiary)
                .monospacedDigit()
        }
        .frame(width: 78, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
    }

    private func footButton(title: String, side: Bool) -> some View {
        return Button {
            guard isRunning else { return }
            if side == laneSide {
                registerStep()
            } else {
                LPHaptics.decline()
            }
        } label: {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(side == laneSide ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(width: 88, height: 88)
                .background(Circle().fill(side == laneSide ? LP.Fill.foundationAccent : LP.Fill.bgContainer))
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isRunning || side != laneSide)
        .accessibilityHint(AppLocalization.text(side == laneSide ? "下一步按这里" : "先按另一只脚"))
    }

    private func registerStep(haptic: Bool = true) {
        if haptic { LPHaptics.success() }
        steps += 1
        laneSide.toggle()
    }

    private func reset() {
        motionInput.stopPedometer()
        countdown.reset()
        isRunning = false
        timeLeft = 45
        steps = 0
        laneSide = false
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        isRunning = false
        motionInput.stopPedometer()
        resultMessage = miniGameRecordedResult(
            for: .stepLights,
            score: steps,
            fallback: steps >= 80 ? "...行吧，Pibo 有点亮了。" : "...还没热起来，再踩一局。"
        )
        showResult = true
        LPHaptics.success()
    }
}
