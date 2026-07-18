import Foundation
import Observation

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
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var history: PiboSpeechHistory

    init(
        defaults: UserDefaults = .standard,
        narrativeProgress: @escaping () -> Int = { 0 },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.catalog = .bundled()
        self.policy = PiboSpeechPolicy()
        self.narrativeProgress = narrativeProgress
        self.now = now
        self.calendar = calendar
        self.history = PiboSpeechHistory(defaults: defaults)
    }

    init(
        catalog: PiboSpeechCatalog,
        defaults: UserDefaults = .standard,
        narrativeProgress: @escaping () -> Int = { 0 },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.catalog = catalog
        self.policy = PiboSpeechPolicy()
        self.narrativeProgress = narrativeProgress
        self.now = now
        self.calendar = calendar
        self.history = PiboSpeechHistory(defaults: defaults)
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
            guard let selected = select(
                from: candidates,
                seed: "\(opportunity)|\(cue.key)"
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
        seed: String
    ) -> PiboSpeechEntry? {
        guard !entries.isEmpty else { return nil }
        let totalWeight = entries.reduce(0) { $0 + max(1, $1.weight) }
        var target = Int(stableHash(seed) % UInt64(totalWeight))
        for entry in entries {
            target -= max(1, entry.weight)
            if target < 0 { return entry }
        }
        return entries.last
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

    /// FNV-1a keeps selection stable across view recomputes and app launches;
    /// Swift's `hashValue` intentionally does not.
    private func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
