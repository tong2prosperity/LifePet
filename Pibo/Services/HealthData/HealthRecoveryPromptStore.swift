import Foundation

/// When a pat may open the health help sheet on its own (2026-09-28, mirrors
/// HarmonyOS `HealthRecoveryPromptStore`). Every `dataUnknown` pat record
/// carries `checkConnection`, so without a limit someone who chose 「暂不连接」
/// was asked for access on almost every touch. Help the person opens
/// (Settings, the observer, the interruption banner) is never limited.
nonisolated enum HealthRecoveryPromptPolicy {
    /// Local calendar day, the same boundary as every other per-day surface.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    /// At most once per local day, and never on the day onboarding finished.
    /// An unknown completion time counts as an earlier day.
    static func patPromptAllowed(
        now: Date,
        lastPromptDay: String?,
        onboardingCompletedAt: Date?,
        allowAuthorizationOnboardingDay: Bool = false,
        calendar: Calendar = .current
    ) -> Bool {
        let today = dayKey(now, calendar: calendar)
        if lastPromptDay == today { return false }
        if !allowAuthorizationOnboardingDay, let onboardingCompletedAt,
           dayKey(onboardingCompletedAt, calendar: calendar) == today {
            return false
        }
        return true
    }
}

/// Remembers the local day a pat last opened the health help sheet. Only a
/// sheet that actually appeared uses up the day.
struct HealthRecoveryPromptStore {
    var defaults: UserDefaults = .standard

    var lastPatPromptDay: String? {
        defaults.string(forKey: PiboPersistenceKeys.Defaults.healthRecoveryPatPromptDay)
    }

    func patPromptAllowed(at now: Date = .now, onboardingCompletedAt: Date?,
                          allowAuthorizationOnboardingDay: Bool = false) -> Bool {
        HealthRecoveryPromptPolicy.patPromptAllowed(
            now: now,
            lastPromptDay: lastPatPromptDay,
            onboardingCompletedAt: onboardingCompletedAt,
            allowAuthorizationOnboardingDay: allowAuthorizationOnboardingDay
        )
    }

    func markPatPromptShown(at date: Date = .now) {
        defaults.set(
            HealthRecoveryPromptPolicy.dayKey(date),
            forKey: PiboPersistenceKeys.Defaults.healthRecoveryPatPromptDay
        )
    }
}
