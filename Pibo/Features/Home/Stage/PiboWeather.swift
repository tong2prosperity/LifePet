import Foundation

// MARK: - Pibo 世界的天气
//
// 现实天气 → 首页 SpriteKit 场景的氛围。Pibo 是异世界种花小精灵,天气是它头上
// 那朵花所处的"世界天气",所以把真实天气映射进 `PiboStageScene` 的场景里。
//
// v1 只渲染 **雨** 三件套(雨幕 + 地面水花 + 滴在 Pibo 上):`.rain` / `.thunderstorm`
// 走下雨路径(雷雨 = 更大的雨,闪电后续);`.clear` / `.cloudy` / `.snow` 暂为占位
// (不渲染特效),等后续各自补氛围。
//
// 数据源由 `WeatherDataService` 使用 WeatherKit 获取。Debug 设置可以做
// 临时覆盖；Release 只读取 WeatherKit 的实时/缓存结果。

/// 当前天气状态(驱动首页场景氛围)。
enum PiboWeather: String, CaseIterable, Sendable {
    case clear          // 晴
    case cloudy         // 多云(占位,暂无特效)
    case fog            // 雾/霾(占位,暂无特效)
    case rain           // 雨
    case thunderstorm   // 雷雨(v1 走 rain,强度更大)
    case snow           // 雪(占位,暂无特效)

    // 降水强度不在这里定义。它是跨平台规则,由 `pibo-core` 的 `rain_intensity`
    // 独占,经 `PiboCoreEnvironmentAdapter.rainIntensity(for:)` 取用 ——
    // 见 `PiboStageEnvironment.rainIntensity`。此处曾留有一份 Swift 副本,
    // 其中雪 = 0.5 与 Core 的 0 不一致;因无人引用而未造成故障,但正是这条
    // 「规则只有一处实现」的约束所要防的漂移,故删除而非修正。
    //
    // 「是否在下雨」同样不需要本地判据:强度 > 0 即为下雨,
    // `PiboWeatherEffectController.rebuild()` 就是这么判的。

    /// 中文短名 —— DEBUG 天气开关用。
    var displayName: String {
        switch self {
        case .clear:        return "晴"
        case .cloudy:       return "多云"
        case .fog:          return "雾"
        case .rain:         return "雨"
        case .thunderstorm: return "雷雨"
        case .snow:         return "雪"
        }
    }
}
