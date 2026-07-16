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
        return PiboCoreSoundscapeAdapter.resolve(
            localHour: environment.localHour,
            weather: environment.weather,
            biome: biome
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
        PiboCoreSoundscapeAdapter.dayWeight(at: rawHour)
    }
}
