import PiboCore

nonisolated enum PiboCoreSoundscapeAdapter {
    static func resolve(
        localHour: Double,
        weather: PiboWeather,
        biome: SoundscapeBiome
    ) -> SoundscapeProfile {
        let core = PiboCoreSoundscape.resolve(
            localHour: localHour,
            weather: coreWeather(weather),
            biome: biome == .forest ? .forest : .rainforest
        )
        return SoundscapeProfile(
            biome: biome,
            loopVolumes: [
                .forestDay: Float(core.forestDay),
                .forestNight: Float(core.forestNight),
                .forestWind: Float(core.forestWind),
                .rainforestRiver: Float(core.rainforestRiver),
                .rainforestBirds: Float(core.rainforestBirds),
                .rainforestTwilight: Float(core.rainforestTwilight),
                .lightRain: Float(core.lightRain),
                .heavyRain: Float(core.heavyRain),
            ],
            thunderEnabled: core.thunderEnabled
        )
    }

    static func dayWeight(at localHour: Double) -> Float {
        Float(PiboCoreSoundscape.dayWeight(localHour: localHour))
    }

    private static func coreWeather(_ weather: PiboWeather) -> PiboCoreWeather {
        switch weather {
        case .clear: .clear
        case .cloudy: .cloudy
        case .fog: .fog
        case .rain: .rain
        case .thunderstorm: .thunderstorm
        case .snow: .snow
        }
    }
}
