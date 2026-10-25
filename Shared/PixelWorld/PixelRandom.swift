import Foundation

// Seeded PRNG (mulberry32) so a scene seed always yields the same pixels on every device.
//
// Ported from HarmonyPibo `pixel/render/PixelRandom.ets`; every draw call in the scene files
// is a pure function of a seed, so both platforms scatter the same grass.

final class PixelRandom {
    private var state: UInt32

    init(_ seed: Int) {
        state = UInt32(truncatingIfNeeded: seed)
    }

    func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    func range(_ min: Double, _ max: Double) -> Double {
        min + (max - min) * next()
    }

    /// Integer in `min...maxInclusive`, the way ArkTS `PixelRandom.int` reads.
    func int(_ min: Int, _ maxInclusive: Int) -> Int {
        PixelMath.floor(range(Double(min), Double(maxInclusive + 1)))
    }
}
