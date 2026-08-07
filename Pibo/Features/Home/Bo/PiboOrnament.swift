import CoreGraphics
import Foundation
import PiboCore

/// 一件可以用 `bo` 解锁、永久留在共同空间里的物件。
///
/// 价格、顺序和前置关系由 `pibo-core` 统一定义，App 只保留展示和场景落位。
struct PiboOrnament: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
        case hammock
        case chime
        case statusObserver
        case lantern

        var coreID: PiboCoreUnlockableItemID {
            switch self {
            case .hammock: .hammock
            case .chime: .chime
            case .statusObserver: .statusObserver
            case .lantern: .lantern
            }
        }

        init?(coreID: PiboCoreUnlockableItemID) {
            if coreID == .hammock {
                self = .hammock
            } else if coreID == .chime {
                self = .chime
            } else if coreID == .statusObserver {
                self = .statusObserver
            } else if coreID == .lantern {
                self = .lantern
            } else {
                return nil
            }
        }
    }

    /// 物件在森林里怎么画。`nil` 表示美术还没到位 —— 面板照常展示与解锁，
    /// 场景里先不出现，等资产补上只需要填这一项。
    struct Placement: Equatable, Sendable {
        /// 物件身上一处可以点亮的部位。
        ///
        /// 坐标是**素材局部 pt、原点在素材左上角**，不是设计画板绝对坐标 ——
        /// 这样挪动 `frame` 不需要跟着改这里，两组数字各管各的。
        struct Light: Equatable, Sendable {
            let center: CGPoint
            /// 发光体本身的半径（素材局部 pt），只决定光晕画多大。
            /// **不是命中半径** —— 命中另有其值，见 `ForestThemeRenderer`。
            let radius: CGFloat
        }

        /// 393×852 设计画板中的位置，和 `ForestSceneManifest` 的图层同一套坐标。
        let frame: CGRect
        let zPosition: CGFloat
        let lightingGroup: ForestLightingGroup
        /// 资产名（`Pibo/Resources/Forest/` 下的裸 PNG，不是 imageset）。
        let image: String
        /// 可点亮的部位。空 = 这件物件不发光，连一个发光节点都不会建。
        let lights: [Light]

        init(
            frame: CGRect,
            zPosition: CGFloat,
            lightingGroup: ForestLightingGroup,
            image: String,
            lights: [Light] = []
        ) {
            self.frame = frame
            self.zPosition = zPosition
            self.lightingGroup = lightingGroup
            self.image = image
            self.lights = lights
        }
    }

    let id: ID
    let name: String
    let cost: Int
    /// 图注。写成《银河系漫游指南》式的条目 —— 这是 Pibo 那本词典里的口吻，
    /// 不是商品说明。
    let entryKey: String
    /// 兑换面板里那张缩略图的资产名。和 `placement` 分开：椰壳没有 `placement`
    /// （它是森林底图的一部分），但面板里仍然要有图。
    let thumbnailImage: String
    let placement: Placement?

    private struct Presentation {
        let id: ID
        let name: String
        let entryKey: String
        let thumbnailImage: String
        let placement: Placement?
    }

    /// Platform-only presentation keyed by semantic item ID. The array below is
    /// never used as catalog order; Core performs that ordering when `all` is built.
    private static let presentations: [ID: Presentation] = {
        let items: [Presentation] = [
            Presentation(
                id: .hammock,
                name: "吊床",
                entryKey: "ornament.hammock.entry",
                thumbnailImage: "forest_yeke",
                placement: Placement(
                    frame: CGRect(x: 41.8, y: 18, width: 176.4, height: 332.5),
                    zPosition: 17,
                    lightingGroup: .midground,
                    image: "forest_yeke"
                )
            ),
            Presentation(
                id: .chime,
                name: "补梦风铃",
                entryKey: "ornament.chime.entry",
                thumbnailImage: "forest_chime",
                placement: Placement(
                    // 风铃自带一根长吊绳，从画面顶端垂下来 —— 和左上角的椰壳一样是
                    // 吊挂物，放在右侧和它配平。素材是连绳带铃带纸签的一整条，
                    // 49×240 = 裁剪后 284×1402 的真实长宽比。
                    frame: CGRect(x: 300, y: -6, width: 49, height: 240),
                    // 压在 Pibo（z 20）之后、椰壳（z 17）与铃兰灯（z 18）之前。
                    zPosition: 19,
                    lightingGroup: .midground,
                    image: "forest_chime"
                )
            ),
            Presentation(
                id: .statusObserver,
                name: "状态观测仪",
                entryKey: "ornament.status_observer.entry",
                thumbnailImage: "forest_status_observer",
                // 左下岩石前、前景叶片后。它是环境里的观测装置，不跟随 Pibo，
                // 也不会凭空显示一个健康分数。
                placement: Placement(
                    frame: CGRect(x: 24, y: 606, width: 76, height: 96),
                    zPosition: 30,
                    lightingGroup: .foreground,
                    image: "forest_status_observer"
                )
            ),
            Presentation(
                id: .lantern,
                name: "铃兰灯",
                entryKey: "ornament.lantern.entry",
                thumbnailImage: "forest_lantern",
                placement: Placement(
                    // 铃兰是**长在地上**的植物，不是吊挂物 —— 底边压在 Pibo 脚下那条
                    // 地平线附近（`piboFootPoint.y ≈ 610`），种在它右手边。
                    // 100×177 = 素材裁剪后 502×888 的真实长宽比，别改成别的比例。
                    frame: CGRect(x: 252, y: 433, width: 100, height: 177),
                    // 压在前景草丛之后（草是 z 37–39），所以草会挡住灯脚，像真的长在里面。
                    zPosition: 18,
                    // 刻意**不用** `.emissive`。`.emissive` 会跳过时段调色的材质 shader
                    // （见 `ForestThemeRenderer.materialShader(for:)`），于是入夜后整个
                    // 场景压暗、只有它保持白天亮度 —— 那是一盏「没点也看着亮」的灯，
                    // 而这盏灯的全部意义就是要用户亲手点。让它跟着环境一起暗下去，
                    // 亮只由 `lights` 负责。
                    lightingGroup: .midground,
                    image: "forest_lantern",
                    // 铃铛的位置是从 `forest_lantern@3x.png` 里量出来的（按亮度+饱和度
                    // 取奶白连通域的质心），不是照着稿子估的。半径取实测包围盒的一半。
                    // **下标会被持久化**，所以只能往后追加，重排等于把用户昨晚点的灯
                    // 挪到别的铃铛上。
                    //
                    // 素材有四个铃铛，这里只列三个。第四个在素材局部 (84.2, 139.2)、
                    // 即设计画板 (336, 572)，正落在 `forest_main_leaf_1`（frame
                    // 211–466 × 494–824，z 32）后面 —— 灯是 z 18，被那片会摇的前景叶
                    // 整个盖住。点亮它只能看见一点从叶子边缘漏出来的光晕；更糟的是叶子
                    // 不透明的地方会先把触摸当成拖叶子接走（`beginInteraction` 排在
                    // `handleTap` 之前），于是那盏灯基本点不到。
                    // 要让第四盏也能用，得挪落位让它避开那片叶子 —— 那是美术落位的事，
                    // 不该由这里偷偷改。
                    lights: [
                        Placement.Light(center: CGPoint(x: 89.5, y: 37.1), radius: 10.7),
                        Placement.Light(center: CGPoint(x: 70.6, y: 82.0), radius: 7.6),
                        Placement.Light(center: CGPoint(x: 14.1, y: 84.9), radius: 13.6),
                    ]
                )
            ),
        ]
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }()

    /// Prices and narrative order come directly from the shared Core catalog.
    /// Missing platform presentation is a programmer error, not a reason to
    /// silently hide a Core-defined item from one platform.
    static let all: [PiboOrnament] = PiboCoreUnlockableItems.catalog.map { definition in
        guard let id = ID(coreID: definition.id),
            let presentation = presentations[id]
        else {
            preconditionFailure("Missing iOS presentation for pibo-core item \(definition.id)")
        }
        return PiboOrnament(
            id: presentation.id,
            name: presentation.name,
            cost: definition.cost,
            entryKey: presentation.entryKey,
            thumbnailImage: presentation.thumbnailImage,
            placement: presentation.placement
        )
    }

    /// 与 Core 目录保持相同的叙事顺序。风铃和观测仪同为 5 bo，不能依赖
    /// 非稳定的价格排序决定谁先出现。
    static let ordered: [PiboOrnament] = all

    /// Hot UI paths (the unlock timeline and SpriteKit accessibility bridge)
    /// ask for the same four definitions repeatedly. Build the lookup tables
    /// once instead of scanning the Core catalog during every view update.
    private static let ornamentsByID: [ID: PiboOrnament] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    private static let coreDefinitionsByID: [ID: PiboCoreUnlockableItemDefinition] = Dictionary(
        uniqueKeysWithValues: PiboCoreUnlockableItems.catalog.compactMap { definition in
            ID(coreID: definition.id).map { ($0, definition) }
        }
    )

    static func coreDefinition(_ id: ID) -> PiboCoreUnlockableItemDefinition {
        guard let definition = coreDefinitionsByID[id] else {
            preconditionFailure("Missing pibo-core item definition for \(id.rawValue)")
        }
        return definition
    }

    static func ornament(_ id: ID) -> PiboOrnament? {
        ornamentsByID[id]
    }

    var localizedName: String { AppLocalization.text(name) }
    var localizedEntry: String { AppLocalization.text(entryKey) }
}
