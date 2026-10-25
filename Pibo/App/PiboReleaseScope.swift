import Foundation

/// 首发（MVP）范围开关。
///
/// 隐藏的权属与历史继续兼容。退役功能没有 Debug 旁路，重新开放需要产品决定。
///
/// 写法沿用 `PiboVectorCharacterFlag`：Release 一律按 base 走；DEBUG 允许用启动
/// 参数临时打开，好让这些功能在开发和验收时仍然跑得起来。
enum PiboReleaseScope {
    /// 新六场面「临时合作」叙事与事件 01–03。当前发布暂时回到旧 Onboarding；
    /// 代码和持久化状态保留，后续确认后可重新打开。
    static let temporaryCooperationOnboarding = false

    /// 餐食相机 + 餐照识别链路（`PiboCameraView` / `FoodRecognitionService` /
    /// `MealDetailView`）。关闭后首页右上角不出相机按钮，餐详情不出「重拍」。
    /// 注意 `SettingsSheet` 的 DEBUG「模拟拍一张午餐」绕过相机直接喂
    /// `handlePhotoSaved`，不受此开关影响 —— 它是验证识别链路的唯一通道。
    static var camera: Bool { on(true, "-PiboEnableCamera") }

    /// 决定 050：散步涂鸦延后到 MVP 之后。Debug 与 Release 同样隐藏（不给启动参数
    /// 旁路），保留实现与历史数据；重新开放需要新的产品决定。
    static let walkDoodle = false

    /// 决定 069：旧游戏与旧页面没有调试旁路。
    static let miniGames = false
    static let footprintsHistory = false
    static let customizePibo = false

    // MARK: 决定 057：移出路线图（原依据决定 051 已由 064 废止）
    //
    // 以下开关只决定本版是否展示／允许发起操作，不改 Core 目录、成本、前置或持久权属，
    // 也不删除好友关系、余额与历史。Debug 不旁路恢复，所以写成常量而不是 `on(...)`。

    /// Shadow Pibo：首页入口、角色映照、好友 Sheet、收光横幅、邀请路由与同步。
    static let shadow = false

    /// 会员购买入口与会员浮层。已有权益读取与账号处理保留。
    static let membership = false

    /// 吊床与状态观测仪之后的物件（补梦风铃、铃兰灯）。
    static let laterOrnaments = false

    /// 决定 054：陪伴提问、记忆回响、心情与草丛／河面热点。
    static let companionPrompts = true

    /// 用户 2026-10-23 要求全量对齐：像素是所有发布面的唯一表现。
    static let pixelHome = true
    static let pixelHistory = true
    static let pixelShare = true
    static let pixelCamera = true
    static let pixelOnboarding = true

    /// 本版森林是否展示／允许操作这件物件。隐藏物件不跳过：它挡住的后续链一并不出现。
    static func allowsOrnament(_ id: PiboOrnament.ID) -> Bool {
        switch id {
        case .hammock, .statusObserver: return true
        default: return laterOrnaments
        }
    }

    /// `debugArguments` 里任意一个命中即视为打开；`-PiboOpenMiniGame=huarongRoad`
    /// 这类带值的写法按前缀匹配。
    private static func on(_ base: Bool, _ debugArguments: String...) -> Bool {
        on(base, enabling: debugArguments, disabling: [])
    }

    private static func on(_ base: Bool, enabling: [String], disabling: [String] = []) -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let disableHit = disabling.contains { flag in
            arguments.contains { $0 == flag || $0.hasPrefix(flag + "=") }
        }
        if disableHit { return false }
        let enableHit = enabling.contains { flag in
            arguments.contains { $0 == flag || $0.hasPrefix(flag + "=") }
        }
        if enableHit { return true }
        #endif
        return base
    }
}
