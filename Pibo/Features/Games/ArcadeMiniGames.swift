import SwiftUI
import AVFoundation
import Foundation
import Observation

// MARK: - 合成花朵

struct FlowerMergeGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = FlowerMergeGameModel()

    var body: some View {
        MiniGameShell(
            kind: .flowerMerge,
            scoreText: miniGameScoreText(for: .flowerMerge, score: model.score),
            detailText: model.hasStarted
                ? (model.isRunning
                    ? "\(model.timeLeft)s · 下一朵 \(model.currentLevel + 1)"
                    : "暂停 · \(model.timeLeft)s")
                : "拖动瞄准，再开始",
            onClose: { dismiss() }
        ) {
            FlowerMergeStage(model: model)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: "落下",
                    system: "arrow.down",
                    variant: .primary,
                    disabled: !model.isRunning || model.isFinished || model.isDropLocked
                ) {
                    model.dropFlower()
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
                primaryTitle: "再来",
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

private struct FlowerMergeStage: View {
    let model: FlowerMergeGameModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.38))

                Rectangle()
                    .fill(LP.Fill.foundationError.opacity(0.22 + model.overflowProgress * 0.58))
                    .frame(height: model.overflowProgress > 0 ? 4 : 2)
                    .offset(y: proxy.size.height * 0.18)

                Rectangle()
                    .fill(MiniGameKind.flowerMerge.tint.opacity(0.14))
                    .frame(width: 2, height: proxy.size.height * 0.11)
                    .position(x: model.aimX * proxy.size.width, y: proxy.size.height * 0.075)

                MergeFlowerView(level: model.currentLevel)
                    .opacity(model.isDropReady ? 1 : 0.42)
                    .position(x: model.aimX * proxy.size.width, y: 38)

                ForEach(model.flowers) { flower in
                    MergeFlowerView(level: flower.level)
                        .position(x: flower.x * proxy.size.width, y: flower.y * proxy.size.height)
                }

                VStack {
                    Spacer()
                    MiniGameStageCaption(
                        "拖动瞄准 · 点按落下",
                        textStyle: LP.Typography.c2Medium,
                        foreground: LP.Content.tertiary,
                        fill: LP.Fill.bgContainer.opacity(0.88)
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
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        model.setAim(x: value.location.x, stageWidth: proxy.size.width)
                    }
                    .onEnded { value in
                        model.setAim(x: value.location.x, stageWidth: proxy.size.width)
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        model.setAim(x: value.location.x, stageWidth: proxy.size.width)
                        model.dropFlower()
                    }
            )
            .onAppear { model.updateStageSize(proxy.size) }
            .onChange(of: proxy.size) { _, size in model.updateStageSize(size) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.text("合成花朵游戏区"))
        .accessibilityHint(AppLocalization.text("左右轻扫移动落点，双击投放花朵"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.moveAim(by: 0.1)
            case .decrement: model.moveAim(by: -0.1)
            @unknown default: break
            }
        }
        .accessibilityValue(AppLocalization.text("落点 \(Int((model.aimX * 100).rounded()))%"))
        .accessibilityAction { model.dropFlower() }
    }
}

private struct MergeFlowerView: View {
    let level: Int

    var body: some View {
        ZStack {
            MiniGameFlowerAsset(level: level)
            Text("\(level + 1)")
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.primary.opacity(0.72))
                .offset(y: CGFloat(13 + level * 3))
        }
    }
}

@MainActor
@Observable
private final class FlowerMergeGameModel {
    var flowers: [MergeFlower] = []
    var currentLevel = 0
    var aimX = 0.5
    var maxUnlockedLevel = 1
    var score = 0
    var timeLeft = 90
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var isDropLocked = false
    var overflowProgress = 0.0
    var resultTitle = "花盆满了"
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var dropUnlockTask: Task<Void, Never>?
    @ObservationIgnored private var lastUpdateAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var remainingTime = 90.0
    @ObservationIgnored private var stageSize = CGSize(width: 360, height: 500)

    private let maxLevel = 5
    private let bucketSizePoints = 96.0

    var isDropReady: Bool {
        isRunning && !isFinished && !isDropLocked
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
                let delta = min(0.06, max(0, now - self.lastUpdateAt))
                self.lastUpdateAt = now
                self.tick(delta: delta)
            }
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        dropUnlockTask?.cancel()
        dropUnlockTask = nil
        isDropLocked = false
    }

    func setAim(x: CGFloat, stageWidth: CGFloat) {
        guard stageWidth > 0 else { return }
        aimX = (Double(x / stageWidth)).clamped(to: 0.08...0.92)
    }

    func updateStageSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        stageSize = size
    }

    func moveAim(by amount: Double) {
        guard isRunning, !isFinished else { return }
        aimX = (aimX + amount).clamped(to: 0.08...0.92)
        LPHaptics.tap()
    }

    func dropFlower() {
        guard isDropReady else { return }
        flowers.append(MergeFlower(
            level: currentLevel,
            x: aimX,
            y: 0.08,
            vx: Double.random(in: -0.034...0.034),
            vy: 0
        ))
        currentLevel = nextDropLevel()
        isDropLocked = true
        dropUnlockTask?.cancel()
        dropUnlockTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.isDropLocked = false
        }
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
        startLoop()
    }

    func pause() {
        isRunning = false
        stopLoop()
    }

    func resume() {
        guard !isFinished else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        startLoop()
    }

    func reset() {
        stopLoop()
        flowers = []
        currentLevel = 0
        aimX = 0.5
        maxUnlockedLevel = 1
        score = 0
        timeLeft = 90
        remainingTime = 90
        hasStarted = false
        isRunning = false
        isFinished = false
        isDropLocked = false
        overflowProgress = 0
        resultTitle = "花盆满了"
        resultMessage = ""
        dropUnlockTask?.cancel()
        dropUnlockTask = nil
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
    }

    private func tick(delta: TimeInterval) {
        guard isRunning, !isFinished, delta > 0 else { return }

        remainingTime = max(0, remainingTime - delta)
        let nextTimeLeft = max(0, Int(ceil(remainingTime)))
        if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
        if remainingTime <= 0 {
            finish(title: "花盆收工", message: "九十秒到了，Pibo 把花先收起来。")
            return
        }

        guard !flowers.isEmpty else { return }
        var nextFlowers = flowers
        integrate(&nextFlowers, delta: delta)
        let didMerge = mergeTouchingFlowers(&nextFlowers)
        settleCollisions(&nextFlowers)
        if nextFlowers != flowers { flowers = nextFlowers }
        if didMerge { LPHaptics.success() }

        let isOverflowing = nextFlowers.count > 12 && nextFlowers.contains {
            $0.y - flowerRadiusY(for: $0.level) < 0.18
        }
        overflowProgress = isOverflowing
            ? min(1, overflowProgress + delta / 1.5)
            : max(0, overflowProgress - delta * 1.4)
        if overflowProgress >= 1 {
            finish(title: "花盆满了", message: "Pibo 说还能再塞一朵。")
        }
    }

    private func integrate(_ flowers: inout [MergeFlower], delta: TimeInterval) {
        let friction = pow(0.86, delta / 0.035)
        for index in flowers.indices {
            let radiusX = flowerRadiusX(for: flowers[index].level)
            let radiusY = flowerRadiusY(for: flowers[index].level)
            flowers[index].vy = min(flowers[index].vy + 0.62 * delta, 0.52)
            flowers[index].x += flowers[index].vx * delta
            flowers[index].y += flowers[index].vy * delta

            if flowers[index].x < 0.08 + radiusX {
                flowers[index].x = 0.08 + radiusX
                flowers[index].vx = abs(flowers[index].vx) * 0.35
            } else if flowers[index].x > 0.92 - radiusX {
                flowers[index].x = 0.92 - radiusX
                flowers[index].vx = -abs(flowers[index].vx) * 0.35
            }

            if flowers[index].y > 0.92 - radiusY {
                flowers[index].y = 0.92 - radiusY
                flowers[index].vy = abs(flowers[index].vy) < 0.025
                    ? 0
                    : min(0, flowers[index].vy * -0.12)
                flowers[index].vx *= friction
                if abs(flowers[index].vx) < 0.001 { flowers[index].vx = 0 }
            }
        }
    }

    private func settleCollisions(_ flowers: inout [MergeFlower]) {
        guard flowers.count > 1 else { return }
        for _ in 0..<2 {
            for pair in nearbyPairs(in: flowers) {
                let leftIndex = pair.left
                let rightIndex = pair.right
                let dx = (flowers[rightIndex].x - flowers[leftIndex].x) * Double(stageSize.width)
                let dy = (flowers[rightIndex].y - flowers[leftIndex].y) * Double(stageSize.height)
                let rawDistance = hypot(dx, dy)
                let distance = max(0.1, rawDistance)
                let target = flowerRadiusPoints(for: flowers[leftIndex].level)
                    + flowerRadiusPoints(for: flowers[rightIndex].level) + 2
                guard distance < target else { continue }

                let overlap = (target - distance) * 0.5
                let nx = rawDistance < 0.0001 ? 1 : dx / distance
                let ny = rawDistance < 0.0001 ? 0 : dy / distance
                flowers[leftIndex].x -= nx * overlap / Double(stageSize.width)
                flowers[leftIndex].y -= ny * overlap / Double(stageSize.height)
                flowers[rightIndex].x += nx * overlap / Double(stageSize.width)
                flowers[rightIndex].y += ny * overlap / Double(stageSize.height)
                flowers[leftIndex].vx -= nx * 0.02
                flowers[rightIndex].vx += nx * 0.02
                flowers[leftIndex].vy = min(flowers[leftIndex].vy, 0.085)
                flowers[rightIndex].vy = min(flowers[rightIndex].vy, 0.085)
            }
        }
    }

    @discardableResult
    private func mergeTouchingFlowers(_ flowers: inout [MergeFlower]) -> Bool {
        var consumed = Set<UUID>()
        var additions: [MergeFlower] = []

        for pair in nearbyPairs(in: flowers) {
            let left = flowers[pair.left]
            let right = flowers[pair.right]
            guard left.level == right.level,
                  left.level < maxLevel,
                  !consumed.contains(left.id),
                  !consumed.contains(right.id),
                  centerDistancePoints(left, right)
                    <= flowerRadiusPoints(for: left.level) + flowerRadiusPoints(for: right.level) + 3
            else { continue }

            let newLevel = left.level + 1
            consumed.insert(left.id)
            consumed.insert(right.id)
            additions.append(MergeFlower(
                level: newLevel,
                x: (left.x + right.x) / 2,
                y: max(0.08, min(left.y, right.y) - 6 / Double(stageSize.height)),
                vx: (left.vx + right.vx) * 0.25,
                vy: -0.085
            ))
            maxUnlockedLevel = max(maxUnlockedLevel, newLevel)
            score += (newLevel + 1) * (newLevel + 1) * 12
        }

        guard !consumed.isEmpty else { return false }
        flowers.removeAll { consumed.contains($0.id) }
        flowers.append(contentsOf: additions)
        return true
    }

    private func nearbyPairs(in flowers: [MergeFlower]) -> [MergePair] {
        var buckets: [MergeSpatialCell: [Int]] = [:]
        for index in flowers.indices {
            buckets[spatialCell(for: flowers[index]), default: []].append(index)
        }

        var pairs: [MergePair] = []
        for leftIndex in flowers.indices {
            let cell = spatialCell(for: flowers[leftIndex])
            for xOffset in -1...1 {
                for yOffset in -1...1 {
                    let neighbor = MergeSpatialCell(x: cell.x + xOffset, y: cell.y + yOffset)
                    for rightIndex in buckets[neighbor, default: []] where rightIndex > leftIndex {
                        pairs.append(MergePair(left: leftIndex, right: rightIndex))
                    }
                }
            }
        }
        return pairs
    }

    private func spatialCell(for flower: MergeFlower) -> MergeSpatialCell {
        MergeSpatialCell(
            x: Int(floor(flower.x * Double(stageSize.width) / bucketSizePoints)),
            y: Int(floor(flower.y * Double(stageSize.height) / bucketSizePoints))
        )
    }

    private func centerDistancePoints(_ left: MergeFlower, _ right: MergeFlower) -> Double {
        hypot(
            (right.x - left.x) * Double(stageSize.width),
            (right.y - left.y) * Double(stageSize.height)
        )
    }

    private func finish(title: String, message: String) {
        guard !isFinished else { return }
        isRunning = false
        stopLoop()
        dropUnlockTask?.cancel()
        dropUnlockTask = nil
        isDropLocked = false
        resultTitle = title
        resultMessage = miniGameRecordedResult(
            for: .flowerMerge,
            score: score,
            fallback: "分数 \(score)。\(message)"
        )
        isFinished = true
    }

    private func nextDropLevel() -> Int {
        let cap = min(3, maxUnlockedLevel)
        let roll = Int.random(in: 0..<100)
        if cap >= 2, roll > 82 { return 2 }
        if cap >= 1, roll > 42 { return 1 }
        return 0
    }

    private func flowerRadiusPoints(for level: Int) -> Double {
        17 + Double(min(level, maxLevel)) * 5.5
    }

    private func flowerRadiusX(for level: Int) -> Double {
        flowerRadiusPoints(for: level) / Double(stageSize.width)
    }

    private func flowerRadiusY(for level: Int) -> Double {
        flowerRadiusPoints(for: level) / Double(stageSize.height)
    }
}

private struct MergeFlower: Identifiable, Equatable {
    let id = UUID()
    var level: Int
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
}

private struct MergeSpatialCell: Hashable {
    let x: Int
    let y: Int
}

private struct MergePair {
    let left: Int
    let right: Int
}

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
        let overlap = max(0, last.width - abs(movement.x - last.x))
        guard overlap > 0.12 else {
            finish(title: "花塔倒了", message: "Pibo 说刚刚是风。")
            LPHaptics.decline()
            return
        }
        let offset = abs(movement.x - last.x)
        let isPerfect = offset < 0.018
        perfectStreak = isPerfect ? perfectStreak + 1 : 0
        let nextWidth = isPerfect ? min(0.78, last.width + min(0.035, Double(perfectStreak) * 0.006)) : min(last.width, overlap)
        let nextX = isPerfect ? last.x : (movement.x + last.x) / 2
        stack.append(StackPot(width: nextWidth, x: nextX, level: stack.count))
        score += 1 + (isPerfect ? min(3, perfectStreak) : 0)
        feedbackText = isPerfect ? "完美！连续 \(perfectStreak) 次" : "削掉了 \(Int(((last.width - nextWidth) / last.width) * 100))%"
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

// MARK: - 节奏点击

struct RhythmTapGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = RhythmTapGameModel()

    var body: some View {
        MiniGameShell(
            kind: .rhythmTap,
            scoreText: miniGameScoreText(for: .rhythmTap, score: model.score),
            detailText: model.hasStarted
                ? "\(model.timeLeft)s · \(model.audioStatus) · 连 \(model.combo)"
                : "先听四拍",
            onClose: { dismiss() }
        ) {
            RhythmTapStage(model: model)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: "点",
                    system: "hand.tap.fill",
                    variant: .primary,
                    disabled: !model.isRunning || model.isFinished
                ) {
                    model.tapBeat()
                }
                MiniGameActionButton(
                    title: model.isRunning ? "暂停" : (model.hasStarted ? "继续" : "开始"),
                    system: model.isRunning ? "pause.fill" : "play.fill",
                    disabled: model.isFinished
                ) {
                    model.startOrToggle()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { model.reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "节拍亮度 \(model.score)",
                message: model.resultMessage,
                primaryTitle: "再点",
                primarySystem: "arrow.clockwise",
                primaryAction: { model.reset() }
            )
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.isRunning {
                model.pause()
            }
        }
    }
}

private struct RhythmTapStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: RhythmTapGameModel

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                paused: !model.isRunning
            )
        ) { _ in
            GeometryReader { proxy in
                let state = model.visualState()
                let targetX = proxy.size.width * 0.22
                let laneY = proxy.size.height * 0.60

                ZStack {
                    RadialGradient(
                        colors: [
                            MiniGameKind.rhythmTap.tint.opacity(min(0.34, Double(model.combo) * 0.018)),
                            .clear
                        ],
                        center: .top,
                        startRadius: 4,
                        endRadius: proxy.size.width * 0.7
                    )

                    MiniGameFlowerAsset(level: min(5, model.combo / 3))
                        .frame(width: 112, height: 112)
                        .scaleEffect(1 + state.targetPulse * 0.06)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.23)

                    Capsule()
                        .fill(LP.Fill.bgContainer.opacity(0.76))
                        .frame(width: proxy.size.width * 0.78, height: 18)
                        .position(x: proxy.size.width * 0.52, y: laneY)

                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .fill(LP.Fill.foundationAccent.opacity(0.20 + state.targetPulse * 0.24))
                        .frame(width: 58, height: 112)
                        .position(x: targetX, y: laneY)

                    ForEach(state.notes) { note in
                        Text(note.syllable)
                            .lpText(LP.Typography.b3Medium)
                            .foregroundStyle(LP.Fill.foundationOnAccent)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle().fill(note.isHigh
                                    ? LP.Colorful.red500
                                    : LP.Colorful.orange500)
                            )
                            .overlay(Circle().strokeBorder(.white.opacity(0.58), lineWidth: 1))
                            .position(x: proxy.size.width * note.x, y: laneY)
                    }

                    VStack(spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text(state.headline))
                            .lpText(LP.Typography.uiH5)
                            .foregroundStyle(LP.Content.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                        Text(AppLocalization.text(model.feedback))
                            .lpText(LP.Typography.handSmall)
                            .foregroundStyle(LP.Content.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.vertical, LP.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(LP.Fill.bgContainer.opacity(0.9))
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.76 : 0.82)
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { model.tapBeat() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("节奏点击，连续 \(model.combo) 拍"))
        .accessibilityHint(AppLocalization.text("听到 pi 或 bo 节拍时点按屏幕"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapBeat() }
    }
}

@MainActor
@Observable
private final class RhythmTapGameModel {
    var score = 0
    var combo = 0
    var maxCombo = 0
    var timeLeft = 45
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var audioStatus = "声音 + 触觉"
    var feedback = "点开始，先听四拍"
    var resultMessage = ""

    @ObservationIgnored private let audioClock = RhythmAudioClock()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var lastPulseBeat = Int.min
    @ObservationIgnored private var lastJudgedBeat = Int.min
    @ObservationIgnored private var lastResolvedBeat = -1
    @ObservationIgnored private var lastTapUptime = 0.0

    private let beatInterval = 0.6
    private let sessionLength = 45.0
    private var countInLength: Double { beatInterval * 4 }

    func startOrToggle() {
        if !hasStarted {
            startSession()
        } else if isRunning {
            pause()
        } else {
            resume()
        }
    }

    func tapBeat() {
        guard isRunning, !isFinished else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastTapUptime >= 0.12 else { return }
        lastTapUptime = uptime

        let rawElapsed = audioClock.elapsed()
        guard rawElapsed >= countInLength else {
            feedback = "先听完四拍"
            LPHaptics.decline()
            return
        }

        let rhythmElapsed = rawElapsed - countInLength
        resolveExpiredBeats(at: rhythmElapsed)
        let nearestBeat = Int((rhythmElapsed / beatInterval).rounded())
        let distance = abs(rhythmElapsed - Double(nearestBeat) * beatInterval)

        guard nearestBeat != lastJudgedBeat else {
            feedback = "这一拍点过了"
            return
        }

        if distance <= 0.075 {
            lastJudgedBeat = nearestBeat
            combo += 1
            maxCombo = max(maxCombo, combo)
            score += 10 + combo
            feedback = "正拍！\(syllable(for: nearestBeat))"
            LPHaptics.success()
        } else if distance <= 0.16 {
            lastJudgedBeat = nearestBeat
            combo += 1
            maxCombo = max(maxCombo, combo)
            score += 4
            feedback = rhythmElapsed < Double(nearestBeat) * beatInterval ? "稍早，接近了" : "稍晚，接近了"
            LPHaptics.tap()
        } else {
            combo = 0
            feedback = "等下一个 pi-bo"
            LPHaptics.decline()
        }
    }

    func pause() {
        guard isRunning else { return }
        audioClock.pause()
        monitorTask?.cancel()
        monitorTask = nil
        isRunning = false
        feedback = "暂停了，节拍不会偷跑"
    }

    func resume() {
        guard hasStarted, !isFinished else { return }
        let audioAvailable = audioClock.resume()
        audioStatus = audioAvailable ? "声音 + 触觉" : "触觉节拍"
        isRunning = true
        feedback = "继续听 pi-bo"
        startMonitor()
    }

    func reset() {
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        score = 0
        combo = 0
        maxCombo = 0
        timeLeft = 45
        hasStarted = false
        isRunning = false
        isFinished = false
        audioStatus = "声音 + 触觉"
        feedback = "点开始，先听四拍"
        resultMessage = ""
        lastPulseBeat = .min
        lastJudgedBeat = .min
        lastResolvedBeat = -1
        lastTapUptime = 0
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        isRunning = false
    }

    func visualState() -> RhythmVisualState {
        let rawElapsed = hasStarted ? audioClock.elapsed() : 0
        let rhythmElapsed = rawElapsed - countInLength
        let baseBeat = Int(floor(rhythmElapsed / beatInterval))
        var notes: [RhythmLaneNote] = []

        for beat in (baseBeat - 1)...(baseBeat + 4) {
            let secondsUntilBeat = Double(beat) * beatInterval - rhythmElapsed
            let x = 0.22 + secondsUntilBeat / (beatInterval * 2.5) * 0.72
            guard x > -0.1, x < 1.12 else { continue }
            notes.append(RhythmLaneNote(
                id: beat,
                syllable: syllable(for: beat),
                isHigh: normalizedPatternIndex(for: beat).isMultiple(of: 2),
                x: x
            ))
        }

        let nearestBeat = (rhythmElapsed / beatInterval).rounded()
        let distance = abs(rhythmElapsed - nearestBeat * beatInterval)
        let pulse = max(0, 1 - distance / 0.16)
        let headline: String
        if !hasStarted {
            headline = "听见 pi-bo 时点按"
        } else if rawElapsed < countInLength {
            headline = "准备 \(max(1, Int(ceil((countInLength - rawElapsed) / beatInterval))))"
        } else {
            headline = "pi · bo · pi · bo"
        }
        return RhythmVisualState(notes: notes, targetPulse: pulse, headline: headline)
    }

    private func startSession() {
        let audioAvailable = audioClock.start()
        audioStatus = audioAvailable ? "声音 + 触觉" : "触觉节拍"
        hasStarted = true
        isRunning = true
        feedback = "先听四拍"
        lastPulseBeat = .min
        startMonitor()
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                guard let self, self.isRunning, !self.isFinished else { continue }
                let rawElapsed = self.audioClock.elapsed()
                let beat = Int(floor((rawElapsed + 0.04) / self.beatInterval))
                if beat != self.lastPulseBeat {
                    self.lastPulseBeat = beat
                    LPHaptics.tap()
                }

                guard rawElapsed >= self.countInLength else { continue }
                let gameElapsed = rawElapsed - self.countInLength
                self.resolveExpiredBeats(at: gameElapsed)
                let nextTimeLeft = max(0, Int(ceil(self.sessionLength - gameElapsed)))
                if nextTimeLeft != self.timeLeft { self.timeLeft = nextTimeLeft }
                if gameElapsed >= self.sessionLength { self.finish() }
            }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        resultMessage = miniGameRecordedResult(
            for: .rhythmTap,
            score: score,
            fallback: maxCombo >= 8 ? "花亮得有点吵。最高连拍 \(maxCombo)。" : "Pibo 说乱码还没对齐。"
        )
        isFinished = true
    }

    private func resolveExpiredBeats(at rhythmElapsed: TimeInterval) {
        let latestExpiredBeat = Int(floor((rhythmElapsed - 0.17) / beatInterval))
        guard latestExpiredBeat > lastResolvedBeat else { return }

        while lastResolvedBeat < latestExpiredBeat {
            lastResolvedBeat += 1
            if lastJudgedBeat != lastResolvedBeat {
                combo = 0
                feedback = "漏了一拍，听下一个 pi-bo"
            }
        }
    }

    private func syllable(for beat: Int) -> String {
        ["pi", "bo", "pi", "bo"][normalizedPatternIndex(for: beat)]
    }

    private func normalizedPatternIndex(for beat: Int) -> Int {
        ((beat % 4) + 4) % 4
    }
}

private struct RhythmVisualState {
    let notes: [RhythmLaneNote]
    let targetPulse: Double
    let headline: String
}

private struct RhythmLaneNote: Identifiable {
    let id: Int
    let syllable: String
    let isHigh: Bool
    let x: Double
}

@MainActor
private final class RhythmAudioClock {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private let beatInterval = 0.6
    private var loopBuffer: AVAudioPCMBuffer?
    private var fallbackAccumulated = 0.0
    private var fallbackStartedAt = 0.0
    private var isRunning = false
    private var isAudioAvailable = false
    private var didActivateSession = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            loopBuffer = makeLoopBuffer(format: format)
        }
        player.volume = 0.55
    }

    func start() -> Bool {
        stop()
        fallbackAccumulated = 0
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true

        guard let loopBuffer else {
            isAudioAvailable = false
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            didActivateSession = true
            player.scheduleBuffer(loopBuffer, at: nil, options: [.loops])
            engine.prepare()
            try engine.start()
            player.play()
            isAudioAvailable = true
        } catch {
            player.stop()
            engine.stop()
            isAudioAvailable = false
            if didActivateSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                didActivateSession = false
            }
        }
        return isAudioAvailable
    }

    func pause() {
        guard isRunning else { return }
        fallbackAccumulated = elapsed()
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = false
        if isAudioAvailable { player.pause() }
    }

    @discardableResult
    func resume() -> Bool {
        guard !isRunning else { return isAudioAvailable }
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        if isAudioAvailable {
            do {
                if !engine.isRunning { try engine.start() }
                player.play()
            } catch {
                isAudioAvailable = false
            }
        }
        return isAudioAvailable
    }

    func stop() {
        player.stop()
        engine.stop()
        isRunning = false
        isAudioAvailable = false
        fallbackAccumulated = 0
        fallbackStartedAt = 0
        if didActivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            didActivateSession = false
        }
    }

    func elapsed() -> TimeInterval {
        if isAudioAvailable,
           let renderTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: renderTime) {
            return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        }
        guard isRunning else { return fallbackAccumulated }
        return fallbackAccumulated + max(0, ProcessInfo.processInfo.systemUptime - fallbackStartedAt)
    }

    private func makeLoopBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let barDuration = beatInterval * 4
        let frameCount = AVAudioFrameCount((barDuration * sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        let frequencies = [720.0, 480.0, 660.0, 440.0]
        let toneFrames = Int((0.12 * sampleRate).rounded())
        let attackFrames = max(1, Int((0.008 * sampleRate).rounded()))
        for beat in 0..<4 {
            let startFrame = Int((Double(beat) * beatInterval * sampleRate).rounded())
            for frame in 0..<toneFrames where startFrame + frame < Int(frameCount) {
                let progress = Double(frame) / Double(toneFrames)
                let attack = min(1, Double(frame) / Double(attackFrames))
                let envelope = attack * pow(1 - progress, 1.6)
                let phase = 2 * Double.pi * frequencies[beat] * Double(frame) / sampleRate
                channel[startFrame + frame] += Float(sin(phase) * envelope * 0.24)
            }
        }
        return buffer
    }
}

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

// MARK: - 放置花田

struct IdleGardenGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenLastCollectAt)
    private var lastCollectAt = 0.0
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenSeeds)
    private var storedSeeds = 0
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenPlantedPlots)
    private var plantedPlots = 1

    @State private var collectionMessage = "...没有惩罚，只有花。"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let snapshot = GardenProductionSnapshot(
                now: timeline.date,
                lastCollectedAt: lastCollectAt,
                plantedPlots: plantedPlots
            )

            MiniGameShell(
                kind: .idleGarden,
                scoreText: "🌱 \(storedSeeds)",
                detailText: "\(plantedPlots)/24 花圃 · \(snapshot.readyFlowers) 可收",
                onClose: { dismiss() }
            ) {
                GeometryReader { proxy in
                    ZStack {
                        ForEach(0..<24, id: \.self) { index in
                            gardenPlot(
                                index: index,
                                isPlanted: index < plantedPlots,
                                isReady: index < snapshot.readyFlowers
                            )
                            .position(
                                x: CGFloat((index % 6) + 1) * proxy.size.width / 7,
                                y: CGFloat((index / 6) + 1) * proxy.size.height / 5
                            )
                        }

                        VStack(spacing: 3) {
                            Text(AppLocalization.text(collectionMessage))
                                .lpText(LP.Typography.handSmall)
                                .foregroundStyle(LP.Content.secondary)
                            Text(AppLocalization.text(snapshot.nextFlowerText))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: proxy.size.width - 32)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 28)
                    }
                }
            } bottomBar: {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: "收 \(snapshot.readyFlowers) 朵",
                        system: "tray.and.arrow.down.fill",
                        variant: .primary,
                        disabled: snapshot.readyFlowers == 0
                    ) {
                        collect(snapshot.readyFlowers, at: timeline.date)
                    }
                    MiniGameActionButton(
                        title: plantedPlots >= 24 ? "已种满" : "扩一块",
                        system: "leaf.fill",
                        disabled: storedSeeds <= 0 || plantedPlots >= 24
                    ) {
                        plantPlot(snapshot: snapshot, at: timeline.date)
                    }
                }
            }
        }
        .onAppear {
            if lastCollectAt == 0 {
                lastCollectAt = Date().timeIntervalSince1970 - GardenProductionSnapshot.growDuration
            }
            plantedPlots = plantedPlots.clamped(to: 1...24)
        }
    }

    @ViewBuilder
    private func gardenPlot(index: Int, isPlanted: Bool, isReady: Bool) -> some View {
        if isReady {
            MiniGameFlowerAsset(level: index % 4)
                .frame(width: 44, height: 44)
        } else if isPlanted {
            MiniGameSproutAsset()
                .frame(width: 30, height: 36)
                .opacity(0.62)
        } else {
            Circle()
                .strokeBorder(LP.Border.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LP.Content.tertiary)
                )
        }
    }

    private func collect(_ collected: Int, at date: Date) {
        guard collected > 0 else { return }
        storedSeeds += collected
        lastCollectAt = date.timeIntervalSince1970
        let newBest = MiniGameBestScoreStore().record(collected, for: .idleGarden)
        let reward = MiniGameRewardStore().grantPetals(for: collected, kind: .idleGarden)
        miniGameTrackResult(kind: .idleGarden, score: collected, reward: reward, newBest: newBest)
        let bestLine = newBest ? "这次最多。" : "慢慢攒。"
        let starLine = MiniGameScoring.starText(score: collected, kind: .idleGarden)
        collectionMessage = reward.petals > 0
            ? "收了 \(collected) 朵，花瓣 +\(reward.petals)。\(starLine)。\(bestLine)"
            : "收了 \(collected) 朵，Pibo 假装不在意。\(starLine)。\(bestLine)"
        LPHaptics.success()
    }

    private func plantPlot(snapshot: GardenProductionSnapshot, at date: Date) {
        guard storedSeeds > 0, plantedPlots < 24 else { return }
        storedSeeds -= 1
        plantedPlots += 1
        lastCollectAt = date.timeIntervalSince1970
            - snapshot.progressFraction * GardenProductionSnapshot.growDuration
        collectionMessage = "多了一块花圃；花会在三分钟内依次长好。"
        LPHaptics.tap()
    }
}

private struct GardenProductionSnapshot {
    static let growDuration = 180.0

    let readyFlowers: Int
    let secondsUntilNext: Int
    let plantedPlots: Int
    let progressFraction: Double

    init(now: Date, lastCollectedAt: Double, plantedPlots: Int) {
        self.plantedPlots = plantedPlots.clamped(to: 1...24)
        let reference = lastCollectedAt == 0
            ? now.timeIntervalSince1970 - Self.growDuration
            : lastCollectedAt
        let elapsed = max(0, now.timeIntervalSince1970 - reference)
        progressFraction = min(1, elapsed / Self.growDuration)
        let exactProgress = progressFraction * Double(self.plantedPlots)
        readyFlowers = Int(floor(exactProgress))

        if readyFlowers >= self.plantedPlots {
            secondsUntilNext = 0
        } else {
            let nextThreshold = Double(readyFlowers + 1) / Double(self.plantedPlots) * Self.growDuration
            secondsUntilNext = max(1, Int(ceil(nextThreshold - elapsed)))
        }
    }

    var nextFlowerText: String {
        guard secondsUntilNext > 0 else { return "这一批已经长好，不收也不会枯" }
        return "下一朵约 \(secondsUntilNext / 60):\(String(format: "%02d", secondsUntilNext % 60)) 后长好"
    }
}
