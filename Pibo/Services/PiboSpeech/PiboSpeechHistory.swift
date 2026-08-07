import Foundation

/// The small amount of persistence needed to make speech scarce and stable.
/// This is deliberately not a second Pibo mood or relationship state.
struct PiboSpeechHistory {
    private struct Usage: Codable {
        var count: Int
        var lastSpokenAt: Date
    }

    private struct State: Codable {
        var dayKey: String = ""
        var scopeCounts: [String: Int] = [:]
        var lineUsage: [String: Usage] = [:]
        var topicLastSpokenAt: [String: Date] = [:]
        var selectedLineByOpportunity: [String: String] = [:]
    }

    private let defaults: UserDefaults
    private let persistenceKey: String
    private var state: State

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.piboSpeechHistory
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    mutating func prepare(for date: Date, calendar: Calendar) {
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        guard dayKey != state.dayKey else { return }
        state.dayKey = dayKey
        state.scopeCounts.removeAll(keepingCapacity: true)
        state.selectedLineByOpportunity.removeAll(keepingCapacity: true)
        persist()
    }

    func count(for scope: String) -> Int {
        state.scopeCounts[scope, default: 0]
    }

    func selectedLineID(for opportunity: String) -> String? {
        state.selectedLineByOpportunity[opportunity]
    }

    func allows(_ entry: PiboSpeechEntry, topic: String, at date: Date) -> Bool {
        if let maximumUses = entry.maximumUses,
           state.lineUsage[entry.id, default: Usage(count: 0, lastSpokenAt: .distantPast)].count
            >= maximumUses {
            return false
        }
        if entry.cooldownHours > 0,
           let usage = state.lineUsage[entry.id],
           Self.isWithinCooldown(
            since: usage.lastSpokenAt,
            at: date,
            duration: entry.cooldownHours * 3_600
           ) {
            return false
        }
        if entry.topicCooldownHours > 0,
           let lastSpokenAt = state.topicLastSpokenAt[topic],
           Self.isWithinCooldown(
            since: lastSpokenAt,
            at: date,
            duration: entry.topicCooldownHours * 3_600
           ) {
            return false
        }
        return true
    }

    mutating func record(
        _ entry: PiboSpeechEntry,
        topic: String,
        opportunity: String,
        scope: String,
        at date: Date
    ) {
        var usage = state.lineUsage[entry.id] ?? Usage(count: 0, lastSpokenAt: date)
        usage.count += 1
        usage.lastSpokenAt = date
        state.lineUsage[entry.id] = usage
        state.topicLastSpokenAt[topic] = date
        state.selectedLineByOpportunity[opportunity] = entry.id
        state.scopeCounts[scope, default: 0] += 1
        persist()
    }

    mutating func reset() {
        state = State()
        defaults.removeObject(forKey: persistenceKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    /// A wall-clock rollback or damaged future timestamp must not silence a
    /// line until the clock catches up. Lifetime use counts remain intact; only
    /// the time-based cooldown is ignored when its timestamp is in the future.
    private static func isWithinCooldown(
        since lastDate: Date,
        at date: Date,
        duration: TimeInterval
    ) -> Bool {
        let elapsed = date.timeIntervalSince(lastDate)
        return elapsed.isFinite && elapsed >= 0 && elapsed < duration
    }
}
