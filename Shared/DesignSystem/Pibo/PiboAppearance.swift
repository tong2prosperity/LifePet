import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pibo appearance DNA (component-separated)
//
// `PiboAppearance` is the single, serializable source of truth for how a Pibo
// *looks*. It is deliberately **component-separated**: each body part — 眼睛 /
// 眉毛 / 鼻子 / 身子 / 手 / 腿 / 头顶植物 — owns its own config struct, and the
// renderer (`PiboPortraitView`) draws each part from its own component view
// (`PiboComponents.swift`). Nothing is a baked image; everything is a parameter.
//
// This is the foundation the custom editor (`CustomPiboPage`) edits and the
// foundation any future surface (home stage, widget) can render from. Borrowed
// from the DiceBear lesson: separate the *config* from the *renderer*, and the
// editor just mutates the config.
//
// Reference: Figma Pibo 主体形象 `1855:4343` — 大椭圆=眼睛, 小圆=眉毛, 浅灰双瓣=
// 鼻子, 头顶单叶=植物.

/// A `Codable` sRGB color (SwiftUI `Color` isn't `Codable`). Components 0…1.
struct PiboColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// From a `0xRRGGBB` literal — mirrors `Color(hex:)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255,
                  g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255,
                  a: alpha)
    }

    /// Decompose a SwiftUI `Color` (used when the editor's `ColorPicker` writes back).
    init(_ color: Color) {
        #if canImport(UIKit)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        UIColor(color).getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        self.init(r: Double(rr), g: Double(gg), b: Double(bb), a: Double(aa))
        #else
        self.init(r: 1, g: 1, b: 1, a: 1)
        #endif
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - Component shape enums

/// 眼睛形状 (大椭圆). Each case is a parametric `Shape` in `PiboComponents.swift`.
enum PiboEyeShape: String, Codable, CaseIterable, Identifiable {
    case ellipse   // 默认：横椭圆 (Figma 1855)
    case round     // 圆豆眼
    case sleepy    // 半阖弧 (慵懒/魔丸)
    case sparkle   // 闪亮高光眼
    case wink      // 一弯笑眼
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ellipse: return "椭圆"
        case .round:   return "圆豆"
        case .sleepy:  return "半阖"
        case .sparkle: return "闪亮"
        case .wink:    return "弯弯"
        }
    }
}

/// 眉毛形状 (小圆). 默认是头顶两点小圆点.
enum PiboBrowShape: String, Codable, CaseIterable, Identifiable {
    case dot       // 小圆点 (Figma 1855)
    case dash      // 短横
    case slash     // 斜挑 (傲娇/不爽)
    case none      // 无眉
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot:   return "圆点"
        case .dash:  return "短横"
        case .slash: return "斜挑"
        case .none:  return "无"
        }
    }
}

/// 鼻子/腮 (浅灰双瓣).
enum PiboNoseShape: String, Codable, CaseIterable, Identifiable {
    case doubleBump  // 双瓣 (Figma 1855)
    case single      // 单点
    case none        // 无
    var id: String { rawValue }
    var label: String {
        switch self {
        case .doubleBump: return "双瓣"
        case .single:     return "单点"
        case .none:       return "无"
        }
    }
}

/// 头顶植物 — 一定是独立组件 (用户强调). 一片单叶 / 双叶嫩芽 / 花苞 / 卷芽.
enum PiboPlantKind: String, Codable, CaseIterable, Identifiable {
    case singleLeaf  // 单叶 (Figma 1855)
    case sprout      // 双叶嫩芽
    case bud         // 花苞
    case curl        // 「?」卷芽 (魔丸 D1)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .singleLeaf: return "单叶"
        case .sprout:     return "嫩芽"
        case .bud:        return "花苞"
        case .curl:       return "卷芽"
        }
    }
}

// MARK: - Per-component configs (separated)

extension PiboAppearance {
    /// 配色 — one slot per drawable part.
    struct Palette: Codable, Hashable {
        var body: PiboColor
        var outline: PiboColor
        var eye: PiboColor
        var brow: PiboColor
        var nose: PiboColor
        var plant: PiboColor
        var limb: PiboColor      // 手 + 腿 (跟身体同色，可单独调)
    }

    /// 身子. Scales the exact Figma body blob.
    struct BodyConfig: Codable, Hashable {
        var widthScale: Double   // 身宽 0.85…1.15
        var aspect: Double       // 身高倍数 0.9…1.2 (越大越瘦高)
    }

    /// 眼睛 (大椭圆). Positions are fractions of the face box (Figma default in
    /// the comment) so the base renders identical to the design.
    struct EyeConfig: Codable, Hashable {
        var shape: PiboEyeShape
        var spacing: Double      // 眼间距：离脸中线的偏移 (占脸宽比例) — Figma 0.354
        var size: Double         // 整体大小 0.6…1.8 — 1.0 = Figma rx10.5 ry5.5
        var height: Double       // 在脸上的高低 (占脸高，从顶) — Figma 0.288
        var tilt: Double         // 倾斜角 (度) — Figma 0
    }

    /// 眉毛 (小圆).
    struct BrowConfig: Codable, Hashable {
        var shape: PiboBrowShape
        var size: Double         // 0.5…2.0 — 1.0 = Figma r3.38
        var lift: Double         // 高低 (占脸高，从顶) — Figma 0.065
        var spacing: Double      // 离脸中线的偏移 (占脸宽比例) — Figma 0.209
        var angle: Double        // 斜挑角度 (度) -25…25
    }

    /// 鼻子 / 腮.
    struct NoseConfig: Codable, Hashable {
        var shape: PiboNoseShape
        var size: Double         // 0.6…1.5 — 1.0 = Figma rx11.7 ry10.4
        var drop: Double         // 高低 (占脸高，从顶) — Figma 0.80
    }

    /// 手.
    struct ArmConfig: Codable, Hashable {
        var visible: Bool
        var length: Double       // 0.6…1.4
        var drop: Double         // 挂的高低 0…0.4
    }

    /// 腿 / 脚.
    struct LegConfig: Codable, Hashable {
        var visible: Bool
        var spread: Double       // 双脚间距 0.5…1.5
        var length: Double       // 0.6…1.4
    }

    /// 头顶植物 (独立组件).
    struct PlantConfig: Codable, Hashable {
        var kind: PiboPlantKind
        var size: Double         // 0.6…1.6
        var sway: Double         // 摆动/倾斜角 (度) -25…25
    }
}

// MARK: - PiboAppearance

/// The full DNA. Edited by `CustomPiboPage`, rendered by `PiboPortraitView`.
struct PiboAppearance: Codable, Hashable {
    var palette: Palette
    var body: BodyConfig
    var eyes: EyeConfig
    var brows: BrowConfig
    var nose: NoseConfig
    var arms: ArmConfig
    var legs: LegConfig
    var plant: PlantConfig

    /// The Figma `1855:4343` 魔丸 look — the default a fresh pet wears, so the
    /// editor opens on something that already matches the design spec.
    static let `default` = PiboAppearance(
        palette: Palette(
            body: PiboColor(hex: 0xFFFFFF),               // Vector 9 fill
            outline: PiboColor(hex: 0x000000, alpha: 0),  // Figma body has NO outline
            eye: PiboColor(hex: 0x56616C),                // Ellipse 11/14
            brow: PiboColor(hex: 0x56616C),               // Ellipse 12/13
            nose: PiboColor(hex: 0xD7E0E5),               // Ellipse 15/16
            plant: PiboColor(hex: 0x468B5B),              // leaf fill
            limb: PiboColor(hex: 0xFFFFFF)                // arms / legs strokes
        ),
        body: BodyConfig(widthScale: 1.0, aspect: 1.0),
        eyes: EyeConfig(shape: .ellipse, spacing: 0.354, size: 1.0, height: 0.288, tilt: 0),
        brows: BrowConfig(shape: .dot, size: 1.0, lift: 0.065, spacing: 0.209, angle: 0),
        nose: NoseConfig(shape: .doubleBump, size: 1.0, drop: 0.80),
        arms: ArmConfig(visible: true, length: 1.0, drop: 0.18),
        legs: LegConfig(visible: true, spread: 1.0, length: 1.0),
        plant: PlantConfig(kind: .singleLeaf, size: 1.0, sway: 0)
    )

    // MARK: Presets (quick starting points in the editor)

    /// A handful of one-tap looks. Each is a small, intentional remix of the
    /// component params — proof the separation pays off (no new art needed).
    static let presets: [(name: String, appearance: PiboAppearance)] = [
        ("魔丸", .default),
        ("圆豆", {
            var a = PiboAppearance.default
            a.eyes.shape = .round; a.eyes.tilt = 0; a.eyes.size = 1.1
            a.brows.shape = .dot; a.plant.kind = .sprout
            return a
        }()),
        ("傲娇", {
            var a = PiboAppearance.default
            a.eyes.shape = .sleepy; a.eyes.tilt = 22
            a.brows.shape = .slash; a.brows.angle = 18
            a.palette.eye = PiboColor(hex: 0x2C3338)
            return a
        }()),
        ("闪亮", {
            var a = PiboAppearance.default
            a.eyes.shape = .sparkle; a.eyes.size = 1.25; a.eyes.tilt = 0
            a.brows.shape = .dash; a.plant.kind = .bud
            a.palette.plant = PiboColor(hex: 0xF3A9BE)
            return a
        }()),
        ("抹茶", {
            var a = PiboAppearance.default
            a.palette.body = PiboColor(hex: 0xE7F0DA)
            a.palette.outline = PiboColor(hex: 0xC4D6AD)
            a.palette.limb = PiboColor(hex: 0xE7F0DA)
            a.eyes.shape = .wink; a.plant.kind = .singleLeaf
            return a
        }()),
    ]

    // MARK: JSON (UserDefaults persistence)

    /// Decode from persisted JSON; falls back to `.default` on any mismatch
    /// (schema drift, corruption) so the editor always has a valid starting DNA.
    static func decoded(from data: Data?) -> PiboAppearance {
        guard let data, let value = try? JSONDecoder().decode(PiboAppearance.self, from: data)
        else { return .default }
        return value
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}
