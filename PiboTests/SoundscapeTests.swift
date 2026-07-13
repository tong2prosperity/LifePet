import Foundation
import XCTest
@testable import Pibo

@MainActor
final class SoundscapeTests: XCTestCase {
    private let petID = UUID(uuidString: "809B25A6-AC27-493D-98C2-DFDD1CB56C12")!

    func testDailyBiomeIsStableAndAlternatesOnTheNextLocalDay() throws {
        let calendar = fixedCalendar
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 1
        )))
        let later = try XCTUnwrap(calendar.date(byAdding: .hour, value: 20, to: first))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: first))

        let biome = SoundscapeResolver.biome(for: first, petID: petID, calendar: calendar)
        XCTAssertEqual(
            SoundscapeResolver.biome(for: later, petID: petID, calendar: calendar),
            biome
        )
        XCTAssertNotEqual(
            SoundscapeResolver.biome(for: nextDay, petID: petID, calendar: calendar),
            biome
        )
    }

    func testDayWeightBlendsAcrossMorningAndDuskBoundaries() {
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 4.99), 0, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 5), 0, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 7), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 9), 1, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 16.5), 1, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 18.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SoundscapeResolver.dayWeight(at: 20.5), 0, accuracy: 0.0001)
    }

    func testWeatherAddsRainAndThunderWithoutMelodicMusic() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clear = profile(weather: .clear, date: date)
        let rain = profile(weather: .rain, date: date)
        let thunderstorm = profile(weather: .thunderstorm, date: date)

        XCTAssertEqual(clear.loopVolumes[.lightRain], 0)
        XCTAssertEqual(clear.loopVolumes[.heavyRain], 0)
        XCTAssertFalse(clear.thunderEnabled)

        XCTAssertEqual(
            rain.loopVolumes[.lightRain] ?? -1,
            Float(0.36),
            accuracy: Float(0.0001)
        )
        XCTAssertEqual(rain.loopVolumes[.heavyRain], 0)
        XCTAssertFalse(rain.thunderEnabled)

        XCTAssertEqual(thunderstorm.loopVolumes[.lightRain], 0)
        XCTAssertEqual(
            thunderstorm.loopVolumes[.heavyRain] ?? -1,
            Float(0.55),
            accuracy: Float(0.0001)
        )
        XCTAssertTrue(thunderstorm.thunderEnabled)

        let baseAsset: SoundscapeAsset = clear.biome == .forest
            ? .forestWind
            : .rainforestRiver
        let clearBase = clear.loopVolumes[baseAsset] ?? 0
        XCTAssertGreaterThan(clearBase, 0)
        XCTAssertLessThan(rain.loopVolumes[baseAsset] ?? 1, clearBase)
        XCTAssertLessThan(
            thunderstorm.loopVolumes[baseAsset] ?? 1,
            rain.loopVolumes[baseAsset] ?? 0
        )
        XCTAssertEqual(
            SoundscapePresentation.ducked.volumeMultiplier,
            Float(0.35),
            accuracy: Float(0.0001)
        )
    }

    func testAppBundleContainsEverySoundscapeAsset() {
        for asset in SoundscapeAsset.allCases {
            let url = Bundle.main.url(
                forResource: asset.rawValue,
                withExtension: "m4a",
                subdirectory: "Audio/Ambience"
            ) ?? Bundle.main.url(forResource: asset.rawValue, withExtension: "m4a")
            XCTAssertNotNil(url, "Missing bundled soundscape asset: \(asset.rawValue).m4a")
        }
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    private func profile(weather: PiboWeather, date: Date) -> SoundscapeProfile {
        SoundscapeResolver.resolve(
            environment: PiboStageEnvironment(localHour: 12, weather: weather),
            date: date,
            petID: petID,
            calendar: fixedCalendar
        )
    }
}
