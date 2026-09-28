import CoreGraphics
import Foundation

struct ForestRGB: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    static let neutral = ForestRGB(red: 1, green: 1, blue: 1)

    static func interpolate(from: ForestRGB, to: ForestRGB, progress: CGFloat) -> ForestRGB {
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

struct ForestRenderConfiguration: Equatable, Sendable {
    var waterFlowSpeed: Double

    static let standard = ForestRenderConfiguration(waterFlowSpeed: 0.62)
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
    /// 0 = 正午，1 = 最深的夜。
    ///
    /// 给「灯该多亮」这类判断用。**不要拿某个材质的 `darkness` 当天色读** ——
    /// 每一层都带着自己的权重和上限（`far` 是 ×0.70，所以它最黑也只到 0.34），
    /// 直接用会得到一个悄悄缩水的强度。
    var nightness: CGFloat
    /// 0…1 how much open daylight the time and weather allow. State moods read
    /// it but never change it, so cross-fading two moods stays linear.
    var daylight: CGFloat = 1
    /// 0…1 warm light falling from the upper left (energetic, daylight only).
    var sunWash: CGFloat = 0
    /// 0…1 low peach light from the left (just woke up, daylight only).
    var dawnWash: CGFloat = 0
    /// 0…1 shade gathering at the lower edges (tired; a deeper night asleep).
    var shade: CGFloat = 0
    /// 0…1 ground mist (no data; a little when tired). Only moods set these four.
    var haze: CGFloat = 0
}

struct ForestEnvironmentSnapshot: Equatable, Sendable {
    var lighting: ForestLightingProfile
    var wind: StageWind
    var rainIntensity: CGFloat

    static let daylight = ForestEnvironmentAdapter.resolve(.daylight)
}

/// Maps the shared stage clock/weather snapshot to the forest's continuous,
/// authored lighting, wind, water, and atmosphere values.
enum ForestEnvironmentAdapter {
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

    /// 关键帧里最深的那个夜。从数组里取而不是写死 0.48 —— 调关键帧的人不该
    /// 还得记得回来同步一个常量。
    private static let peakDarkness: CGFloat = keyframes.map(\.darkness).max() ?? 1

    static func resolve(_ environment: PiboStageEnvironment) -> ForestEnvironmentSnapshot {
        let value = sampledKeyframe(at: environment.localHour)

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
            fireflyBirthRate: value.fireflies,
            nightness: peakDarkness > 0 ? min(value.darkness / peakDarkness, 1) : 0,
            // 1 at clear midday, 0 from late dusk on; rain dims it further.
            daylight: min(max(1 - value.darkness / 0.36, 0), 1)
                * (1 - min(max(environment.rainIntensity, 0), 1) * 0.7)
        )

        return ForestEnvironmentSnapshot(
            lighting: lighting,
            wind: StageWind(
                direction: value.windDirection,
                strength: value.windStrength,
                gustiness: value.gustiness
            ),
            rainIntensity: min(max(environment.rainIntensity, 0), 1)
        )
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

    private static func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let x = min(max((value - lower) / (upper - lower), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// The forest's reading of Pibo's Core state (2026-09-28, mirrors HarmonyOS
/// `ForestMood`). Presentation only: Core owns the state; the platform decides
/// how the same forest light answers it, so the state reads at a glance
/// instead of only through two-pixel eye changes.
enum ForestMood: String, CaseIterable, Sendable {
    case neutral
    case bright
    case weary
    case dawn
    case hush
    case haze

    init(state: PiboActivityState) {
        self = switch state {
        case .energetic: .bright
        case .tired: .weary
        case .waking: .dawn
        case .sleeping: .hush
        case .dataUnknown: .haze
        case .stable: .neutral
        }
    }
}

struct ForestMoodProfile: Equatable, Sendable {
    var darknessDelta: CGFloat = 0
    var saturationDelta: CGFloat = 0
    var tint: ForestRGB = .neutral
    var tintAmount: CGFloat = 0
    /// Minimum morning-beam opacity at full daylight; scaled down toward night.
    var beamFloor: CGFloat = 0
    var beamScale: CGFloat = 1
    /// Added fireflies. Scaled by darkness so a bright day never shows them.
    var fireflyDelta: CGFloat = 0
    var windScale: CGFloat = 1
    var haze: CGFloat = 0
    /// Peak sun/dawn wash at full daylight; scaled down toward night.
    var sunWash: CGFloat = 0
    var dawnWash: CGFloat = 0
    var shade: CGFloat = 0

    private static let warm = ForestRGB(red: 1.00, green: 0.93, blue: 0.80)
    private static let dawnLight = ForestRGB(red: 1.00, green: 0.86, blue: 0.66)
    private static let cool = ForestRGB(red: 0.84, green: 0.90, blue: 1.00)
    private static let moon = ForestRGB(red: 0.82, green: 0.87, blue: 1.00)
    private static let mist = ForestRGB(red: 0.93, green: 0.95, blue: 0.96)

    static func profile(for mood: ForestMood) -> ForestMoodProfile {
        switch mood {
        case .bright:
            ForestMoodProfile(darknessDelta: -0.05, saturationDelta: 0.10, tint: warm, tintAmount: 0.09,
                              beamFloor: 0.42, fireflyDelta: 1.5, windScale: 1.22, sunWash: 0.42)
        case .weary:
            ForestMoodProfile(darknessDelta: 0.08, saturationDelta: -0.12, tint: cool, tintAmount: 0.12,
                              beamScale: 0.35, fireflyDelta: -1, windScale: 0.55, haze: 0.12, shade: 0.42)
        case .dawn:
            ForestMoodProfile(darknessDelta: -0.03, saturationDelta: 0.04, tint: dawnLight, tintAmount: 0.12,
                              beamFloor: 0.40, windScale: 0.9, haze: 0.06, dawnWash: 0.4)
        case .hush:
            ForestMoodProfile(darknessDelta: 0.08, saturationDelta: -0.06, tint: moon, tintAmount: 0.10,
                              beamScale: 0.5, fireflyDelta: 1, windScale: 0.6, shade: 0.46)
        case .haze:
            ForestMoodProfile(saturationDelta: -0.18, tint: mist, tintAmount: 0.10,
                              beamScale: 0.4, fireflyDelta: -0.5, windScale: 0.8, haze: 0.55)
        case .neutral:
            ForestMoodProfile()
        }
    }
}

extension ForestEnvironmentSnapshot {
    /// Layers a state mood over the time-of-day/weather environment. `weight`
    /// is 0…1 so a state change cross-fades instead of cutting the forest's
    /// light: the renderer applies the outgoing mood at (1 - t) and the
    /// incoming one at t. Pibo and the water keep their own light.
    func applying(_ mood: ForestMood, weight: CGFloat) -> ForestEnvironmentSnapshot {
        let w = min(max(weight, 0), 1)
        guard mood != .neutral, w > 0 else { return self }
        let profile = ForestMoodProfile.profile(for: mood)
        let daylight = lighting.daylight

        func material(_ base: ForestMaterialLighting, tintAmount: CGFloat) -> ForestMaterialLighting {
            let added = tintAmount * w
            let total = min(base.tintAmount + added, 1)
            let share = total > 0 ? added / total : 0
            return ForestMaterialLighting(
                darkness: min(max(base.darkness + profile.darknessDelta * w, 0), 0.88),
                tint: .interpolate(from: base.tint, to: profile.tint, progress: share),
                tintAmount: total,
                saturation: min(max(base.saturation + profile.saturationDelta * w, 0.5), 1.15),
                lift: base.lift
            )
        }

        var result = self
        result.lighting.far = material(lighting.far, tintAmount: profile.tintAmount)
        result.lighting.midground = material(lighting.midground, tintAmount: profile.tintAmount)
        result.lighting.foreground = material(lighting.foreground, tintAmount: profile.tintAmount * 0.9)
        result.lighting.morningBeam = max(
            lighting.morningBeam * (1 + (profile.beamScale - 1) * w),
            profile.beamFloor * daylight * w
        )
        result.lighting.duskBeam = lighting.duskBeam * (1 + (profile.beamScale - 1) * w)
        result.lighting.fireflyBirthRate = max(
            0,
            lighting.fireflyBirthRate + profile.fireflyDelta * (1 - daylight) * w
        )
        result.lighting.sunWash = min(max(lighting.sunWash + profile.sunWash * daylight * w, 0), 1)
        result.lighting.dawnWash = min(max(lighting.dawnWash + profile.dawnWash * daylight * w, 0), 1)
        result.lighting.shade = min(max(lighting.shade + profile.shade * w, 0), 1)
        result.lighting.haze = min(max(lighting.haze + profile.haze * w, 0), 1)
        result.wind.strength = wind.strength * (1 + (profile.windScale - 1) * w)
        return result
    }
}
