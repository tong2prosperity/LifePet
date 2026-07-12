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
// 数据源:v1 由设置页的 DEBUG 开关手动切换(见 `SettingsSheet`),写进
// `PetStateStore.weather`,由 `HomeView` 映射进 `ForestEnvironmentSnapshot`。
// 接入 WeatherKit 后,改由 `WeatherService` 写入 `store.weather` —— 映射见文件
// 末尾"WeatherKit 接入"注释块,届时取消注释即可,无需改动场景层。

/// 当前天气状态(驱动首页场景氛围)。
enum PiboWeather: String, CaseIterable, Sendable {
    case clear          // 晴
    case cloudy         // 多云(占位,暂无特效)
    case rain           // 雨
    case thunderstorm   // 雷雨(v1 走 rain,强度更大)
    case snow           // 雪(占位,暂无特效)

    /// 降水强度 0–1 —— 驱动雨幕粒子量 / 水花频率。晴/多云 = 0。
    var precipitation: Double {
        switch self {
        case .clear, .cloudy: return 0
        case .rain:           return 0.6
        case .thunderstorm:   return 1.0
        case .snow:           return 0.5   // 预留:雪量
        }
    }

    /// v1 是否渲染"下雨三件套"。雷雨也算(更大的雨)。
    var isRainy: Bool { self == .rain || self == .thunderstorm }

    /// 中文短名 —— DEBUG 天气开关用。
    var displayName: String {
        switch self {
        case .clear:        return "晴"
        case .cloudy:       return "多云"
        case .rain:         return "雨"
        case .thunderstorm: return "雷雨"
        case .snow:         return "雪"
        }
    }
}

// MARK: - WeatherKit 接入(之后启用)
//
// WeatherKit 是 iOS 16+ 系统框架,Swift API 极简:传一个 `CLLocation`(WalkDoodle
// 的 `WalkDoodleSession` 已有定位)即可拿到 `currentWeather.condition`。
//
// 运行期前置条件(本次未做,刻意不动 pbxproj/签名):
//   1. target 开 WeatherKit capability + entitlement(绑定已注册 bundle id)。
//   2. 付费 Apple Developer Program(真机才跑得起来;模拟器/免费账号拿不到数据)。
//   3. UI 上展示 Apple Weather 商标 + `weather.attribution` 法律链接(条款强制)。
//
// 满足后,新建一个 `Services/Weather/WeatherDataService`(仿 `HealthDataService`
// 的 `@MainActor @Observable` 形态,复用 WalkDoodle 的 `CLLocationManager`),拉到
// 天气后用下面的映射写 `store.weather`。映射本身零依赖签名,但需 `import WeatherKit`
// 才能引用 `WeatherCondition`,故先以注释形式预留 —— 启用时取消注释:
//
//   #if canImport(WeatherKit)
//   import WeatherKit
//
//   @available(iOS 16.0, *)
//   extension WeatherCondition {
//       /// WeatherKit 当前天气 → PiboWeather。
//       var piboWeather: PiboWeather {
//           switch self {
//           case .clear, .mostlyClear, .hot:
//               return .clear
//           case .cloudy, .mostlyCloudy, .partlyCloudy, .foggy, .haze, .smoky, .breezy, .windy:
//               return .cloudy
//           case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain:
//               return .rain
//           case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
//                .strongStorms, .tropicalStorm, .hurricane:
//               return .thunderstorm
//           case .snow, .heavySnow, .flurries, .sleet, .blizzard, .blowingSnow,
//                .frigid, .hail, .wintryMix:
//               return .snow
//           @unknown default:
//               return .clear
//           }
//       }
//   }
//   #endif
//
// 用法(WeatherDataService 内):
//   let weather = try await WeatherService.shared.weather(for: location)
//   store.weather = weather.currentWeather.condition.piboWeather
