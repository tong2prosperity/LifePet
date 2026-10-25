import Foundation

/// Measures the actor pixels surviving foreground scenery, before lighting.
/// Matches Harmony's presentation check; it never changes Core activity decisions.
final class PixelActorVisibility {
    private var before: [UInt8] = []
    private var marks: [(Int, UInt8)] = []
    private var left = 0
    private var top = 0
    private var width = 0
    private var height = 0

    func begin(_ frame: PixelFrame, x: Int, y: Int, width: Int, height: Int) {
        left = max(0, x)
        top = max(0, y)
        self.width = max(0, min(frame.width, x + width) - left)
        self.height = max(0, min(frame.height, y + height) - top)
        before.removeAll(keepingCapacity: true)
        marks.removeAll(keepingCapacity: true)
        for row in 0..<self.height {
            let start = (top + row) * frame.width + left
            before.append(contentsOf: frame.data[start..<(start + self.width)])
        }
    }

    func mark(_ frame: PixelFrame) {
        for row in 0..<height {
            for col in 0..<width {
                let index = (top + row) * frame.width + left + col
                let ink = frame.data[index]
                if ink != before[row * width + col] { marks.append((index, ink)) }
            }
        }
    }

    func readable(_ frame: PixelFrame) -> Bool {
        !marks.isEmpty && marks.reduce(0) { $0 + (frame.data[$1.0] == $1.1 ? 1 : 0) } * 4 >= marks.count
    }
}
