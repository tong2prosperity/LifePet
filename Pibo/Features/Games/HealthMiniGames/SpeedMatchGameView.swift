import SwiftUI

// MARK: - Speed Match

struct SpeedMatchGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var previous: SpeedMatchCard?
    @State private var current = SpeedMatchCard.random()
    @State private var score = 0
    @State private var streak = 0
    @State private var correctAnswers = 0
    @State private var timeLeft = 45
    @State private var running = false
    @State private var isExample = true
    @State private var isRevealing = false
    @State private var feedbackText = "先记住这一张，不计分"
    @State private var questionElapsedBeforeRun = 0.0
    @State private var questionStartedAt = ProcessInfo.processInfo.systemUptime
    @State private var advanceTask: Task<Void, Never>?
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var countdown = MiniGameCountdownClock(duration: 45)

    private let cardColors: [Color] = [
        LP.Colorful.red500,
        LP.Colorful.cyan500,
        LP.Colorful.purple500,
        LP.Colorful.orange500
    ]

    private var pace: SpeedMatchPace {
        if correctAnswers >= 12 { return .flash }
        if correctAnswers >= 5 { return .quick }
        return .steady
    }

    private var questionDuration: TimeInterval { pace.duration }

    var body: some View {
        MiniGameShell(
            kind: .speedMatch,
            scoreText: miniGameScoreText(for: .speedMatch, score: score),
            detailText: isExample
                ? "示例牌 · 准备"
                : (running ? "\(pace.title) · \(timeLeft)s · 连 \(streak)" : "暂停 · 连 \(streak)"),
            onClose: { dismiss() }
        ) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !running || isRevealing || showResult)) { _ in
                let remaining = max(
                    0,
                    1 - questionElapsed(at: ProcessInfo.processInfo.systemUptime) / questionDuration
                )
                VStack(spacing: LP.Spacing.l) {
                    ProgressView(value: isExample ? 1 : remaining)
                        .tint(isRevealing ? LP.Fill.foundationSuccess : MiniGameKind.speedMatch.tint)
                        .frame(maxWidth: 240)
                        .opacity(isExample ? 0.35 : 1)

                    Spacer(minLength: 0)
                    Text(current.symbol)
                        .font(.system(size: 92, weight: .bold, design: .rounded))
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .frame(width: 190, height: 190)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                                .fill(cardColors[current.colorIndex])
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                                .strokeBorder(.white.opacity(0.72), lineWidth: 3)
                        )
                        .shadow(color: cardColors[current.colorIndex].opacity(0.26), radius: 18, y: 8)
                        .rotationEffect(.degrees(streak.isMultiple(of: 2) ? -2 : 2))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppLocalization.text(current.accessibilityLabel))

                    VStack(spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text(isExample ? "示例牌" : "符号和颜色都要比"))
                            .lpText(LP.Typography.handMid)
                            .foregroundStyle(LP.Content.secondary)
                        Text(AppLocalization.text(feedbackText))
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(isRevealing ? LP.Content.primary : LP.Content.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minHeight: 56)
                    Spacer(minLength: 0)
                }
            }
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                if isExample {
                    MiniGameControlBar {
                        MiniGameActionButton(title: "记住，开始", system: "play.fill", variant: .primary) {
                            beginSession()
                        }
                        MiniGameActionButton(title: "换一张", system: "arrow.clockwise") {
                            current = .random()
                        }
                    }
                } else {
                    MiniGameControlBar {
                        MiniGameActionButton(
                            title: "不同",
                            system: "xmark",
                            variant: .secondary,
                            disabled: !running || isRevealing || showResult
                        ) { answer(match: false) }
                        MiniGameActionButton(
                            title: "完全相同",
                            system: "checkmark",
                            variant: .primary,
                            disabled: !running || isRevealing || showResult
                        ) { answer(match: true) }
                    }
                    MiniGameControlBar {
                        MiniGameActionButton(
                            title: running ? "暂停" : "继续",
                            system: running ? "pause.fill" : "play.fill",
                            disabled: showResult
                        ) {
                            running ? pause() : resume()
                        }
                        MiniGameActionButton(title: "重来", system: "arrow.clockwise") {
                            reset()
                        }
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "反应分 \(score)",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .onAppear { reset() }
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled, running, !showResult {
                let nextTimeLeft = countdown.secondsLeft()
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                if !isExample,
                   !isRevealing,
                   questionElapsed(at: ProcessInfo.processInfo.systemUptime) >= questionDuration {
                    LPHaptics.decline()
                    revealAnswer(wasCorrect: false, prefix: "超时")
                }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, running, !showResult {
                pause()
            }
        }
        .onDisappear { advanceTask?.cancel() }
    }

    private func answer(match: Bool) {
        guard running, !isExample, !isRevealing, let previous else { return }
        let correct = ((previous == current) == match)
        if correct {
            streak += 1
            let responseProgress = max(
                0,
                1 - questionElapsed(at: ProcessInfo.processInfo.systemUptime) / questionDuration
            )
            correctAnswers += 1
            score += 6 + Int((responseProgress * 6).rounded()) + min(8, streak)
            LPHaptics.success()
        } else {
            streak = 0
            LPHaptics.decline()
        }
        revealAnswer(wasCorrect: correct, prefix: correct ? "答对" : "答错")
    }

    private func revealAnswer(wasCorrect: Bool, prefix: String) {
        guard !isRevealing, let previous else { return }
        if !wasCorrect { streak = 0 }
        let correctAnswer = previous == current ? "完全相同" : differenceText(previous, current)
        let milestone = wasCorrect && [5, 12].contains(correctAnswers) ? " · 节奏升级" : ""
        feedbackText = "\(prefix)：\(correctAnswer)\(milestone)"
        isRevealing = true
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, running, !showResult else { return }
            advanceQuestion()
        }
    }

    private func beginSession() {
        previous = current
        isExample = false
        countdown.reset(startsRunning: true)
        running = true
        timeLeft = 45
        advanceQuestion()
    }

    private func advanceQuestion() {
        let last = current
        previous = last
        if Bool.random() {
            current = last
        } else {
            current = SpeedMatchCard.nearMiss(from: last, unlockColorOnly: correctAnswers >= 5)
        }
        isRevealing = false
        feedbackText = "\(pace.title)：判断是否完全相同"
        questionElapsedBeforeRun = 0
        questionStartedAt = ProcessInfo.processInfo.systemUptime
    }

    private func questionElapsed(at now: TimeInterval) -> TimeInterval {
        min(
            questionDuration,
            questionElapsedBeforeRun + (running && !isRevealing ? max(0, now - questionStartedAt) : 0)
        )
    }

    private func differenceText(_ previous: SpeedMatchCard, _ current: SpeedMatchCard) -> String {
        if previous.symbol == current.symbol { return "符号相同，但颜色变了" }
        if previous.colorIndex == current.colorIndex { return "颜色相同，但符号变了" }
        return "符号和颜色都不同"
    }

    private func pause() {
        if isRevealing {
            advanceTask?.cancel()
            advanceQuestion()
        } else {
            questionElapsedBeforeRun = questionElapsed(at: ProcessInfo.processInfo.systemUptime)
        }
        countdown.pause()
        running = false
    }

    private func resume() {
        guard !showResult, !isExample else { return }
        questionStartedAt = ProcessInfo.processInfo.systemUptime
        countdown.resume()
        running = true
    }

    private func reset() {
        advanceTask?.cancel()
        advanceTask = nil
        countdown.reset()
        previous = nil
        current = .random()
        score = 0
        streak = 0
        correctAnswers = 0
        timeLeft = 45
        running = false
        isExample = true
        isRevealing = false
        feedbackText = "先记住这一张，不计分"
        questionElapsedBeforeRun = 0
        questionStartedAt = ProcessInfo.processInfo.systemUptime
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        advanceTask?.cancel()
        countdown.pause()
        running = false
        resultMessage = miniGameRecordedResult(
            for: .speedMatch,
            score: score,
            fallback: "这一题只练这一题，别被 Pibo 骗了。"
        )
        showResult = true
    }
}

private struct SpeedMatchCard: Equatable {
    private static let symbols = ["P", "I", "B", "O", "花", "露"]
    private static let colorNames = ["红色", "青色", "紫色", "橙色"]
    private static let colorCount = 4

    let symbol: String
    let colorIndex: Int

    var accessibilityLabel: String {
        "\(Self.colorNames[colorIndex.clamped(to: 0...(Self.colorNames.count - 1))]) \(symbol)"
    }

    static func random() -> SpeedMatchCard {
        SpeedMatchCard(
            symbol: symbols.randomElement() ?? "P",
            colorIndex: Int.random(in: 0..<colorCount)
        )
    }

    static func nearMiss(from previous: SpeedMatchCard, unlockColorOnly: Bool) -> SpeedMatchCard {
        if unlockColorOnly, Bool.random() {
            let nextColor = (0..<colorCount).filter { $0 != previous.colorIndex }.randomElement() ?? 0
            return SpeedMatchCard(symbol: previous.symbol, colorIndex: nextColor)
        }

        let nextSymbol = symbols.filter { $0 != previous.symbol }.randomElement() ?? "O"
        let keepColor = unlockColorOnly && Bool.random()
        return SpeedMatchCard(
            symbol: nextSymbol,
            colorIndex: keepColor ? previous.colorIndex : Int.random(in: 0..<colorCount)
        )
    }
}

private enum SpeedMatchPace {
    case steady
    case quick
    case flash

    var title: String {
        switch self {
        case .steady: return "稳住"
        case .quick: return "加速"
        case .flash: return "闪回"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .steady: return 3.0
        case .quick: return 2.15
        case .flash: return 1.55
        }
    }
}
