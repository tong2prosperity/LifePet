import Foundation
import Testing
@testable import Pibo

/// A pat offers health help at most once per local day and never on the
/// onboarding day (HarmonyOS `test_health_prompt_policy.mjs`,
/// docs/harmony-first/2026-09-28-无数据时温和提示.md).
struct HealthRecoveryPromptPolicyTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private static func allowed(_ now: Date, last: String?, onboarded: Date?) -> Bool {
        HealthRecoveryPromptPolicy.patPromptAllowed(
            now: now,
            lastPromptDay: last,
            onboardingCompletedAt: onboarded,
            calendar: calendar
        )
    }

    private static func day(_ date: Date) -> String {
        HealthRecoveryPromptPolicy.dayKey(date, calendar: calendar)
    }

    @Test func theOnboardingDayNeverAsks() {
        let onboarded = Self.at(28, 9)
        #expect(!Self.allowed(Self.at(28, 9, 5), last: nil, onboarded: onboarded))
        #expect(!Self.allowed(Self.at(28, 23, 59), last: nil, onboarded: onboarded))
    }

    @Test func anExplicitAuthorizationPatCanHelpOnDayOneButOnlyOnce() {
        let now = Self.at(28, 10)
        #expect(HealthRecoveryPromptPolicy.patPromptAllowed(
            now: now, lastPromptDay: nil, onboardingCompletedAt: Self.at(28, 9),
            allowAuthorizationOnboardingDay: true, calendar: Self.calendar))
        #expect(!HealthRecoveryPromptPolicy.patPromptAllowed(
            now: now, lastPromptDay: Self.day(now), onboardingCompletedAt: Self.at(28, 9),
            allowAuthorizationOnboardingDay: true, calendar: Self.calendar))
    }

    @Test func theNextDayAsksOnce() {
        let onboarded = Self.at(28, 9)
        let morning = Self.at(29, 8)
        #expect(Self.allowed(morning, last: nil, onboarded: onboarded))
        #expect(!Self.allowed(Self.at(29, 20), last: Self.day(morning), onboarded: onboarded))
    }

    @Test func midnightStartsANewDay() {
        let lateNight = Self.at(29, 23, 50)
        #expect(!Self.allowed(Self.at(29, 23, 59), last: Self.day(lateNight), onboarded: nil))
        #expect(Self.allowed(Self.at(30, 0, 1), last: Self.day(lateNight), onboarded: nil))
    }

    @Test func anUnknownOnboardingDayStillAsksOnceADay() {
        #expect(Self.allowed(Self.at(28, 9), last: nil, onboarded: nil))
        #expect(!Self.allowed(Self.at(28, 10), last: Self.day(Self.at(28, 9)), onboarded: nil))
    }

    @Test func theShownDaySurvivesARelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let noon = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))

        let store = HealthRecoveryPromptStore(defaults: defaults)
        #expect(store.patPromptAllowed(at: noon, onboardingCompletedAt: nil))
        store.markPatPromptShown(at: noon)

        let relaunched = HealthRecoveryPromptStore(defaults: defaults)
        #expect(!relaunched.patPromptAllowed(at: noon.addingTimeInterval(3600), onboardingCompletedAt: nil))
        #expect(relaunched.patPromptAllowed(at: noon.addingTimeInterval(86_400), onboardingCompletedAt: nil))
    }
}
