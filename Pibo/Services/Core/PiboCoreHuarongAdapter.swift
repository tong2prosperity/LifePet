import PiboCore

enum PiboCoreHuarongAdapter {
    struct Piece {
        var x: Int
        var y: Int
        let width: Int
        let height: Int
    }

    struct DragLimits {
        let left: Int
        let right: Int
        let up: Int
        let down: Int
    }

    struct MoveResult {
        let pieces: [Piece]
        let movedSteps: Int
    }

    static func canMove(
        _ pieces: [Piece],
        pieceIndex: Int,
        dx: Int,
        dy: Int
    ) -> Bool {
        PiboCoreHuarong.canMove(
            pieces.map(\.corePiece),
            pieceIndex: pieceIndex,
            dx: dx,
            dy: dy
        )
    }

    static func move(
        _ pieces: [Piece],
        pieceIndex: Int,
        dx: Int,
        dy: Int,
        steps: Int
    ) -> MoveResult {
        let result = PiboCoreHuarong.move(
            pieces.map(\.corePiece),
            pieceIndex: pieceIndex,
            dx: dx,
            dy: dy,
            steps: steps
        )
        return MoveResult(
            pieces: result.pieces.map { piece in
                Piece(
                    x: piece.x,
                    y: piece.y,
                    width: piece.width,
                    height: piece.height
                )
            },
            movedSteps: result.movedSteps
        )
    }

    static func dragLimits(_ pieces: [Piece], pieceIndex: Int) -> DragLimits {
        let result = PiboCoreHuarong.dragLimits(
            pieces.map(\.corePiece),
            pieceIndex: pieceIndex
        )
        return DragLimits(
            left: result.left,
            right: result.right,
            up: result.up,
            down: result.down
        )
    }

    static func isSolved(_ pieces: [Piece], goalIndex: Int) -> Bool {
        PiboCoreHuarong.isSolved(pieces.map(\.corePiece), goalIndex: goalIndex)
    }
}

private extension PiboCoreHuarongAdapter.Piece {
    var corePiece: PiboCoreHuarongPiece {
        PiboCoreHuarongPiece(x: x, y: y, width: width, height: height)
    }
}
