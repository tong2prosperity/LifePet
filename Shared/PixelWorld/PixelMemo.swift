import Foundation

/// Remembers what a pure draw call painted, keyed by everything its picture depends on, so
/// a prop that has not changed since the last tick is replayed instead of redrawn.
///
/// Painting into an empty (Clear) layer and laying that over the frame is the same as
/// painting the frame directly: `set` skips Clear, and the art only ever reads the frame to
/// dither against what is underneath (keep it, or ink), which an empty layer turns into
/// "skip, or ink". Callers must put every input of the picture into the key.
///
/// Ported from HarmonyPibo `pixel/render/PixelMemo.ets`.
final class PixelMemo {
    private struct Layer {
        var index: [Int32]
        var ink: [UInt8]
    }

    private let capacity: Int
    private var layers: [String: Layer] = [:]
    private var order: [String] = []
    private var scratch = PixelFrame(1, 1)

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func draw(_ frame: PixelFrame, key: String, paint: (PixelFrame) -> Void) {
        let full = "\(frame.width)x\(frame.height)|\(key)"
        let layer: Layer
        if let cached = layers[full] {
            layer = cached
            if let i = order.firstIndex(of: full) { order.remove(at: i) }
        } else {
            layer = capture(frame.width, frame.height, paint)
            if order.count >= capacity, let oldest = order.first {
                order.removeFirst()
                layers[oldest] = nil
            }
        }
        order.append(full)
        layers[full] = layer
        for i in 0..<layer.index.count {
            frame.data[Int(layer.index[i])] = layer.ink[i]
        }
    }

    func forgetAll() {
        layers.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private func capture(_ width: Int, _ height: Int, _ paint: (PixelFrame) -> Void) -> Layer {
        if scratch.width != width || scratch.height != height { scratch = PixelFrame(width, height) }
        let art = scratch
        art.clear(.clear)
        paint(art)
        var index: [Int32] = []
        var ink: [UInt8] = []
        for i in 0..<art.data.count where art.data[i] != 0 {
            index.append(Int32(i))
            ink.append(art.data[i])
        }
        return Layer(index: index, ink: ink)
    }
}
