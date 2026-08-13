import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeAtmosphereClockTests {
    @Test func refreshReplacesTheSnapshotWithTheProvidedDate() {
        let initial = Date(timeIntervalSince1970: 100)
        let refreshed = Date(timeIntervalSince1970: 200)
        let clock = HomeAtmosphereClock(now: initial, dateProvider: { refreshed })

        clock.refresh()

        #expect(clock.now == refreshed)
    }

    @Test func tickPublishesTheSameSnapshotItStores() {
        let refreshed = Date(timeIntervalSince1970: 300)
        let clock = HomeAtmosphereClock(
            now: Date(timeIntervalSince1970: 100),
            dateProvider: { refreshed }
        )
        var received: Date?

        clock.tick { received = $0 }

        #expect(clock.now == refreshed)
        #expect(received == refreshed)
    }

    @Test func runWaitsBeforeEachTickAndStopsWhenTheWaiterDeclines() async {
        let refreshed = Date(timeIntervalSince1970: 400)
        var waitCount = 0
        let clock = HomeAtmosphereClock(
            now: Date(timeIntervalSince1970: 100),
            dateProvider: { refreshed },
            waitForNextMinute: {
                waitCount += 1
                return waitCount == 1
            }
        )
        var received: [Date] = []

        await clock.run { received.append($0) }

        #expect(waitCount == 2)
        #expect(received == [refreshed])
        #expect(clock.now == refreshed)
    }

    @Test func localHourPreservesHourMinuteAndSecondPrecision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 15,
            minute: 30,
            second: 45
        )))

        let hour = HomeAtmosphereClock.localHour(at: date, calendar: calendar)

        #expect(abs(hour - 15.5125) < 0.000_001)
    }
}
