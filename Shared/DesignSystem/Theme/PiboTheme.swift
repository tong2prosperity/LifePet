import SwiftUI

// MARK: - Pibo home appearance tokens
//
// A *theme* scopes two things in the home activity zone:
//   1. the **scene** Pibo stands in (sky + ground), and
//   2. the **kind of 毛/花** growing on its head.
//
// `forest` is the only runtime appearance. The token shape remains shared by
// SpriteKit and the lightweight SwiftUI preview renderer.

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
    /// Production home appearance. The forest itself is assembled from the
    /// layered Figma artwork in `ForestSceneManifest`; these scene colors are
    /// the safe fallback behind transparent edges and for non-home previews.
    static let forest = PiboTheme(
        id: "forest",
        displayName: "",
        scene: PiboScene(
            skyTop: Color(hex: 0xD3EEE3), skyBottom: Color(hex: 0xB5DFCF),
            ground: Color(hex: 0x9BCA5A), groundAccent: Color(hex: 0x41C7C9),
            terrain: .meadow
        ),
        headItem: .sprout,
        bodyImage: "forest_pibo_body",
        bodyCenterX: 196.5,
        bodyCenterY: 510.2,
        // The canonical Figma SVG is asymmetric: its root is not at the texture
        // center. These coordinates put that root on the body's top-center with
        // a small overlap so no transparent seam appears.
        headSprite: PiboThemeSprite(image: "forest_pibo_head", centerX: 193.5, centerY: 381.0),
        // The current Figma file has one latest head state. Keeping a replacement
        // entry preserves the existing first-energy flow while the animation is
        // expressed through scale/rotation instead of an old texture swap.
        sproutedHeadSprite: PiboThemeSprite(image: "forest_pibo_head", centerX: 193.5, centerY: 381.0)
    )

    /// Fixtures for lightweight shared previews. Runtime availability comes
    /// exclusively from the iOS app's `PiboThemeCatalog` registrations.
    static let previewFixtures: [PiboTheme] = [.forest]
}
