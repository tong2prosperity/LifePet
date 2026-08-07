import Foundation
import PiboCore

struct PiboHomePatResolution: Equatable {
    let speech: PiboSpeech?
    let shouldSpeak: Bool
    let countsTowardAngry: Bool
}

struct PiboHomeSpeechFacts {
    var hasSteps = false
    var hasSleepDuration = false
    var hasWorkoutType = false
    var pendingBoCount = 0
    var connectionAccepted = false

    var core: PiboCoreHomeSpeechFacts {
        PiboCoreHomeSpeechFacts(
            hasSteps: hasSteps,
            hasSleepDuration: hasSleepDuration,
            hasWorkoutType: hasWorkoutType,
            pendingBoCount: pendingBoCount,
            connectionAccepted: connectionAccepted
        )
    }
}

struct PiboHomeSpeechHistory {
    private struct State: Codable {
        var patSpeechTimes: [Date] = []
        var contentLastShownAt: [Int32: Date] = [:]
    }

    private let defaults: UserDefaults
    private let persistenceKey: String
    private var state: State

    init(
        defaults: UserDefaults,
        persistenceKey: String = PiboPersistenceKeys.Defaults.homeSpeechHistory
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let data = defaults.data(forKey: persistenceKey),
           let restored = try? JSONDecoder().decode(State.self, from: data) {
            state = restored
        } else {
            state = State()
        }
    }

    mutating func speechCounts(at date: Date) -> (daily: Int, recent: Int) {
        prune(at: date)
        let recent = state.patSpeechTimes.filter {
            let age = date.timeIntervalSince($0)
            return age.isFinite && age >= 0
                && age < PiboCorePatAdapter.recentWindowSeconds
        }.count
        return (state.patSpeechTimes.count, recent)
    }

    mutating func excludedContentKeys(at date: Date) -> [PiboCoreHomeContentKey] {
        prune(at: date)
        return state.contentLastShownAt.compactMap { raw, shownAt in
            let age = date.timeIntervalSince(shownAt)
            guard age.isFinite, age >= 0,
                  age < PiboCorePatAdapter.dailyWindowSeconds else {
                return nil
            }
            return PiboCoreHomeContentKey(rawValue: raw)
        }
    }

    mutating func record(
        key: PiboCoreHomeContentKey,
        at date: Date,
        consumesPatBudget: Bool
    ) {
        guard key != .none, date.timeIntervalSince1970.isFinite else { return }
        state.contentLastShownAt[key.rawValue] = date
        if consumesPatBudget { state.patSpeechTimes.append(date) }
        persist()
    }

    mutating func reset() {
        state = State()
        defaults.removeObject(forKey: persistenceKey)
    }

    private mutating func prune(at date: Date) {
        let dailyWindow = PiboCorePatAdapter.dailyWindowSeconds
        let speechCount = state.patSpeechTimes.count
        let contentCount = state.contentLastShownAt.count
        state.patSpeechTimes.removeAll {
            let age = date.timeIntervalSince($0)
            return !age.isFinite || age < 0 || age >= dailyWindow
        }
        state.contentLastShownAt = state.contentLastShownAt.filter {
            let age = date.timeIntervalSince($0.value)
            return age.isFinite && age >= 0 && age < dailyWindow
        }
        if state.patSpeechTimes.count != speechCount
            || state.contentLastShownAt.count != contentCount {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: persistenceKey)
    }
}

extension PiboCoreHomeContentKey {
    var localizationKey: String {
        switch self {
        case .none: ""
        case .tap01: "home.tap.01"
        case .tap02: "home.tap.02"
        case .tap03: "home.tap.03"
        case .tap04: "home.tap.04"
        case .tap05: "home.tap.05"
        case .tap06: "home.tap.06"
        case .tap07: "home.tap.07"
        case .tap08: "home.tap.08"
        case .tap09: "home.tap.09"
        case .tap10: "home.tap.10"
        case .gar01: "home.garbled.01"
        case .gar02: "home.garbled.02"
        case .gar03: "home.garbled.03"
        case .gar04: "home.garbled.04"
        case .waking01: "home.waking.01"
        case .waking02: "home.waking.02"
        case .waking03: "home.waking.03"
        case .waking04: "home.waking.04"
        case .wakingTired01: "home.wakingTired.01"
        case .wakingTired02: "home.wakingTired.02"
        case .idle01: "home.idle.01"
        case .idle02: "home.idle.02"
        case .idle03: "home.idle.03"
        case .idle04: "home.idle.04"
        case .idle05: "home.idle.05"
        case .idle06: "home.idle.06"
        case .lowSleep01: "home.lowSleep.01"
        case .lowSleep02: "home.lowSleep.02"
        case .lowActivity01: "home.lowActivity.01"
        case .lowActivity02: "home.lowActivity.02"
        case .lowBoth01: "home.lowBoth.01"
        case .lowBoth02: "home.lowBoth.02"
        case .coolhide01: "home.coolhide.01"
        case .coolhide02: "home.coolhide.02"
        case .dive01: "home.dive.01"
        case .dive02: "home.dive.02"
        case .missingSystem01: "home.missing.system.01"
        case .missingSystem02: "home.missing.system.02"
        case .missingPibo01: "home.missing.pibo.01"
        case .missingPibo02: "home.missing.pibo.02"
        case .boFirstRipe: "home.bo.firstRipe"
        case .boFirstPluckPrompt: "home.bo.firstPluckPrompt"
        case .boRipe: "home.bo.ripe"
        case .boCollectedSystem: "home.bo.collected"
        case .boSlow: "home.bo.slow"
        @unknown default: ""
        }
    }
}
