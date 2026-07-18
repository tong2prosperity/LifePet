import CoreGraphics
import Foundation

/// Semantic wall-clock phase shared by every home theme. A theme maps this
/// neutral input to its own authored lighting and material values.
enum PiboDayPhase: String, CaseIterable, Sendable {
    case morning
    case day
    case dusk
    case night

    var displayName: String {
        switch self {
        case .morning: return "早晨"
        case .day: return "白天"
        case .dusk: return "傍晚"
        case .night: return "夜晚"
        }
    }

    /// Reference hours used only to migrate the former four-state debug control.
    var referenceHour: Double {
        switch self {
        case .morning: return 6.5
        case .day: return 12
        case .dusk: return 18.5
        case .night: return 23
        }
    }

    /// The single semantic phase rule shared by every theme. Individual theme
    /// renderers remain free to interpolate their authored lighting continuously
    /// from `localHour` instead of switching visuals at these boundaries.
    static func resolve(hour: Double) -> PiboDayPhase {
        PiboCoreEnvironmentAdapter.dayPhase(at: hour)
    }
}

/// Theme-neutral input owned by Home. It deliberately preserves the weather
/// kind instead of collapsing every precipitation type into "rain".
struct PiboStageEnvironment: Equatable, Sendable {
    /// Local wall-clock hour in the circular 0..<24 domain.
    let localHour: Double
    let weather: PiboWeather

    var dayPhase: PiboDayPhase { .resolve(hour: localHour) }

    init(localHour: Double, weather: PiboWeather) {
        self.localHour = PiboStageEnvironmentResolver.normalizedHour(localHour)
        self.weather = weather
    }

    static let daylight = PiboStageEnvironment(
        localHour: 12,
        weather: .clear
    )

    var rainIntensity: CGFloat {
        CGFloat(PiboCoreEnvironmentAdapter.rainIntensity(for: weather))
    }
}

enum PiboStageEnvironmentResolver {
    static func resolve(
        date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        forcedHour: Double? = nil,
        weather: PiboWeather = .clear
    ) -> PiboStageEnvironment {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let wallClockHour = Double(components.hour ?? 12)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3_600
        let hour = normalizedHour(forcedHour ?? wallClockHour)
        return PiboStageEnvironment(
            localHour: hour,
            weather: weather
        )
    }

    static func normalizedHour(_ hour: Double) -> Double {
        PiboCoreEnvironmentAdapter.normalizedHour(hour)
    }
}

struct StageWind: Equatable, Sendable {
    var direction: CGVector
    var strength: CGFloat
    var gustiness: CGFloat
}

/// Runtime controls shared by every stage. Theme-specific tuning belongs to a
/// capability protocol instead of accumulating in this type.
struct StageRenderTuning: Equatable, Sendable {
    var piboVisible: Bool
    var ambientMotionScale: Double
    var headSproutFlexibility: Double

    static let standard = StageRenderTuning(
        piboVisible: true,
        ambientMotionScale: 1,
        headSproutFlexibility: 0.68
    )

    var sanitized: StageRenderTuning {
        StageRenderTuning(
            piboVisible: piboVisible,
            ambientMotionScale: min(max(ambientMotionScale, 0), 2),
            headSproutFlexibility: min(max(headSproutFlexibility, 0), 1)
        )
    }
}

/// Renderer-facing policy derived by the stage from generic tuning and system
/// state. It contains no character visibility or theme-specific controls.
struct PiboThemeRenderPolicy: Equatable, Sendable {
    var ambientMotionScale: Double
    var lowPowerMode: Bool
}
