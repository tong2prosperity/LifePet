import Foundation
import Observation
import PiboCore

/// Decision 054 local-only memory for companion prompts.
///
/// Custom replies never leave this store: they are not logged, tracked,
/// synced or shown on the widget. Times are Unix seconds. Budget, expiry and
/// selection rules are all Core's; this type only records what happened.
@MainActor
@Observable
final class PiboCompanionStore {
    static let customOptionID = "custom"
    static let persistenceKey = "pibo.companion.state.v1"
    private static let maxAskHistory = 60
    private static let recentAnswerRateWindow = 10

    struct AnswerRecord: Codable, Equatable {
        var promptId: String
        var optionId: String
        var customText: String?
        var retention: Int32
        var answeredAt: Double
        var expiresAt: Double
    }

    struct AskRecord: Codable, Equatable {
        var promptId: String
        var askedAt: Double
        var answered: Bool
    }

    struct UsageRecord: Codable, Equatable {
        var key: String
        var count: Int
        var lastAt: Double
    }

    struct Snapshot: Codable, Equatable {
        var firstSeenAt: Double
        var lastVisibleAt: Double = 0
        var dayKey: Int
        var linesToday = 0
        var promptsToday = 0
        var consecutiveIgnored = 0
        var lastIgnoredAt: Double = 0
        var answeredTotal = 0
        var answers: [AnswerRecord] = []
        var asks: [AskRecord] = []
        var echoUsage: [UsageRecord] = []
        var topicUsage: [UsageRecord] = []
        var sceneUsage: [UsageRecord] = []
        var hideSeekDayKey = 0
        var hideSeekStartedAt: Double = 0
        var positiveAnswerAt: Double = 0
        var tiredAnswerAt: Double = 0
        var wakingFirstEpisode = ""

        init(now: Double) {
            firstSeenAt = now
            dayKey = PiboCompanionStore.localDayKey(now)
        }
    }

    private(set) var revision = 0
    private(set) var entryAt: Double = 0
    private(set) var entryID = ""
    private(set) var linesThisEntry = 0
    private(set) var absenceSecondsAtEntry: Double = 0
    private(set) var hasPreviousVisit = false
    private(set) var hideSeekFound = false
    private(set) var snapshot: Snapshot

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let clock: () -> Double

    init(
        defaults: UserDefaults = .standard,
        key: String = PiboCompanionStore.persistenceKey,
        clock: @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.defaults = defaults
        self.key = key
        self.clock = clock
        let now = clock()
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot(now: now)
        }
        pruneExpired(now)
    }

    func reset() {
        let now = clock()
        snapshot = Snapshot(now: now)
        beginEntry(now: now, measureAbsence: false)
        persist()
    }

    /// Starts a Home entry; absence is measured from the last time Home was visible.
    func beginEntry(now: Double, measureAbsence: Bool = true) {
        rollDay(now)
        let last = snapshot.lastVisibleAt
        hasPreviousVisit = measureAbsence && last > 0 && last <= now
        absenceSecondsAtEntry = hasPreviousVisit ? now - last : 0
        entryAt = now
        entryID = String(Int64(now * 1000))
        linesThisEntry = 0
        hideSeekFound = false
        snapshot.lastVisibleAt = now
        pruneExpired(now)
        persist()
    }

    /// DEBUG: pretend Home was last visible `seconds` ago, then re-enter. Every
    /// remembered time shifts back so echoes reach their delays.
    func debugSimulateAbsence(seconds: Double, now: Double) {
        let back = { (at: Double) in at > 0 ? at - seconds : at }
        snapshot.firstSeenAt = back(snapshot.firstSeenAt)
        snapshot.lastVisibleAt = now - seconds
        snapshot.lastIgnoredAt = back(snapshot.lastIgnoredAt)
        snapshot.positiveAnswerAt = back(snapshot.positiveAnswerAt)
        snapshot.tiredAnswerAt = back(snapshot.tiredAnswerAt)
        for index in snapshot.answers.indices { snapshot.answers[index].answeredAt = back(snapshot.answers[index].answeredAt) }
        for index in snapshot.asks.indices { snapshot.asks[index].askedAt = back(snapshot.asks[index].askedAt) }
        for index in snapshot.echoUsage.indices { snapshot.echoUsage[index].lastAt = back(snapshot.echoUsage[index].lastAt) }
        for index in snapshot.topicUsage.indices { snapshot.topicUsage[index].lastAt = back(snapshot.topicUsage[index].lastAt) }
        for index in snapshot.sceneUsage.indices { snapshot.sceneUsage[index].lastAt = back(snapshot.sceneUsage[index].lastAt) }
        if Self.localDayKey(now - seconds) != Self.localDayKey(now) { snapshot.dayKey = 0 }
        snapshot.hideSeekDayKey = 0
        beginEntry(now: now)
    }

    func markVisible(now: Double) {
        snapshot.lastVisibleAt = now
        persist()
    }

    var relationshipDays: Int { max(0, Self.localDaysBetween(snapshot.firstSeenAt, clock())) }
    var linesToday: Int { snapshot.dayKey == Self.localDayKey(clock()) ? snapshot.linesToday : 0 }
    var promptsToday: Int { snapshot.dayKey == Self.localDayKey(clock()) ? snapshot.promptsToday : 0 }
    var consecutiveIgnored: Int { snapshot.consecutiveIgnored }
    var answeredTotal: Int { snapshot.answeredTotal }
    var positiveAnswerAt: Double { snapshot.positiveAnswerAt }
    var tiredAnswerAt: Double { snapshot.tiredAnswerAt }
    var answers: [AnswerRecord] { snapshot.answers }

    func daysSinceLastIgnored(now: Double) -> Int? {
        snapshot.lastIgnoredAt > 0 ? max(0, Self.localDaysBetween(snapshot.lastIgnoredAt, now)) : nil
    }

    func recentAnswerRatePercent() -> Int? {
        let recent = snapshot.asks.suffix(Self.recentAnswerRateWindow)
        guard !recent.isEmpty else { return nil }
        let answered = recent.filter(\.answered).count
        return Int((Double(answered) * 100 / Double(recent.count)).rounded())
    }

    func lastAsked(_ promptId: String) -> Double? {
        snapshot.asks.last { $0.promptId == promptId }?.askedAt
    }

    func topicLastAt(_ topic: String) -> Double? {
        snapshot.topicUsage.first { $0.key == topic }?.lastAt
    }

    func echoUseCount(_ key: String) -> Int {
        snapshot.echoUsage.first { $0.key == key }?.count ?? 0
    }

    func sceneUseCount(_ key: String) -> Int {
        snapshot.sceneUsage.first { $0.key == key }?.count ?? 0
    }

    func answer(_ promptId: String) -> AnswerRecord? {
        snapshot.answers.first { $0.promptId == promptId }
    }

    func hideSeekUsedToday(now: Double) -> Bool {
        snapshot.hideSeekDayKey == Self.localDayKey(now) && snapshot.hideSeekStartedAt < entryAt
    }

    func markHideSeekStarted(now: Double) {
        if snapshot.hideSeekDayKey == Self.localDayKey(now), snapshot.hideSeekStartedAt >= entryAt { return }
        snapshot.hideSeekDayKey = Self.localDayKey(now)
        snapshot.hideSeekStartedAt = now
        persist()
    }

    func markHideSeekFound() {
        hideSeekFound = true
        revision += 1
    }

    func claimWakingFirst(episode: String) -> Bool {
        guard !episode.isEmpty, snapshot.wakingFirstEpisode != episode else { return false }
        snapshot.wakingFirstEpisode = episode
        persist()
        return true
    }

    func recordLineShown(now: Double, proactive: Bool, prompt: Bool, topic: String?) {
        rollDay(now)
        if proactive {
            linesThisEntry += 1
            snapshot.linesToday += 1
        }
        if prompt { snapshot.promptsToday += 1 }
        if let topic, !topic.isEmpty { Self.bump(&snapshot.topicUsage, topic, now) }
        persist()
    }

    func recordEchoUsed(_ key: String, now: Double) {
        Self.bump(&snapshot.echoUsage, key, now)
        persist()
    }

    func recordSceneUsed(_ key: String, now: Double) {
        Self.bump(&snapshot.sceneUsage, key, now)
        persist()
    }

    func recordIgnored(promptId: String, askedAt: Double, now: Double) {
        pushAsk(AskRecord(promptId: promptId, askedAt: askedAt, answered: false))
        snapshot.consecutiveIgnored += 1
        snapshot.lastIgnoredAt = now
        persist()
    }

    func recordAnswer(_ record: AnswerRecord, askedAt: Double, positive: Bool, tired: Bool) {
        pushAsk(AskRecord(promptId: record.promptId, askedAt: askedAt, answered: true))
        snapshot.answers.removeAll { $0.promptId == record.promptId }
        snapshot.answers.append(record)
        // Echo usage belongs to the previous answer of this prompt.
        snapshot.echoUsage.removeAll { $0.key.hasPrefix("\(record.promptId):") }
        snapshot.consecutiveIgnored = 0
        snapshot.answeredTotal += 1
        if positive { snapshot.positiveAnswerAt = record.answeredAt }
        if tired { snapshot.tiredAnswerAt = record.answeredAt }
        persist()
    }

    // MARK: Private

    private func pushAsk(_ record: AskRecord) {
        snapshot.asks.append(record)
        if snapshot.asks.count > Self.maxAskHistory {
            snapshot.asks = Array(snapshot.asks.suffix(Self.maxAskHistory))
        }
    }

    private func pruneExpired(_ now: Double) {
        let before = snapshot.answers.count
        snapshot.answers.removeAll { record in
            !(record.expiresAt.isFinite && record.expiresAt > now)
                || (record.optionId == Self.customOptionID && (record.customText ?? "").isEmpty)
                || !(PiboCoreCompanionRetention.today.rawValue...PiboCoreCompanionRetention.recent.rawValue)
                    .contains(record.retention)
        }
        if before != snapshot.answers.count { persist() }
    }

    private func rollDay(_ now: Double) {
        let key = Self.localDayKey(now)
        guard key != snapshot.dayKey else { return }
        snapshot.dayKey = key
        snapshot.linesToday = 0
        snapshot.promptsToday = 0
        persist()
    }

    private func persist() {
        revision += 1
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    private static func bump(_ records: inout [UsageRecord], _ key: String, _ now: Double) {
        if let index = records.firstIndex(where: { $0.key == key }) {
            records[index].count += 1
            records[index].lastAt = now
        } else {
            records.append(UsageRecord(key: key, count: 1, lastAt: now))
        }
    }

    nonisolated static func localDayKey(_ seconds: Double) -> Int {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: seconds))
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    nonisolated static func localMidnight(_ seconds: Double) -> Double {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: seconds)).timeIntervalSince1970
    }

    nonisolated static func localDaysBetween(_ earlier: Double, _ later: Double) -> Int {
        Int(((localMidnight(later) - localMidnight(earlier)) / 86_400).rounded())
    }
}
