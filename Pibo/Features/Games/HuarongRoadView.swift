import Foundation
import SwiftUI
import UIKit

struct HuarongRoadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(PiboPersistenceKeys.Defaults.huarongRoadDifficulty)
    private var storedLevelID = HuarongLevel.defaultLevel.id

    @State private var levelIndex = 0
    @State private var pieces: [HuarongPiece] = []
    @State private var history: [[HuarongPiece]] = []
    @State private var moveCount = 0
    @State private var resultMessage = ""
    @State private var bestMoves = 0
    @State private var minimumMoves = 0

    private var level: HuarongLevel { HuarongLevel.catalog[levelIndex] }
    private var isSolved: Bool { HuarongBoard.isSolved(pieces) }
    private var scoreText: String {
        bestMoves > 0 ? "\(moveCount) / \(bestMoves)" : "\(moveCount)"
    }

    var body: some View {
        MiniGameShell(
            kind: .huarongRoad,
            scoreText: scoreText,
            detailText: "\(level.title) · 最少 \(minimumMoves > 0 ? "\(minimumMoves)" : "—") 步",
            onClose: { dismiss() }
        ) {
            huarongStage
        } bottomBar: {
            controlBar
        } overlay: {
            MiniGameResultOverlay(
                isPresented: isSolved,
                title: "到了",
                message: resultMessage.isEmpty ? "Pibo 假装没在等这一刻。" : resultMessage,
                primaryTitle: levelIndex == HuarongLevel.catalog.count - 1 ? "再来一局" : "下一关",
                primarySystem: levelIndex == HuarongLevel.catalog.count - 1 ? "arrow.clockwise" : "arrow.right",
                primaryAction: {
                    if levelIndex < HuarongLevel.catalog.count - 1 {
                        levelIndex += 1
                    } else {
                        startLevel(level)
                    }
                }
            )
        }
        .onAppear {
            levelIndex = HuarongLevel.catalog.firstIndex { $0.id == storedLevelID }
                ?? HuarongLevel.catalog.firstIndex { $0.id == HuarongLevel.defaultLevel.id }
                ?? 0
            startLevel(level)
        }
        .onChange(of: levelIndex) { _, newIndex in
            guard HuarongLevel.catalog.indices.contains(newIndex) else { return }
            storedLevelID = HuarongLevel.catalog[newIndex].id
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86)) {
                startLevel(HuarongLevel.catalog[newIndex])
            }
        }
    }

    // MARK: Stage

    private var huarongStage: some View {
        GeometryReader { proxy in
            let stageWidth = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
            let stageHeight = proxy.size.height.isFinite ? max(0, proxy.size.height) : 0
            let boardWidth = min(
                stageWidth,
                max(
                    180,
                    max(0, stageHeight - 40)
                        * CGFloat(HuarongBoard.columns)
                        / CGFloat(HuarongBoard.rows)
                )
            )

            VStack(spacing: LP.Spacing.m) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    HuarongExitGlow()
                        .frame(width: boardWidth * 0.52, height: 42)
                        .offset(y: 18)

                    HuarongLayerBoardView(
                        pieces: pieces,
                        reduceMotion: reduceMotion
                    ) { pieceID, offset, cell in
                        movePiece(pieceID, offset: offset, cell: cell)
                    } onAccessibilityMove: { pieceID, dx, dy in
                        movePieceOneCell(pieceID, dx: dx, dy: dy)
                    }
                    .frame(width: boardWidth, height: boardWidth * CGFloat(HuarongBoard.rows) / CGFloat(HuarongBoard.columns))
                    .allowsHitTesting(!isSolved)
                }
                .frame(maxWidth: .infinity)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                            Label(AppLocalization.text(level.boardLabel), systemImage: "square.grid.3x3.fill")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(AppLocalization.text(level.boardLabel))
                            Label(AppLocalization.text("主块到底部出口"), systemImage: "arrow.down.to.line.compact")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(AppLocalization.text("主块到底部出口"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: LP.Spacing.s) {
                            Label(AppLocalization.text(level.boardLabel), systemImage: "square.grid.3x3.fill")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(AppLocalization.text(level.boardLabel))
                            Spacer(minLength: 0)
                            Label(AppLocalization.text("主块到底部出口"), systemImage: "arrow.down.to.line.compact")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(AppLocalization.text("主块到底部出口"))
                        }
                    }
                }
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.tertiary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                .padding(.horizontal, LP.Spacing.s)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var controlBar: some View {
        VStack(spacing: LP.Spacing.s) {
            levelPicker

            MiniGameControlBar {
                MiniGameActionButton(
                    title: "撤销",
                    system: "arrow.uturn.backward",
                    disabled: history.isEmpty
                ) {
                    undo()
                }

                MiniGameActionButton(
                    title: "重开",
                    system: "arrow.clockwise"
                ) {
                    startLevel(level)
                }
            }
        }
    }

    private var levelPicker: some View {
        HStack(spacing: LP.Spacing.xs) {
            Button {
                LPHaptics.tap()
                levelIndex = max(0, levelIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LP.Fill.bgContainer.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .disabled(levelIndex == 0)
            .accessibilityLabel(AppLocalization.text("上一关"))

            Menu {
                ForEach(Array(HuarongLevel.catalog.enumerated()), id: \.element.id) { index, option in
                    Button {
                        levelIndex = index
                    } label: {
                        if index == levelIndex {
                            Label("\(index + 1). \(option.title)", systemImage: "checkmark")
                        } else {
                            Text("\(index + 1). \(option.title)")
                        }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text(AppLocalization.text("第 \(levelIndex + 1) / \(HuarongLevel.catalog.count) 关"))
                        .lpText(LP.Typography.c1Medium)
                    Text(AppLocalization.text(level.subtitle))
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                .foregroundStyle(LP.Content.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.72)))
                .overlay(Capsule().strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair))
            }
            .accessibilityLabel(AppLocalization.text("选择关卡，当前第 \(levelIndex + 1) 关，\(level.title)"))

            Button {
                LPHaptics.tap()
                levelIndex = min(HuarongLevel.catalog.count - 1, levelIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LP.Fill.bgContainer.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .disabled(levelIndex == HuarongLevel.catalog.count - 1)
            .accessibilityLabel(AppLocalization.text("下一关"))
        }
    }

    // MARK: Actions

    private func startLevel(_ level: HuarongLevel) {
        pieces = HuarongBoard.initialPieces(for: level)
        history = []
        moveCount = 0
        resultMessage = ""
        bestMoves = HuarongBestMoveStore().bestMoves(for: level)
        minimumMoves = level.minimumMoves
    }

    private func movePiece(_ pieceID: String, offset: CGSize, cell: CGFloat) {
        guard cell > 0 else { return }

        let horizontal = abs(offset.width) >= abs(offset.height)
        let distance = horizontal ? offset.width : offset.height
        let units = abs(distance) / cell
        guard units >= 0.34 else { return }

        let steps = max(1, Int(units.rounded(.toNearestOrAwayFromZero)))
        let dx = horizontal ? (distance > 0 ? 1 : -1) : 0
        let dy = horizontal ? 0 : (distance > 0 ? 1 : -1)
        let before = pieces

        guard let moved = HuarongBoard.movedPieces(before, pieceID: pieceID, dx: dx, dy: dy, steps: steps) else {
            LPHaptics.decline()
            return
        }

        commitMove(before: before, moved: moved)
    }

    private func movePieceOneCell(_ pieceID: String, dx: Int, dy: Int) {
        let before = pieces
        guard let moved = HuarongBoard.movedPieces(
            before,
            pieceID: pieceID,
            dx: dx,
            dy: dy,
            steps: 1
        ) else {
            LPHaptics.decline()
            return
        }
        commitMove(before: before, moved: moved)
    }

    private func commitMove(before: [HuarongPiece], moved: [HuarongPiece]) {
        history.append(before)
        pieces = moved
        moveCount += 1

        if HuarongBoard.isSolved(moved) {
            let store = HuarongBestMoveStore()
            let newBest = store.record(moveCount, for: level)
            bestMoves = store.bestMoves(for: level)
            let extraMoves = max(0, moveCount - minimumMoves)
            let score = max(1, 160 - extraMoves * 3)
            let reward = MiniGameRewardStore().grantPetals(for: score, kind: .huarongRoad)
            miniGameTrackResult(kind: .huarongRoad, score: score, reward: reward, newBest: newBest)
            let recordLine = newBest ? "新最少 \(moveCount) 步" : "最少 \(bestMoves) 步"
            let starLine = MiniGameScoring.starText(score: score, kind: .huarongRoad)
            let rewardLine = reward.petals > 0 ? "收集到 \(reward.petals) 片花瓣 · 共 \(reward.balance)" : "花瓣先攒着"
            resultMessage = "Pibo 假装没在等这一刻。\n\(starLine)\n\(recordLine)\n\(rewardLine)"
            LPHaptics.success()
        } else {
            LPHaptics.tap()
        }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        pieces = previous
        moveCount = max(0, moveCount - 1)
    }
}

private struct HuarongExitGlow: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LP.Fill.foundationAccent.opacity(0.20))
                .blur(radius: 14)
            Capsule()
                .fill(LP.Fill.bgContainer.opacity(0.8))
                .overlay(
                    Capsule()
                        .strokeBorder(LP.Fill.foundationAccent.opacity(0.5), lineWidth: 1)
                )
        }
        .accessibilityHidden(true)
    }
}

/// The surrounding screen stays in SwiftUI, while direct manipulation lives in
/// a retained UIKit/Core Animation surface. A pan changes one existing layer's
/// position and does not rebuild a SwiftUI display list on every touch sample.
private struct HuarongLayerBoardView: UIViewRepresentable {
    let pieces: [HuarongPiece]
    let reduceMotion: Bool
    var onMove: (String, CGSize, CGFloat) -> Void
    var onAccessibilityMove: (String, Int, Int) -> Void

    func makeUIView(context: Context) -> HuarongBoardUIKitView {
        let view = HuarongBoardUIKitView()
        view.onMove = onMove
        view.onAccessibilityMove = onAccessibilityMove
        view.reduceMotion = reduceMotion
        view.setPieces(pieces, animated: false)
        return view
    }

    func updateUIView(_ view: HuarongBoardUIKitView, context: Context) {
        view.onMove = onMove
        view.onAccessibilityMove = onAccessibilityMove
        view.reduceMotion = reduceMotion
        view.setPieces(pieces, animated: !reduceMotion)
    }
}

private final class HuarongBoardUIKitView: UIView {
    var onMove: (String, CGSize, CGFloat) -> Void = { _, _, _ in }
    var onAccessibilityMove: (String, Int, Int) -> Void = { _, _, _ in }
    var reduceMotion = false

    private let boardLayer = CALayer()
    private let slotLayers = (0..<(HuarongBoard.columns * HuarongBoard.rows)).map { _ in
        CALayer()
    }
    private let exitLayer = CALayer()
    private let exitTextLayer = CATextLayer()
    private var pieceLayers: [String: HuarongPieceLayer] = [:]
    private var pieces: [HuarongPiece] = []
    private var cell: CGFloat = 0
    private var dragSession: HuarongUIKitDragSession?

    private lazy var panGesture = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = false
        configureBoardLayers()
        addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPieces(_ newPieces: [HuarongPiece], animated: Bool) {
        guard newPieces != pieces else { return }

        let previousOrigins = Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0.origin) })
        let newIDs = Set(newPieces.map(\.id))

        let removedIDs = pieceLayers.keys.filter { !newIDs.contains($0) }
        for id in removedIDs {
            pieceLayers.removeValue(forKey: id)?.layer.removeFromSuperlayer()
        }

        for piece in newPieces {
            let pieceLayer: HuarongPieceLayer
            if let existing = pieceLayers[piece.id] {
                pieceLayer = existing
            } else {
                pieceLayer = HuarongPieceLayer(piece: piece)
                pieceLayers[piece.id] = pieceLayer
                boardLayer.addSublayer(pieceLayer.layer)
            }
            pieceLayer.configure(piece: piece)
        }

        pieces = newPieces
        if cell > 0 {
            let changedIDs = Set(newPieces.compactMap { piece in
                previousOrigins[piece.id] == piece.origin ? nil : piece.id
            })
            syncPieceFrames(animatedIDs: animated ? changedIDs : [])
            rebuildAccessibilityElements()
        } else {
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        let height = bounds.height
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0
        else {
            cell = 0
            boardLayer.isHidden = true
            accessibilityElements = []
            return
        }

        let nextCell = min(
            width / CGFloat(HuarongBoard.columns),
            height / CGFloat(HuarongBoard.rows)
        )
        guard nextCell.isFinite, nextCell > 0 else {
            cell = 0
            boardLayer.isHidden = true
            accessibilityElements = []
            return
        }

        cell = nextCell
        let boardSize = CGSize(
            width: cell * CGFloat(HuarongBoard.columns),
            height: cell * CGFloat(HuarongBoard.rows)
        )
        let boardFrame = CGRect(
            x: (width - boardSize.width) / 2,
            y: (height - boardSize.height) / 2,
            width: boardSize.width,
            height: boardSize.height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        boardLayer.isHidden = false
        boardLayer.frame = boardFrame
        boardLayer.cornerRadius = LP.Radius.l
        boardLayer.shadowPath = UIBezierPath(
            roundedRect: boardLayer.bounds,
            cornerRadius: LP.Radius.l
        ).cgPath

        for row in 0..<HuarongBoard.rows {
            for column in 0..<HuarongBoard.columns {
                let index = row * HuarongBoard.columns + column
                let inset = HuarongBoard.cellGap / 2
                let slotSize = max(0, cell - HuarongBoard.cellGap)
                slotLayers[index].frame = CGRect(
                    x: CGFloat(column) * cell + inset,
                    y: CGFloat(row) * cell + inset,
                    width: slotSize,
                    height: slotSize
                )
                slotLayers[index].cornerRadius = min(LP.Radius.s, slotSize / 2)
            }
        }

        let exitInset = HuarongBoard.cellGap / 2
        exitLayer.frame = CGRect(
            x: cell + exitInset,
            y: cell * 4 + exitInset,
            width: max(0, cell * 2 - HuarongBoard.cellGap),
            height: max(0, cell - HuarongBoard.cellGap)
        )
        exitLayer.cornerRadius = min(LP.Radius.s, exitLayer.bounds.height / 2)
        exitTextLayer.frame = CGRect(x: cell, y: cell * 4, width: cell * 2, height: cell)
        exitTextLayer.fontSize = max(10, min(13, cell * 0.16))
        CATransaction.commit()

        syncPieceFrames(animatedIDs: [])
        rebuildAccessibilityElements()
    }

    private func configureBoardLayers() {
        boardLayer.backgroundColor = UIColor(LP.Fill.bgSurfaceSecondary).cgColor
        boardLayer.borderColor = UIColor(LP.Border.primary).cgColor
        boardLayer.borderWidth = LP.BorderWidth.hair
        boardLayer.cornerCurve = .continuous
        boardLayer.shadowColor = UIColor.black.cgColor
        boardLayer.shadowOpacity = 0.03
        boardLayer.shadowRadius = 2
        boardLayer.shadowOffset = CGSize(width: 0, height: 0.5)
        layer.addSublayer(boardLayer)

        for slotLayer in slotLayers {
            slotLayer.backgroundColor = UIColor(LP.Fill.bgContainer.opacity(0.58)).cgColor
            slotLayer.cornerCurve = .continuous
            boardLayer.addSublayer(slotLayer)
        }

        exitLayer.backgroundColor = UIColor(LP.Fill.foundationAccent.opacity(0.14)).cgColor
        exitLayer.borderColor = UIColor(LP.Fill.foundationAccent.opacity(0.45)).cgColor
        exitLayer.borderWidth = LP.BorderWidth.hair
        exitLayer.cornerCurve = .continuous
        boardLayer.addSublayer(exitLayer)

        exitTextLayer.string = AppLocalization.text("出口")
        exitTextLayer.foregroundColor = UIColor(LP.Content.accent).cgColor
        exitTextLayer.alignmentMode = .center
        exitTextLayer.contentsScale = UIScreen.main.scale
        boardLayer.addSublayer(exitTextLayer)
    }

    private func syncPieceFrames(animatedIDs: Set<String>) {
        guard cell > 0 else { return }

        for piece in pieces {
            guard let pieceLayer = pieceLayers[piece.id],
                  dragSession?.pieceID != piece.id
            else { continue }

            pieceLayer.setFrame(
                frame(for: piece),
                animated: animatedIDs.contains(piece.id) && !reduceMotion
            )
        }
    }

    private func frame(for piece: HuarongPiece) -> CGRect {
        let width = max(
            0,
            CGFloat(piece.size.columns) * cell - HuarongBoard.tileInset * 2
        )
        let height = max(
            0,
            CGFloat(piece.size.rows) * cell - HuarongBoard.tileInset * 2
        )
        return CGRect(
            x: CGFloat(piece.origin.x) * cell + HuarongBoard.tileInset,
            y: CGFloat(piece.origin.y) * cell + HuarongBoard.tileInset,
            width: width,
            height: height
        )
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.translation(in: self)
        let translation = CGSize(width: point.x, height: point.y)
        switch gesture.state {
        case .began:
            beginDrag(at: gesture.location(in: self))
        case .changed:
            updateDrag(translation: translation)
        case .ended:
            finishDrag(translation: translation, cancelled: false)
        case .cancelled, .failed:
            finishDrag(translation: translation, cancelled: true)
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture, cell > 0 else { return false }
        return piece(at: gestureRecognizer.location(in: self)) != nil
    }

    private func beginDrag(at point: CGPoint) {
        guard cell > 0 else { return }
        guard let (piece, pieceLayer) = piece(at: point) else { return }

        pieceLayer.layer.removeAnimation(forKey: "position")
        pieceLayer.setDragging(true)
        dragSession = HuarongUIKitDragSession(
            pieceID: piece.id,
            limits: HuarongBoard.dragLimits(for: pieces, pieceID: piece.id),
            axis: nil,
            baseFrame: pieceLayer.layer.frame
        )
    }

    private func piece(at point: CGPoint) -> (HuarongPiece, HuarongPieceLayer)? {
        let boardPoint = boardLayer.convert(point, from: layer)
        let candidates = pieces.compactMap { piece -> (HuarongPiece, HuarongPieceLayer)? in
            guard let pieceLayer = pieceLayers[piece.id] else { return nil }
            let hitLayer = pieceLayer.layer.presentation() ?? pieceLayer.layer
            guard hitLayer.frame.contains(boardPoint)
            else { return nil }
            return (piece, pieceLayer)
        }
        return candidates.max(by: {
            $0.1.layer.zPosition < $1.1.layer.zPosition
        })
    }

    private func updateDrag(translation: CGSize) {
        guard var session = dragSession,
              let pieceLayer = pieceLayers[session.pieceID]
        else { return }

        session.axis = HuarongBoard.dragAxis(
            limits: session.limits,
            translation: translation,
            cell: cell,
            current: session.axis
        )
        let offset = HuarongBoard.constrainedOffset(
            limits: session.limits,
            axis: session.axis,
            translation: translation,
            cell: cell
        )
        pieceLayer.setDragOffset(offset, from: session.baseFrame)
        dragSession = session
    }

    private func finishDrag(translation: CGSize, cancelled: Bool) {
        guard var session = dragSession,
              let piece = pieces.first(where: { $0.id == session.pieceID }),
              let pieceLayer = pieceLayers[session.pieceID]
        else {
            dragSession = nil
            return
        }

        session.axis = HuarongBoard.dragAxis(
            limits: session.limits,
            translation: translation,
            cell: cell,
            current: session.axis
        )
        let offset = cancelled ? CGSize.zero : HuarongBoard.constrainedOffset(
            limits: session.limits,
            axis: session.axis,
            translation: translation,
            cell: cell,
            rubberBand: false
        )
        let snappedOffset = snappedOffset(for: offset)
        let targetFrame = session.baseFrame.offsetBy(
            dx: snappedOffset.width,
            dy: snappedOffset.height
        )

        let didMove = !cancelled && snappedOffset != .zero
        pieceLayer.setDragging(false)
        pieceLayer.setFrame(targetFrame, animated: !reduceMotion)
        dragSession = nil

        if didMove {
            onMove(piece.id, snappedOffset, cell)
        } else {
            rebuildAccessibilityElements()
        }
    }

    private func snappedOffset(for offset: CGSize) -> CGSize {
        guard cell > 0 else { return .zero }
        let horizontal = abs(offset.width) >= abs(offset.height)
        let distance = horizontal ? offset.width : offset.height
        let units = abs(distance) / cell
        guard units >= 0.34 else { return .zero }

        let steps = max(1, Int(units.rounded(.toNearestOrAwayFromZero)))
        let snappedDistance = CGFloat(steps) * cell * (distance >= 0 ? 1 : -1)
        return horizontal
            ? CGSize(width: snappedDistance, height: 0)
            : CGSize(width: 0, height: snappedDistance)
    }

    private func rebuildAccessibilityElements() {
        guard cell > 0 else {
            accessibilityElements = []
            return
        }

        let elements = pieces.compactMap { piece -> UIAccessibilityElement? in
            guard let pieceLayer = pieceLayers[piece.id] else { return nil }
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityIdentifier = "miniGame.huarongRoad.piece.\(piece.id)"
            element.accessibilityLabel = AppLocalization.text(piece.accessibilityTitle)
            element.accessibilityValue = AppLocalization.text(
                "第 \(piece.origin.x + 1) 列，第 \(piece.origin.y + 1) 行"
            )
            element.accessibilityHint = AppLocalization.text(
                HuarongBoard.availableDirectionText(for: pieces, pieceID: piece.id)
            )
            element.accessibilityFrameInContainerSpace = pieceLayer.layer.frame.offsetBy(
                dx: boardLayer.frame.minX,
                dy: boardLayer.frame.minY
            )
            let directions = [
                ("向上移动一格", 0, -1),
                ("向下移动一格", 0, 1),
                ("向左移动一格", -1, 0),
                ("向右移动一格", 1, 0)
            ]
            element.accessibilityCustomActions = directions.compactMap { name, dx, dy in
                guard HuarongBoard.canMove(pieces, pieceID: piece.id, dx: dx, dy: dy) else {
                    return nil
                }
                return accessibilityAction(name, pieceID: piece.id, dx: dx, dy: dy)
            }
            return element
        }
        accessibilityElements = elements
    }

    private func accessibilityAction(
        _ name: String,
        pieceID: String,
        dx: Int,
        dy: Int
    ) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: AppLocalization.text(name)) { [weak self] _ in
            guard let self else { return false }
            guard HuarongBoard.canMove(pieces, pieceID: pieceID, dx: dx, dy: dy) else {
                return false
            }
            onAccessibilityMove(pieceID, dx, dy)
            return true
        }
    }
}

private struct HuarongUIKitDragSession {
    let pieceID: String
    let limits: HuarongDragLimits
    var axis: HuarongDragAxis?
    let baseFrame: CGRect
}

private final class HuarongPieceLayer {
    let layer = CALayer()

    private let imageLayer = CALayer()
    private let sproutLayer = CALayer()
    private let stemLayer = CALayer()
    private let leftLeafLayer = CALayer()
    private let rightLeafLayer = CALayer()
    private let textureLayers = [CALayer(), CALayer(), CALayer()]
    private var pieceSize = HuarongPieceSize.single
    private var restingZPosition: CGFloat = 1

    init(piece: HuarongPiece) {
        layer.masksToBounds = false
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.07

        imageLayer.contents = UIImage(named: "pibo_body")?.cgImage
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(imageLayer)

        for textureLayer in textureLayers {
            textureLayer.backgroundColor = UIColor.white.withAlphaComponent(0.42).cgColor
            layer.addSublayer(textureLayer)
        }

        stemLayer.backgroundColor = UIColor(LP.Colorful.green600).cgColor
        leftLeafLayer.backgroundColor = UIColor(LP.Colorful.lime400).cgColor
        rightLeafLayer.backgroundColor = UIColor(LP.Colorful.green500).cgColor
        sproutLayer.addSublayer(stemLayer)
        sproutLayer.addSublayer(leftLeafLayer)
        sproutLayer.addSublayer(rightLeafLayer)
        layer.addSublayer(sproutLayer)

        configure(piece: piece)
    }

    func configure(piece: HuarongPiece) {
        pieceSize = piece.size
        layer.backgroundColor = UIColor(piece.style.fill).cgColor
        layer.borderColor = UIColor(piece.style.stroke).cgColor
        layer.borderWidth = 1.2
        layer.cornerRadius = piece.isGoal ? LP.Radius.m : LP.Radius.s
        restingZPosition = piece.isGoal ? 2 : 1
        layer.zPosition = restingZPosition
        imageLayer.isHidden = !piece.isGoal
        sproutLayer.isHidden = !piece.isGoal
        textureLayers.forEach { $0.isHidden = piece.isGoal }
        layoutContent()
    }

    func setFrame(_ frame: CGRect, animated: Bool) {
        let currentPosition = (layer.presentation() ?? layer).position

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = frame
        layoutContent()
        layer.shadowPath = UIBezierPath(
            roundedRect: layer.bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
        CATransaction.commit()

        guard animated, currentPosition != layer.position else { return }
        let animation = CASpringAnimation(keyPath: "position")
        animation.fromValue = currentPosition
        animation.toValue = layer.position
        animation.mass = 1
        animation.stiffness = 260
        animation.damping = 24
        animation.initialVelocity = 0
        animation.duration = min(animation.settlingDuration, 0.34)
        layer.add(animation, forKey: "position")
    }

    func setDragOffset(_ offset: CGSize, from baseFrame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(
            x: baseFrame.midX + offset.width,
            y: baseFrame.midY + offset.height
        )
        CATransaction.commit()
    }

    func setDragging(_ dragging: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.zPosition = dragging ? 10 : restingZPosition
        layer.shadowRadius = dragging ? 12 : 4
        layer.shadowOpacity = dragging ? 0.11 : 0.07
        layer.shadowOffset = dragging
            ? CGSize(width: 0, height: 2.4)
            : CGSize(width: 0, height: 0.5)
        CATransaction.commit()
    }

    private func layoutContent() {
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let imageInset = min(bounds.width, bounds.height) * 0.15
        imageLayer.frame = bounds.insetBy(dx: imageInset, dy: imageInset)

        let sproutWidth = min(24, bounds.width * 0.22)
        let sproutHeight = min(30, bounds.height * 0.24)
        sproutLayer.frame = CGRect(
            x: bounds.midX - sproutWidth / 2,
            y: max(2, imageInset * 0.16),
            width: sproutWidth,
            height: sproutHeight
        )
        layoutSprout()

        if pieceSize.columns > pieceSize.rows {
            for (index, textureLayer) in textureLayers.enumerated() {
                let stripeWidth = max(4, bounds.width * 0.12)
                let stripeHeight = max(0, bounds.height - 16)
                let centerX = bounds.width * CGFloat(index + 1) / 4
                textureLayer.setAffineTransform(.identity)
                textureLayer.frame = CGRect(
                    x: centerX - stripeWidth / 2,
                    y: 8,
                    width: stripeWidth,
                    height: stripeHeight
                )
                textureLayer.cornerRadius = stripeWidth / 2
            }
        } else if pieceSize.rows > pieceSize.columns {
            for (index, textureLayer) in textureLayers.enumerated() {
                let stripeWidth = max(0, bounds.width - 16)
                let stripeHeight = max(4, bounds.height * 0.12)
                let centerY = bounds.height * CGFloat(index + 1) / 4
                textureLayer.setAffineTransform(.identity)
                textureLayer.frame = CGRect(
                    x: 8,
                    y: centerY - stripeHeight / 2,
                    width: stripeWidth,
                    height: stripeHeight
                )
                textureLayer.cornerRadius = stripeHeight / 2
            }
        } else {
            let side = min(bounds.width, bounds.height) * 0.36
            textureLayers[0].frame = CGRect(
                x: bounds.midX - side / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            textureLayers[0].cornerRadius = 4
            textureLayers[0].setAffineTransform(
                CGAffineTransform(rotationAngle: .pi / 4)
            )
            textureLayers[1].frame = .zero
            textureLayers[2].frame = .zero
        }
    }

    private func layoutSprout() {
        let bounds = sproutLayer.bounds
        let stemWidth = max(2, bounds.width * 0.16)
        stemLayer.frame = CGRect(
            x: bounds.midX - stemWidth / 2,
            y: bounds.height * 0.32,
            width: stemWidth,
            height: bounds.height * 0.62
        )
        stemLayer.cornerRadius = stemWidth / 2

        let leafWidth = bounds.width * 0.42
        let leafHeight = bounds.height * 0.58
        leftLeafLayer.frame = CGRect(
            x: bounds.midX - leafWidth,
            y: 0,
            width: leafWidth,
            height: leafHeight
        )
        leftLeafLayer.cornerRadius = leafWidth / 2
        leftLeafLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.55))

        rightLeafLayer.frame = CGRect(
            x: bounds.midX,
            y: 0,
            width: leafWidth,
            height: leafHeight
        )
        rightLeafLayer.cornerRadius = leafWidth / 2
        rightLeafLayer.setAffineTransform(CGAffineTransform(rotationAngle: 0.55))
    }
}

// MARK: - Levels

private struct HuarongLevel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let boardLabel: String
    let minimumMoves: Int
    let setup: HuarongLevelSetup

    static let catalog: [HuarongLevel] = [
        sourced("open-01", "初见", "四手热身", 1, 4, "BBAA/ECD./ECD./PPIH/PPFG"),
        generated("starter", "入门", "短路可解", 2, 6, 0x5049_424F_0001, 8),
        sourced("open-02", "列阵", "先腾出中路", 3, 8, "AC.D/AC.D/EBPP/EBPP/FGHI"),
        generated("wander", "绕行", "需要换位", 4, 12, 0x5049_424F_0016, 28),
        sourced("open-03", "羽扇", "出口藏在转身后", 5, 19, "CAAH/CPPD/EPPD/EGBI/.FB."),
        sourced("open-04", "似远实近", "横竖交错", 6, 19, "DDCC/PPEB/PPEB/AAHI/FG.."),
        sourced("open-05", "高枕", "两侧都要让路", 7, 21, "ACGH/ACDE/PPDE/PPBI/.FB."),
        sourced("open-22", "近在咫尺", "横木成墙", 8, 23, "AAPP/BBPP/CCDD/EEHI/FG.."),
        sourced("open-23", "身先", "四层横阵", 9, 23, "..PP/AAPP/CCDD/BBEE/FGHI"),
        sourced("open-24", "前后", "上下换位", 10, 23, "FGPP/CCPP/BBDD/AAEE/..HI"),
        generated("knot", "困局", "出口很远", 11, 23, 0x5049_424F_000E, 70),
        sourced("open-21", "孤阵", "纵横相扣", 12, 24, "CDFH/CDGI/EBAA/EBPP/..PP"),
        sourced("open-25", "春风", "最后一重横阵", 13, 25, "FPP./GPP./AADD/BBEE/CCHI")
    ]

    static let defaultLevel = catalog[0]

    private static func sourced(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ number: Int,
        _ minimumMoves: Int,
        _ layout: String
    ) -> HuarongLevel {
        HuarongLevel(
            id: id,
            title: title,
            subtitle: subtitle,
            boardLabel: String(format: "HUA RONG · %02d", number),
            minimumMoves: minimumMoves,
            setup: .encoded(layout)
        )
    }

    private static func generated(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ number: Int,
        _ minimumMoves: Int,
        _ seed: UInt64,
        _ depth: Int
    ) -> HuarongLevel {
        HuarongLevel(
            id: id,
            title: title,
            subtitle: subtitle,
            boardLabel: String(format: "HUA RONG · %02d", number),
            minimumMoves: minimumMoves,
            setup: .scrambled(seed: seed, depth: depth)
        )
    }
}

private enum HuarongLevelSetup {
    case scrambled(seed: UInt64, depth: Int)
    case encoded(String)
}

private struct HuarongBestMoveStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bestMoves(for level: HuarongLevel) -> Int {
        defaults.integer(forKey: key(for: level))
    }

    @discardableResult
    func record(_ moves: Int, for level: HuarongLevel) -> Bool {
        let key = key(for: level)
        let current = defaults.integer(forKey: key)
        guard moves > 0, current == 0 || moves < current else { return false }
        defaults.set(moves, forKey: key)
        return true
    }

    private func key(for level: HuarongLevel) -> String {
        PiboPersistenceKeys.Defaults.huarongRoadBestMovesPrefix + level.id
    }
}

// MARK: - Model

private struct HuarongPiece: Identifiable, Equatable {
    let id: String
    let title: String
    let size: HuarongPieceSize
    let style: HuarongPieceStyle
    var origin: HuarongCell

    var isGoal: Bool { id == HuarongBoard.goalID }

    var accessibilityTitle: String {
        "\(title)，\(size.columns)×\(size.rows)"
    }

    var cells: [HuarongCell] {
        (0..<size.rows).flatMap { row in
            (0..<size.columns).map { column in
                HuarongCell(x: origin.x + column, y: origin.y + row)
            }
        }
    }
}

private struct HuarongPieceSize: Equatable {
    let columns: Int
    let rows: Int

    static let goal = HuarongPieceSize(columns: 2, rows: 2)
    static let vertical = HuarongPieceSize(columns: 1, rows: 2)
    static let horizontal = HuarongPieceSize(columns: 2, rows: 1)
    static let single = HuarongPieceSize(columns: 1, rows: 1)
}

private struct HuarongCell: Hashable {
    var x: Int
    var y: Int
}

private enum HuarongDragAxis {
    case horizontal
    case vertical
}

private struct HuarongDragLimits {
    let left: Int
    let right: Int
    let up: Int
    let down: Int

    var horizontalRoom: Int { left + right }
    var verticalRoom: Int { up + down }
}

private enum HuarongPieceStyle: String {
    case goal
    case pine
    case coral
    case amber
    case sky
    case teal
    case rose
    case violet
    case lime
    case cyan

    var fill: Color {
        switch self {
        case .goal:   return LP.Fill.foundationAccent
        case .pine:   return LP.Colorful.green200
        case .coral:  return LP.Colorful.orange300
        case .amber:  return LP.Colorful.yellow300
        case .sky:    return LP.Colorful.blue300
        case .teal:   return LP.Colorful.teal300
        case .rose:   return LP.Colorful.pink300
        case .violet: return LP.Colorful.purple300
        case .lime:   return LP.Colorful.lime300
        case .cyan:   return LP.Colorful.cyan300
        }
    }

    var stroke: Color {
        switch self {
        case .goal:   return LP.Colorful.green700.opacity(0.62)
        case .pine:   return LP.Colorful.green700.opacity(0.42)
        case .coral:  return LP.Colorful.orange700.opacity(0.42)
        case .amber:  return LP.Colorful.yellow700.opacity(0.42)
        case .sky:    return LP.Colorful.blue700.opacity(0.42)
        case .teal:   return LP.Colorful.teal700.opacity(0.42)
        case .rose:   return LP.Colorful.pink700.opacity(0.42)
        case .violet: return LP.Colorful.purple700.opacity(0.42)
        case .lime:   return LP.Colorful.lime700.opacity(0.42)
        case .cyan:   return LP.Colorful.cyan700.opacity(0.42)
        }
    }

}

private struct HuarongMove: Equatable {
    let pieceID: String
    let dx: Int
    let dy: Int

    func isReverse(of other: HuarongMove) -> Bool {
        pieceID == other.pieceID && dx == -other.dx && dy == -other.dy
    }
}

private struct HuarongRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x5049_424F : seed
    }

    mutating func nextInt(upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state % UInt64(upperBound))
    }
}

// MARK: - Rules

private enum HuarongBoard {
    static let columns = 4
    static let rows = 5
    static let goalID = "pibo"
    static let cellGap: CGFloat = 6
    static let tileInset: CGFloat = 4

    static func initialPieces(for level: HuarongLevel) -> [HuarongPiece] {
        switch level.setup {
        case let .encoded(layout):
            return pieces(from: layout)
        case let .scrambled(seed, depth):
            return scrambledPieces(seed: seed, depth: depth)
        }
    }

    private static func scrambledPieces(seed: UInt64, depth: Int) -> [HuarongPiece] {
        var pieces = solvedPieces()
        var random = HuarongRandom(seed: seed)
        var previousMove: HuarongMove?

        for _ in 0..<depth {
            var candidates = legalMoves(in: pieces)

            if let previousMove {
                let filtered = candidates.filter { !$0.isReverse(of: previousMove) }
                if !filtered.isEmpty {
                    candidates = filtered
                }
            }

            let nonSolved = candidates.filter { move in
                var testPieces = pieces
                applyOneStep(&testPieces, move: move)
                return !isSolved(testPieces)
            }
            if !nonSolved.isEmpty {
                candidates = nonSolved
            }

            guard !candidates.isEmpty else { break }

            let move = candidates[random.nextInt(upperBound: candidates.count)]
            applyOneStep(&pieces, move: move)
            previousMove = move
        }

        return pieces
    }

    /// Compact 4×5 layouts adapted from the MIT-licensed KlotskiPuzzle map set.
    /// Source and attribution: docs/games/huarong-road-level-sources.md
    private static func pieces(from layout: String) -> [HuarongPiece] {
        let rows = layout.split(separator: "/").map(Array.init)
        guard rows.count == Self.rows,
              rows.allSatisfy({ $0.count == Self.columns })
        else { return solvedPieces() }

        var cellsByMarker: [Character: [HuarongCell]] = [:]
        for (y, row) in rows.enumerated() {
            for (x, marker) in row.enumerated() where marker != "." {
                cellsByMarker[marker, default: []].append(HuarongCell(x: x, y: y))
            }
        }

        let styles: [HuarongPieceStyle] = [
            .pine, .coral, .amber, .sky, .teal, .rose, .violet, .lime, .cyan
        ]
        let markers = cellsByMarker.keys.sorted { String($0) < String($1) }
        let result = markers.enumerated().compactMap { index, marker -> HuarongPiece? in
            guard let cells = cellsByMarker[marker],
                  let minX = cells.map(\.x).min(),
                  let maxX = cells.map(\.x).max(),
                  let minY = cells.map(\.y).min(),
                  let maxY = cells.map(\.y).max()
            else { return nil }

            let size = HuarongPieceSize(columns: maxX - minX + 1, rows: maxY - minY + 1)
            guard cells.count == size.columns * size.rows else { return nil }
            let isGoal = marker == "P"
            let title: String
            if isGoal {
                title = "Pibo 主块"
            } else if size == .single {
                title = "小块 \(marker)"
            } else if size == .horizontal {
                title = "横块 \(marker)"
            } else {
                title = "长块 \(marker)"
            }

            return HuarongPiece(
                id: isGoal ? goalID : "block-\(marker)",
                title: title,
                size: size,
                style: isGoal ? .goal : styles[index % styles.count],
                origin: HuarongCell(x: minX, y: minY)
            )
        }

        guard result.count == cellsByMarker.count,
              result.contains(where: { $0.id == goalID })
        else { return solvedPieces() }
        return result
    }

    static func movedPieces(_ pieces: [HuarongPiece],
                            pieceID: String,
                            dx: Int,
                            dy: Int,
                            steps: Int) -> [HuarongPiece]? {
        guard let pieceIndex = pieces.firstIndex(where: { $0.id == pieceID }) else {
            return nil
        }
        let result = PiboCoreHuarongAdapter.move(
            corePieces(pieces),
            pieceIndex: pieceIndex,
            dx: dx,
            dy: dy,
            steps: steps
        )
        guard result.movedSteps > 0 else { return nil }
        return pieces.enumerated().map { index, piece in
            var updated = piece
            updated.origin = HuarongCell(
                x: result.pieces[index].x,
                y: result.pieces[index].y
            )
            return updated
        }
    }

    static func dragLimits(for pieces: [HuarongPiece], pieceID: String) -> HuarongDragLimits {
        guard let pieceIndex = pieces.firstIndex(where: { $0.id == pieceID }) else {
            return HuarongDragLimits(left: 0, right: 0, up: 0, down: 0)
        }
        let limits = PiboCoreHuarongAdapter.dragLimits(corePieces(pieces), pieceIndex: pieceIndex)
        return HuarongDragLimits(
            left: limits.left,
            right: limits.right,
            up: limits.up,
            down: limits.down
        )
    }

    static func dragAxis(limits: HuarongDragLimits,
                         translation: CGSize,
                         cell: CGFloat,
                         current: HuarongDragAxis? = nil) -> HuarongDragAxis? {
        let lockThreshold = max(4, cell * 0.07)
        let switchThreshold = max(18, cell * 0.28)
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard max(absX, absY) >= lockThreshold else { return nil }

        if let current, max(absX, absY) >= switchThreshold {
            return current
        }

        let horizontalScore = limits.horizontalRoom > 0 ? absX : 0
        let verticalScore = limits.verticalRoom > 0 ? absY : 0

        if horizontalScore == 0, verticalScore == 0 {
            return absX >= absY ? .horizontal : .vertical
        }

        return horizontalScore >= verticalScore ? .horizontal : .vertical
    }

    static func constrainedOffset(limits: HuarongDragLimits,
                                  axis: HuarongDragAxis?,
                                  translation: CGSize,
                                  cell: CGFloat,
                                  rubberBand: Bool = true) -> CGSize {
        guard cell > 0,
              let axis
        else { return .zero }

        switch axis {
        case .horizontal:
            let distance = constrainedDistance(
                translation.width,
                negativeLimit: CGFloat(limits.left) * cell,
                positiveLimit: CGFloat(limits.right) * cell,
                cell: cell,
                rubberBand: rubberBand
            )
            return CGSize(width: distance, height: 0)
        case .vertical:
            let distance = constrainedDistance(
                translation.height,
                negativeLimit: CGFloat(limits.up) * cell,
                positiveLimit: CGFloat(limits.down) * cell,
                cell: cell,
                rubberBand: rubberBand
            )
            return CGSize(width: 0, height: distance)
        }
    }

    static func isSolved(_ pieces: [HuarongPiece]) -> Bool {
        guard let goalIndex = pieces.firstIndex(where: { $0.id == goalID }) else {
            return false
        }
        return PiboCoreHuarongAdapter.isSolved(corePieces(pieces), goalIndex: goalIndex)
    }

    static func availableDirectionText(for pieces: [HuarongPiece], pieceID: String) -> String {
        let candidates = [
            ("上", 0, -1),
            ("下", 0, 1),
            ("左", -1, 0),
            ("右", 1, 0)
        ]
        let available = candidates.compactMap { title, dx, dy in
            canMove(pieces, pieceID: pieceID, dx: dx, dy: dy) ? title : nil
        }
        return available.isEmpty ? "当前不能移动" : "可以向\(available.joined(separator: "、"))移动"
    }

    private static func solvedPieces() -> [HuarongPiece] {
        [
            HuarongPiece(id: goalID, title: "Pibo 主块", size: .goal,
                         style: .goal, origin: HuarongCell(x: 1, y: 3)),
            HuarongPiece(id: "leftTop", title: "青色长块", size: .vertical,
                         style: .pine, origin: HuarongCell(x: 0, y: 0)),
            HuarongPiece(id: "rightTop", title: "橙色长块", size: .vertical,
                         style: .coral, origin: HuarongCell(x: 3, y: 0)),
            HuarongPiece(id: "leftBottom", title: "黄色长块", size: .vertical,
                         style: .amber, origin: HuarongCell(x: 0, y: 2)),
            HuarongPiece(id: "rightBottom", title: "蓝色长块", size: .vertical,
                         style: .sky, origin: HuarongCell(x: 3, y: 2)),
            HuarongPiece(id: "bridge", title: "青绿横块", size: .horizontal,
                         style: .teal, origin: HuarongCell(x: 1, y: 0)),
            HuarongPiece(id: "sparkOne", title: "粉色小块", size: .single,
                         style: .rose, origin: HuarongCell(x: 1, y: 1)),
            HuarongPiece(id: "sparkTwo", title: "紫色小块", size: .single,
                         style: .violet, origin: HuarongCell(x: 2, y: 1)),
            HuarongPiece(id: "sparkThree", title: "青柠小块", size: .single,
                         style: .lime, origin: HuarongCell(x: 0, y: 4)),
            HuarongPiece(id: "sparkFour", title: "天蓝小块", size: .single,
                         style: .cyan, origin: HuarongCell(x: 3, y: 4))
        ]
    }

    private static func legalMoves(in pieces: [HuarongPiece]) -> [HuarongMove] {
        pieces.flatMap { piece in
            [
                HuarongMove(pieceID: piece.id, dx: 1, dy: 0),
                HuarongMove(pieceID: piece.id, dx: -1, dy: 0),
                HuarongMove(pieceID: piece.id, dx: 0, dy: 1),
                HuarongMove(pieceID: piece.id, dx: 0, dy: -1)
            ].filter { canMove(pieces, pieceID: piece.id, dx: $0.dx, dy: $0.dy) }
        }
    }

    private static func constrainedDistance(_ raw: CGFloat,
                                            negativeLimit: CGFloat,
                                            positiveLimit: CGFloat,
                                            cell: CGFloat,
                                            rubberBand: Bool) -> CGFloat {
        if raw > positiveLimit {
            guard rubberBand else { return positiveLimit }
            return positiveLimit + resistedOverflow(raw - positiveLimit, cell: cell)
        }

        if raw < -negativeLimit {
            guard rubberBand else { return -negativeLimit }
            return -negativeLimit - resistedOverflow(abs(raw + negativeLimit), cell: cell)
        }

        return raw
    }

    private static func resistedOverflow(_ overflow: CGFloat, cell: CGFloat) -> CGFloat {
        min(overflow * 0.18, cell * 0.16)
    }

    static func canMove(_ pieces: [HuarongPiece],
                        pieceID: String,
                        dx: Int,
                        dy: Int) -> Bool {
        guard let pieceIndex = pieces.firstIndex(where: { $0.id == pieceID }) else {
            return false
        }
        return PiboCoreHuarongAdapter.canMove(
            corePieces(pieces),
            pieceIndex: pieceIndex,
            dx: dx,
            dy: dy
        )
    }

    private static func corePieces(_ pieces: [HuarongPiece]) -> [PiboCoreHuarongAdapter.Piece] {
        pieces.map { piece in
            PiboCoreHuarongAdapter.Piece(
                x: piece.origin.x,
                y: piece.origin.y,
                width: piece.size.columns,
                height: piece.size.rows
            )
        }
    }

    private static func applyOneStep(_ pieces: inout [HuarongPiece], move: HuarongMove) {
        guard let index = pieces.firstIndex(where: { $0.id == move.pieceID }) else { return }
        pieces[index].origin.x += move.dx
        pieces[index].origin.y += move.dy
    }
}

#Preview {
    HuarongRoadView()
}
