import CoreGraphics
import Foundation
import PiboCore

/// 一件可以用 `bo` 换来、永久留在森林里的物件。
///
/// 三件物品对应决定 014 的「睡眠窝 / 悬挂的灯 / 风铃植物」，命名沿用各自名称 ——
/// 决定 013 里那个混合称呼「风铃灯」已经作废，不要再用。
///
/// 价格、顺序和前置关系由 `pibo-core` 统一定义，App 只保留展示和场景落位。
struct PiboOrnament: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
        case hammock
        case chime
        case lantern

        var coreID: PiboCoreUnlockableItemID {
            switch self {
            case .hammock: .hammock
            case .chime: .chime
            case .lantern: .lantern
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
    let entry: String
    /// 兑换面板里那张缩略图的资产名。和 `placement` 分开：椰壳没有 `placement`
    /// （它是森林底图的一部分），但面板里仍然要有图。
    let thumbnailImage: String
    let placement: Placement?

    static let all: [PiboOrnament] = [
        PiboOrnament(
            id: .hammock,
            name: "吊床",
            cost: coreDefinition(.hammock).cost,
            entry: """
            一种极其古老的反重力装置。

            它实际上并不能真的反抗地心引力，只是用非常委婉的方式劝说地心引力暂时别把人体拉向地面。

            这个星球的人似乎认为：愿意把下午交给两棵树而非任务列表，是文明尚未彻底失败的证据。

            但 pibo 不知道的是，在这个星球上，文明依然时常失败——毕竟现实的引力远比地心引力沉重。
            """,
            thumbnailImage: "forest_yeke",
            placement: Placement(
                frame: CGRect(x: 41.8, y: 18, width: 176.4, height: 332.5),
                zPosition: 17,
                lightingGroup: .midground,
                image: "forest_yeke"
            )
        ),
        PiboOrnament(
            id: .chime,
            name: "补梦风铃",
            cost: coreDefinition(.chime).cost,
            entry: """
            声音和梦境信号接收器，用于捕捉“噩梦”——在新的银河标准词典里，这个词几乎可以代表一切声音和信息。

            一般而言，它会把风声分成三类：仍有有限收听价值的风；听了让人想说脏话、但尚可原谅的风；以及形如“我们一会要开个会”的垃圾信息。

            来自本品生产商银河总部的保证：本产品内置垃圾过滤系统，过滤成功率达百分之九十九以上。
            """,
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
        PiboOrnament(
            id: .lantern,
            name: "铃兰灯",
            cost: coreDefinition(.lantern).cost,
            entry: """
            基于天然活体植物的小型照明体。原产于鸟星，基本无公害。

            作为纯天然农产品，其亮度不足以用于战争、审讯、大规模基础建设或任何严肃得令人不安的事业。

            编者建议用它照亮一本书、一杯茶，或者某个智慧生物作出“我的生命依然值得继续”判断的瞬间。
            """,
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

    /// 按价格升序 —— 面板的进度轨依赖这个顺序。
    static let ordered: [PiboOrnament] = all.sorted { $0.cost < $1.cost }

    static func coreDefinition(_ id: ID) -> PiboCoreUnlockableItemDefinition {
        guard let definition = PiboCoreUnlockableItems.catalog.first(where: { $0.id == id.coreID }) else {
            preconditionFailure("Missing pibo-core item definition for \(id.rawValue)")
        }
        return definition
    }

    static func ornament(_ id: ID) -> PiboOrnament? {
        all.first { $0.id == id }
    }

    var localizedName: String { AppLocalization.text(name) }
    var localizedEntry: String { AppLocalization.text(entry) }
}
