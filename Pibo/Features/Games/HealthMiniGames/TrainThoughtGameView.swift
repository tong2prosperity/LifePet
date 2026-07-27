import Observation
import SwiftUI

// MARK: - Train of Thought

struct TrainThoughtGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrainThoughtGameModel()

    private let colors = [LP.Colorful.green500, LP.Colorful.orange500, LP.Colorful.cyan500]

    var body: some View {
        MiniGameShell(
            kind: .trainThought,
            scoreText: miniGameScoreText(for: .trainThought, score: model.score),
            detailText: model.hasStarted
                ? (model.isRunning
                    ? "\(model.timeLeft)s · 送达 \(model.delivered) · 连 \(model.combo) · 错 \(model.misses)/5"
                    : "暂停 · 送达 \(model.delivered)")
                : "先看道岔，再开始",
            onClose: { dismiss() }
        ) {
            TrainThoughtStage(model: model, colors: colors)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: model.isRunning ? "暂停" : (model.hasStarted ? "继续" : "开始"),
                    system: model.isRunning ? "pause.fill" : "play.fill",
                    variant: .primary,
                    disabled: model.isFinished
                ) {
                    model.toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { model.reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "送达 \(model.delivered) 列",
                message: model.resultMessage,
                primaryTitle: "再送",
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

private struct TrainThoughtStage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: TrainThoughtGameModel
    let colors: [Color]

    private let laneX = [0.2, 0.5, 0.8]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.34))

                trackPath(size: proxy.size)
                    .stroke(LP.Border.tertiary, style: StrokeStyle(lineWidth: 5, lineCap: .round))

                selectedTrackPath(size: proxy.size)
                    .stroke(
                        colors[model.selectedLane].opacity(0.78),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [12, 8])
                    )

                Circle()
                    .fill(colors[model.selectedLane])
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * TrainThoughtGameModel.junctionY)

                ForEach(model.trains) { train in
                    MiniGameTrainAsset(tint: colors[train.colorIndex])
                        .frame(width: 58, height: 32)
                        .overlay(alignment: .topTrailing) {
                            Text(AppLocalization.text(["绿", "橙", "蓝"][train.colorIndex]))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.primary)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(LP.Fill.bgContainer.opacity(0.94)))
                                .overlay(Circle().strokeBorder(colors[train.colorIndex], lineWidth: 2))
                        }
                        .position(
                            x: trainX(train) * proxy.size.width,
                            y: train.y * proxy.size.height
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppLocalization.text(
                            "\(["绿", "橙", "蓝"][train.colorIndex])色列车"
                        ))
                }

                ForEach(0..<3, id: \.self) { index in
                    Button {
                        model.selectLane(index)
                    } label: {
                        VStack(spacing: 2) {
                            MiniGameStationAsset(tint: colors[index], active: model.selectedLane == index)
                                .frame(width: proxy.size.width * 0.28, height: 62)
                            Text(AppLocalization.text(["绿站", "橙站", "蓝站"][index]))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isRunning || model.isFinished)
                    .accessibilityLabel(AppLocalization.text("切到 \(["绿", "橙", "蓝"][index])站"))
                    .position(x: laneX[index] * proxy.size.width, y: proxy.size.height * 0.89)
                }

                MiniGameStageCaption(
                    "道岔 → \(["绿", "橙", "蓝"][model.selectedLane])站 · \(model.statusText)",
                    fill: LP.Fill.bgContainer.opacity(0.92)
                )
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("三轨列车调度区"))
        .accessibilityValue(AppLocalization.text(accessibilityStatus))
        .accessibilityHint(AppLocalization.text("选择和列车颜色相同的站台，列车经过道岔时会锁定路线"))
        .accessibilityAction(named: Text(AppLocalization.text("切到绿站"))) {
            model.selectLane(0)
        }
        .accessibilityAction(named: Text(AppLocalization.text("切到橙站"))) {
            model.selectLane(1)
        }
        .accessibilityAction(named: Text(AppLocalization.text("切到蓝站"))) {
            model.selectLane(2)
        }
    }

    private var accessibilityStatus: String {
        let names = ["绿", "橙", "蓝"]
        let approaching = model.trains
            .sorted { $0.y > $1.y }
            .prefix(3)
            .map { "\(names[$0.colorIndex])色列车" }
            .joined(separator: "、")
        let queue = approaching.isEmpty ? "暂无线车" : "当前 \(approaching)"
        return "道岔指向 \(names[model.selectedLane])站；\(queue)"
    }

    private func trainX(_ train: ThoughtTrain) -> Double {
        guard train.y > TrainThoughtGameModel.junctionY else { return 0.5 }
        let lane = train.routedLane ?? model.selectedLane
        let branchProgress = min(1, (train.y - TrainThoughtGameModel.junctionY) / 0.3)
        return 0.5 + (laneX[lane] - 0.5) * branchProgress
    }

    private func trackPath(size: CGSize) -> Path {
        Path { path in
            let junction = CGPoint(x: size.width * 0.5, y: size.height * TrainThoughtGameModel.junctionY)
            path.move(to: CGPoint(x: size.width * 0.5, y: 0))
            path.addLine(to: junction)
            for x in laneX {
                path.move(to: junction)
                path.addLine(to: CGPoint(x: size.width * x, y: size.height * 0.84))
            }
        }
    }

    private func selectedTrackPath(size: CGSize) -> Path {
        Path { path in
            let junction = CGPoint(x: size.width * 0.5, y: size.height * TrainThoughtGameModel.junctionY)
            path.move(to: junction)
            path.addLine(to: CGPoint(x: size.width * laneX[model.selectedLane], y: size.height * 0.84))
        }
    }
}

@MainActor
@Observable
private final class TrainThoughtGameModel {
    static let junctionY = 0.4

    var trains: [ThoughtTrain] = []
    var score = 0
    var delivered = 0
    var misses = 0
    var combo = 0
    var bestCombo = 0
    var selectedLane = 1
    var timeLeft = 45
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var statusText = "点站台切换道岔"
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var remainingTime = 45.0
    @ObservationIgnored private var nextSpawnIn = 1.2
    @ObservationIgnored private var lastUpdateAt = ProcessInfo.processInfo.systemUptime

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

    func selectLane(_ lane: Int) {
        guard isRunning, !isFinished else { return }
        selectedLane = lane.clamped(to: 0...2)
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
        trains = []
        score = 0
        delivered = 0
        misses = 0
        combo = 0
        bestCombo = 0
        selectedLane = 1
        timeLeft = 45
        hasStarted = false
        isRunning = false
        isFinished = false
        statusText = "点站台切换道岔"
        resultMessage = ""
        remainingTime = 45
        nextSpawnIn = 1.2
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
    }

    private func tick(delta: TimeInterval) {
        guard isRunning, !isFinished, delta > 0 else { return }
        remainingTime = max(0, remainingTime - delta)
        let nextTimeLeft = max(0, Int(ceil(remainingTime)))
        if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
        if remainingTime <= 0 {
            finish(message: "小列车先停靠，送达了 \(delivered) 列。")
            return
        }

        nextSpawnIn -= delta
        if nextSpawnIn <= 0 {
            trains.append(ThoughtTrain(colorIndex: Int.random(in: 0..<3), y: 0.08))
            // Teach one train at a time before the board becomes busy. The old
            // 0.35 s opener produced three misses before a newcomer had located
            // the junction control.
            nextSpawnIn += max(1.45, 2.3 - Double(delivered) * 0.025)
        }

        var deliveredLanes: [(target: Int, route: Int)] = []
        let nextTrains = trains.compactMap { train -> ThoughtTrain? in
            var next = train
            next.y += (0.13 + min(Double(delivered) * 0.0018, 0.055)) * delta
            if next.routedLane == nil, next.y >= Self.junctionY {
                next.routedLane = selectedLane
            }
            if next.y >= 0.82 {
                deliveredLanes.append((next.colorIndex, next.routedLane ?? selectedLane))
                return nil
            }
            return next
        }
        if nextTrains != trains { trains = nextTrains }

        for arrival in deliveredLanes {
            if arrival.target == arrival.route {
                delivered += 1
                combo += 1
                bestCombo = max(bestCombo, combo)
                score += 10 + min(12, combo * 2)
                statusText = combo >= 3 ? "连送 \(combo)，加速" : "送达，连 \(combo)"
                LPHaptics.success()
            } else {
                misses += 1
                combo = 0
                statusText = "进错站，重新看颜色"
                LPHaptics.decline()
            }
        }
        if misses >= 5 {
            finish(message: "五列车进错站，先把道岔停下来。")
        }
    }

    private func finish(message: String) {
        guard !isFinished else { return }
        isRunning = false
        stopLoop()
        resultMessage = miniGameRecordedResult(
            for: .trainThought,
            score: score,
            fallback: "\(message)\n最佳连送 \(bestCombo) 列。"
        )
        isFinished = true
    }
}

private struct ThoughtTrain: Identifiable, Equatable {
    let id = UUID()
    var colorIndex: Int
    var y: Double
    var routedLane: Int? = nil
}
