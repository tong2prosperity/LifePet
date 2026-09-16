import Foundation

/// 首发（MVP）范围开关。
///
/// 被关掉的功能**代码原样保留**；这里同时收起入口并暂停对应状态观察 —— 恢复某项时
/// 把对应的 base 改回 `true` 即可，不需要还原任何实现。把范围集中在一个文件里，是为了让"首发
/// 到底关了什么"一眼能看全，而不是散成各处的注释。
///
/// 写法沿用 `PiboVectorCharacterFlag`：Release 一律按 base 走；DEBUG 允许用启动
/// 参数临时打开，好让这些功能在开发和验收时仍然跑得起来。
enum PiboReleaseScope {
    /// 新六场面「临时合作」叙事与事件 01–03。当前发布暂时回到旧 Onboarding；
    /// 代码和持久化状态保留，后续确认后可重新打开。
    static var temporaryCooperationOnboarding: Bool {
        on(false, "-PiboEnableTemporaryCooperation")
    }

    /// 餐食相机 + 餐照识别链路（`PiboCameraView` / `FoodRecognitionService` /
    /// `MealDetailView`）。关闭后首页右上角不出相机按钮，餐详情不出「重拍」。
    /// 注意 `SettingsSheet` 的 DEBUG「模拟拍一张午餐」绕过相机直接喂
    /// `handlePhotoSaved`，不受此开关影响 —— 它是验证识别链路的唯一通道。
    static var camera: Bool { on(true, "-PiboEnableCamera") }

    /// 决定 050：散步涂鸦延后到 MVP 之后。Debug 与 Release 同样隐藏（不给启动参数
    /// 旁路），保留实现与历史数据；重新开放需要新的产品决定。
    static let walkDoodle = false

    /// 游戏场（`GameListView` 及其下除 Walk Doodle 外的工程存量）。
    /// 横向逛场景被删后 Release 本就没有入口，这个开关是把"关着"这件事写明，
    /// 免得后面有人重新接线时以为它只是忘了接。
    ///
    /// 已有的 `-PiboOpenGames` / `-PiboOpenMiniGame` 直接算作打开，这样现成的
    /// 调试流程不用再多带一个参数。
    static var miniGames: Bool {
        on(false, "-PiboEnableGames", "-PiboOpenGames", "-PiboOpenMiniGame")
    }

    /// 历史页的新版「足迹」tab（`PiboFootprintsView`）。关闭后历史页只剩「原版」
    /// `PiboHistoryView`（带云朵睡眠卡），且不再套 `TabView`。
    static var footprintsHistory: Bool { on(false, "-PiboEnableFootprints") }

    /// 自定义 Pibo 形象页（`CustomPiboPage`）。此前是在 `HistoryFloorView` 里
    /// 注释掉 tab，现归口到这里。
    static var customizePibo: Bool { on(false, "-PiboEnableCustomize") }

    // MARK: 决定 051：单人陪伴 MVP
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
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let hit = debugArguments.contains { flag in
            arguments.contains { $0 == flag || $0.hasPrefix(flag + "=") }
        }
        if hit { return true }
        #endif
        return base
    }
}
