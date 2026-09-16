import Foundation
import Observation
import PiboCore
import os

/// Decision 054 companion prompts, memory echoes and moods on Home.
///
/// Every budget, slot, tier, selection, expiry and mood rule is decided by
/// pibo-core (`PiboCoreCompanionPolicy`); this controller gathers facts from
/// Home, renders authored copy and records what the user actually did. Mirrors
/// HarmonyOS `HomeCompanionController.ets`.
@MainActor
@Observable
final class HomeCompanionController {
    /// Live Home facts, re-bound by `HomeView` on every render.
    struct Environment {
        var appActive: () -> Bool = { false }
        var state: () -> PiboActivityState = { .dataUnknown }
        var patBehavior: () -> PiboCorePatBehavior = { .default }
        var isThinking: () -> Bool = { false }
        var patEpisodeKey: () -> String = { "" }
        var overlayOpen: () -> Bool = { false }
        var foodProjectionVisible: () -> Bool = { false }
        var achievementVisible: () -> Bool = { false }
        var sproutBusy: () -> Bool = { false }
        var hasRipeBo: () -> Bool = { false }
        var dailyGuideActive: () -> Bool = { false }
        var speechVisible: () -> Bool = { false }
        var currentLine: () -> PiboSpeechLine? = { nil }
        var lastSpeechAt: () -> Double? = { nil }
        var weather: () -> PiboWeather = { .clear }
        var speechValues: () -> [String: String] = { [:] }
        var show: (PiboSpeechLine) -> Void = { _ in }
        var dismiss: () -> Void = {}
    }

    struct ActivePrompt {
        let prompt: PiboCompanionCatalog.Prompt
        let slot: PiboCoreCompanionSlot
        let askedAt: Double
        var line: PiboSpeechLine
    }

    static let lineAdvanceSeconds: Double = 2.6
    static let readingSecondsPerCharacter: Double = 0.2
    static let returnOfferDelaySeconds: Double = 1.8
    static let statusLineTTLSeconds: Double = 30 * 60
    static let hammockReplyDelaySeconds: Double = 0.6
    private static let echoDelayToday: Double = 10 * 60
    private static let echoDelayRecent: Double = 8 * 3600
    private static let echoDelayPreference: Double = 20 * 3600
    private static let echoSlotMask: UInt32 = PiboCoreCompanionSlot.patAfter.mask
        | PiboCoreCompanionSlot.wakingFirst.mask
        | PiboCoreCompanionSlot.returnShort.mask
        | PiboCoreCompanionSlot.returnLong.mask

    struct Mood: Equatable {
        var mood: PiboCoreCompanionMood = .none
        var cause: PiboCoreCompanionMoodCause = .none
        var hidesBody = false
    }

    private(set) var mood = Mood()
    private(set) var replySheetOpen = false
    /// True while a companion sequence owns the bubble; other speech waits.
    private(set) var holdsSpeech = false
    private(set) var active: ActivePrompt?

    @ObservationIgnored var environment = Environment()
    @ObservationIgnored let store: PiboCompanionStore
    @ObservationIgnored private let catalog: PiboCompanionCatalog?
    @ObservationIgnored private var sequenceTask: Task<Void, Never>?
    @ObservationIgnored private var sequenceRunning = false
    @ObservationIgnored private var ignoreTask: Task<Void, Never>?
    @ObservationIgnored private var returnOfferTask: Task<Void, Never>?
    @ObservationIgnored private var returnOffered = false
    @ObservationIgnored private var pendingPatContext: PiboCorePatContext?
    @ObservationIgnored private var lastWeather: PiboWeather?
    @ObservationIgnored private var thinkingSince: Double = 0
    @ObservationIgnored private var hammockVisitAt: Double = 0
    @ObservationIgnored private let clock: () -> Double

    init(
        store: PiboCompanionStore,
        catalog: PiboCompanionCatalog? = PiboCompanionCatalog.shared,
        clock: @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.store = store
        self.catalog = catalog
        self.clock = clock
    }

    /// Home is a single surface; one controller keeps timers and memory stable
    /// across the transient `HomeView` values SwiftUI creates.
    static let shared = HomeCompanionController(store: PiboCompanionStore())

    var enabled: Bool { PiboReleaseScope.companionPrompts && catalog != nil }

    // MARK: Lifecycle

    func enterHome() {
        guard enabled else { return }
        store.beginEntry(now: clock())
        returnOffered = false
        pendingPatContext = nil
        lastWeather = environment.weather()
        scheduleReturnOffer()
        refreshMood()
    }

    func leaveHome() {
        returnOfferTask?.cancel()
        hammockVisitAt = 0
        ignoreActivePrompt(reason: "background")
        clearSequence()
        replySheetOpen = false
        if enabled { store.markVisible(now: clock()) }
    }

    /// Called about once a second while Home is visible.
    func tick() {
        guard enabled, environment.appActive() else { return }
        trackThinking()
        refreshMood()
        reconcileHammockVisit()
        if let active, !replySheetOpen, !sequenceRunning, environment.currentLine() != active.line {
            ignoreActivePrompt(reason: "dismissed")
        }
        let condition = environment.weather()
        if condition != lastWeather {
            let becameRain = condition == .rain || condition == .thunderstorm
            lastWeather = condition
            if becameRain { _ = offer(.eventWeather) }
        }
    }

    // MARK: Slots

    /// Called by the pat flow after the physical reaction. Returns true when a
    /// companion utterance used this pat's text opportunity.
    func consumePatTextOpportunity() -> Bool {
        guard enabled else { return false }
        if active != nil { return true }
        // A pat interrupts a finished reply or echo instead of queueing behind it.
        clearSequence()
        holdsSpeech = false
        guard let context = pendingPatContext else { return false }
        pendingPatContext = nil
        if environment.state() == .waking,
           store.claimWakingFirst(episode: environment.patEpisodeKey()),
           offer(.wakingFirst) {
            return true
        }
        return offer(.patAfter, patContext: context)
    }

    /// A pat conversation unit finished its last line.
    func patInteractionCompleted(_ context: PiboCorePatContext) {
        guard enabled else { return }
        pendingPatContext = context
    }

    func onMealObserved() { _ = offer(.eventMeal) }
    func onBoCollected() { _ = offer(.eventBoCollected) }
    func onRiverTapped() { _ = offer(.sceneRiver) }

    /// The hammock keeps its own action; Pibo talks about it once that surface
    /// closes, or right away if nothing opened.
    func onHammockTapped() {
        guard enabled else { return }
        hammockVisitAt = clock()
    }

    var riverHotspotEnabled: Bool { enabled && moodAnimationID != "dive" }

    var grassHotspotEnabled: Bool { enabled && (mood.hidesBody || moodAnimationID != "coolhide") }

    func onGrassTapped() {
        guard enabled else { return }
        if mood.cause == .hideAndSeek {
            store.markHideSeekFound()
            refreshMood()
            Analytics.track(.companionMoodShown, screen: "home", ["mood": .string("hideSeekFound")])
            _ = offer(.sceneGrass, hideSeek: .found)
            return
        }
        _ = offer(.sceneGrass, hideSeek: .none)
    }

    /// Tries echo → prompt → scene line for a slot. Returns true if Pibo spoke.
    @discardableResult
    func offer(
        _ slot: PiboCoreCompanionSlot,
        patContext: PiboCorePatContext? = nil,
        hideSeek: PiboCompanionCatalog.HideSeekCondition = .none
    ) -> Bool {
        guard enabled, let catalog, environment.appActive(), active == nil else { return false }
        let state = environment.state()
        let context = selectionContext(slot: slot, state: state, patContext: patContext)
        let now = clock()
        if allowed(.echo, slot: slot, state: state),
           let echo = selectEcho(context: context, catalog: catalog, now: now) {
            store.recordEchoUsed(echo.usageKey, now: now)
            store.recordLineShown(now: now, proactive: true, prompt: false, topic: nil)
            Analytics.track(.companionEchoShown, screen: "home", [
                "item": .string(echo.answer.promptId),
                "trigger": .string(PiboCompanionCatalog.key(for: slot)),
            ])
            playLines(echo.lines, customText: echo.answer.customText)
            return true
        }
        if allowed(.prompt, slot: slot, state: state),
           let prompt = selectPrompt(context: context, catalog: catalog, hideSeek: hideSeek, now: now) {
            startPrompt(prompt, slot: slot, now: now)
            return true
        }
        if allowed(.sceneLine, slot: slot, state: state),
           let line = selectSceneLine(slot: slot, state: state, hideSeek: hideSeek, catalog: catalog) {
            store.recordSceneUsed(line.id, now: now)
            store.recordLineShown(now: now, proactive: !Self.userInitiated(slot), prompt: false, topic: nil)
            playLines(line.lines, customText: nil)
            return true
        }
        return false
    }

    // MARK: Answers

    func choose(_ choiceID: String) {
        guard let active, let option = active.prompt.options.first(where: { $0.id == choiceID }) else { return }
        let now = clock()
        finishPrompt()
        store.recordAnswer(
            answerRecord(prompt: active.prompt, optionID: option.id, customText: nil, now: now),
            askedAt: active.askedAt,
            positive: option.mood == .coolhide,
            tired: option.mood == .dive
        )
        Analytics.track(.companionPromptAnswered, screen: "home", [
            "item": .string(active.prompt.id),
            "input": .string(option.id),
            "trigger": .string(PiboCompanionCatalog.key(for: active.slot)),
        ])
        refreshMood()
        playLines(option.reaction, customText: nil)
    }

    func openReply() {
        guard var active else { return }
        replySheetOpen = true
        ignoreTask?.cancel()
        // Keep the question visible behind the card; the fade resumes on cancel.
        active.line.lingerDuration = 30 * 60
        self.active = active
        environment.show(active.line)
    }

    func cancelReply() {
        replySheetOpen = false
        guard var active else { return }
        active.line.lingerDuration = PiboCoreCompanionPolicy.promptIgnoreSeconds + 0.6
        self.active = active
        environment.show(active.line)
        armIgnoreTimer()
    }

    var promptQuestion: String { active?.line.text ?? "" }

    var maxReplyScalars: Int { PiboCoreCompanionPolicy.customTextMaxScalars }

    func replyScalarCount(_ text: String) -> Int? {
        PiboCoreCompanionPolicy.customTextScalarCount(text)
    }

    @discardableResult
    func submitReply(_ text: String) -> Bool {
        guard let active, let catalog, let count = PiboCoreCompanionPolicy.customTextScalarCount(text), count >= 1
        else { return false }
        let reply = text.trimmingCharacters(in: .whitespaces)
        let now = clock()
        replySheetOpen = false
        finishPrompt()
        store.recordAnswer(
            answerRecord(prompt: active.prompt, optionID: PiboCompanionStore.customOptionID, customText: reply, now: now),
            askedAt: active.askedAt,
            positive: false,
            tired: false
        )
        // Only the fact that a custom reply exists is tracked — never its text or length.
        Analytics.track(.companionPromptAnswered, screen: "home", [
            "item": .string(active.prompt.id),
            "input": .string(PiboCompanionStore.customOptionID),
            "trigger": .string(PiboCompanionCatalog.key(for: active.slot)),
        ])
        let pool = customReactions(state: environment.state(), catalog: catalog)
        let reaction = pool[Int(Self.hash(active.prompt.id).magnitude % UInt32(pool.count))]
        playLines(reaction.lines, customText: reply)
        return true
    }

    // MARK: Debug

    #if DEBUG
    func debugRun(_ command: String) -> String {
        guard enabled else { return "陪伴功能未启用" }
        let now = clock()
        switch command {
        case "pat-ready":
            pendingPatContext = .stableIdle
            return "下一次双击 Pibo 会尝试提问或回响"
        case "absence-short":
            finishPrompt()
            store.debugSimulateAbsence(seconds: 4 * 3600, now: now)
            returnOffered = false
            scheduleReturnOffer()
            refreshMood()
            return "已模拟离开 4 小时"
        case "absence-long":
            finishPrompt()
            store.debugSimulateAbsence(seconds: 25 * 3600, now: now)
            returnOffered = false
            scheduleReturnOffer()
            refreshMood()
            return "已模拟离开 25 小时"
        case "reset":
            finishPrompt()
            store.reset()
            refreshMood()
            return "陪伴记忆已清空"
        default:
            return ""
        }
    }
    #endif

    // MARK: Mood

    /// Clip ID for the current mood, or nil when the durable expression applies.
    var moodAnimationID: String? {
        guard enabled else { return nil }
        switch mood.mood {
        case .boring: return "boring"
        case .coolhide: return "coolhide"
        case .dive: return "dive"
        case .none: return nil
        }
    }

    /// Short widget phrase for the current mood; never user text.
    static func statusLine(for cause: PiboCoreCompanionMoodCause) -> String? {
        switch cause {
        case .longAbsence, .quietAfterThinking: "在森林里转圈"
        case .positiveAnswer: "在草丛里耍酷"
        case .hideAndSeek: "躲在草丛里"
        case .tiredAnswer: "泡在水里"
        case .none: nil
        }
    }

    func refreshMood() {
        guard enabled else { return }
        let now = clock()
        let state = environment.state()
        var blockers: PiboCoreCompanionBlockers = []
        if environment.overlayOpen() { blockers.insert(.overlay) }
        if environment.achievementVisible() { blockers.insert(.achievement) }
        if environment.sproutBusy() { blockers.insert(.sprout) }
        if environment.hasRipeBo() { blockers.insert(.boRipe) }
        let since = { (at: Double) -> Double? in at > 0 ? now - at : nil }
        let previous = mood
        let resolved = PiboCoreCompanionPolicy.resolveMood(PiboCoreCompanionMoodFacts(
            state: state.core.rawValue,
            patBehavior: environment.patBehavior().rawValue,
            blockers: blockers,
            secondsSincePositiveAnswer: since(store.positiveAnswerAt),
            secondsSinceTiredAnswer: since(store.tiredAnswerAt),
            absenceSecondsAtEntry: store.hasPreviousVisit ? store.absenceSecondsAtEntry : nil,
            secondsSinceEntry: max(0, now - store.entryAt),
            hideSeekUsedToday: store.hideSeekUsedToday(now: now),
            hideSeekFound: store.hideSeekFound,
            isThinking: environment.isThinking(),
            quietSeconds: thinkingSince > 0 ? now - thinkingSince : 0
        ))
        let next = Mood(mood: resolved.mood, cause: resolved.cause, hidesBody: resolved.hidesBody)
        guard next.mood != previous.mood || next.cause != previous.cause || next.hidesBody != previous.hidesBody else {
            mood = next
            return
        }
        mood = next
        if next.cause == .hideAndSeek { store.markHideSeekStarted(now: now) }
        if next.mood != .none {
            Analytics.track(.companionMoodShown, screen: "home", ["mood": .string(Self.moodKey(next.cause))])
            PiboCompanionStatusLine.publish(Self.statusLine(for: next.cause), until: now + Self.statusLineTTLSeconds)
        }
        if previous.cause == .hideAndSeek, !store.hideSeekFound, next.cause != .hideAndSeek, blockers.isEmpty {
            _ = offer(.hideSeekTimeout)
        }
    }

    private func trackThinking() {
        // Hiding, cooling off or diving is not quiet thinking; restart the clock after a mood ends.
        let otherMood = mood.mood != .none && mood.cause != .quietAfterThinking
        if environment.isThinking(), !otherMood {
            if thinkingSince == 0 { thinkingSince = clock() }
        } else {
            thinkingSince = 0
        }
    }

    private func reconcileHammockVisit() {
        guard hammockVisitAt > 0, !environment.overlayOpen(),
              clock() - hammockVisitAt >= Self.hammockReplyDelaySeconds else { return }
        hammockVisitAt = 0
        _ = offer(.sceneHammock)
    }

    private static func moodKey(_ cause: PiboCoreCompanionMoodCause) -> String {
        switch cause {
        case .longAbsence: "boringReturn"
        case .quietAfterThinking: "boringQuiet"
        case .positiveAnswer: "coolhide"
        case .hideAndSeek: "hideSeek"
        case .tiredAnswer: "dive"
        case .none: "none"
        }
    }

    // MARK: Budget and selection facts

    static func userInitiated(_ slot: PiboCoreCompanionSlot) -> Bool {
        slot == .sceneGrass || slot == .sceneRiver || slot == .sceneHammock
    }

    private func allowed(_ utterance: PiboCoreCompanionUtterance, slot: PiboCoreCompanionSlot, state: PiboActivityState) -> Bool {
        let now = clock()
        var blockers: PiboCoreCompanionBlockers = []
        if environment.overlayOpen() || environment.foodProjectionVisible() { blockers.insert(.overlay) }
        if environment.achievementVisible() { blockers.insert(.achievement) }
        if environment.sproutBusy() { blockers.insert(.sprout) }
        if environment.dailyGuideActive() { blockers.insert(.dailyGuide) }
        // A pat or scene tap replaces the visible bubble exactly like pat speech does.
        if slot != .patAfter, slot != .wakingFirst, !Self.userInitiated(slot), environment.speechVisible() {
            blockers.insert(.speechVisible)
        }
        let decision = PiboCoreCompanionPolicy.budgetDecision(PiboCoreCompanionBudgetFacts(
            utterance: utterance,
            slot: slot,
            state: state.core.rawValue,
            blockers: blockers,
            linesThisEntry: store.linesThisEntry,
            proactiveLinesToday: store.linesToday,
            promptsToday: store.promptsToday,
            secondsSinceLastSpeech: environment.lastSpeechAt().map { max(0, now - $0) },
            consecutiveIgnoredPrompts: store.consecutiveIgnored,
            daysSinceLastIgnored: store.daysSinceLastIgnored(now: now),
            relationshipDays: store.relationshipDays,
            recentAnswerRatePercent: store.recentAnswerRatePercent()
        ))
        if decision != .allowed {
            LPLog.speech.debug("companion slot=\(PiboCompanionCatalog.key(for: slot), privacy: .public) utterance=\(utterance.rawValue, privacy: .public) blocked=\(decision.rawValue, privacy: .public)")
        }
        return decision == .allowed
    }

    private func selectionContext(
        slot: PiboCoreCompanionSlot,
        state: PiboActivityState,
        patContext: PiboCorePatContext?
    ) -> PiboCoreCompanionSelectionContext {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: clock()))
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return PiboCoreCompanionSelectionContext(
            slot: slot,
            state: state.core.rawValue,
            patContext: patContext?.rawValue,
            weather: Self.companionWeather(environment.weather()),
            phase: PiboCoreCompanionPolicy.phase(localMinuteOfDay: minute),
            unlockedTier: PiboCoreCompanionPolicy.unlockedTier(
                answeredTotal: store.answeredTotal,
                relationshipDays: store.relationshipDays,
                recentAnswerRatePercent: store.recentAnswerRatePercent()
            )
        )
    }

    static func companionWeather(_ condition: PiboWeather) -> PiboCoreCompanionWeather {
        switch condition {
        case .clear: .clear
        case .cloudy: .cloudy
        case .rain, .thunderstorm: .rain
        case .snow: .snow
        case .fog: .other
        }
    }

    private func selectPrompt(
        context: PiboCoreCompanionSelectionContext,
        catalog: PiboCompanionCatalog,
        hideSeek: PiboCompanionCatalog.HideSeekCondition,
        now: Double
    ) -> PiboCompanionCatalog.Prompt? {
        let values = environment.speechValues()
        let candidates = catalog.prompts.map { prompt -> PiboCoreCompanionPromptCandidate in
            let answer = store.answer(prompt.id)
            let hideSeekMet = prompt.conditions.hideSeek == .any || prompt.conditions.hideSeek == hideSeek
            return PiboCoreCompanionPromptCandidate(
                slotMask: prompt.slotMask,
                stateMask: prompt.conditions.stateMask,
                patContextMask: prompt.conditions.patContextMask,
                weatherMask: prompt.conditions.weatherMask,
                phaseMask: prompt.conditions.phaseMask,
                tier: prompt.tier,
                weight: prompt.weight,
                retention: prompt.retention,
                requirementMet: hideSeekMet && Self.templateAvailable(prompt.lines, values: values),
                hasActiveMemory: answer.map { PiboCoreCompanionPolicy.memoryActive(expiresAt: $0.expiresAt, now: now) } ?? false,
                secondsSinceAsked: store.lastAsked(prompt.id).map { now - $0 },
                cooldownDays: prompt.cooldownDays,
                secondsSinceTopic: store.topicLastAt(prompt.topic).map { now - $0 }
            )
        }
        // Same seed text as HarmonyOS, hashed with Core's shared text hash.
        let seed = "\(PiboCompanionStore.localDayKey(now)):\(context.slot.rawValue):\(store.entryID):\(store.promptsToday)"
        guard let index = PiboCoreCompanionPolicy.selectedPromptIndex(
            opportunityHash: PiboCoreSpeechHash.text(seed),
            candidates: candidates,
            context: context
        ), catalog.prompts.indices.contains(index) else { return nil }
        return catalog.prompts[index]
    }

    private struct EchoChoice {
        let answer: PiboCompanionStore.AnswerRecord
        let lines: [String]
        let usageKey: String
    }

    private func selectEcho(
        context: PiboCoreCompanionSelectionContext,
        catalog: PiboCompanionCatalog,
        now: Double
    ) -> EchoChoice? {
        var choices: [EchoChoice] = []
        var candidates: [PiboCoreCompanionEchoCandidate] = []
        for answer in store.answers {
            guard let prompt = catalog.prompt(answer.promptId) else { continue }
            let active = PiboCoreCompanionPolicy.memoryActive(expiresAt: answer.expiresAt, now: now)
            let secondsSinceAnswer = now - answer.answeredAt
            let delay: Double = switch PiboCoreCompanionRetention(rawValue: answer.retention) {
            case .preference: Self.echoDelayPreference
            case .recent: Self.echoDelayRecent
            default: Self.echoDelayToday
            }
            if answer.optionId == PiboCompanionStore.customOptionID {
                let pool = catalog.customEchoes
                let echo = pool[Int(Self.hash("\(answer.promptId):\(Int64(answer.answeredAt * 1000))").magnitude % UInt32(pool.count))]
                let usageKey = "\(answer.promptId):custom"
                choices.append(EchoChoice(answer: answer, lines: echo.lines, usageKey: usageKey))
                candidates.append(PiboCoreCompanionEchoCandidate(
                    slotMask: Self.echoSlotMask,
                    memoryActive: active,
                    secondsSinceAnswer: secondsSinceAnswer,
                    minimumDelaySeconds: delay,
                    maximumUses: 1,
                    useCount: store.echoUseCount(usageKey),
                    customTextScalars: PiboCoreCompanionPolicy.customTextScalarCount(answer.customText ?? "") ?? 0
                ))
                continue
            }
            guard let option = prompt.options.first(where: { $0.id == answer.optionId }) else { continue }
            for echo in option.echoes {
                let usageKey = "\(answer.promptId):\(option.id):\(echo.id)"
                choices.append(EchoChoice(answer: answer, lines: echo.lines, usageKey: usageKey))
                candidates.append(PiboCoreCompanionEchoCandidate(
                    slotMask: Self.echoSlotMask,
                    weatherMask: echo.weatherMask,
                    phaseMask: echo.phaseMask,
                    memoryActive: active,
                    secondsSinceAnswer: secondsSinceAnswer,
                    minimumDelaySeconds: delay,
                    maximumUses: 1,
                    useCount: store.echoUseCount(usageKey),
                    customTextScalars: nil
                ))
            }
        }
        guard let index = PiboCoreCompanionPolicy.selectedEchoIndex(candidates: candidates, context: context),
              choices.indices.contains(index) else { return nil }
        return choices[index]
    }

    private func selectSceneLine(
        slot: PiboCoreCompanionSlot,
        state: PiboActivityState,
        hideSeek: PiboCompanionCatalog.HideSeekCondition,
        catalog: PiboCompanionCatalog
    ) -> PiboCompanionCatalog.Line? {
        let stateBit = UInt32(1) << UInt32(state.core.rawValue)
        let matches = catalog.sceneLines.filter { line in
            line.slotMask & slot.mask != 0
                && (line.conditions.stateMask == 0 || line.conditions.stateMask & stateBit != 0)
                && (line.conditions.hideSeek == .any || line.conditions.hideSeek == hideSeek)
        }
        // Least used first; catalog order breaks ties.
        return matches.reduce(nil) { best, line in
            guard let best else { return line }
            return store.sceneUseCount(line.id) < store.sceneUseCount(best.id) ? line : best
        }
    }

    private func customReactions(state: PiboActivityState, catalog: PiboCompanionCatalog) -> [PiboCompanionCatalog.Line] {
        let stateBit = UInt32(1) << UInt32(state.core.rawValue)
        let pool = catalog.customReactions.filter {
            $0.conditions.stateMask == 0 || $0.conditions.stateMask & stateBit != 0
        }
        return pool.isEmpty ? catalog.customReactions : pool
    }

    private func answerRecord(
        prompt: PiboCompanionCatalog.Prompt,
        optionID: String,
        customText: String?,
        now: Double
    ) -> PiboCompanionStore.AnswerRecord {
        let dayEnd = PiboCompanionStore.localMidnight(now) + 86_400
        return PiboCompanionStore.AnswerRecord(
            promptId: prompt.id,
            optionId: optionID,
            customText: customText,
            retention: prompt.retention.rawValue,
            answeredAt: now,
            expiresAt: PiboCoreCompanionPolicy.memoryExpiresAt(
                answeredAt: now,
                retention: prompt.retention,
                secondsUntilLocalDayEnd: dayEnd - now
            )
        )
    }

    // MARK: Presentation

    private func startPrompt(_ prompt: PiboCompanionCatalog.Prompt, slot: PiboCoreCompanionSlot, now: Double) {
        store.recordLineShown(now: now, proactive: !Self.userInitiated(slot), prompt: true, topic: prompt.topic)
        Analytics.track(.companionPromptShown, screen: "home", [
            "item": .string(prompt.id),
            "trigger": .string(PiboCompanionCatalog.key(for: slot)),
        ])
        let values = environment.speechValues()
        let texts = prompt.lines.map { Self.render($0, values: values, customText: nil) }
        var last = PiboSpeechLine(text: texts[texts.count - 1])
        last.interaction = PiboSpeechInteraction(
            choices: prompt.options.map { PiboSpeechChoice(id: $0.id, label: $0.label) },
            allowsCustom: true
        )
        last.lingerDuration = PiboCoreCompanionPolicy.promptIgnoreSeconds + 0.6
        active = ActivePrompt(prompt: prompt, slot: slot, askedAt: now, line: last)
        playSequence(leading: Array(texts.dropLast()), last: last)
    }

    private func playLines(_ lines: [String], customText: String?) {
        let values = environment.speechValues()
        let texts = lines.map { Self.render($0, values: values, customText: customText) }
        guard let final = texts.last else { return }
        var last = PiboSpeechLine(text: final)
        // Reactions and echoes often quote the user; give them time to be read.
        last.lingerDuration = max(Self.lineAdvanceSeconds + 0.4, Double(final.count) * Self.readingSecondsPerCharacter)
        playSequence(leading: Array(texts.dropLast()), last: last)
    }

    private func playSequence(leading: [String], last: PiboSpeechLine) {
        clearSequence()
        holdsSpeech = true
        sequenceRunning = !leading.isEmpty
        sequenceTask = Task { @MainActor [weak self] in
            for text in leading {
                guard let self, !Task.isCancelled else { return }
                var line = PiboSpeechLine(text: text)
                line.hasNext = true
                line.lingerDuration = Self.lineAdvanceSeconds + 0.4
                self.environment.show(line)
                try? await Task.sleep(for: .seconds(Self.lineAdvanceSeconds))
            }
            guard let self, !Task.isCancelled else { return }
            self.sequenceRunning = false
            self.environment.show(last)
            if self.active?.line == last {
                self.armIgnoreTimer()
            } else {
                self.holdsSpeech = false
            }
        }
    }

    private func armIgnoreTimer() {
        ignoreTask?.cancel()
        ignoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PiboCoreCompanionPolicy.promptIgnoreSeconds))
            guard !Task.isCancelled else { return }
            self?.ignoreActivePrompt(reason: "timeout")
        }
    }

    private func ignoreActivePrompt(reason: String) {
        guard let active else { return }
        let now = clock()
        let shown = environment.currentLine() == active.line
        finishPrompt()
        replySheetOpen = false
        store.recordIgnored(promptId: active.prompt.id, askedAt: active.askedAt, now: now)
        Analytics.track(.companionPromptIgnored, screen: "home", [
            "item": .string(active.prompt.id),
            "reason": .string(reason),
            "trigger": .string(PiboCompanionCatalog.key(for: active.slot)),
        ])
        if shown { environment.dismiss() }
    }

    private func finishPrompt() {
        active = nil
        holdsSpeech = false
        ignoreTask?.cancel()
        clearSequence()
    }

    private func clearSequence() {
        sequenceTask?.cancel()
        sequenceTask = nil
        sequenceRunning = false
    }

    private func scheduleReturnOffer() {
        returnOfferTask?.cancel()
        guard let slot = PiboCoreCompanionPolicy.returnSlot(
            absenceSeconds: store.absenceSecondsAtEntry,
            hasPreviousVisit: store.hasPreviousVisit
        ) else { return }
        returnOfferTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.returnOfferDelaySeconds))
            guard let self, !Task.isCancelled, !self.returnOffered else { return }
            self.returnOffered = true
            _ = self.offer(slot)
        }
    }

    // MARK: Text

    static func templateAvailable(_ lines: [String], values: [String: String]) -> Bool {
        lines.allSatisfy { line in
            placeholders(in: line).allSatisfy { name in
                name != "custom" && !(values[name] ?? "").isEmpty
            }
        }
    }

    static func render(_ line: String, values: [String: String], customText: String?) -> String {
        var rendered = line
        var all = values
        all["custom"] = customText ?? ""
        for (name, value) in all {
            rendered = rendered.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return rendered
    }

    private static func placeholders(in line: String) -> [String] {
        var names: [String] = []
        var remainder = Substring(line)
        while let open = remainder.firstIndex(of: "{"),
              let close = remainder[open...].firstIndex(of: "}") {
            let name = remainder[remainder.index(after: open)..<close]
            if !name.isEmpty, name.allSatisfy({ $0.isASCII && $0.isLetter }) { names.append(String(name)) }
            remainder = remainder[remainder.index(after: close)...]
        }
        return names
    }

    /// Java-style 31 hash over UTF-16 units, matching HarmonyOS `hash()` so the
    /// same custom reply/echo is picked on both platforms.
    static func hash(_ text: String) -> Int32 {
        var value: Int32 = 0
        for unit in text.utf16 {
            value = value &* 31 &+ Int32(unit)
        }
        return value
    }
}

/// Widget-visible mood phrase with an expiry. Never user text.
enum PiboCompanionStatusLine {
    static func publish(_ line: String?, until expiresAt: Double) {
        var snapshot = PiboWidgetSnapshotStore.load()
        snapshot.companionStatusLabel = line
        snapshot.companionStatusExpiresAt = line == nil ? nil : Date(timeIntervalSince1970: expiresAt)
        guard PiboWidgetSnapshotStore.save(snapshot) else { return }
        PetStateWidgetBridge.reloadHomeWidget()
    }
}
