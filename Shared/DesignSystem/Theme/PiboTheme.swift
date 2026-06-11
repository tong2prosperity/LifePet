import SwiftUI

// MARK: - 关于毛的主题 (Pibo theme system)
//
// A *theme* scopes two things in the home activity zone:
//   1. the **scene** Pibo stands in (sky + ground), and
//   2. the **kind of 毛/花** growing on its head.
//
// Themes are 节气限定 / 活动限定 (seasonal / event-limited) — e.g. 桃花时节,
// 阿那亚的海风里. Each theme is pure token data (`PiboTheme`), so adding one is a
// single value with no new view code; `PiboStageScene` (home) and
// `PiboThemeScene` (widget/preview Canvas) interpret it.
//
// Sourced from the home《关于毛的主题》mockup (Figma node 74:6101 — three screens:
// 桃花时节 D127 / 阿那亚的海风里 D7 / 魔丸态 D1). The user picks a theme from the
// settings gear (`SettingsSheet`); the choice persists via
// `PetStateStore.selectedThemeID`.

/// One positioned artwork sprite: an asset name plus its **center in the
/// 393×852 Figma design frame**, so each theme's 毛/花/黑洞 sits exactly where
/// the mockup put it (the stage rescales by the live screen size).
struct PiboThemeSprite: Hashable {
    let image: String
    /// Sprite center, design-frame points. Defaults to the shared head anchor
    /// derived for 桃花枝 (Figma 74:5954) and reused by 海草.
    var centerX: CGFloat = 194
    var centerY: CGFloat = 292.75
}

/// How far Pibo's head 毛 has grown. MVP ships two steps of the 魔丸 arc:
/// the D1 「?」 curl, and the first 发芽 (a leaf sprouts after the first
/// collected 运动能量 — Figma《识别到用户的活动》74:6102).
enum PiboGrowthStage: String {
    case mystery    // D1 — 黑洞 + 「?」卷芽, nothing grown yet
    case sprouted   // 第一次能量收集后 — 卷芽长出叶片, 黑洞消失
}

/// One unlockable theme: its scene backdrop + head decoration.
struct PiboTheme: Identifiable, Hashable {
    /// Stable key for persistence / unlock bookkeeping.
    let id: String
    /// Shown on the greeting header above 与Pibo相识的第 N 天, e.g. "桃花时节".
    /// Empty for the default 魔丸 look (no theme line).
    let displayName: String
    let scene: PiboScene
    let headItem: PiboHeadItem
    /// Pibo body artwork (asset name). When set, the stage shows this sprite
    /// instead of the procedural egg/face geometry. `headItem` still drives the
    /// procedural fallback head when `headSprite` is nil.
    var bodyImage: String? = nil
    /// Turned-away (背对) body artwork — the 拍一拍 不理睬 pose (Figma 76:7175,
    /// curl removed so the theme's own head 毛 stays planted). When nil the
    /// stage falls back to a procedural turn animation.
    var bodyBackImage: String? = nil
    /// Body center in the 393×852 design frame (per-theme: 魔丸 stands a touch
    /// higher on its floating slab than the meadow/beach themes).
    var bodyCenterX: CGFloat = 195.64
    var bodyCenterY: CGFloat = 436.5
    /// Head decoration artwork — 桃花枝 / 海草 / 「?」卷芽. Overrides the
    /// procedural `PiboHeadItemView` render when set.
    var headSprite: PiboThemeSprite? = nil
    /// 发芽后 replacement for `headSprite` (魔丸: 卷芽 → 带叶嫩芽, Figma 70:4579).
    /// nil = the head doesn't change with growth (桃花/阿那亚 art is already grown).
    var sproutedHeadSprite: PiboThemeSprite? = nil
    /// Artwork hovering *above* the head — the 魔丸 黑洞 (Figma 74:5918). Drawn
    /// over the head 毛 so the curl reads as emerging from the hole; removed
    /// once sprouted (Figma 70:4549 hides it).
    var overheadSprite: PiboThemeSprite? = nil

    /// Effective head/overhead artwork for a growth stage. 发芽 swaps the head
    /// sprite and removes the 黑洞.
    func resolvedHead(for stage: PiboGrowthStage) -> (head: PiboThemeSprite?, overhead: PiboThemeSprite?) {
        switch stage {
        case .mystery:
            return (headSprite, overheadSprite)
        case .sprouted:
            return (sproutedHeadSprite ?? headSprite, sproutedHeadSprite == nil ? overheadSprite : nil)
        }
    }
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
    /// 魔丸态默认 — Day 1: floating slab in a void, 黑洞 + 「?」卷芽 over the head.
    /// Fully image-backed (restored from Figma 74:5917): the platform slab
    /// (`demon_bg`), the shared 白团子 (`pibo_body`), the 「?」卷芽 (`demon_curl`,
    /// growing into `demon_curl_sprouted` after the first 能量收集) and the 黑洞
    /// (`demon_hole`). Scene colors mirror the SVG fills for the procedural
    /// fallback (slab `#EAEAEA`, edge `#BFBFBF`).
    static let demon = PiboTheme(
        id: "demon",
        displayName: "",
        scene: PiboScene(
            skyTop: Color(hex: 0xF4F8F9), skyBottom: Color(hex: 0xF4F8F9),
            ground: Color(hex: 0xEAEAEA), groundAccent: Color(hex: 0xBFBFBF),
            terrain: .platform,
            backgroundImage: "demon_bg"        // 还原自 Figma 74:5917（悬浮平台 Group 78）
        ),
        headItem: .mystery,
        bodyImage: "pibo_body",                // 复用白团子 + 脸（同一本体）
        bodyBackImage: "pibo_body_back",
        bodyCenterY: 428.5,                    // 魔丸 Figma 帧的本体中心略高（站在台沿上）
        headSprite: PiboThemeSprite(image: "demon_curl", centerX: 200.43, centerY: 299),
        sproutedHeadSprite: PiboThemeSprite(image: "demon_curl_sprouted", centerX: 211.43, centerY: 299),
        overheadSprite: PiboThemeSprite(image: "demon_hole", centerX: 196, centerY: 271)
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
        bodyBackImage: "pibo_body_back",
        headSprite: PiboThemeSprite(image: "peach_branch")   // Group74 + 枝干
    )

    /// 活动限定 · 阿那亚的海风里 — sea-and-sand beach, green sea leaf on head.
    /// Fully image-backed (restored from Figma `488:1340` / `488:1353`): a sand
    /// band over `bgSurface` with a painted sea inlet (`aranya_bg`), the shared
    /// 白团子 body (`pibo_body`), and a single 海草叶片 (`aranya_seaweed`). Scene
    /// colors mirror the SVG fills (sand `#D5C5AA`, sea-foam `#AADDE5`) so the
    /// procedural fallback stays on-palette if an asset ever fails to load.
    static let aranyaSeaBreeze = PiboTheme(
        id: "aranya-sea-breeze",
        displayName: "阿那亚的海风里",
        scene: PiboScene(
            skyTop: Color(hex: 0xFFFFFF), skyBottom: Color(hex: 0xF1F8FA),
            ground: Color(hex: 0xD5C5AA), groundAccent: Color(hex: 0xAADDE5),
            terrain: .beach,
            backgroundImage: "aranya_bg"       // 还原自 Figma 488:1340（沙滩 + 海湾 + 贝壳）
        ),
        headItem: .seaweed,
        bodyImage: "pibo_body",                // 复用桃花的白团子 + 脸（同一本体）
        bodyBackImage: "pibo_body_back",
        headSprite: PiboThemeSprite(image: "aranya_seaweed") // Group83：海草叶片
    )

    /// Default sprout theme — neutral meadow, the everyday green sprout.
    /// Procedural-only; kept as the fallback look and for the widget Canvas.
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

    /// Themes offered in the settings 主题 picker — the three finished,
    /// image-backed looks from Figma 74:6101 (procedural `.sprout` stays a
    /// fallback, not a user choice).
    static let selectable: [PiboTheme] = [.demon, .peachSeason, .aranyaSeaBreeze]
}
