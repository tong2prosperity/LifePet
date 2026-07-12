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

    /// Reference hours used only to migrate the former four-state debug control.
    var referenceHour: Double {
        switch self {
        case .morning: return 6.5
        case .day: return 12
        case .dusk: return 18.5
        case .night: return 23
        }
    }
}

struct ForestRGB: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    static let neutral = ForestRGB(red: 1, green: 1, blue: 1)

    fileprivate static func interpolate(from: ForestRGB, to: ForestRGB, progress: CGFloat) -> ForestRGB {
        ForestRGB(
            red: from.red + (to.red - from.red) * progress,
            green: from.green + (to.green - from.green) * progress,
            blue: from.blue + (to.blue - from.blue) * progress
        )
    }
}

struct ForestMaterialLighting: Equatable, Sendable {
    var darkness: CGFloat
    var tint: ForestRGB
    var tintAmount: CGFloat
    var saturation: CGFloat
    var lift: CGFloat
}

struct ForestWaterLighting: Equatable, Sendable {
    var darkness: CGFloat
    var tint: ForestRGB
    var tintAmount: CGFloat
    var highlightStrength: CGFloat
    var reflectionStrength: CGFloat
}

struct ForestLightingProfile: Equatable, Sendable {
    var far: ForestMaterialLighting
    var midground: ForestMaterialLighting
    var foreground: ForestMaterialLighting
    var pibo: ForestMaterialLighting
    var water: ForestWaterLighting
    var morningBeam: CGFloat
    var duskBeam: CGFloat
    var fireflyBirthRate: CGFloat
}

struct ForestWind: Equatable, Sendable {
    var direction: CGVector
    var strength: CGFloat
    var gustiness: CGFloat
}

struct ForestEnvironmentSnapshot: Equatable, Sendable {
    var dayPhase: ForestDayPhase
    /// Local wall-clock hour in the circular 0..<24 domain.
    var localHour: Double
    var lighting: ForestLightingProfile
    var wind: ForestWind
    var rainIntensity: CGFloat

    static let daylight = ForestDayPhaseResolver.resolve(
        date: Date(timeIntervalSinceReferenceDate: 43_200),
        forcedHour: 12
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
    private struct Keyframe {
        var hour: Double
        var darkness: CGFloat
        var tint: ForestRGB
        var tintAmount: CGFloat
        var morningBeam: CGFloat
        var duskBeam: CGFloat
        var fireflies: CGFloat
        var windDirection: CGVector
        var windStrength: CGFloat
        var gustiness: CGFloat
        var waterHighlight: CGFloat
        var reflectionStrength: CGFloat
    }

    /// The final keyframe intentionally duplicates midnight. It closes the
    /// interpolation circle without a discontinuity at 24:00 → 00:00.
    private static let keyframes: [Keyframe] = [
        Keyframe(hour: 0, darkness: 0.48,
                 tint: ForestRGB(red: 0.38, green: 0.58, blue: 0.86), tintAmount: 0.30,
                 morningBeam: 0, duskBeam: 0, fireflies: 6,
                 windDirection: CGVector(dx: -0.96, dy: -0.04), windStrength: 0.20, gustiness: 0.16,
                 waterHighlight: 0.38, reflectionStrength: 0.40),
        Keyframe(hour: 5, darkness: 0.30,
                 tint: ForestRGB(red: 0.62, green: 0.70, blue: 0.78), tintAmount: 0.22,
                 morningBeam: 0.05, duskBeam: 0, fireflies: 2,
                 windDirection: CGVector(dx: -0.90, dy: -0.07), windStrength: 0.28, gustiness: 0.22,
                 waterHighlight: 0.50, reflectionStrength: 0.55),
        Keyframe(hour: 6.5, darkness: 0.08,
                 tint: ForestRGB(red: 1.00, green: 0.78, blue: 0.46), tintAmount: 0.20,
                 morningBeam: 0.72, duskBeam: 0, fireflies: 0,
                 windDirection: CGVector(dx: -0.86, dy: -0.10), windStrength: 0.45, gustiness: 0.34,
                 waterHighlight: 0.92, reflectionStrength: 0.90),
        Keyframe(hour: 9, darkness: 0,
                 tint: .neutral, tintAmount: 0,
                 morningBeam: 0.08, duskBeam: 0, fireflies: 0,
                 windDirection: CGVector(dx: -0.92, dy: -0.08), windStrength: 0.35, gustiness: 0.28,
                 waterHighlight: 0.82, reflectionStrength: 1),
        Keyframe(hour: 16.5, darkness: 0,
                 tint: .neutral, tintAmount: 0,
                 morningBeam: 0, duskBeam: 0.04, fireflies: 0,
                 windDirection: CGVector(dx: -0.90, dy: -0.09), windStrength: 0.36, gustiness: 0.30,
                 waterHighlight: 0.82, reflectionStrength: 1),
        Keyframe(hour: 18.5, darkness: 0.18,
                 tint: ForestRGB(red: 1.00, green: 0.44, blue: 0.19), tintAmount: 0.24,
                 morningBeam: 0, duskBeam: 0.34, fireflies: 1.2,
                 windDirection: CGVector(dx: -0.78, dy: -0.18), windStrength: 0.55, gustiness: 0.44,
                 waterHighlight: 0.68, reflectionStrength: 0.75),
        Keyframe(hour: 20.5, darkness: 0.40,
                 tint: ForestRGB(red: 0.38, green: 0.56, blue: 0.82), tintAmount: 0.28,
                 morningBeam: 0, duskBeam: 0.04, fireflies: 4,
                 windDirection: CGVector(dx: -0.92, dy: -0.07), windStrength: 0.28, gustiness: 0.22,
                 waterHighlight: 0.45, reflectionStrength: 0.50),
        Keyframe(hour: 24, darkness: 0.48,
                 tint: ForestRGB(red: 0.38, green: 0.58, blue: 0.86), tintAmount: 0.30,
                 morningBeam: 0, duskBeam: 0, fireflies: 6,
                 windDirection: CGVector(dx: -0.96, dy: -0.04), windStrength: 0.20, gustiness: 0.16,
                 waterHighlight: 0.38, reflectionStrength: 0.40),
    ]

    static func resolve(
        date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        forcedHour: Double? = nil,
        rainIntensity: CGFloat = 0
    ) -> ForestEnvironmentSnapshot {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let wallClockHour = Double(components.hour ?? 12)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3_600
        let hour = normalizedHour(forcedHour ?? wallClockHour)
        let value = sampledKeyframe(at: hour)

        let material = { (darknessWeight: CGFloat, tintWeight: CGFloat, lift: CGFloat) in
            ForestMaterialLighting(
                darkness: min(value.darkness * darknessWeight, 0.88),
                tint: value.tint,
                tintAmount: min(value.tintAmount * tintWeight, 1),
                saturation: max(0.72, 1 - value.darkness * 0.24),
                lift: lift
            )
        }
        let piboLift = smoothstep(0.22, 0.48, value.darkness) * 0.045
        let lighting = ForestLightingProfile(
            far: material(0.70, 1, 0),
            midground: material(1, 1, 0),
            foreground: material(1.15, 0.9, 0),
            pibo: material(0.55, 0.45, piboLift),
            water: ForestWaterLighting(
                darkness: min(value.darkness * 1.05, 0.88),
                tint: value.tint,
                tintAmount: min(value.tintAmount * 0.72, 1),
                highlightStrength: value.waterHighlight,
                reflectionStrength: value.reflectionStrength
            ),
            morningBeam: value.morningBeam,
            duskBeam: value.duskBeam,
            fireflyBirthRate: value.fireflies
        )

        return ForestEnvironmentSnapshot(
            dayPhase: semanticPhase(for: hour),
            localHour: hour,
            lighting: lighting,
            wind: ForestWind(
                direction: value.windDirection,
                strength: value.windStrength,
                gustiness: value.gustiness
            ),
            rainIntensity: min(max(rainIntensity, 0), 1)
        )
    }

    static func normalizedHour(_ hour: Double) -> Double {
        let remainder = hour.truncatingRemainder(dividingBy: 24)
        return remainder >= 0 ? remainder : remainder + 24
    }

    private static func sampledKeyframe(at hour: Double) -> Keyframe {
        guard let upperIndex = keyframes.firstIndex(where: { hour < $0.hour }), upperIndex > 0 else {
            return keyframes[0]
        }
        let lower = keyframes[upperIndex - 1]
        let upper = keyframes[upperIndex]
        let linear = CGFloat((hour - lower.hour) / (upper.hour - lower.hour))
        let progress = linear * linear * (3 - 2 * linear)

        func scalar(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
            lhs + (rhs - lhs) * progress
        }
        return Keyframe(
            hour: hour,
            darkness: scalar(lower.darkness, upper.darkness),
            tint: .interpolate(from: lower.tint, to: upper.tint, progress: progress),
            tintAmount: scalar(lower.tintAmount, upper.tintAmount),
            morningBeam: scalar(lower.morningBeam, upper.morningBeam),
            duskBeam: scalar(lower.duskBeam, upper.duskBeam),
            fireflies: scalar(lower.fireflies, upper.fireflies),
            windDirection: CGVector(
                dx: scalar(lower.windDirection.dx, upper.windDirection.dx),
                dy: scalar(lower.windDirection.dy, upper.windDirection.dy)
            ),
            windStrength: scalar(lower.windStrength, upper.windStrength),
            gustiness: scalar(lower.gustiness, upper.gustiness),
            waterHighlight: scalar(lower.waterHighlight, upper.waterHighlight),
            reflectionStrength: scalar(lower.reflectionStrength, upper.reflectionStrength)
        )
    }

    private static func semanticPhase(for hour: Double) -> ForestDayPhase {
        switch hour {
        case 5..<9: return .morning
        case 9..<16.5: return .day
        case 16.5..<20.5: return .dusk
        default: return .night
        }
    }

    private static func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let x = min(max((value - lower) / (upper - lower), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
