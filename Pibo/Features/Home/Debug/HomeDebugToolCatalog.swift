#if DEBUG
import Foundation

/// Developer-only command metadata for the floating DEV dock (2026-09-08,
/// shared with HarmonyOS `DebugToolCatalog.ets`). No product rules live here;
/// side effects are spelled out in `detail`.
struct HomeDebugTool: Identifiable, Equatable {
    let id: String
    let group: String
    let title: String
    let detail: String
}

enum HomeDebugToolCatalog {
    static let recentGroup = "最近"
    static let groups = [recentGroup, "Pibo", "动画", "bo 与物件", "森林", "功能流程", "高级"]

    /// Every shipped character resource, grouped as main state, behavior or
    /// historical material, plus a way back to the real presentation.
    static let animationTitles: [String: (title: String, historical: Bool)] = [
        PiboAnimationResourceID.stable: ("安稳 · stable", false),
        PiboAnimationResourceID.energetic: ("活跃 · energetic", false),
        PiboAnimationResourceID.tired: ("疲倦 · tired", false),
        PiboAnimationResourceID.dataUnknown: ("等待数据", false),
        PiboAnimationResourceID.wakingGround: ("苔藓初醒", false),
        PiboAnimationResourceID.sleepingGroundA: ("苔藓睡眠", false),
        PiboAnimationResourceID.sleepingHammockA: ("吊床睡眠 A", false),
        PiboAnimationResourceID.sleepingHammockB: ("吊床睡眠 B", false),
        PiboAnimationResourceID.wakingHammock: ("吊床初醒", false),
        PiboAnimationResourceID.wakingGroundRecovering: ("初醒 · 恢复不足", false),
        PiboAnimationResourceID.stableThinking: ("安稳 · 思考", false),
        PiboAnimationResourceID.tiredResting: ("疲倦 · 休息", false),
        PiboAnimationResourceID.wakingGreeted: ("初醒 · 早安后", false),
        PiboAnimationResourceID.wakingRecoveringGreeted: ("恢复不足 · 早安后", false),
        PiboAnimationResourceID.activityMilestoneCelebrate: ("活动里程碑 · 8k·腹肌", false),
        PiboAnimationResourceID.workoutCelebrate: ("运动庆祝 · pigu", false),
        "weak": ("低落 · weak", true),
        "angry": ("生气 · angry", true),
        "boring": ("树旁观察 · boring", false),
        "dive": ("石后探头 · dive", false),
        "coolhide": ("草丛躲藏 · coolhide", false),
    ]

    static var tools: [HomeDebugTool] {
        var tools: [HomeDebugTool] = [
            .init(id: "onboarding", group: "功能流程", title: "Onboarding · 首启预览", detail: "日常人格 · 独立会话 · 不申请权限、不写入数据"),
            .init(id: "pat", group: "Pibo", title: "拍一拍场景", detail: "27 个上下文 · 临时会话 · 双击 Pibo 推进"),
            .init(id: "pat-again", group: "Pibo", title: "拍一次", detail: "当前临时场景 · 可重复触发"),
            .init(id: "pat-reset", group: "Pibo", title: "重开拍一拍场景", detail: "重置当前临时会话"),
        ]
        for state in PiboActivityState.allCases {
            tools.append(.init(id: "state:\(state.rawValue)", group: "Pibo", title: state.displayName, detail: "只覆盖角色表现"))
        }
        tools += [
            .init(id: "companion:pat-ready", group: "Pibo", title: "陪伴 · 下次拍一拍", detail: "下一次双击尝试提问或回响 · 仍受 Core 预算"),
            .init(id: "companion:absence-short", group: "Pibo", title: "陪伴 · 离开 4 小时", detail: "重新进入首页 · 捉迷藏与回来槽位"),
            .init(id: "companion:absence-long", group: "Pibo", title: "陪伴 · 离开 25 小时", detail: "回答与账本同步变旧 · boring、回响与回来槽位"),
            .init(id: "companion:reset", group: "Pibo", title: "陪伴 · 清空记忆", detail: "清空本地回答、预算与退避"),
            .init(id: "food-left", group: "Pibo", title: "观察左侧食物", detail: "重复播放观察动作"),
            .init(id: "food-right", group: "Pibo", title: "观察右侧食物", detail: "重复播放观察动作"),
            .init(id: "animation:auto", group: "动画", title: "恢复当前真实表现", detail: "结束角色动画覆盖"),
        ]
        for id in PiboAnimationStateMap.available.sorted() {
            let entry = animationTitles[id] ?? (id, false)
            tools.append(.init(
                id: "animation:\(id)",
                group: "动画",
                title: entry.title,
                detail: (entry.historical ? "历史素材预览 · 非当前主状态 · " : "素材预览 · 可重复播放 · ") + id
            ))
        }
        tools += [
            .init(id: "bo:charging", group: "bo 与物件", title: "bo 充能中", detail: "临时容器 · 轻拉不可收取"),
            .init(id: "bo:almost", group: "bo 与物件", title: "bo 即将成熟", detail: "临时容器 · 90% 充能"),
            .init(id: "bo:ripe", group: "bo 与物件", title: "bo 成熟待收取", detail: "直接拉取 · 临时余额不写盘"),
            .init(id: "bo:reserve", group: "bo 与物件", title: "bo 成熟＋储备", detail: "收取后储备补满 · 可反复试"),
            .init(id: "bo:effect", group: "bo 与物件", title: "播放成熟效果", detail: "每次点击重新播放 · 不写账本"),
            .init(id: "bo:growth-hint", group: "bo 与物件", title: "播放成长提示", detail: "未成熟里程碑 · 演示数值 · 不写账本"),
            .init(id: "item:hammock", group: "bo 与物件", title: "吊床显影", detail: "仅预览 · 不解锁真实物件"),
            .init(id: "item:statusObserver", group: "bo 与物件", title: "观测仪显影", detail: "仅预览 · 不解锁真实物件"),
            .init(id: "weather:auto", group: "森林", title: "恢复真实天气", detail: "结束天气覆盖"),
            .init(id: "weather:rain", group: "森林", title: "雨天", detail: "持续覆盖 · 退出调试恢复"),
            .init(id: "weather:storm", group: "森林", title: "雷暴", detail: "持续覆盖 · 退出调试恢复"),
            .init(id: "hour:6.5", group: "森林", title: "清晨 06:30", detail: "持续光影预览"),
            .init(id: "hour:12", group: "森林", title: "正午 12:00", detail: "持续光影预览"),
            .init(id: "hour:18.5", group: "森林", title: "傍晚 18:30", detail: "持续光影预览"),
            .init(id: "hour:23", group: "森林", title: "夜晚 23:00", detail: "持续光影预览"),
            .init(id: "day", group: "森林", title: "24 秒播放一天", detail: "收起面板观察 · 重播从头开始"),
            .init(id: "forest", group: "森林", title: "森林细节参数", detail: "树叶、水面、头草与角色素材"),
            .init(id: "observer", group: "功能流程", title: "状态观测仪", detail: "示例数据 · 不写健康记录"),
            .init(id: "sleep", group: "功能流程", title: "晨间睡眠卡片", detail: "示例预览 · 标注 DEBUG"),
            .init(id: "notification", group: "功能流程", title: "睡眠通知", detail: "系统副作用 · 发送真实本地通知"),
            .init(id: "workout", group: "功能流程", title: "运动完成", detail: "写入测试运动 · 可能通知"),
            .init(id: "history-data", group: "功能流程", title: "足迹示例数据", detail: "写入本地测试数据并打开足迹"),
            .init(id: "backend-meal", group: "高级", title: "后台餐食识别", detail: "真实网络请求 · 测试图片"),
            .init(id: "legacy", group: "高级", title: "其他维护设置", detail: "账户、通知、诊断、实验室与重置"),
        ]
        return tools
    }

    static func tool(_ id: String) -> HomeDebugTool? { tools.first { $0.id == id } }

    /// Search across every group by title, detail or id.
    static func filter(group: String, query: String, recents: [String]) -> [HomeDebugTool] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return tools.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.detail.localizedCaseInsensitiveContains(trimmed)
                    || $0.id.localizedCaseInsensitiveContains(trimmed)
            }
        }
        if group == recentGroup { return recents.compactMap(tool) }
        return tools.filter { $0.group == group }
    }
}

/// Dock position, last group and six recents — the only persisted dock state.
/// Temporary simulations never survive a relaunch.
struct HomeDebugDockPreferences: Codable, Equatable {
    static let key = "pibo.debug.dock.v1"
    var onRightEdge = true
    var verticalFraction: Double = 0.62
    var lastGroup = "Pibo"
    var recents: [String] = []

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    mutating func noteUsed(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(6))
    }
}
#endif
