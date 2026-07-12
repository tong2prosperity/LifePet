import CoreGraphics
import Foundation

/// Local, presentation-only atmosphere for the fixed portrait forest.
/// Rain stays zero in Release; DEBUG can override it from Settings.
enum ForestDayPhase: String, CaseIterable, Sendable {
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
}

struct ForestWind: Equatable, Sendable {
    var direction: CGVector
    var strength: CGFloat
    var gustiness: CGFloat
}

struct ForestEnvironmentSnapshot: Equatable, Sendable {
    var dayPhase: ForestDayPhase
    /// Progress through the current phase, 0...1. Used to keep ambient motion
    /// deterministic without asking the renderer to read wall-clock time.
    var phaseProgress: CGFloat
    var wind: ForestWind
    var rainIntensity: CGFloat

    static let daylight = ForestEnvironmentSnapshot(
        dayPhase: .day,
        phaseProgress: 0.5,
        wind: ForestWind(direction: CGVector(dx: -0.92, dy: -0.08), strength: 0.35, gustiness: 0.28),
        rainIntensity: 0
    )
}

/// Runtime presentation controls for the production forest renderer. Home only
/// exposes them in DEBUG; Release always supplies `.standard`.
struct ForestSceneTuning: Equatable, Sendable {
    var piboVisible: Bool
    var foliageMotionScale: Double
    var waterFlowSpeed: Double

    static let standard = ForestSceneTuning(
        piboVisible: true,
        foliageMotionScale: 1,
        waterFlowSpeed: 0.62
    )

    var sanitized: ForestSceneTuning {
        ForestSceneTuning(
            piboVisible: piboVisible,
            foliageMotionScale: min(max(foliageMotionScale, 0), 2),
            waterFlowSpeed: min(max(waterFlowSpeed, 0), 1.4)
        )
    }
}

enum ForestDayPhaseResolver {
    static func resolve(
        date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        forcedPhase: ForestDayPhase? = nil,
        rainIntensity: CGFloat = 0
    ) -> ForestEnvironmentSnapshot {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(components.hour ?? 12)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3_600

        let resolved = forcedPhase.map { ($0, 0.5) } ?? phaseAndProgress(for: hour)
        let wind: ForestWind
        switch resolved.0 {
        case .morning:
            wind = ForestWind(direction: CGVector(dx: -0.86, dy: -0.10), strength: 0.45, gustiness: 0.34)
        case .day:
            wind = ForestWind(direction: CGVector(dx: -0.92, dy: -0.08), strength: 0.35, gustiness: 0.28)
        case .dusk:
            wind = ForestWind(direction: CGVector(dx: -0.78, dy: -0.18), strength: 0.55, gustiness: 0.44)
        case .night:
            wind = ForestWind(direction: CGVector(dx: -0.96, dy: -0.04), strength: 0.20, gustiness: 0.16)
        }

        return ForestEnvironmentSnapshot(
            dayPhase: resolved.0,
            phaseProgress: CGFloat(resolved.1),
            wind: wind,
            rainIntensity: min(max(rainIntensity, 0), 1)
        )
    }

    private static func phaseAndProgress(for hour: Double) -> (ForestDayPhase, Double) {
        switch hour {
        case 5..<10:
            return (.morning, (hour - 5) / 5)
        case 10..<17:
            return (.day, (hour - 10) / 7)
        case 17..<20:
            return (.dusk, (hour - 17) / 3)
        default:
            let normalized = hour >= 20 ? hour - 20 : hour + 4
            return (.night, normalized / 9)
        }
    }
}
