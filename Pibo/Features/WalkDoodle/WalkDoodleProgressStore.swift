import Foundation
import Observation
import PiboCore
import os

struct WalkDoodleDayProgress: Codable, Equatable, Sendable {
    let dayKey: Int64
    private var shapeRawValue: Int32
    var bestScore: Int
    var rewardedEnergy: Double
    var accepted: Bool
    var attemptCount: Int

    var shape: PiboCoreWalkDoodleShape {
        get { PiboCoreWalkDoodleShape(rawValue: shapeRawValue) ?? .circle }
        set { shapeRawValue = newValue.rawValue }
    }

    init(
        dayKey: Int64,
        shape: PiboCoreWalkDoodleShape,
        bestScore: Int = 0,
        rewardedEnergy: Double = 0,
        accepted: Bool = false,
        attemptCount: Int = 0
    ) {
        self.dayKey = dayKey
        shapeRawValue = shape.rawValue
        self.bestScore = min(100, max(0, bestScore))
        self.rewardedEnergy = rewardedEnergy.isFinite ? max(0, rewardedEnergy) : 0
        self.accepted = accepted
        self.attemptCount = max(0, attemptCount)
    }
}

struct WalkDoodlePendingReward: Codable, Equatable, Sendable {
    let eventID: String
    let energy: Double
}

struct WalkDoodleProgressCommit: Equatable, Sendable {
    let eventID: String
    let day: WalkDoodleDayProgress
    let firstAcceptance: Bool
}

private struct WalkDoodleProgressSnapshot: Codable {
    var scoringVersion: UInt32
    var rewardVersion: UInt32
    var acceptedTaskCount: Int
    var days: [WalkDoodleDayProgress]
    var pendingRewards: [WalkDoodlePendingReward]
}

/// Persistent daily task assignment, best score and crash-safe reward outbox.
/// Shape, score and reward policy all remain in Core; this store only owns
/// device-local progression and exactly-once delivery to the `bo` ledger.
@MainActor
@Observable
final class WalkDoodleProgressStore {
    private(set) var acceptedTaskCount: Int = 0
    private(set) var days: [WalkDoodleDayProgress] = []
    private(set) var rewardOutbox: [WalkDoodlePendingReward] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = "pibo.walk-doodle.progress.v1"
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore()
        prune(currentDayKey: Self.dayKey())
        persist()
    }

    func task(at date: Date = .now) -> WalkDoodleDayProgress {
        let key = Self.dayKey(date)
        if let existing = days.first(where: { $0.dayKey == key }) {
            return existing
        }
        return WalkDoodleDayProgress(
            dayKey: key,
            shape: PiboCoreDoodleAdapter.shape(
                dayKey: key,
                acceptedTaskCount: acceptedTaskCount
            )
        )
    }

    func commit(
        shape: PiboCoreWalkDoodleShape,
        evaluation: PiboCoreDoodleAdapter.Evaluation,
        at date: Date = .now
    ) -> WalkDoodleProgressCommit {
        var current = task(at: date)
        let firstAcceptance = evaluation.score.isCompleted && !current.accepted
        current.shape = shape
        current.attemptCount += 1
        current.bestScore = max(current.bestScore, evaluation.reward.newBestScore)
        current.rewardedEnergy = max(
            current.rewardedEnergy,
            evaluation.reward.newDailyRewardedEnergy
        )
        current.accepted = current.accepted || evaluation.score.isCompleted
        if firstAcceptance { acceptedTaskCount += 1 }

        let eventID: String
        if evaluation.reward.grantedEnergy > 0 {
            eventID = "walk-doodle:\(PiboCoreDoodleAdapter.rewardVersion):\(current.dayKey):\(Int((current.rewardedEnergy * 1_000).rounded()))"
            if !rewardOutbox.contains(where: { $0.eventID == eventID }) {
                rewardOutbox.append(.init(
                    eventID: eventID,
                    energy: evaluation.reward.grantedEnergy
                ))
                rewardOutbox = Array(rewardOutbox.suffix(16))
            }
        } else {
            eventID = ""
        }

        days.removeAll { $0.dayKey == current.dayKey }
        days.append(current)
        prune(currentDayKey: current.dayKey)
        persist()
        return WalkDoodleProgressCommit(
            eventID: eventID,
            day: current,
            firstAcceptance: firstAcceptance
        )
    }

    func acknowledgeReward(eventID: String) {
        let priorCount = rewardOutbox.count
        rewardOutbox.removeAll { $0.eventID == eventID }
        guard rewardOutbox.count != priorCount else { return }
        persist()
    }

    func reset() {
        acceptedTaskCount = 0
        days = []
        rewardOutbox = []
        persist()
    }

    static func dayKey(_ date: Date = .now, calendar: Calendar = .current) -> Int64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let civilDate = utc.date(from: components) ?? Date(timeIntervalSince1970: 0)
        return Int64((civilDate.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    private func restore() {
        guard let data = defaults.data(forKey: persistenceKey),
              let snapshot = try? JSONDecoder().decode(
                  WalkDoodleProgressSnapshot.self,
                  from: data
              )
        else { return }
        acceptedTaskCount = max(0, snapshot.acceptedTaskCount)
        days = snapshot.days.compactMap(Self.normalizedDay)
        rewardOutbox = Array(snapshot.pendingRewards.filter {
            $0.eventID.hasPrefix("walk-doodle:")
                && $0.energy.isFinite
                && $0.energy > 0
        }.suffix(16))
        if snapshot.scoringVersion != PiboCoreDoodleAdapter.scoringVersion
            || snapshot.rewardVersion != PiboCoreDoodleAdapter.rewardVersion {
            LPLog.walkDoodle.notice(
                "walk doodle policy \(snapshot.scoringVersion, privacy: .public)/\(snapshot.rewardVersion, privacy: .public)→\(PiboCoreDoodleAdapter.scoringVersion, privacy: .public)/\(PiboCoreDoodleAdapter.rewardVersion, privacy: .public); history kept"
            )
        }
    }

    private static func normalizedDay(_ value: WalkDoodleDayProgress) -> WalkDoodleDayProgress? {
        guard PiboCoreWalkDoodleShape(rawValue: value.shape.rawValue) != nil else { return nil }
        return WalkDoodleDayProgress(
            dayKey: value.dayKey,
            shape: value.shape,
            bestScore: value.bestScore,
            rewardedEnergy: value.rewardedEnergy,
            accepted: value.accepted,
            attemptCount: value.attemptCount
        )
    }

    private func prune(currentDayKey: Int64) {
        days = days
            .filter { $0.dayKey >= currentDayKey - 90 }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private func persist() {
        let snapshot = WalkDoodleProgressSnapshot(
            scoringVersion: PiboCoreDoodleAdapter.scoringVersion,
            rewardVersion: PiboCoreDoodleAdapter.rewardVersion,
            acceptedTaskCount: acceptedTaskCount,
            days: days,
            pendingRewards: rewardOutbox
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: persistenceKey)
    }
}
