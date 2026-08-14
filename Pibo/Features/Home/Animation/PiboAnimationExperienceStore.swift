import Foundation
import Observation

enum PiboAnimationAchievementKind: String, Codable, Sendable {
    case pigu
    case muscle

}

struct PiboAnimationAchievementPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: PiboAnimationAchievementKind
    let occurredAt: Date
    let workoutLabel: String?
    let workoutDurationMinutes: Int?

    var stateID: String { PiboAnimationResourceID.achievement(kind) }
}

/// App-owned persistence and lifecycle around Core's deterministic animation
/// policy. It stores facts (pending achievement, actual pats and expiry), never
/// thresholds or selection rules.
@MainActor
@Observable
final class PiboAnimationExperienceStore {
    private(set) var pendingAchievement: PiboAnimationAchievementPayload?
    private(set) var angryUntil: Date?
    private(set) var actualPatTimes: [Date] = []
    private(set) var notificationPresentationRequestID: UUID?

    private let defaults: UserDefaults
    private let calendar: Calendar

    private static let pendingKey = "pibo.animation.pending-achievement.v1"
    private static let legacyHeldKey = "pibo.animation.held-achievement.v1"
    private static let legacyHeldUntilKey = "pibo.animation.held-until.v1"
    private static let angryUntilKey = "pibo.animation.angry-until.v1"
    private static let patTimesKey = "pibo.animation.actual-pats.v1"
    private static let handledStepsDayKey = "pibo.animation.steps-handled-day.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
        restore(now: .now)
    }

    var angryActive: Bool {
        angryActive(at: .now)
    }

    func angryActive(at date: Date) -> Bool {
        angryUntil.map { $0 > date } ?? false
    }

    func queueWorkout(_ workout: PendingWorkout) {
        if let pendingAchievement,
           pendingAchievement.kind == .pigu,
           pendingAchievement.occurredAt >= workout.endedAt {
            return
        }
        queue(
            PiboAnimationAchievementPayload(
                id: workout.id,
                kind: .pigu,
                occurredAt: workout.endedAt,
                workoutLabel: workout.label,
                workoutDurationMinutes: workout.durationMin
            )
        )
    }

    func requestNotificationPresentation() {
        notificationPresentationRequestID = UUID()
    }

    @discardableResult
    func queueStepsAchievement(at date: Date = .now) -> Bool {
        guard calendar.isDateInToday(date), !stepsAchievementHandled(on: date) else {
            return false
        }
        defaults.set(calendar.startOfDay(for: date).timeIntervalSince1970,
                     forKey: Self.handledStepsDayKey)
        queue(
            PiboAnimationAchievementPayload(
                id: UUID(),
                kind: .muscle,
                occurredAt: date,
                workoutLabel: nil,
                workoutDurationMinutes: nil
            )
        )
        return true
    }

    private func queue(_ payload: PiboAnimationAchievementPayload) {
        guard calendar.isDateInToday(payload.occurredAt) else { return }
        pendingAchievement = payload
        persistPending()
    }

    @discardableResult
    func confirmPending(now: Date = .now) -> PiboAnimationAchievementPayload? {
        guard let payload = pendingAchievement else { return nil }
        pendingAchievement = nil
        notificationPresentationRequestID = nil
        defaults.removeObject(forKey: Self.pendingKey)
        return payload
    }

    /// Returns true only for the pat that enters angry.
    func registerActualPat(
        localHour: Double,
        countsTowardAngry: Bool = true,
        now: Date = .now
    ) -> Bool {
        refreshExpiries(now: now)
        guard countsTowardAngry, !angryActive(at: now) else { return false }
        let window = PiboCorePatAdapter.recentWindowSeconds
        actualPatTimes = actualPatTimes.filter {
            let age = now.timeIntervalSince($0)
            return age.isFinite && age >= 0 && age < window
        }
        actualPatTimes.append(now)
        let shouldStart = PiboCoreAnimationAdapter.angryShouldStart(
            state: .stable,
            recentActualPatCount: actualPatTimes.count,
            angryActive: false
        )
        if shouldStart {
            angryUntil = now.addingTimeInterval(window)
            actualPatTimes.removeAll()
        }
        persistInteractionState()
        return shouldStart
    }

    func refreshExpiries(now: Date = .now) {
        if let angryUntil {
            let remaining = angryUntil.timeIntervalSince(now)
            if !remaining.isFinite || remaining <= 0
                || remaining > PiboCorePatAdapter.recentWindowSeconds {
                self.angryUntil = nil
                actualPatTimes.removeAll()
                persistInteractionState()
            }
        }
        if let pendingAchievement, !calendar.isDate(pendingAchievement.occurredAt, inSameDayAs: now) {
            self.pendingAchievement = nil
            defaults.removeObject(forKey: Self.pendingKey)
        }
    }

    private func stepsAchievementHandled(on date: Date) -> Bool {
        guard defaults.object(forKey: Self.handledStepsDayKey) != nil else { return false }
        let handled = Date(timeIntervalSince1970: defaults.double(forKey: Self.handledStepsDayKey))
        return calendar.isDate(handled, inSameDayAs: date)
    }

    private func restore(now: Date) {
        if let data = defaults.data(forKey: Self.pendingKey),
           let value = try? JSONDecoder().decode(PiboAnimationAchievementPayload.self, from: data),
           calendar.isDate(value.occurredAt, inSameDayAs: now) {
            pendingAchievement = value
        }
        defaults.removeObject(forKey: Self.legacyHeldKey)
        defaults.removeObject(forKey: Self.legacyHeldUntilKey)
        let angryDate = Date(timeIntervalSince1970: defaults.double(forKey: Self.angryUntilKey))
        let angryRemaining = angryDate.timeIntervalSince(now)
        if angryRemaining.isFinite, angryRemaining > 0,
           angryRemaining <= PiboCorePatAdapter.recentWindowSeconds {
            angryUntil = angryDate
        } else {
            defaults.removeObject(forKey: Self.angryUntilKey)
        }
        if let data = defaults.data(forKey: Self.patTimesKey),
           let values = try? JSONDecoder().decode([Date].self, from: data) {
            actualPatTimes = values.filter {
                let age = now.timeIntervalSince($0)
                return age.isFinite && age >= 0
                    && age < PiboCorePatAdapter.recentWindowSeconds
            }
            if actualPatTimes.count != values.count { persistInteractionState() }
        }
    }

    private func persistPending() {
        if let pendingAchievement, let data = try? JSONEncoder().encode(pendingAchievement) {
            defaults.set(data, forKey: Self.pendingKey)
        }
    }

    private func persistInteractionState() {
        if let angryUntil {
            defaults.set(angryUntil.timeIntervalSince1970, forKey: Self.angryUntilKey)
        } else {
            defaults.removeObject(forKey: Self.angryUntilKey)
        }
        if let data = try? JSONEncoder().encode(actualPatTimes) {
            defaults.set(data, forKey: Self.patTimesKey)
        }
    }
}
