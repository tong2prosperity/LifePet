import PiboCore

/// App-domain adapter around the platform-neutral Rust environment engine.
/// Platform acquisition (clock, location, WeatherKit) remains native; only
/// deterministic Pibo rules cross the SDK boundary.
enum PiboCoreEnvironmentAdapter {
    static func normalizedHour(_ hour: Double) -> Double {
        PiboCoreEnvironment.normalizedHour(hour)
    }

    static func dayPhase(at hour: Double) -> PiboDayPhase {
        switch PiboCoreEnvironment.dayPhase(at: hour) {
        case .morning: .morning
        case .day: .day
        case .dusk: .dusk
        case .night: .night
        }
    }

    static func rainIntensity(for weather: PiboWeather) -> Double {
        PiboCoreEnvironment.rainIntensity(for: weather.coreWeather)
    }
}

private extension PiboWeather {
    var coreWeather: PiboCoreWeather {
        switch self {
        case .clear: .clear
        case .cloudy: .cloudy
        case .rain: .rain
        case .thunderstorm: .thunderstorm
        case .snow: .snow
        }
    }
}

