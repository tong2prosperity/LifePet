import SwiftUI

// MARK: - Pet Detective

struct PetDetectiveGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = GridPoint(x: 0, y: 0)
    @State private var target = GridPoint(x: 4, y: 4)
    @State private var rocks: Set<GridPoint> = []
    @State private var pathHistory: [GridPoint] = []
    @State private var moves = 0
    @State private var shortestPath = 8
    @State private var showResult = false
    @State private var resultMessage = ""

    private let size = 5

    var body: some View {
        MiniGameShell(
            kind: .petDetective,
            scoreText: showResult
                ? miniGameScoreText(for: .petDetective, score: completedRouteScore)
                : "\(moves) 步",
            detailText: "最短 \(shortestPath) · 已走 \(moves)",
            onClose: { dismiss() }
        ) {
            VStack(spacing: LP.Spacing.l) {
                Spacer(minLength: 0)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: size), spacing: 8) {
                    ForEach(0..<(size * size), id: \.self) { index in
                        let point = GridPoint(x: index % size, y: index / size)
                        detectiveCell(point)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(title: "新地图", system: "map", variant: .primary) { reset() }
                MiniGameActionButton(
                    title: "撤回",
                    system: "arrow.uturn.backward",
                    disabled: pathHistory.isEmpty || showResult
                ) {
                    undoMove()
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "找到了",
                message: resultMessage,
                primaryTitle: "下一张",
                primarySystem: "arrow.right",
                primaryAction: { reset() }
            )
        }
        .onAppear { reset() }
    }

    private var completedRouteScore: Int {
        PiboCorePetDetectiveAdapter.score(
            shortestPath: shortestPath,
            moves: moves
        )
    }

    private func detectiveCell(_ point: GridPoint) -> some View {
        let isMovable = canMove(to: point)
        let isBlocked = rocks.contains(point)

        return Button {
            move(to: point)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                    .fill(cellFill(point))
                    .overlay(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).strokeBorder(LP.Border.tertiary, lineWidth: 1))
                if point == player {
                    MiniGamePiboAsset(flowerScale: 0.3, showFlower: false)
                        .padding(4)
                } else if point == target {
                    MiniGameMemoryShardAsset()
                        .padding(14)
                } else if rocks.contains(point) {
                    MiniGameRockAsset()
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .opacity(isBlocked ? 0.58 : (isMovable || point == player ? 1 : 0.72))
        .disabled(showResult || !isMovable)
        .accessibilityLabel(AppLocalization.text(cellAccessibilityLabel(point)))
        .accessibilityHint(AppLocalization.text(
            isBlocked ? "石块挡住了" : (isMovable ? "可以移动到这里" : "不在当前位置旁边")
        ))
    }

    private func cellFill(_ point: GridPoint) -> Color {
        if point == player { return LP.Fill.foundationAccent }
        if point == target { return LP.Colorful.yellow200 }
        if rocks.contains(point) { return LP.Neutral.grey300 }
        if pathHistory.contains(point) { return LP.Fill.foundationAccent.opacity(0.18) }
        return LP.Fill.bgContainer.opacity(0.88)
    }

    private func move(to point: GridPoint) {
        guard canMove(to: point) else {
            LPHaptics.decline()
            return
        }
        pathHistory.append(player)
        player = point
        moves += 1
        if point == target {
            let finalScore = completedRouteScore
            resultMessage = miniGameRecordedResult(
                for: .petDetective,
                score: finalScore,
                fallback: moves <= shortestPath ? "...最短路线，行吧。" : "...绕远了，但找到了。"
            )
            showResult = true
            LPHaptics.success()
        } else {
            LPHaptics.tap()
        }
    }

    private func undoMove() {
        guard !showResult, let previous = pathHistory.popLast() else { return }
        player = previous
        LPHaptics.tap()
    }

    private func cellAccessibilityLabel(_ point: GridPoint) -> String {
        if point == player { return "Pibo 当前所在，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        if point == target { return "记忆碎片，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        if rocks.contains(point) { return "石块，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        return "空地，第 \(point.x + 1) 列第 \(point.y + 1) 行"
    }

    private func reset() {
        player = GridPoint(x: 0, y: 0)
        target = GridPoint(x: 4, y: 4)
        pathHistory = []
        moves = 0
        showResult = false
        resultMessage = ""

        for _ in 0..<40 {
            var nextRocks = Set<GridPoint>()
            while nextRocks.count < 7 {
                let point = GridPoint(x: Int.random(in: 0..<size), y: Int.random(in: 0..<size))
                if point != player, point != target, point.x != point.y {
                    nextRocks.insert(point)
                }
            }
            if let length = shortestPathLength(rocks: nextRocks) {
                rocks = nextRocks
                shortestPath = length
                return
            }
        }

        rocks = []
        shortestPath = 8
    }

    private func shortestPathLength(rocks: Set<GridPoint>) -> Int? {
        PiboCorePetDetectiveAdapter.shortestPath(
            size: size,
            rocks: Set(rocks.map(\.corePoint)),
            start: player.corePoint,
            target: target.corePoint
        )
    }

    private func canMove(to point: GridPoint) -> Bool {
        PiboCorePetDetectiveAdapter.canMove(
            size: size,
            rocks: Set(rocks.map(\.corePoint)),
            from: player.corePoint,
            to: point.corePoint
        )
    }
}

private struct GridPoint: Hashable {
    var x: Int
    var y: Int

    var corePoint: PiboCorePetDetectiveAdapter.Point {
        PiboCorePetDetectiveAdapter.Point(x: x, y: y)
    }
}
