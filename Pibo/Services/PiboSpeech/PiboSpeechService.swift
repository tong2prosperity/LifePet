import Foundation
import Observation
import PiboCore

@MainActor
protocol PiboSpeechProviding {
    func resolve(
        cues: [PiboSpeechCue],
        context: PiboSpeechContext
    ) -> PiboSpeech?
}

/// The app-wide speech black box. A caller supplies semantic cues plus its local
/// scene context and receives one authored line or silence.
@MainActor
@Observable
final class PiboSpeechService: PiboSpeechProviding {
    @ObservationIgnored private let catalog: PiboSpeechCatalog
    @ObservationIgnored private let policy: PiboSpeechPolicy
    @ObservationIgnored private let narrativeProgress: () -> Int
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let patSpeechRoll: () -> Double
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var history: PiboSpeechHistory
    @ObservationIgnored private var homeHistory: PiboHomeSpeechHistory

    init(
        defaults: UserDefaults = .standard,
        narrativeProgress: @escaping () -> Int = { 0 },
        now: @escaping () -> Date = Date.init,
        patSpeechRoll: @escaping () -> Double = { Double.random(in: 0..<1) },
        calendar: Calendar = .current
    ) {
        self.catalog = .bundled()
        self.policy = PiboSpeechPolicy()
        self.narrativeProgress = narrativeProgress
        self.now = now
        self.patSpeechRoll = patSpeechRoll
        self.calendar = calendar
        self.history = PiboSpeechHistory(defaults: defaults)
        self.homeHistory = PiboHomeSpeechHistory(defaults: defaults)
    }

    init(
        catalog: PiboSpeechCatalog,
        defaults: UserDefaults = .standard,
        narrativeProgress: @escaping () -> Int = { 0 },
        now: @escaping () -> Date = Date.init,
        patSpeechRoll: @escaping () -> Double = { Double.random(in: 0..<1) },
        calendar: Calendar = .current
    ) {
        self.catalog = catalog
        self.policy = PiboSpeechPolicy()
        self.narrativeProgress = narrativeProgress
        self.now = now
        self.patSpeechRoll = patSpeechRoll
        self.calendar = calendar
        self.history = PiboSpeechHistory(defaults: defaults)
        self.homeHistory = PiboHomeSpeechHistory(defaults: defaults)
    }

    func resolve(
        cues: [PiboSpeechCue],
        context: PiboSpeechContext
    ) -> PiboSpeech? {
        guard !cues.isEmpty else { return nil }
        let date = now()
        history.prepare(for: date, calendar: calendar)
        guard policy.canSpeak(in: context, history: history) else { return nil }

        for cue in cues.sorted(by: { $0.priority > $1.priority }) {
            let opportunity = opportunityKey(for: cue, context: context, date: date)
            let allEntries = catalog.entries(
                for: cue,
                context: context,
                storyProgress: narrativeProgress()
            )
            if let selectedID = history.selectedLineID(for: opportunity),
               let selected = allEntries.first(where: { $0.id == selectedID }) {
                // Persistent data cards need a stable line when SwiftUI
                // recomputes. Ephemeral home/game bubbles must not replay the
                // same opportunity every time a timer or lifecycle hook fires.
                switch context.surface {
                case .dashboard, .sleepCard, .walkCard:
                    return speech(from: selected, cue: cue)
                case .home, .game:
                    return nil
                }
            }

            let candidates = allEntries.filter { entry in
                history.allows(entry, topic: cue.topic, at: date)
            }
            let opportunityHash = coreOpportunityHash(for: cue, context: context, date: date)
            guard let selected = select(
                from: candidates,
                opportunityHash: opportunityHash,
                context: context,
                storyProgress: narrativeProgress()
            ) else { continue }

            history.record(
                selected,
                topic: cue.topic,
                opportunity: opportunity,
                scope: policy.scope(for: context),
                at: date
            )
            return speech(from: selected, cue: cue)
        }
        return nil
    }

    func resetHistory() {
        history.reset()
        homeHistory.reset()
    }

    func resolvePat(
        storyStage: PiboCoreStorySpeechStage,
        restingState: Bool,
        sleepingState: Bool,
        facts: PiboHomeSpeechFacts,
        neutralLegacyMode: Bool = false
    ) -> PiboHomePatResolution {
        let date = now()
        let counts = homeHistory.speechCounts(at: date)
        let decision = PiboCorePatAdapter.decideV2(
            spokenIn24Hours: counts.daily,
            spokenIn10Minutes: counts.recent,
            speechRoll: patSpeechRoll(),
            restingState: restingState
        )
        if sleepingState {
            return PiboHomePatResolution(
                speech: nil,
                shouldSpeak: true,
                countsTowardAngry: decision.countsTowardAngry
            )
        }
        if restingState {
            if decision.speaks {
                homeHistory.record(key: .waking04, at: date, consumesPatBudget: true)
            }
            return PiboHomePatResolution(
                speech: nil,
                shouldSpeak: decision.speaks,
                countsTowardAngry: decision.countsTowardAngry
            )
        }
        guard decision.speaks else {
            return PiboHomePatResolution(
                speech: nil,
                shouldSpeak: false,
                countsTowardAngry: decision.countsTowardAngry
            )
        }
        let key = selectHomeKey(
            context: neutralLegacyMode ? .patGarbled : .pat,
            storyStage: storyStage,
            facts: facts,
            values: [:],
            at: date
        )
        guard let key, let speech = homeSpeech(key: key, values: [:]) else {
            return PiboHomePatResolution(
                speech: nil,
                shouldSpeak: false,
                countsTowardAngry: decision.countsTowardAngry
            )
        }
        homeHistory.record(key: key, at: date, consumesPatBudget: true)
        return PiboHomePatResolution(
            speech: speech,
            shouldSpeak: true,
            countsTowardAngry: decision.countsTowardAngry
        )
    }

    func resolveIdle(
        context: PiboCoreHomeSpeechContext,
        storyStage: PiboCoreStorySpeechStage,
        facts: PiboHomeSpeechFacts,
        values: [String: String]
    ) -> PiboSpeech? {
        guard PiboCorePatAdapter.shouldIdleMutter(roll: Double.random(in: 0..<1)) else {
            return nil
        }
        let date = now()
        guard let key = selectHomeKey(
            context: context,
            storyStage: storyStage,
            facts: facts,
            values: values,
            at: date
        ), let speech = homeSpeech(key: key, values: values, presentation: .murmur) else {
            return nil
        }
        homeHistory.record(key: key, at: date, consumesPatBudget: false)
        return speech
    }

    func fixedHomeSpeech(
        key: PiboCoreHomeContentKey,
        values: [String: String] = [:],
        presentation: PiboSpeechPresentation = .normal
    ) -> PiboSpeech? {
        homeSpeech(key: key, values: values, presentation: presentation)
    }

    private func speech(from entry: PiboSpeechEntry, cue: PiboSpeechCue) -> PiboSpeech {
        var text = entry.text
        for (name, value) in cue.values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return PiboSpeech(
            id: entry.id,
            text: AppLocalization.text(text),
            presentation: entry.presentation,
            cueKey: cue.key
        )
    }

    private func select(
        from entries: [PiboSpeechEntry],
        opportunityHash: UInt64,
        context: PiboSpeechContext,
        storyProgress: Int
    ) -> PiboSpeechEntry? {
        guard !entries.isEmpty else { return nil }
        let candidates = entries.map { entry in
            PiboCoreSpeechCandidate(
                surfaceMask: coreSurface(context.surface).mask,
                length: coreLength(entry.length.value),
                minimumStoryProgress: entry.minimumStoryProgress,
                weight: entry.weight
            )
        }
        guard let index = PiboCoreSpeechPolicy.selectedCandidateIndex(
            opportunityHash: opportunityHash,
            candidates: candidates,
            surface: coreSurface(context.surface),
            maximumLength: coreLength(context.length),
            storyProgress: storyProgress
        ), entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    private func opportunityKey(
        for cue: PiboSpeechCue,
        context: PiboSpeechContext,
        date: Date
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        let values = cue.values
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(day)|\(context.surface.rawValue)|\(context.trigger.rawValue)|\(cue.key)|\(values)"
    }

    private func coreOpportunityHash(
        for cue: PiboSpeechCue,
        context: PiboSpeechContext,
        date: Date
    ) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return PiboCoreSpeechPolicy.opportunityHash(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0,
            surface: coreSurface(context.surface),
            trigger: coreTrigger(context.trigger),
            cue: cue.key,
            values: cue.values
        )
    }

    private func selectHomeKey(
        context: PiboCoreHomeSpeechContext,
        storyStage: PiboCoreStorySpeechStage,
        facts: PiboHomeSpeechFacts,
        values: [String: String],
        at date: Date
    ) -> PiboCoreHomeContentKey? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let seed = PiboCoreSpeechPolicy.opportunityHash(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0,
            surface: .home,
            trigger: (context == .pat || context == .patGarbled) ? .userAction : .idle,
            cue: "home.\(context.rawValue).\(Int(date.timeIntervalSince1970 * 1_000))",
            values: values
        )
        return PiboCoreHomeSpeech.selectContentKey(
            context: context,
            storyStage: storyStage,
            seed: seed,
            excludedKeys: homeHistory.excludedContentKeys(at: date),
            facts: facts.core
        )
    }

    private func homeSpeech(
        key: PiboCoreHomeContentKey,
        values: [String: String],
        presentation: PiboSpeechPresentation = .normal
    ) -> PiboSpeech? {
        guard key != .none, !key.localizationKey.isEmpty else { return nil }
        var text = AppLocalization.narrative(key.localizationKey)
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        guard !text.contains("{") else { return nil }
        return PiboSpeech(
            id: key.localizationKey,
            text: text,
            presentation: presentation,
            cueKey: key.localizationKey
        )
    }

    private func coreSurface(_ surface: PiboSpeechSurface) -> PiboCoreSpeechSurface {
        switch surface {
        case .home: .home
        case .dashboard: .dashboard
        case .sleepCard: .sleepCard
        case .walkCard: .walkCard
        case .game: .game
        }
    }

    private func coreTrigger(_ trigger: PiboSpeechTrigger) -> PiboCoreSpeechTrigger {
        switch trigger {
        case .entered: .entered
        case .expanded: .expanded
        case .completed: .completed
        case .idle: .idle
        case .environmentChanged: .environmentChanged
        case .userAction: .userAction
        }
    }

    private func coreLength(_ length: PiboSpeechLength) -> PiboCoreSpeechLength {
        switch length {
        case .tiny: .tiny
        case .short: .short
        case .medium: .medium
        }
    }
}
