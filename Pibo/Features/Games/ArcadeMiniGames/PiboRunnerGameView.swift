import Foundation
import Observation
import SwiftUI

// MARK: - 宠物跑酷

struct PiboRunnerGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = PiboRunnerGameModel()

    var body: some View {
        MiniGameShell(
            kind: .piboRunner,
            scoreText: miniGameScoreText(for: .piboRunner, score: model.score),
            detailText: model.hasStarted
                ? (model.isRunning
                    ? "\(model.timeLeft)s · 越过 \(model.rocksCleared) 块"
                    : "暂停 · \(model.timeLeft)s")
                : "准备好再起跑",
            onClose: { dismiss() }
        ) {
            PiboRunnerStage(model: model)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: "跳",
                    system: "arrow.up",
                    variant: .primary,
                    disabled: !model.canJump
                ) {
                    model.jump()
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
                title: model.resultTitle,
                message: model.resultMessage,
                primaryTitle: "再跑",
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

private struct PiboRunnerStage: View {
    let model: PiboRunnerGameModel

    var body: some View {
        GeometryReader { proxy in
            let groundY = proxy.size.height * PiboRunnerGameModel.groundRatio

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.34))

                runnerScenery(size: proxy.size, groundY: groundY)

                ForEach(model.obstacles) { obstacle in
                    MiniGameRockAsset()
                        .frame(
                            width: PiboRunnerGameModel.rockSize.width,
                            height: PiboRunnerGameModel.rockSize.height
                        )
                        .position(
                            x: obstacle.x * proxy.size.width,
                            y: groundY - PiboRunnerGameModel.rockSize.height / 2
                        )
                }

                MiniGamePiboAsset(flowerScale: 0.42)
                    .frame(
                        width: PiboRunnerGameModel.playerSize.width,
                        height: PiboRunnerGameModel.playerSize.height
                    )
                    .position(
                        x: proxy.size.width * PiboRunnerGameModel.playerX,
                        y: groundY - PiboRunnerGameModel.playerSize.height / 2 - model.playerHeight
                    )

                VStack {
                    Spacer()
                    MiniGameStageCaption(
                        model.stageMessage,
                        textStyle: LP.Typography.c2Medium
                    )
                        .padding(.bottom, LP.Spacing.m)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.jump() }
            .onAppear { model.updateStageSize(proxy.size) }
            .onChange(of: proxy.size) { _, size in model.updateStageSize(size) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.text("宠物跑酷游戏区"))
        .accessibilityValue(AppLocalization.text("跑了 \(model.score) 米，越过 \(model.rocksCleared) 块石头"))
        .accessibilityHint(AppLocalization.text("点按屏幕或跳按钮，跳过迎面而来的石块"))
        .accessibilityAction(named: AppLocalization.text("跳")) { model.jump() }
    }

    @ViewBuilder
    private func runnerScenery(size: CGSize, groundY: CGFloat) -> some View {
        let markerCount = 7

        Rectangle()
            .fill(LP.Content.tertiary.opacity(0.2))
            .frame(height: 3)
            .position(x: size.width / 2, y: groundY)

        ForEach(0..<markerCount, id: \.self) { index in
            let base = Double(index) / Double(markerCount)
            let phase = (base - model.trackPhase).truncatingRemainder(dividingBy: 1)
            let normalizedX = phase < 0 ? phase + 1 : phase
            Capsule()
                .fill(MiniGameKind.piboRunner.tint.opacity(0.28))
                .frame(width: 28, height: 4)
                .position(x: normalizedX * size.width, y: groundY + 16)
        }
    }
}

@MainActor
@Observable
private final class PiboRunnerGameModel {
    static let playerX = 0.22
    static let groundRatio = 0.72
    static let playerSize = CGSize(width: 64, height: 72)
    static let rockSize = CGSize(width: 34, height: 48)

    var playerHeight = 0.0
    var obstacles: [RunnerObstacle] = []
    var trackPhase = 0.0
    var score = 0
    var rocksCleared = 0
    var timeLeft = 60
    var isGrounded = true
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var stageMessage = "点按画面，跳过石块"
    var resultTitle = "跑了 0 米"
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var stageSize = CGSize.zero
    @ObservationIgnored private var playerVelocity = 0.0
    @ObservationIgnored private var elapsedTime = 0.0
    @ObservationIgnored private var distance = 0.0
    @ObservationIgnored private var nextObstacleIn = 1.55
    @ObservationIgnored private var obstaclePatternIndex = 0
    @ObservationIgnored private var hudPublishAccumulator = 0.0
    @ObservationIgnored private var lastUpdateAt = ProcessInfo.processInfo.systemUptime

    private let obstacleGaps = [1.65, 1.45, 1.8, 1.32, 1.58, 1.4]

    var canJump: Bool {
        isRunning && !isFinished && isGrounded
    }

    func startLoop() {
        guard loopTask == nil else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = min(0.08, max(0, now - self.lastUpdateAt))
                self.lastUpdateAt = now
                self.tick(delta: delta)
            }
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func updateStageSize(_ size: CGSize) {
        stageSize = size
    }

    func jump() {
        guard canJump else { return }
        playerVelocity = 420
        isGrounded = false
        stageMessage = "起跳"
        LPHaptics.tap()
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
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        stageMessage = "开始跑"
        startLoop()
    }

    func pause() {
        isRunning = false
        stageMessage = "已暂停"
        stopLoop()
    }

    func resume() {
        guard !isFinished else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        stageMessage = "继续跑"
        startLoop()
    }

    func reset() {
        stopLoop()
        playerHeight = 0
        obstacles = []
        trackPhase = 0
        score = 0
        rocksCleared = 0
        timeLeft = 60
        isGrounded = true
        hasStarted = false
        isRunning = false
        isFinished = false
        stageMessage = "点按画面，跳过石块"
        resultTitle = "跑了 0 米"
        resultMessage = ""
        playerVelocity = 0
        elapsedTime = 0
        distance = 0
        nextObstacleIn = 1.55
        obstaclePatternIndex = 0
        hudPublishAccumulator = 0
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
    }

    private func tick(delta: TimeInterval) {
        guard isRunning, !isFinished, delta > 0 else { return }

        var remainingDelta = delta
        while remainingDelta > 0, !isFinished {
            let step = min(remainingDelta, 1.0 / 60.0)
            advance(step: step)
            remainingDelta -= step
        }

        hudPublishAccumulator += delta
        if hudPublishAccumulator >= 0.2 || isFinished {
            publishHUD()
            hudPublishAccumulator = 0
        }
    }

    private func advance(step: TimeInterval) {
        elapsedTime = min(60, elapsedTime + step)
        let speed = 0.57 + min(distance / 650, 0.22)
        distance += (6.0 + min(distance / 90, 3.0)) * step
        trackPhase = (trackPhase + speed * step).truncatingRemainder(dividingBy: 1)

        playerVelocity -= 1_180 * step
        playerHeight = max(0, playerHeight + playerVelocity * step)
        if playerHeight == 0 {
            playerVelocity = 0
            if !isGrounded { isGrounded = true }
        }

        nextObstacleIn -= step
        if nextObstacleIn <= 0 {
            obstacles.append(RunnerObstacle(x: 1.06))
            let baseGap = obstacleGaps[obstaclePatternIndex % obstacleGaps.count]
            let difficultyReduction = min(distance / 1_600, 0.18)
            nextObstacleIn = max(1.08, baseGap - difficultyReduction)
            obstaclePatternIndex += 1
        }

        var didCollide = false
        var clearedCount = 0
        let playerRect = playerCollisionRect
        obstacles = obstacles.compactMap { obstacle in
            var next = obstacle
            next.x -= speed * step
            let rockRect = collisionRect(for: next)
            if !next.hasPassedPlayer,
               !playerRect.isNull,
               rockRect.maxX < playerRect.minX {
                next.hasPassedPlayer = true
                clearedCount += 1
            }
            if rockRect.intersects(playerRect) {
                didCollide = true
            }
            return next.x < -0.12 ? nil : next
        }

        if clearedCount > 0 {
            rocksCleared += clearedCount
            stageMessage = rocksCleared % 5 == 0 ? "连续越过 \(rocksCleared) 块！" : "越过去了"
            LPHaptics.success()
        }

        if didCollide {
            finish(title: "撞到石块", fallback: "跑了 \(Int(distance)) 米，越过 \(rocksCleared) 块石头。Pibo 说刚才是石头先动的。")
            LPHaptics.decline()
        } else if elapsedTime >= 60 {
            finish(title: "跑完全程", fallback: "六十秒到了，跑了 \(Int(distance)) 米，越过 \(rocksCleared) 块石头。")
            LPHaptics.success()
        }
    }

    private var playerCollisionRect: CGRect {
        guard stageSize.width > 0, stageSize.height > 0 else { return .null }
        let groundY = stageSize.height * Self.groundRatio
        let center = CGPoint(
            x: stageSize.width * Self.playerX,
            y: groundY - Self.playerSize.height / 2 - playerHeight
        )
        return CGRect(
            x: center.x - Self.playerSize.width / 2 + 11,
            y: center.y - Self.playerSize.height / 2 + 7,
            width: Self.playerSize.width - 22,
            height: Self.playerSize.height - 12
        )
    }

    private func collisionRect(for obstacle: RunnerObstacle) -> CGRect {
        guard stageSize.width > 0, stageSize.height > 0 else { return .null }
        let groundY = stageSize.height * Self.groundRatio
        let center = CGPoint(
            x: obstacle.x * stageSize.width,
            y: groundY - Self.rockSize.height / 2
        )
        return CGRect(
            x: center.x - Self.rockSize.width / 2 + 4,
            y: center.y - Self.rockSize.height / 2 + 3,
            width: Self.rockSize.width - 8,
            height: Self.rockSize.height - 5
        )
    }

    private func publishHUD() {
        score = Int(distance)
        timeLeft = max(0, Int(ceil(60 - elapsedTime)))
    }

    private func finish(title: String, fallback: String) {
        guard !isFinished else { return }
        publishHUD()
        isRunning = false
        stopLoop()
        resultTitle = title == "跑完全程" ? title : "跑了 \(score) 米"
        resultMessage = miniGameRecordedResult(for: .piboRunner, score: score, fallback: fallback)
        isFinished = true
    }
}

private struct RunnerObstacle: Identifiable, Equatable {
    let id = UUID()
    var x: Double
    var hasPassedPlayer = false
}
