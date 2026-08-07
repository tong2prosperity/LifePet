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

    /// Walk Doodle 是初版的独立步行创作工具，不属于小游戏。它必须能在
    /// `miniGames == false` 时单独发布，避免再被游戏场范围误伤。
    static var walkDoodle: Bool { on(true, "-PiboEnableWalkDoodle") }

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
