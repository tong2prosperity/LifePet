import Foundation

enum PixelMath {
    static func round(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    static func floor(_ value: Double) -> Int {
        Int(value.rounded(.down))
    }

    /// The ink `offset` steps after `ink` in the palette (`PixelInk.StarA + i % 3`).
    static func ink(_ ink: PixelInk, _ offset: Int) -> PixelInk {
        PixelInk(rawValue: UInt8(clamping: ink.index + offset)) ?? ink
    }
}
