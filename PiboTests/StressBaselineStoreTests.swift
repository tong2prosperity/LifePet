import Foundation
import Testing
@testable import Pibo

@Suite("Stress baseline eligibility", .serialized)
@MainActor
struct StressBaselineStoreTests {
    @Test func recordOnlyMeasurementDoesNotEnterThePersonalBaseline() throws {
        StressBaselineStore.reset()
        defer { StressBaselineStore.reset() }

        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date())
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let thirdDay = try #require(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let noon: TimeInterval = 12 * 60 * 60

        // A visible but ineligible measurement must not create a daily bucket.
        #expect(StressBaselineStore.record(
            rmssd: 20,
            isEligible: false,
            date: firstDay.addingTimeInterval(noon),
            now: firstDay.addingTimeInterval(noon)
        ) == nil)

        #expect(StressBaselineStore.record(
            rmssd: 40,
            isEligible: true,
            date: secondDay.addingTimeInterval(noon),
            now: secondDay.addingTimeInterval(noon)
        ) == nil)
        let baseline = try #require(StressBaselineStore.record(
            rmssd: 60,
            isEligible: true,
            date: thirdDay.addingTimeInterval(noon),
            now: thirdDay.addingTimeInterval(noon)
        ))

        #expect(baseline.dayCount == 1)
        #expect(abs(baseline.geoMean - 40) < 0.001)
    }

    @Test func futureAndNonFiniteMeasurementsDoNotEnterTheBaseline() throws {
        StressBaselineStore.reset()
        defer { StressBaselineStore.reset() }

        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date())
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let noon: TimeInterval = 12 * 60 * 60
        let now = firstDay.addingTimeInterval(noon)

        #expect(StressBaselineStore.record(
            rmssd: 999,
            isEligible: true,
            date: now.addingTimeInterval(60),
            now: now
        ) == nil)
        #expect(StressBaselineStore.record(
            rmssd: .infinity,
            isEligible: true,
            date: now,
            now: now
        ) == nil)
        #expect(StressBaselineStore.record(
            rmssd: 40,
            isEligible: true,
            date: now,
            now: now
        ) == nil)

        let nextNoon = secondDay.addingTimeInterval(noon)
        let baseline = try #require(StressBaselineStore.record(
            rmssd: 60,
            isEligible: true,
            date: nextNoon,
            now: nextNoon
        ))
        #expect(baseline.dayCount == 1)
        #expect(abs(baseline.geoMean - 40) < 0.001)
    }

    @Test func backfillUsesNaturalDayMedianAndSeriesIdentity() throws {
        StressBaselineStore.reset()
        defer { StressBaselineStore.reset() }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let firstDay = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let secondDay = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        _ = StressBaselineStore.backfill([
            (firstID, 20, firstDay.addingTimeInterval(10 * 60 * 60)),
            (secondID, 60, firstDay.addingTimeInterval(12 * 60 * 60)),
            (thirdID, 80, secondDay.addingTimeInterval(12 * 60 * 60)),
        ], now: today.addingTimeInterval(12 * 60 * 60))
        let baseline = try #require(StressBaselineStore.backfill([
            // Retrying the same series must replace, not add another weight.
            (firstID, 20, firstDay.addingTimeInterval(10 * 60 * 60)),
        ], now: today.addingTimeInterval(12 * 60 * 60)))

        #expect(baseline.dayCount == 2)
        // Day medians are 40 and 80; their geometric mean is sqrt(3200).
        #expect(abs(baseline.geoMean - sqrt(3_200)) < 0.001)
        #expect(StressBaselineStore.dailyMedian(for: firstDay) == 40)
    }

    @Test func backfillRejectsFutureAndNonFiniteValues() throws {
        StressBaselineStore.reset()
        defer { StressBaselineStore.reset() }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let now = today.addingTimeInterval(12 * 60 * 60)

        #expect(StressBaselineStore.backfill([
            (UUID(), .infinity, yesterday),
            (UUID(), 40, now.addingTimeInterval(60)),
        ], now: now) == nil)
        #expect(StressBaselineStore.dailyMedian(for: yesterday) == nil)
    }

    @Test func retryingTodaysSeriesDoesNotDuplicateItsWeight() throws {
        StressBaselineStore.reset()
        defer { StressBaselineStore.reset() }

        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date())
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let firstNoon = firstDay.addingTimeInterval(12 * 60 * 60)
        let secondNoon = secondDay.addingTimeInterval(12 * 60 * 60)
        let id = UUID()
        _ = StressBaselineStore.record(
            rmssd: 20, isEligible: true, date: firstNoon, now: firstNoon, seriesID: id)
        _ = StressBaselineStore.record(
            rmssd: 20, isEligible: true, date: firstNoon, now: firstNoon, seriesID: id)
        _ = StressBaselineStore.record(
            rmssd: 60, isEligible: true, date: firstNoon, now: firstNoon, seriesID: UUID())

        let baseline = try #require(StressBaselineStore.record(
            rmssd: 50, isEligible: true, date: secondNoon, now: secondNoon, seriesID: UUID()))
        #expect(abs(baseline.geoMean - 40) < 0.001)
    }
}

@Suite("Stress sample timing")
struct StressSampleTimingTests {
    @Test func futureSamplesCannotNotifyEvenInEveryReadingMode() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let future = now.addingTimeInterval(1)

        #expect(StressSampleTiming.age(measuredAt: future, now: now) == nil)
        #expect(!StressSampleTiming.shouldAttemptNotification(
            measuredAt: future,
            now: now,
            everyReading: false
        ))
        #expect(!StressSampleTiming.shouldAttemptNotification(
            measuredAt: future,
            now: now,
            everyReading: true
        ))
    }

    @Test func staleSamplesRemainAvailableOnlyToEveryReadingMode() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let stale = now.addingTimeInterval(-DerivedStressModel.maxAnchorAge - 1)

        #expect(!StressSampleTiming.shouldAttemptNotification(
            measuredAt: stale,
            now: now,
            everyReading: false
        ))
        #expect(StressSampleTiming.shouldAttemptNotification(
            measuredAt: stale,
            now: now,
            everyReading: true
        ))
    }
}
