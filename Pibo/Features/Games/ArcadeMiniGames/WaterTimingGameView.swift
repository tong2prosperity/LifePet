import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 浇水计时

struct WaterTimingGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WaterTimingGameModel()

    var body: some View {
        MiniGameShell(
            kind: .waterTiming,
            scoreText: miniGameScoreText(for: .waterTiming, score: model.score),
            detailText: model.hasStarted
                ? (model.isRunning
                    ? "\(model.timeLeft)s · 连 \(model.streak)"
                    : "暂停 · 连 \(model.streak)")
                : "看准花心，再开始",
            onClose: { dismiss() }
        ) {
            WaterTimingStage(model: model)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: "浇水",
                    system: "drop.fill",
                    variant: .primary,
                    disabled: !model.isRunning || model.isResolving || model.isFinished
                ) {
                    model.waterNow()
                }
                MiniGameActionButton(
                    title: model.isRunning ? "暂停" : (model.hasStarted ? "继续" : "开始"),
                    system: model.isRunning ? "pause.fill" : "play.fill",
                    disabled: model.isFinished
                ) {
                    model.toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { model.reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "水准 \(model.score)",
                message: model.resultMessage,
                primaryTitle: "再浇",
                primarySystem: "arrow.clockwise",
                primaryAction: { model.reset() }
            )
        }
        .onDisappear { model.stopLoop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.isRunning, !model.isFinished {
                model.pause()
            }
        }
    }
}

private struct WaterTimingStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: WaterTimingGameModel

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                paused: !model.isRunning || model.isFinished
            )
        ) { _ in
            GeometryReader { proxy in
                let dropY = model.currentDropY()
                let impactProgress = model.currentImpactProgress()

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.34))

                    Rectangle()
                        .fill(LP.Border.tertiary.opacity(0.7))
                        .frame(width: 2, height: proxy.size.height * 0.78)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.47)

                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(MiniGameKind.waterTiming.tint.opacity(0.11))
                        .frame(height: proxy.size.height * 0.12)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * WaterTimingGameModel.targetY
                        )

                    ZStack {
                        Circle()
                            .strokeBorder(MiniGameKind.waterTiming.tint.opacity(0.72), lineWidth: 4)
                        Text(AppLocalization.text("花心"))
                            .lpText(LP.Typography.c2Medium)
                            .foregroundStyle(LP.Content.secondary)
                    }
                    .frame(width: 70, height: 70)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * WaterTimingGameModel.targetY
                    )

                    MiniGameFlowerAsset(level: 2)
                        .frame(width: 104, height: 104)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.79)

                    if !model.isResolving {
                        MiniGameDewAsset()
                            .frame(width: 42, height: 54)
                            .position(x: proxy.size.width / 2, y: dropY * proxy.size.height)
                    } else if let grade = model.impactGrade {
                        Circle()
                            .strokeBorder(grade.tint.opacity(1 - impactProgress), lineWidth: 5)
                            .frame(width: 64, height: 64)
                            .scaleEffect(0.55 + impactProgress * 1.25)
                            .position(
                                x: proxy.size.width / 2,
                                y: model.impactY * proxy.size.height
                            )

                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(grade.tint.opacity(1 - impactProgress))
                                .frame(width: 8, height: 8)
                                .offset(
                                    x: cos(Double(index) * 1.256) * impactProgress * 42,
                                    y: sin(Double(index) * 1.256) * impactProgress * 30
                                )
                                .position(
                                    x: proxy.size.width / 2,
                                    y: model.impactY * proxy.size.height
                                )
                        }
                    }

                    MiniGameStageCaption(
                        model.feedbackText,
                        foreground: model.impactGrade?.tint ?? LP.Content.secondary,
                        fill: LP.Fill.bgContainer.opacity(0.92)
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: dynamicTypeSize.isAccessibilitySize ? 54 : 26
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.waterNow() }
                .onAppear { model.updateStageSize(proxy.size) }
                .onChange(of: proxy.size) { _, size in model.updateStageSize(size) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.text("浇水计时游戏区"))
        .accessibilityValue(AppLocalization.text(model.feedbackText))
        .accessibilityHint(AppLocalization.text("水滴进入花心圆环时浇水"))
        .accessibilityAction(named: AppLocalization.text("浇水")) { model.waterNow() }
    }
}

private enum WaterTimingGrade {
    case perfect
    case close
    case miss

    var tint: Color {
        switch self {
        case .perfect: return LP.Fill.foundationSuccess
        case .close: return LP.Colorful.yellow700
        case .miss: return LP.Fill.foundationError
        }
    }
}

@MainActor
@Observable
private final class WaterTimingGameModel {
    static let targetY = 0.58
    private static let startY = 0.08
    private static let endY = 0.94
    private static let sessionDuration = 35.0
    private static let impactDuration = 0.46

    var score = 0
    var streak = 0
    var bestStreak = 0
    var timeLeft = 35
    var hasStarted = false
    var isRunning = false
    var isResolving = false
    var isFinished = false
    var feedbackText = "水滴进入花心时点按"
    var impactGrade: WaterTimingGrade?
    var impactY = targetY
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var sessionElapsed = 0.0
    @ObservationIgnored private var sessionStartedAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var dropElapsed = 0.0
    @ObservationIgnored private var dropStartedAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var dropDuration = 1.65
    @ObservationIgnored private var impactElapsed = 0.0
    @ObservationIgnored private var impactStartedAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var stageHeight = 400.0

    func startLoop() {
        guard loopTask == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        sessionStartedAt = now
        dropStartedAt = now
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func currentDropY() -> Double {
        let progress = min(1, currentDropElapsed() / dropDuration)
        return Self.startY + (Self.endY - Self.startY) * progress
    }

    func currentImpactProgress() -> Double {
        guard isResolving else { return 0 }
        return min(1, currentImpactElapsed() / Self.impactDuration)
    }

    func updateStageSize(_ size: CGSize) {
        guard size.height > 0 else { return }
        stageHeight = Double(size.height)
    }

    func waterNow() {
        guard isRunning, !isFinished, !isResolving else { return }
        let y = currentDropY()
        let distancePoints = abs(y - Self.targetY) * stageHeight

        if distancePoints <= 18 {
            streak += 1
            bestStreak = max(bestStreak, streak)
            score += 10 + streak * 2
            beginImpact(.perfect, y: y, message: streak > 1 ? "完美 · 连续 \(streak)" : "正中花心")
            LPHaptics.success()
        } else if distancePoints <= 42 {
            score += 3
            streak = max(0, streak - 1)
            beginImpact(.close, y: y, message: "擦到花心")
            LPHaptics.tap()
        } else {
            streak = 0
            beginImpact(.miss, y: y, message: y < Self.targetY ? "早了一点" : "晚了一点")
            LPHaptics.decline()
        }
    }

    func toggleRunning() {
        if !hasStarted {
            start()
        } else {
            isRunning ? pause() : resume()
        }
    }

    func start() {
        guard !hasStarted, !isFinished else { return }
        hasStarted = true
        isRunning = true
        let now = ProcessInfo.processInfo.systemUptime
        sessionStartedAt = now
        dropStartedAt = now
        startLoop()
    }

    func pause() {
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        sessionElapsed = currentSessionElapsed(at: now)
        if isResolving {
            impactElapsed = currentImpactElapsed(at: now)
        } else {
            dropElapsed = currentDropElapsed(at: now)
        }
        isRunning = false
        stopLoop()
    }

    func resume() {
        guard !isFinished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        sessionStartedAt = now
        if isResolving {
            impactStartedAt = now
        } else {
            dropStartedAt = now
        }
        isRunning = true
        startLoop()
    }

    func reset() {
        stopLoop()
        let now = ProcessInfo.processInfo.systemUptime
        score = 0
        streak = 0
        bestStreak = 0
        timeLeft = 35
        hasStarted = false
        isRunning = false
        isResolving = false
        isFinished = false
        feedbackText = "水滴进入花心时点按"
        impactGrade = nil
        impactY = Self.targetY
        resultMessage = ""
        sessionElapsed = 0
        sessionStartedAt = now
        dropElapsed = 0
        dropStartedAt = now
        dropDuration = 1.65
        impactElapsed = 0
        impactStartedAt = now
    }

    private func tick() {
        guard isRunning, !isFinished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = currentSessionElapsed(at: now)
        let nextTimeLeft = max(0, Int(ceil(Self.sessionDuration - elapsed)))
        if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
        if elapsed >= Self.sessionDuration {
            finish()
            return
        }

        if isResolving {
            if currentImpactElapsed(at: now) >= Self.impactDuration {
                startNextDrop(at: now)
            }
        } else if currentDropElapsed(at: now) >= dropDuration {
            streak = 0
            beginImpact(.miss, y: Self.endY, message: "水滴落空 · 下一滴")
            LPHaptics.decline()
        }
    }

    private func beginImpact(_ grade: WaterTimingGrade, y: Double, message: String) {
        impactGrade = grade
        impactY = y
        feedbackText = message
        isResolving = true
        impactElapsed = 0
        impactStartedAt = ProcessInfo.processInfo.systemUptime
    }

    private func startNextDrop(at now: TimeInterval) {
        isResolving = false
        impactGrade = nil
        dropElapsed = 0
        dropStartedAt = now
        dropDuration = max(0.96, 1.65 - Double(min(streak, 12)) * 0.045)
        feedbackText = streak > 0 ? "保持连击" : "等水滴进入花心"
    }

    private func currentSessionElapsed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        min(Self.sessionDuration, sessionElapsed + (isRunning ? max(0, now - sessionStartedAt) : 0))
    }

    private func currentDropElapsed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        dropElapsed + (isRunning && !isResolving ? max(0, now - dropStartedAt) : 0)
    }

    private func currentImpactElapsed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        impactElapsed + (isRunning && isResolving ? max(0, now - impactStartedAt) : 0)
    }

    private func finish() {
        guard !isFinished else { return }
        isRunning = false
        stopLoop()
        resultMessage = miniGameRecordedResult(
            for: .waterTiming,
            score: score,
            fallback: bestStreak >= 5
                ? "最高连续 \(bestStreak) 次，花心被浇准了。"
                : "最高连续 \(bestStreak) 次。Pibo 说下滴水会更准。"
        )
        isFinished = true
    }
}
