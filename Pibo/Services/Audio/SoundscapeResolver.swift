import Foundation

nonisolated enum SoundscapeBiome: String, Equatable, Sendable {
    case forest
    case rainforest
}

nonisolated enum SoundscapePresentation: Equatable, Sendable {
    case active
    case ducked
    case suspended

    var volumeMultiplier: Float {
        switch self {
        case .active: return 1
        case .ducked: return 0.35
        case .suspended: return 0
        }
    }
}

nonisolated enum SoundscapeAsset: String, CaseIterable, Sendable {
    case forestDay = "ambient_forest_day"
    case forestNight = "ambient_forest_night"
    case forestWind = "ambient_forest_wind"
    case rainforestRiver = "ambient_rainforest_river"
    case rainforestBirds = "ambient_rainforest_birds"
    case rainforestTwilight = "ambient_rainforest_twilight"
    case lightRain = "weather_rain_light"
    case heavyRain = "weather_rain_heavy"
    case thunderDistant = "weather_thunder_distant"
    case thunderDeep = "weather_thunder_deep"
    case thunderBig = "weather_thunder_big"

    static let loopAssets: [SoundscapeAsset] = [
        .forestDay,
        .forestNight,
        .forestWind,
        .rainforestRiver,
        .rainforestBirds,
        .rainforestTwilight,
        .lightRain,
        .heavyRain,
    ]

    static let thunderAssets: [SoundscapeAsset] = [
        .thunderDistant,
        .thunderDeep,
        .thunderBig,
    ]
}

nonisolated struct SoundscapeProfile: Equatable, Sendable {
    let biome: SoundscapeBiome
    let loopVolumes: [SoundscapeAsset: Float]
    let thunderEnabled: Bool
}

/// Converts the same neutral time/weather snapshot used by the SpriteKit stage
/// into stable audio targets. It deliberately owns no playback state.
nonisolated enum SoundscapeResolver {
    static func resolve(
        environment: PiboStageEnvironment,
        date: Date,
        petID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SoundscapeProfile {
        let biome = biome(for: date, petID: petID, calendar: calendar)
        let day = dayWeight(at: environment.localHour)
        let night = 1 - day

        let baseScale: Float
        let wildlifeScale: Float
        let lightRain: Float
        let heavyRain: Float
        let thunderEnabled: Bool
        switch environment.weather {
        case .rain:
            baseScale = 0.75
            wildlifeScale = 0.25
            lightRain = 0.36
            heavyRain = 0
            thunderEnabled = false
        case .thunderstorm:
            baseScale = 0.55
            wildlifeScale = 0
            lightRain = 0
            heavyRain = 0.55
            thunderEnabled = true
        case .clear, .cloudy, .snow:
            baseScale = 1
            wildlifeScale = 1
            lightRain = 0
            heavyRain = 0
            thunderEnabled = false
        }

        var volumes = Dictionary(
            uniqueKeysWithValues: SoundscapeAsset.loopAssets.map { ($0, Float.zero) }
        )
        switch biome {
        case .forest:
            volumes[.forestDay] = 0.32 * day * baseScale
            volumes[.forestNight] = 0.22 * night * wildlifeScale
            volumes[.forestWind] = (0.06 + 0.04 * day) * baseScale
        case .rainforest:
            volumes[.rainforestRiver] = 0.26 * baseScale
            volumes[.rainforestBirds] = 0.24 * day * wildlifeScale
            volumes[.rainforestTwilight] = 0.18 * night * wildlifeScale
        }
        volumes[.lightRain] = lightRain
        volumes[.heavyRain] = heavyRain

        return SoundscapeProfile(
            biome: biome,
            loopVolumes: volumes,
            thunderEnabled: thunderEnabled
        )
    }

    static func biome(
        for date: Date,
        petID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SoundscapeBiome {
        // `ordinality(of: .day, in: .era, for:)` can advance within one local
        // date when called with an arbitrary time. Normalize first so the
        // selected biome cannot change partway through the user's day.
        let localDay = calendar.startOfDay(for: date)
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: localDay) ?? 0
        let petOffset = petID.uuidString.utf8.reduce(0) { ($0 + Int($1)) % 2 }
        return (dayOrdinal + petOffset).isMultiple(of: 2) ? .forest : .rainforest
    }

    static func dayWeight(at rawHour: Double) -> Float {
        let hour = PiboStageEnvironmentResolver.normalizedHour(rawHour)
        switch hour {
        case 5..<9:
            return Float(smoothstep((hour - 5) / 4))
        case 9..<16.5:
            return 1
        case 16.5..<20.5:
            return Float(1 - smoothstep((hour - 16.5) / 4))
        default:
            return 0
        }
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
