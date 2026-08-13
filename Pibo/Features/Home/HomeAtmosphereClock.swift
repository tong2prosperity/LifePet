import Foundation
import Observation

/// Owns Home's wall-clock snapshot and minute cadence. Environment rendering,
/// animation selection, and ornament effects remain with their existing owners.
@MainActor
@Observable
final class HomeAtmosphereClock {
    typealias DateProvider = @MainActor () -> Date
    typealias MinuteWaiter = @MainActor () async -> Bool

    private(set) var now: Date

    @ObservationIgnored private let dateProvider: DateProvider
    @ObservationIgnored private let waitForNextMinute: MinuteWaiter

    init(
        now: Date = .now,
        dateProvider: @escaping DateProvider = { .now },
        waitForNextMinute: @escaping MinuteWaiter = {
            try? await Task.sleep(for: .seconds(60))
            return !Task.isCancelled
        }
    ) {
        self.now = now
        self.dateProvider = dateProvider
        self.waitForNextMinute = waitForNextMinute
    }

    func refresh() {
        now = dateProvider()
    }

    func run(onMinute: @escaping @MainActor (Date) -> Void) async {
        while !Task.isCancelled {
            guard await waitForNextMinute(), !Task.isCancelled else { return }
            tick(onMinute: onMinute)
        }
    }

    func tick(onMinute: @MainActor (Date) -> Void) {
        refresh()
        onMinute(now)
    }

    static func localHour(
        at date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let values = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(values.hour ?? 0)
            + Double(values.minute ?? 0) / 60
            + Double(values.second ?? 0) / 3_600
    }
}
