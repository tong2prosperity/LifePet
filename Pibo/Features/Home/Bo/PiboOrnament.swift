import CoreGraphics
import Foundation

/// 一件可以用 `bo` 换来、永久留在森林里的物件。
///
/// 三件物品对应决定 014 的「睡眠窝 / 悬挂的灯 / 风铃植物」，命名沿用各自名称 ——
/// 决定 013 里那个混合称呼「风铃灯」已经作废，不要再用。
///
/// 定价按 Core 的现状定：`BO_ENERGY_PER_BO = 75`、`BO_DAILY_HEALTH_CAP = 110`，
/// 满勤最快约 1.5 天一枚、普通用户两天左右一枚。于是 1 / 8 / 20 大致是
/// 第 1 天 / 一周半 / 三到四周 —— 首月之内三次兑现，中间不留长空窗。
struct PiboOrnament: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
        case hammock
        case lantern
        case chime
    }

    /// 物件在森林里怎么画。`nil` 表示美术还没到位 —— 面板照常展示与解锁，
    /// 场景里先不出现，等资产补上只需要填这一项。
    struct Placement: Equatable, Sendable {
        /// 393×852 设计画板中的位置，和 `ForestSceneManifest` 的图层同一套坐标。
        let frame: CGRect
        let zPosition: CGFloat
        let lightingGroup: ForestLightingGroup
        /// 资产名（`Pibo/Resources/Forest/` 下的裸 PNG，不是 imageset）。
        let image: String
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
    /// 一开始就属于用户的物件。
    ///
    /// 椰壳吊床必须是这一种：它是睡眠三态的承重件 —— 角色形状按洞口手工裁切过、
    /// 蒙版烘焙进了美术里（见 `ForestSceneManifest` 里 `forest_yeke` 那段注释），
    /// 藏掉它会让 `sleep-1` / `sleep-2` / `awake` 三态直接穿帮。标价先挂着，
    /// 上线前再定要不要真收。
    let isGrantedAtStart: Bool

    static let all: [PiboOrnament] = [
        PiboOrnament(
            id: .hammock,
            name: "椰壳吊床",
            cost: 1,
            entry: """
            一种极其古老的反重力装置。

            它实际上并不能真的反抗地心引力，只是用非常委婉的方式劝说地心引力暂时别把人体拉向地面。

            这个星球的人似乎认为：愿意把下午交给两棵树而非任务列表，是文明尚未彻底失败的证据。

            但 pibo 不知道的是，在这个星球上，文明依然时常失败——毕竟现实的引力远比地心引力沉重。
            """,
            thumbnailImage: "forest_yeke",
            // 已经是 `ForestSceneManifest.backgroundLayers` 的一层，不由这里重复绘制。
            placement: nil,
            isGrantedAtStart: true
        ),
        PiboOrnament(
            id: .lantern,
            name: "铃兰灯",
            cost: 8,
            entry: """
            基于天然活体植物的小型照明体。原产于鸟星，基本无公害。

            作为纯天然农产品，其亮度不足以用于战争、审讯、大规模基础建设或任何严肃得令人不安的事业。

            编者建议用它照亮一台基于植物纤维薄片的语言信号固化装置（简称"书"）、一杯用于日常饮用的植物浸出液（简称"茶"）、或者某个智慧生物作出"我的生命依然值得继续"判断的瞬间。

            pibo 路过鸟星时曾经拜过一位师傅教它改变形态伪装自己。
            """,
            thumbnailImage: "forest_lantern",
            placement: Placement(
                // 铃兰是**长在地上**的植物，不是吊挂物 —— 底边压在 Pibo 脚下那条
                // 地平线附近（`piboFootPoint.y ≈ 610`），种在它右手边。
                // 100×177 = 素材裁剪后 502×888 的真实长宽比，别改成别的比例。
                frame: CGRect(x: 252, y: 433, width: 100, height: 177),
                // 压在前景草丛之后（草是 z 37–39），所以草会挡住灯脚，像真的长在里面。
                zPosition: 18,
                // 夜里要亮 —— `.emissive` 不吃时段调色的材质 shader
                // （见 `ForestThemeRenderer.materialShader(for:)`），所以灯不会
                // 跟着环境一起被压暗。
                lightingGroup: .emissive,
                image: "forest_lantern"
            ),
            isGrantedAtStart: false
        ),
        PiboOrnament(
            id: .chime,
            name: "捕梦网风铃",
            cost: 20,
            entry: """
            声音和梦境信号接收器，用于捕捉"噩梦"——在新的银河标准词典里，这个词几乎可以代表一切声音和信息。

            一般而言，它会把风声分成三类：

            其一：仍有有限收听价值的风；
            其二：听了必然让人说脏话，但总体而言尚可原谅的风；
            其三：形如"我们一会要开个会，大家都没意见吧"的垃圾信息。

            来自本品生产商银河总部的保证：本产品内置垃圾过滤系统，过滤成功率达百分之九十九以上。

            pibo 发现这个装置能让它听到更多来自契约者的声音¹。
            """,
            thumbnailImage: "forest_chime",
            placement: Placement(
                // 风铃自带一根长吊绳，从画面顶端垂下来 —— 和左上角的椰壳一样是
                // 吊挂物，放在右侧和它配平。素材是连绳带铃带纸签的一整条，
                // 49×240 = 裁剪后 284×1402 的真实长宽比。
                frame: CGRect(x: 300, y: -6, width: 49, height: 240),
                zPosition: 19,
                lightingGroup: .midground,
                image: "forest_chime"
            ),
            isGrantedAtStart: false
        ),
    ]

    /// 按价格升序 —— 面板的进度轨依赖这个顺序。
    static let ordered: [PiboOrnament] = all.sorted { $0.cost < $1.cost }

    static func ornament(_ id: ID) -> PiboOrnament? {
        all.first { $0.id == id }
    }

    var localizedName: String { AppLocalization.text(name) }
    var localizedEntry: String { AppLocalization.text(entry) }
}
