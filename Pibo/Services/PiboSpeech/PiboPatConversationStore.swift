import Foundation
import os
import PiboCore

enum PiboPatSpeaker: String, Codable {
    case pibo
    case system
}

enum PiboPatAction: String, Codable {
    case checkConnection
    case letSleep
    case morningGreeting
    case checkIn
    case play
    case rest
    case none

    var contextualAction: PiboCoreAnimationAdapter.ContextualAction? {
        switch self {
        case .checkConnection: .checkConnection
        case .letSleep: .letSleep
        case .morningGreeting: .morningGreeting
        case .checkIn: .checkIn
        case .play: .play
        case .rest: .rest
        case .none: nil
        }
    }
}

struct PiboPatLine: Codable, Equatable {
    let text: String
    let stages: [String]?
}

struct PiboPatUnit: Codable, Equatable {
    let state: String
    let context: String
    let action: PiboPatAction
    let speaker: PiboPatSpeaker
    let lines: [PiboPatLine]
}

struct PiboPatEventCandidate: Equatable {
    let event: PiboCorePatEvent
    let token: String
    var values: [String: String] = [:]
}

struct PiboPatConversationInput {
    let state: PiboActivityState
    let episodeKey: String
    var stableThinking = false
    var ambientEvent: PiboCorePatEvent = .none
    var dataUnknownReason: PiboCorePatDataUnknownReason = .waitingData
    let storyStage: String
    var values: [String: String] = [:]
    var events: [PiboPatEventCandidate] = []
}

struct PiboPatResolution: Equatable {
    let accepted: Bool
    var text: String?
    var speaker: PiboPatSpeaker?
    var action: PiboPatAction?
    var shouldExecuteAction = false
    var hasNext = false
    var interactionCompleted = false
    var context: PiboCorePatContext = .none

    static let rejected = PiboPatResolution(accepted: false)
}

struct PiboPatCatalog {
    private let unitsByKey: [String: [PiboPatUnit]]

    init(units: [PiboPatUnit]) {
        unitsByKey = Dictionary(grouping: units) { "\($0.state).\($0.context)" }
    }

    static func bundled(bundle: Bundle = .main) -> PiboPatCatalog {
        guard let url = bundle.url(
            forResource: "pibo-home-pat.zh-Hans",
            withExtension: "jsonl"
        ), let source = try? String(contentsOf: url, encoding: .utf8) else {
            LPLog.speech.error("Missing pibo-home-pat.zh-Hans.jsonl")
            return PiboPatCatalog(units: [])
        }
        let decoder = JSONDecoder()
        let units: [PiboPatUnit] = source.split(whereSeparator: { $0.isNewline }).compactMap { raw in
            do {
                let unit = try decoder.decode(PiboPatUnit.self, from: Data(raw.utf8))
                guard !unit.lines.isEmpty,
                      unit.lines.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
                else { return nil }
                return unit
            } catch {
                LPLog.speech.error("Invalid pat JSONL row: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return PiboPatCatalog(units: units)
    }

    func units(for context: PiboCorePatContext, storyStage: String) -> [PiboPatUnit] {
        guard let key = context.catalogKey else { return [] }
        return (unitsByKey[key] ?? []).compactMap { unit in
            let lines = unit.lines.filter { line in
                guard let stages = line.stages, !stages.isEmpty else { return true }
                return stages.contains(storyStage)
            }
            guard !lines.isEmpty else { return nil }
            return PiboPatUnit(
                state: unit.state,
                context: unit.context,
                action: unit.action,
                speaker: unit.speaker,
                lines: lines
            )
        }
    }
}

@MainActor
final class PiboPatConversationStore {
    private struct Snapshot: Codable {
        var cursors: [String: Int] = [:]
        var touchDiscoveryCompleted = 0
        var tiredRestingEpisodeKey = ""
        var wakingGreetedEpisodeKey = ""
        var consumedEventTokens: [String] = []
    }

    private struct ActiveUnit {
        let state: PiboActivityState
        let episodeKey: String
        let context: PiboCorePatContext
        let recordIndex: Int
        var nextLineIndex: Int
        let eventToken: String?
        let touchDiscovery: Bool
    }

    private static let persistenceKey = "pibo.pat.conversation.v1"
    private static let maximumConsumedEvents = 96
    private static let touchDiscoveryCount = 3

    private let catalog: PiboPatCatalog
    private let defaults: UserDefaults
    private var snapshot: Snapshot
    private var active: ActiveUnit?
    private var lastAcceptedAt: Date?
    private var lastState: PiboActivityState?
    private var lastEpisodeKey = ""

    init(
        catalog: PiboPatCatalog? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.catalog = catalog ?? .bundled()
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.persistenceKey),
           let restored = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = restored
            snapshot.touchDiscoveryCompleted = min(
                Self.touchDiscoveryCount,
                max(0, snapshot.touchDiscoveryCompleted)
            )
            snapshot.consumedEventTokens = Array(
                snapshot.consumedEventTokens.suffix(Self.maximumConsumedEvents)
            )
        } else {
            snapshot = Snapshot()
        }
    }

    func leaveHome() {
        active = nil
        lastAcceptedAt = nil
        lastState = nil
        lastEpisodeKey = ""
    }

    func stateChanged(_ state: PiboActivityState, episodeKey: String) {
        guard let lastState else {
            self.lastState = state
            lastEpisodeKey = episodeKey
            return
        }
        guard lastState != state || lastEpisodeKey != episodeKey else { return }
        active = nil
        lastAcceptedAt = nil
        self.lastState = state
        lastEpisodeKey = episodeKey
    }

    func resolve(_ input: PiboPatConversationInput, at date: Date = .now) -> PiboPatResolution {
        stateChanged(input.state, episodeKey: input.episodeKey)
        if let lastAcceptedAt,
           !PiboCorePat.cooldownAllows(
               elapsedSinceLastAcceptedSeconds: date.timeIntervalSince(lastAcceptedAt),
               hasPreviousAcceptedTap: true
           ) {
            return .rejected
        }

        if let active,
           active.state == input.state,
           active.episodeKey == input.episodeKey,
           let continued = continueActive(input, active: active, at: date) {
            return continued
        }
        active = nil

        let eventCandidate = input.events.first {
            !$0.token.isEmpty && !snapshot.consumedEventTokens.contains($0.token)
        }
        var event = eventCandidate?.event ?? .none
        var eventToken = eventCandidate?.token
        var touchDiscovery = false
        if event == .none,
           input.state == .stable,
           snapshot.touchDiscoveryCompleted < Self.touchDiscoveryCount {
            event = .touchDiscovery
            touchDiscovery = true
        }
        if event == .none { event = input.ambientEvent }
        let behavior = behavior(for: input)
        if behavior == .tiredResting, event == .insufficientSleep {
            event = .none
            eventToken = nil
        }
        let values = input.values.merging(eventCandidate?.values ?? [:]) { _, event in event }
        var context = PiboCorePat.context(
            state: input.state.core,
            behavior: behavior,
            event: event,
            dataUnknownReason: input.dataUnknownReason
        )
        var units = catalog.units(for: context, storyStage: input.storyStage)
        var selected = selectedRecord(context: context, units: units, values: values)

        if selected == nil, event != .none {
            eventToken = nil
            touchDiscovery = false
            context = PiboCorePat.context(
                state: input.state.core,
                behavior: behavior,
                event: input.ambientEvent,
                dataUnknownReason: input.dataUnknownReason
            )
            units = catalog.units(for: context, storyStage: input.storyStage)
            selected = selectedRecord(context: context, units: units, values: input.values)
        }
        guard let selected, units.indices.contains(selected) else { return .rejected }

        let unit = units[selected]
        let progress = PiboCorePat.lineProgress(currentLineIndex: 0, lineCount: unit.lines.count)
        lastAcceptedAt = date
        beginBehavior(input, context: context)
        if progress.hasNext {
            active = ActiveUnit(
                state: input.state,
                episodeKey: input.episodeKey,
                context: context,
                recordIndex: selected,
                nextLineIndex: progress.nextLineIndex,
                eventToken: eventToken,
                touchDiscovery: touchDiscovery
            )
        } else {
            complete(
                context: context,
                selectedRecord: selected,
                recordCount: units.count,
                eventToken: eventToken,
                touchDiscovery: touchDiscovery,
                episodeKey: input.episodeKey
            )
        }
        return PiboPatResolution(
            accepted: true,
            text: render(unit.lines[0].text, values: values),
            speaker: unit.speaker,
            action: unit.action,
            shouldExecuteAction: unit.action != .none
                && !(behavior == .tiredResting && unit.action == .rest),
            hasNext: progress.hasNext,
            interactionCompleted: progress.interactionCompleted,
            context: context
        )
    }

    func reset() {
        snapshot = Snapshot()
        leaveHome()
        defaults.removeObject(forKey: Self.persistenceKey)
    }

    private func continueActive(
        _ input: PiboPatConversationInput,
        active current: ActiveUnit,
        at date: Date
    ) -> PiboPatResolution? {
        let units = catalog.units(for: current.context, storyStage: input.storyStage)
        guard units.indices.contains(current.recordIndex) else { return nil }
        let unit = units[current.recordIndex]
        guard unit.lines.indices.contains(current.nextLineIndex),
              unitAvailable(unit, values: input.values) else { return nil }
        let lineIndex = current.nextLineIndex
        let progress = PiboCorePat.lineProgress(
            currentLineIndex: lineIndex,
            lineCount: unit.lines.count
        )
        lastAcceptedAt = date
        if progress.hasNext {
            var next = current
            next.nextLineIndex = progress.nextLineIndex
            active = next
        } else {
            complete(
                context: current.context,
                selectedRecord: current.recordIndex,
                recordCount: units.count,
                eventToken: current.eventToken,
                touchDiscovery: current.touchDiscovery,
                episodeKey: current.episodeKey
            )
            active = nil
        }
        return PiboPatResolution(
            accepted: true,
            text: render(unit.lines[lineIndex].text, values: input.values),
            speaker: unit.speaker,
            action: unit.action,
            shouldExecuteAction: false,
            hasNext: progress.hasNext,
            interactionCompleted: progress.interactionCompleted,
            context: current.context
        )
    }

    private func behavior(for input: PiboPatConversationInput) -> PiboCorePatBehavior {
        if input.state == .tired, snapshot.tiredRestingEpisodeKey == input.episodeKey {
            return .tiredResting
        }
        if input.state == .waking, snapshot.wakingGreetedEpisodeKey == input.episodeKey {
            return .wakingGreeted
        }
        if input.state == .stable, input.stableThinking { return .stableThinking }
        return .default
    }

    private func beginBehavior(_ input: PiboPatConversationInput, context: PiboCorePatContext) {
        guard input.state == .tired,
              context == .tiredAwake || context == .tiredInsufficientSleep,
              snapshot.tiredRestingEpisodeKey != input.episodeKey else { return }
        snapshot.tiredRestingEpisodeKey = input.episodeKey
        persist()
    }

    private func complete(
        context: PiboCorePatContext,
        selectedRecord: Int,
        recordCount: Int,
        eventToken: String?,
        touchDiscovery: Bool,
        episodeKey: String
    ) {
        if let key = context.catalogKey {
            snapshot.cursors[key] = PiboCorePat.nextRecordCursor(
                selectedRecord: selectedRecord,
                recordCount: recordCount
            )
        }
        if let eventToken, !eventToken.isEmpty {
            snapshot.consumedEventTokens.append(eventToken)
            snapshot.consumedEventTokens = Array(
                snapshot.consumedEventTokens.suffix(Self.maximumConsumedEvents)
            )
        }
        if touchDiscovery {
            snapshot.touchDiscoveryCompleted = min(
                Self.touchDiscoveryCount,
                snapshot.touchDiscoveryCompleted + 1
            )
        }
        if context == .wakingOrienting || context == .wakingRecovering {
            snapshot.wakingGreetedEpisodeKey = episodeKey
        }
        persist()
    }

    private func selectedRecord(
        context: PiboCorePatContext,
        units: [PiboPatUnit],
        values: [String: String]
    ) -> Int? {
        let cursor = context.catalogKey.flatMap { snapshot.cursors[$0] } ?? 0
        return PiboCorePat.selectRecord(
            cursor: cursor,
            eligible: units.map { unitAvailable($0, values: values) }
        )
    }

    private func unitAvailable(_ unit: PiboPatUnit, values: [String: String]) -> Bool {
        unit.lines.allSatisfy { templateAvailable($0.text, values: values) }
    }

    private func templateAvailable(_ template: String, values: [String: String]) -> Bool {
        var remainder = template[...]
        while let opening = remainder.firstIndex(of: "{") {
            guard let closing = remainder[opening...].firstIndex(of: "}") else { return false }
            let name = String(remainder[remainder.index(after: opening)..<closing])
            guard !name.isEmpty, values[name] != nil else { return false }
            remainder = remainder[remainder.index(after: closing)...]
        }
        return true
    }

    private func render(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { result, pair in
            result.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
    }
}

private extension PiboCorePatContext {
    var catalogKey: String? {
        switch self {
        case .stableTouchDiscovery: "stable.touchDiscovery"
        case .stableIdle: "stable.idle"
        case .stableThinking: "stable.thinking"
        case .stableSteps: "stable.steps"
        case .stableSleep: "stable.sleep"
        case .stableSleepTogether: "stable.sleepTogether"
        case .energeticReady: "energetic.ready"
        case .energeticWorkoutRun: "energetic.workout.run"
        case .energeticWorkoutWalk: "energetic.workout.walk"
        case .energeticWorkoutCycle: "energetic.workout.cycle"
        case .energeticWorkoutSwim: "energetic.workout.swim"
        case .energeticWorkoutHiit: "energetic.workout.hiit"
        case .energeticWorkoutYoga: "energetic.workout.yoga"
        case .energeticWorkoutOther: "energetic.workout.other"
        case .energeticActivityMilestone: "energetic.activityMilestone"
        case .energeticGoodSleep: "energetic.goodSleep"
        case .tiredInsufficientSleep: "tired.insufficientSleep"
        case .tiredAwake: "tired.awake"
        case .tiredResting: "tired.resting"
        case .wakingOrienting: "waking.orienting"
        case .wakingRecovering: "waking.recovering"
        case .wakingGreeted: "waking.greeted"
        case .sleepingAsleep: "sleeping.asleep"
        case .dataUnknownAuthorization: "dataUnknown.authorization"
        case .dataUnknownWaitingData: "dataUnknown.waitingData"
        case .dataUnknownUnavailable: "dataUnknown.unavailable"
        case .dataUnknownInterruptedNoTrustedState: "dataUnknown.interruptedNoTrustedState"
        case .none: nil
        }
    }
}
