import Foundation
import SwiftUI

// MARK: - 叠花盆

struct PotStackGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var stack: [StackPot] = [StackPot(width: 0.72, x: 0.5, level: 0)]
    @State private var movementStartedAt = ProcessInfo.processInfo.systemUptime
    @State private var movementStartX = 0.18
    @State private var movementDirection = 1.0
    @State private var score = 0
    @State private var perfectStreak = 0
    @State private var timeLeft = 90
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var showResult = false
    @State private var resultTitle = "花塔倒了"
    @State private var resultMessage = ""
    @State private var feedbackText = "点击画面，让花盆落下"
    @State private var countdown = MiniGameCountdownClock(duration: 90)

    var body: some View {
        MiniGameShell(
            kind: .potStack,
            scoreText: miniGameScoreText(for: .potStack, score: score),
            detailText: hasStarted
                ? (isRunning
                    ? "\(timeLeft)s · \(perfectStreak > 0 ? "完美 \(perfectStreak)" : "点按落盆")"
                    : "暂停 · \(timeLeft)s")
                : "看准位置，再开始",
            onClose: { dismiss() }
        ) {
            TimelineView(
                .animation(
                    minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                    paused: !isRunning || showResult
                )
            ) { _ in
                GeometryReader { proxy in
                    let movement = movementState(at: ProcessInfo.processInfo.systemUptime)
                    let step = min(42.0, max(34.0, proxy.size.height * 0.075))
                    let towerHeight = CGFloat(max(0, stack.count - 1)) * step
                    let cameraOffset = max(0, towerHeight - proxy.size.height * 0.56)
                    let baseY = proxy.size.height - 34 + cameraOffset
                    let nextY = baseY - CGFloat(stack.count) * step

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(LP.Fill.bgContainer.opacity(0.34))

                        if let last = stack.last {
                            Capsule()
                                .fill(MiniGameKind.potStack.tint.opacity(0.12))
                                .frame(width: last.width * proxy.size.width, height: 8)
                                .position(x: last.x * proxy.size.width, y: nextY + 23)
                        }

                        ForEach(stack.suffix(18)) { pot in
                            potView(width: pot.width * proxy.size.width)
                                .position(
                                    x: pot.x * proxy.size.width,
                                    y: baseY - CGFloat(pot.level) * step
                                )
                        }

                        if !showResult {
                            potView(width: (stack.last?.width ?? 0.7) * proxy.size.width)
                                .position(x: movement.x * proxy.size.width, y: nextY)
                        }

                        MiniGameStageCaption(feedbackText)
                            .position(
                                x: proxy.size.width / 2,
                                y: dynamicTypeSize.isAccessibilitySize ? 54 : 24
                            )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { dropPot() }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.text("叠花盆游戏区"))
            .accessibilityValue(AppLocalization.text("已叠 \(max(0, stack.count - 1)) 层"))
            .accessibilityHint(AppLocalization.text("双击让移动中的花盆落下"))
            .accessibilityAction { dropPot() }
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(title: "落下", system: "arrow.down.to.line", variant: .primary, disabled: !isRunning || showResult) { dropPot() }
                MiniGameActionButton(
                    title: isRunning ? "暂停" : (hasStarted ? "继续" : "开始"),
                    system: isRunning ? "pause.fill" : "play.fill",
                    disabled: showResult
                ) {
                    toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: resultTitle,
                message: resultMessage,
                primaryTitle: "再叠",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning, !showResult else { return }
            while !Task.isCancelled, isRunning, !showResult {
                let nextTimeLeft = countdown.secondsLeft()
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish(title: "花塔封顶", message: "Pibo 抬头已经看不到顶了。")
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

    private func potView(width: CGFloat) -> some View {
        MiniGamePotAsset()
            .frame(width: width, height: 42)
    }

    private func movementState(at now: TimeInterval) -> (x: Double, direction: Double) {
        let lowerBound = 0.12
        let upperBound = 0.88
        let travel = upperBound - lowerBound
        let speed = (0.0075 + min(Double(stack.count), 18) * 0.00045) * 60
        let startOffset = movementStartX.clamped(to: lowerBound...upperBound) - lowerBound
        let initialPhase = movementDirection > 0 ? startOffset : travel * 2 - startOffset
        let elapsed = max(0, now - movementStartedAt)
        let phase = (initialPhase + elapsed * speed).truncatingRemainder(dividingBy: travel * 2)

        if phase <= travel {
            return (lowerBound + phase, 1)
        }
        return (upperBound - (phase - travel), -1)
    }

    private func dropPot(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !showResult, isRunning, let last = stack.last else { return }
        let movement = movementState(at: now)
        let drop = PiboCorePotStackAdapter.drop(
            topX: last.x,
            topWidth: last.width,
            movingX: movement.x,
            perfectStreak: perfectStreak
        )
        guard drop.success else {
            finish(title: "花塔倒了", message: "Pibo 说刚刚是风。")
            LPHaptics.decline()
            return
        }
        perfectStreak = drop.newStreak
        stack.append(StackPot(width: drop.nextWidth, x: drop.nextX, level: stack.count))
        score += drop.scoreGain
        feedbackText = drop.perfect
            ? "完美！连续 \(perfectStreak) 次"
            : "削掉了 \(drop.cutPercent)%"
        movementDirection = -movement.direction
        movementStartX = movementDirection > 0 ? 0.12 : 0.88
        movementStartedAt = now
        LPHaptics.success()
    }

    private func toggleRunning() {
        if !hasStarted {
            start()
        } else {
            isRunning ? pause() : resume()
        }
    }

    private func start() {
        guard !hasStarted, !showResult else { return }
        hasStarted = true
        movementStartedAt = ProcessInfo.processInfo.systemUptime
        countdown.reset(startsRunning: true)
        isRunning = true
    }

    private func pause() {
        let now = ProcessInfo.processInfo.systemUptime
        let movement = movementState(at: now)
        movementStartX = movement.x
        movementDirection = movement.direction
        movementStartedAt = now
        countdown.pause()
        isRunning = false
    }

    private func resume() {
        movementStartedAt = ProcessInfo.processInfo.systemUptime
        countdown.resume()
        isRunning = true
    }

    private func reset() {
        stack = [StackPot(width: 0.72, x: 0.5, level: 0)]
        movementStartedAt = ProcessInfo.processInfo.systemUptime
        movementStartX = 0.18
        movementDirection = 1
        score = 0
        perfectStreak = 0
        timeLeft = 90
        hasStarted = false
        isRunning = false
        showResult = false
        resultTitle = "花塔倒了"
        resultMessage = ""
        feedbackText = "点击画面，让花盆落下"
        countdown.reset()
    }

    private func finish(title: String, message: String) {
        guard !showResult else { return }
        countdown.pause()
        isRunning = false
        resultTitle = title
        resultMessage = miniGameRecordedResult(
            for: .potStack,
            score: score,
            fallback: "叠了 \(max(0, stack.count - 1)) 层，得分 \(score)。\(message)"
        )
        showResult = true
    }
}

private struct StackPot: Identifiable {
    let id = UUID()
    var width: Double
    var x: Double
    var level: Int
}
