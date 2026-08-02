import CoreLocation
import Foundation
import WeatherKit
import os

/// Acquires the device's current location and maps WeatherKit's current
/// condition into the small provider-neutral weather vocabulary rendered by
/// Home. The last successful result is cached so launch never flashes back to
/// clear weather while a refresh is in flight.
@MainActor
@Observable
final class WeatherDataService: NSObject {
    private static let conditionKey = "pibo.weather.systemCondition.v1"
    private static let fetchedAtKey = "pibo.weather.systemFetchedAt.v1"
    private static let refreshInterval: TimeInterval = 30 * 60

    private(set) var systemCondition: PiboWeather
    private(set) var fetchedAt: Date?
    private(set) var isRefreshing = false

    #if DEBUG
    private(set) var debugCondition: PiboWeather?
    #endif

    private let locationManager = CLLocationManager()

    override init() {
        let defaults = UserDefaults.standard
        let storedCondition = defaults.string(forKey: Self.conditionKey)
            .flatMap(PiboWeather.init(rawValue:))
        let storedDate = defaults.object(forKey: Self.fetchedAtKey) as? Date
        if let storedCondition, let storedDate {
            systemCondition = storedCondition
            fetchedAt = storedDate
        } else {
            // Treat the two cache keys as one record. A partial/corrupt record
            // must not make the fallback `.clear` look fresh for 30 minutes.
            systemCondition = .clear
            fetchedAt = nil
            defaults.removeObject(forKey: Self.conditionKey)
            defaults.removeObject(forKey: Self.fetchedAtKey)
        }
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.delegate = self
    }

    var condition: PiboWeather {
        #if DEBUG
        debugCondition ?? systemCondition
        #else
        systemCondition
        #endif
    }

    func start() {
        // App startup may still be presenting onboarding. Refresh immediately
        // when permission already exists, but never interrupt onboarding with
        // a location prompt.
        refreshIfStale()
    }

    func activateForHome() {
        refreshIfStale(requestPermission: true)
    }

    func refreshIfStale(force: Bool = false, requestPermission: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let fetchedAt {
            let age = Date().timeIntervalSince(fetchedAt)
            if age >= 0, age < Self.refreshInterval {
                return
            }
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isRefreshing = true
            locationManager.requestLocation()
        case .notDetermined where requestPermission:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted, .notDetermined:
            LPLog.weather.info("WeatherKit refresh skipped: location is not authorized")
        @unknown default:
            break
        }
    }

    #if DEBUG
    func setDebugCondition(_ condition: PiboWeather?) {
        debugCondition = condition
    }
    #endif

    private func fetch(for location: CLLocation) async {
        defer { isRefreshing = false }
        do {
            let current = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .current
            )
            let condition = current.condition.piboWeather
            let now = Date()
            systemCondition = condition
            fetchedAt = now
            let defaults = UserDefaults.standard
            defaults.set(condition.rawValue, forKey: Self.conditionKey)
            defaults.set(now, forKey: Self.fetchedAtKey)
            LPLog.weather.notice("WeatherKit current condition=\(condition.rawValue, privacy: .public)")
        } catch {
            LPLog.weather.error("WeatherKit refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WeatherDataService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshIfStale()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            await self?.fetch(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isRefreshing = false
            LPLog.weather.error("Location for WeatherKit failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension WeatherCondition {
    var piboWeather: PiboWeather {
        switch self {
        case .clear, .mostlyClear, .hot:
            .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy, .breezy, .windy, .blowingDust:
            .cloudy
        case .foggy, .haze, .smoky:
            .fog
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain:
            .rain
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .tropicalStorm, .hurricane:
            .thunderstorm
        case .snow, .heavySnow, .flurries, .sunFlurries, .sleet, .blizzard,
             .blowingSnow, .frigid, .hail, .wintryMix:
            .snow
        @unknown default:
            .cloudy
        }
    }
}
