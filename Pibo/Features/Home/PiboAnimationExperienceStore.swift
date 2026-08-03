import Foundation
import Observation

enum PiboAnimationAchievementKind: String, Codable, Sendable {
    case pigu
    case muscle

    /// 成果姿势会不会留在主场景。
    ///
    /// 运动完成的 `pigu` 只在成果卡片里演一次，确认后首页直接切回健康状态 ——
    /// 那个姿势不是一种「今天的状态」，把它挂一整天会盖掉真正在变化的东西。
    /// 万步的 `muscle` 仍然保持到 22:00。
    var holdsOnHome: Bool { self == .muscle }
}

struct PiboAnimationAchievementPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: PiboAnimationAchievementKind
    let occurredAt: Date
    let workoutLabel: String?
    let workoutDurationMinutes: Int?

    var stateID: String { kind.rawValue }
}

/// App-owned persistence and lifecycle around Core's deterministic animation
/// policy. It stores facts (pending achievement, actual pats and expiry), never
/// thresholds or selection rules.
@MainActor
@Observable
final class PiboAnimationExperienceStore {
    private(set) var pendingAchievement: PiboAnimationAchievementPayload?
    private(set) var heldAchievement: PiboAnimationAchievementKind?
    private(set) var angryUntil: Date?
    private(set) var actualPatTimes: [Date] = []
    private(set) var notificationPresentationRequestID: UUID?
    var previousStressStateID = "default" {
        didSet {
            guard previousStressStateID != oldValue else { return }
            defaults.set(previousStressStateID, forKey: Self.previousStressStateKey)
        }
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    private static let pendingKey = "pibo.animation.pending-achievement.v1"
    private static let heldKey = "pibo.animation.held-achievement.v1"
    private static let heldUntilKey = "pibo.animation.held-until.v1"
    private static let angryUntilKey = "pibo.animation.angry-until.v1"
    private static let patTimesKey = "pibo.animation.actual-pats.v1"
    private static let handledStepsDayKey = "pibo.animation.steps-handled-day.v1"
    private static let previousStressStateKey = "pibo.animation.previous-stress-state.v1"

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
        guard payload.kind.holdsOnHome else {
            clearHold()
            return payload
        }
        heldAchievement = payload.kind
        let start = calendar.startOfDay(for: now)
        let holdUntil = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: start) ?? now
        if holdUntil > now {
            defaults.set(payload.kind.rawValue, forKey: Self.heldKey)
            defaults.set(holdUntil.timeIntervalSince1970, forKey: Self.heldUntilKey)
        } else {
            clearHold()
        }
        return payload
    }

    /// Returns true only for the pat that enters angry.
    func registerActualPat(localHour: Double, now: Date = .now) -> Bool {
        refreshExpiries(now: now)
        guard !angryActive(at: now) else { return false }
        let cutoff = now.addingTimeInterval(-600)
        actualPatTimes = actualPatTimes.filter { $0 > cutoff }
        actualPatTimes.append(now)
        let shouldStart = PiboCoreAnimationAdapter.angryShouldStart(
            localHour: localHour,
            recentActualPatCount: actualPatTimes.count,
            angryActive: false
        )
        if shouldStart {
            angryUntil = now.addingTimeInterval(600)
            actualPatTimes.removeAll()
        }
        persistInteractionState()
        return shouldStart
    }

    func refreshExpiries(now: Date = .now) {
        if let angryUntil, angryUntil <= now {
            self.angryUntil = nil
            actualPatTimes.removeAll()
            persistInteractionState()
        }
        let heldUntil = Date(timeIntervalSince1970: defaults.double(forKey: Self.heldUntilKey))
        if heldAchievement != nil, heldUntil <= now { clearHold() }
        if let pendingAchievement, !calendar.isDate(pendingAchievement.occurredAt, inSameDayAs: now) {
            self.pendingAchievement = nil
            defaults.removeObject(forKey: Self.pendingKey)
        }
    }

    private func clearHold() {
        heldAchievement = nil
        defaults.removeObject(forKey: Self.heldKey)
        defaults.removeObject(forKey: Self.heldUntilKey)
    }

    private func stepsAchievementHandled(on date: Date) -> Bool {
        guard defaults.object(forKey: Self.handledStepsDayKey) != nil else { return false }
        let handled = Date(timeIntervalSince1970: defaults.double(forKey: Self.handledStepsDayKey))
        return calendar.isDate(handled, inSameDayAs: date)
    }

    private func restore(now: Date) {
        if let restoredStress = defaults.string(forKey: Self.previousStressStateKey),
           ["default", "dive", "coolhide"].contains(restoredStress) {
            previousStressStateID = restoredStress
        }
        if let data = defaults.data(forKey: Self.pendingKey),
           let value = try? JSONDecoder().decode(PiboAnimationAchievementPayload.self, from: data),
           calendar.isDate(value.occurredAt, inSameDayAs: now) {
            pendingAchievement = value
        }
        let heldUntil = Date(timeIntervalSince1970: defaults.double(forKey: Self.heldUntilKey))
        if heldUntil > now,
           let raw = defaults.string(forKey: Self.heldKey),
           let kind = PiboAnimationAchievementKind(rawValue: raw),
           kind.holdsOnHome {
            heldAchievement = kind
        }
        let angryDate = Date(timeIntervalSince1970: defaults.double(forKey: Self.angryUntilKey))
        if angryDate > now { angryUntil = angryDate }
        if let data = defaults.data(forKey: Self.patTimesKey),
           let values = try? JSONDecoder().decode([Date].self, from: data) {
            actualPatTimes = values.filter { now.timeIntervalSince($0) < 600 }
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
