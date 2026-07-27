import SwiftUI

// MARK: - Pibo 漂浮

struct BreathFloatGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var elapsedBeforeRun = 0.0
    @State private var runStartedAt = ProcessInfo.processInfo.systemUptime
    @State private var timeLeft = 60
    @State private var score = 0
    @State private var combo = 0
    @State private var ringY = Double.random(in: 0.28...0.72)
    @State private var feedback = "跟着呼吸上下移动，重合时点屏幕"
    @State private var showResult = false
    @State private var resultMessage = ""

    private let cycleLength = 10.0
    private let sessionLength = 60.0

    var body: some View {
        MiniGameShell(
            kind: .breathFloat,
            scoreText: miniGameScoreText(for: .breathFloat, score: score),
            detailText: hasStarted
                ? (isRunning ? "\(timeLeft)s · 连 \(combo)" : "暂停 · \(timeLeft)s · 连 \(combo)")
                : "看准圆环再开始",
            onClose: { dismiss() }
        ) {
            TimelineView(
                .animation(
                    minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                    paused: !isRunning || showResult
                )
            ) { _ in
                GeometryReader { proxy in
                    let phase = breathPhase(at: ProcessInfo.processInfo.systemUptime)
                    let distance = abs(phase.y - ringY)

                    ZStack {
                        ForEach(0..<5, id: \.self) { index in
                            Capsule()
                                .fill(LP.Colorful.cyan200.opacity(0.45))
                                .frame(width: proxy.size.width * CGFloat(0.32 + Double(index) * 0.08), height: 2)
                                .position(x: proxy.size.width * CGFloat(0.5),
                                          y: proxy.size.height * CGFloat(0.2 + Double(index) * 0.13))
                        }

                        Capsule()
                            .fill(MiniGameKind.breathFloat.tint.opacity(distance < 0.09 ? 0.18 : 0.07))
                            .frame(width: 132, height: proxy.size.height * 0.18)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * ringY)

                        Circle()
                            .stroke(MiniGameKind.breathFloat.tint, lineWidth: distance < 0.09 ? 10 : 7)
                            .frame(width: 112, height: 112)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * ringY)
                            .shadow(
                                color: MiniGameKind.breathFloat.tint.opacity(distance < 0.09 ? 0.58 : 0.24),
                                radius: distance < 0.09 ? 22 : 10
                            )

                        MiniGamePiboAsset(flowerScale: 0.72)
                            .frame(width: 96, height: 106)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * phase.y)

                        VStack(spacing: 3) {
                            Text(AppLocalization.text(phase.isInhale ? "吸气 · 上浮" : "呼气 · 下沉"))
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(LP.Content.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                            Text(AppLocalization.text(feedback))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.tertiary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, LP.Spacing.m)
                        .padding(.vertical, LP.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgContainer.opacity(0.9))
                        )
                        .position(
                            x: proxy.size.width / 2,
                            y: dynamicTypeSize.isAccessibilitySize ? 66 : 34
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { passRing() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AppLocalization.text("Pibo 漂浮游戏区"))
                    .accessibilityValue(AppLocalization.text(
                        "\(phase.isInhale ? "吸气上浮" : "呼气下沉")，\(ringProximityText(distance: distance))。\(feedback)"
                    ))
                    .accessibilityHint(AppLocalization.text("重合时双击穿过圆环"))
                    .accessibilityAction { passRing() }
                }
            }
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(title: "穿过", system: "circle.dashed", variant: .primary, disabled: !isRunning) {
                    passRing()
                }
                MiniGameActionButton(
                    title: isRunning ? "暂停" : (hasStarted ? "继续" : "开始"),
                    system: isRunning ? "pause.fill" : "play.fill"
                ) {
                    toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") {
                    reset()
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "穿过 \(score)",
                message: resultMessage,
                primaryTitle: "再漂",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning, !showResult else { return }
            while !Task.isCancelled, isRunning, !showResult {
                let nextTimeLeft = max(
                    0,
                    Int(ceil(sessionLength - elapsed(at: ProcessInfo.processInfo.systemUptime)))
                )
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning, !showResult {
                pause()
            }
        }
    }

    private func elapsed(at now: TimeInterval) -> Double {
        min(
            sessionLength,
            elapsedBeforeRun + (isRunning ? max(0, now - runStartedAt) : 0)
        )
    }

    private func breathPhase(at now: TimeInterval) -> (y: Double, isInhale: Bool) {
        let phaseTime = elapsed(at: now).truncatingRemainder(dividingBy: cycleLength)
        let isInhale = phaseTime < 4
        let progress = isInhale ? phaseTime / 4 : (phaseTime - 4) / 6
        let y = isInhale ? 0.78 - progress * 0.54 : 0.24 + progress * 0.54
        return (y, isInhale)
    }

    private func ringProximityText(distance: Double) -> String {
        if distance < 0.035 { return "正对圆心" }
        if distance < 0.09 { return "接近圆环" }
        return "还没对齐"
    }

    private func passRing(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRunning, !showResult else { return }
        let phase = breathPhase(at: now)
        let distance = abs(phase.y - ringY)
        if distance < 0.09 {
            combo += 1
            score += 10 + combo
            feedback = distance < 0.035 ? "正中圆环！" : "穿过去了"
            moveRing(awayFrom: phase.y)
            LPHaptics.success()
        } else {
            combo = 0
            feedback = distance < 0.16 ? "差一点，再贴近圆心" : "等 Pibo 靠近圆环"
            LPHaptics.decline()
        }
    }

    private func moveRing(awayFrom y: Double) {
        let candidates = [0.3, 0.42, 0.58, 0.7].filter { abs($0 - y) > 0.16 }
        ringY = candidates.randomElement() ?? 0.5
    }

    private func toggleRunning() {
        if isRunning {
            pause()
        } else {
            resume()
        }
    }

    private func pause() {
        elapsedBeforeRun = elapsed(at: ProcessInfo.processInfo.systemUptime)
        isRunning = false
    }

    private func resume() {
        guard !showResult else { return }
        hasStarted = true
        runStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
    }

    private func reset() {
        hasStarted = false
        isRunning = false
        elapsedBeforeRun = 0
        runStartedAt = ProcessInfo.processInfo.systemUptime
        timeLeft = 60
        score = 0
        combo = 0
        ringY = Double.random(in: 0.28...0.72)
        feedback = "跟着呼吸上下移动，重合时点屏幕"
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        isRunning = false
        resultMessage = miniGameRecordedResult(
            for: .breathFloat,
            score: score,
            fallback: score >= 50 ? "...穿过去了，别太骄傲。" : "...呼吸还在水面下。"
        )
        showResult = true
    }
}
