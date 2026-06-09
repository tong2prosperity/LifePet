import SwiftUI

// MARK: - 关于毛的主题 (Pibo theme system)
//
// A *theme* scopes two things in the home activity zone:
//   1. the **scene** Pibo stands in (sky + ground), and
//   2. the **kind of 毛/花** growing on its head.
//
// Themes are 节气限定 / 活动限定 (seasonal / event-limited) — e.g. 桃花时节,
// 阿那亚的海风里. Each theme is pure token data (`PiboTheme`), so adding one is a
// single value with no new view code; `PiboThemeScene` interprets it.
//
// Sourced from the home《关于毛的主题》mockup (Figma node 74:6101 — three screens:
// 桃花时节 D127 / 阿那亚的海风里 D7 / 魔丸态 D1). Scene colors are derived from those
// screens and are **provisional** (see `LPTokens` — the Figma color variables
// aren't filled yet).

/// One unlockable theme: its scene backdrop + head decoration.
struct PiboTheme: Identifiable, Hashable {
    /// Stable key for persistence / unlock bookkeeping.
    let id: String
    /// Shown on the greeting line above 与Pibo相识的第 N 天, e.g. "桃花时节".
    /// Empty for the default (no theme unlocked).
    let displayName: String
    let scene: PiboScene
    let headItem: PiboHeadItem
    /// Pibo body artwork (asset name). When set, the stage shows this sprite
    /// instead of the procedural egg/face geometry. `headItem` still drives the
    /// procedural fallback head when `headImage` is nil.
    var bodyImage: String? = nil
    /// Head decoration artwork (asset name) — 桃花枝 / 嫩芽 etc. Overrides the
    /// `PiboHeadItemView` render when set.
    var headImage: String? = nil
}

/// Backdrop tokens — a vertical sky gradient over a ground band.
struct PiboScene: Hashable {
    var skyTop: Color
    var skyBottom: Color
    var ground: Color
    /// Petals (meadow) / sea-foam (beach) / slab edge (platform).
    var groundAccent: Color
    var terrain: Terrain
    /// Full-bleed backdrop artwork (asset name). When set, the stage shows this
    /// single sprite instead of the procedural sky-gradient + ground band.
    var backgroundImage: String? = nil

    /// How the ground band is drawn. See `PiboThemeScene`.
    enum Terrain: Hashable { case meadow, beach, platform }
}

/// What grows on Pibo's head for a given theme.
enum PiboHeadItem: Hashable {
    case sprout         // default green sprout / leaf
    case peachBranch    // 桃花枝 — pink blossom on a twig
    case seaweed        // 海草叶片 — a green sea leaf
    case mystery        // 魔丸: a black hole with a green "?" (D1, nothing grown yet)
}

// MARK: - Presets

extension PiboTheme {
    /// 魔丸态默认 — Day 1, no theme unlocked, only a "?" over the head.
    static let demon = PiboTheme(
        id: "demon",
        displayName: "",
        scene: PiboScene(
            skyTop: Color(hex: 0xFFFFFF), skyBottom: Color(hex: 0xF3F3F1),
            ground: Color(hex: 0xEAEAE7), groundAccent: Color(hex: 0xD3D3CE),
            terrain: .platform
        ),
        headItem: .mystery
    )

    /// 节气限定 · 桃花时节 — pink-petalled meadow, blossom twig on head.
    static let peachSeason = PiboTheme(
        id: "peach-season",
        displayName: "桃花时节",
        scene: PiboScene(
            skyTop: Color(hex: 0xFFFFFF), skyBottom: Color(hex: 0xFDF3F6),
            ground: Color(hex: 0xAFC98E), groundAccent: Color(hex: 0xF3A9BE),
            terrain: .meadow,
            backgroundImage: "peach_bg"        // 还原自 Figma 74:5954（4 层笔刷草地 + 底部白圆）
        ),
        headItem: .peachBranch,
        bodyImage: "pibo_body",                // Group70：白团子 + 脸
        headImage: "peach_branch"              // Group74 + 枝干
    )

    /// 活动限定 · 阿那亚的海风里 — sea-and-sand beach, green sea leaf on head.
    static let aranyaSeaBreeze = PiboTheme(
        id: "aranya-sea-breeze",
        displayName: "阿那亚的海风里",
        scene: PiboScene(
            skyTop: Color(hex: 0xFFFFFF), skyBottom: Color(hex: 0xF1F8FA),
            ground: Color(hex: 0xD9C39C), groundAccent: Color(hex: 0xA9D6E5),
            terrain: .beach
        ),
        headItem: .seaweed
    )

    /// Default sprout theme — neutral meadow, the everyday green sprout.
    static let sprout = PiboTheme(
        id: "sprout",
        displayName: "",
        scene: PiboScene(
            skyTop: Color(hex: 0xFFFFFF), skyBottom: Color(hex: 0xF6F6F2),
            ground: Color(hex: 0xDDE3D6), groundAccent: Color(hex: 0xC2D0AE),
            terrain: .meadow
        ),
        headItem: .sprout
    )

    /// All themes shipped today (default first).
    static let presets: [PiboTheme] = [.demon, .sprout, .peachSeason, .aranyaSeaBreeze]
}
