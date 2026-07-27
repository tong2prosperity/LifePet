import Foundation
import Observation
import SwiftUI

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
