import Foundation
import Observation
import PiboCore
import os

// Plays queued growth moments on Home one at a time: a stage effect, a Pibo line chosen by
// tone, and for a level-up the reveal card. It waits while a sheet, a companion prompt or
// another bubble owns the screen.
//
// Ported from HarmonyPibo `services/growth/HomeGrowthController.ets`. Core owns every
// threshold and roll; the copy catalog owns the wording; this type only sequences them.

@MainActor
@Observable
final class HomeGrowthController {
    struct Dependencies {
        var growth: () -> GrowthStore
        var coordinator: () -> GrowthCoordinator
        var decor: () -> DecorStore
        var ledger: () -> BoLedgerStore
        var speech: () -> HomeSpeechPresentationController
        var companionBusy: () -> Bool
        var dayCount: () -> Int
        var polaroids: () -> PolaroidStore
        var appActive: () -> Bool
        var overlayOpen: () -> Bool
        /// Decision 058: an untold trip turns the away summary into a diary line.
        var awayDiary: () -> PiboSpeechLine?
        var lastWorkoutEndedAt: () -> Date?
        var lastWorkoutKind: () -> String?
    }

    private static let tickInterval: Duration = .milliseconds(800)
    private static let lineLinger: TimeInterval = 4.2
    /// Quiet gap after any bubble before a growth moment speaks, so lines never stack.
    private static let speechGap: TimeInterval = 1.5
    private static let patPopWindow: TimeInterval = 0.6
    /// Let Home settle (away summary, morning line) before the evening polaroid.
    private static let polaroidSettle: TimeInterval = 8
    private static let shootLinger: TimeInterval = 3.2

    /// The level-up card's contents; nil while it is not up.
    private(set) var levelUpLevel = 0
    private(set) var levelUpLine = ""
    private(set) var levelUpVisible = false
    private(set) var polaroid: PolaroidShot?
    private(set) var polaroidVisible = false
    private(set) var revision = 0
    let stageEffects = PixelStageEffects()

    @ObservationIgnored private var dependencies: Dependencies?
    @ObservationIgnored private var catalog: GrowthCopyCatalog?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var levelCardDueAt: Date?
    @ObservationIgnored private var pendingLevelEventID: String?
    @ObservationIgnored private var lastShakeAt: Date?
    @ObservationIgnored private var busyUntil = Date.distantPast
    @ObservationIgnored private var homeSince = Date()
    @ObservationIgnored private var printing = false
    @ObservationIgnored private var debugMorningBand = 0

    func bind(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        catalog = GrowthCopyCatalog.shared
    }

    func start() {
        guard tickTask == nil else { return }
        homeSince = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        // Keep the persisted level event pending across a covered or stopped Home.
    }

    // MARK: - Queue

    func tick(now: Date = .now) {
        guard let deps = dependencies, deps.appActive() else { return }
        guard levelCardDueAt != nil || now >= busyUntil else { return }
        if deps.overlayOpen() || deps.companionBusy() { return }
        let speech = deps.speech()
        if speech.line != nil { return }
        if let shown = speech.lastShownAt, now.timeIntervalSince1970 - shown < Self.speechGap {
            return
        }
        let growth = deps.growth()
        if let due = levelCardDueAt {
            guard now >= due else { return }
            levelUpVisible = true
            if let id = pendingLevelEventID { growth.consume(id: id) }
            levelCardDueAt = nil
            pendingLevelEventID = nil
            return
        }
        guard let event = growth.peek() else {
            maybePolaroid(now)
            return
        }
        if event.kind != .level { growth.consume(id: event.id) }
        present(event, now: now)
    }

    private func present(_ event: GrowthFeedbackEvent, now: Date, preview: Bool = false) {
        guard let deps = dependencies else { return }
        let effects = stageEffects
        switch event.kind {
        case .away:
            let sources = [event.sleep ?? 0, event.steps ?? 0, event.activity ?? 0]
            for (source, value) in sources.enumerated() where value >= 1 {
                let xp = source == event.dominant ? Double(event.xp ?? 0) : 0
                Task {
                    try? await Task.sleep(for: .milliseconds(source * 350))
                    effects.play(.awayOrbs, value: xp, source: source)
                }
            }
            let facts = sources.enumerated()
                .map { $0.element >= 1 ? "\(GrowthPresentation.sourceName($0.offset)) +\($0.element)" : "" }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if let diary = deps.awayDiary() {
                deps.speech().show(diary)
            } else {
                say("awaySummary", band: nil, kind: event.dominant, level: nil, fact: facts)
            }
            busyUntil = now.addingTimeInterval(1.8)

        case .pop:
            let sources = [event.sleep ?? 0, event.steps ?? 0, event.activity ?? 0]
            let best = sources.indices.max { sources[$0] < sources[$1] } ?? 1
            effects.play(.sourcePop, value: Double(event.xp ?? 0), source: best)
            // Steps that crossed another thousand also open a flower on the ground.
            if (event.steps ?? 0) >= 1 { effects.play(.bloom, value: 0, source: 1) }

        case .level:
            let level = event.level ?? deps.growth().level
            Analytics.track(.levelUp, screen: "home", ["level": .int(level)])
            effects.play(.levelUp, value: Double(level), source: -1)
            levelUpLevel = level
            levelUpLine = line("levelUp", level: level) ?? ""
            revision += 1
            pendingLevelEventID = preview ? nil : event.id
            levelCardDueAt = now.addingTimeInterval(1.5)
            busyUntil = now.addingTimeInterval(1.9)

        case .heart:
            effects.play(.heartUp, value: Double(event.hearts ?? 0), source: -1)
            say(event.toneUnlocked == true ? "toneUnlocked" : "heartUp",
                band: nil, kind: Int(deps.growth().tone.rawValue), level: nil, fact: "")

        case .wish:
            effects.play(.wishStamp, value: Double(event.xp ?? 0), source: -1)
            say("wishDone", band: nil, kind: event.wish, level: nil, fact: "")

        case .patCap:
            say("patCap", band: nil, kind: nil, level: nil, fact: "")

        case .decor:
            effects.play(.celebrate, value: 0, source: -1)
            let name = event.decor.flatMap { PiboCoreDecorID(rawValue: Int32($0)) }
                .map(GrowthPresentation.decorName) ?? ""
            say("decorPlaced", band: nil, kind: event.decor, level: nil, fact: name)

        case .star:
            effects.play(.starWish, value: Double(event.xp ?? 0), source: -1)
            say("starWish", band: nil, kind: nil, level: nil, fact: "")

        case .anniversary:
            effects.play(.celebrate, value: 0, source: -1)
            say("anniversary", band: nil, kind: nil, level: event.day,
                fact: "第 \(event.day ?? 0) 天")

        case .morningSleep:
            say("morningSleep", band: event.band, kind: nil, level: nil, fact: "")

        default:
            break
        }
    }

    // MARK: - Lines

    private func line(_ event: String, band: Int? = nil, kind: Int? = nil,
                      level: Int? = nil) -> String? {
        guard let catalog, let deps = dependencies else { return nil }
        let growth = deps.growth()
        return catalog.select(
            GrowthCopyQuery(
                event: event,
                tone: growth.tone,
                band: band,
                kind: kind,
                level: level,
                values: ["day": "\(deps.dayCount())", "level": "\(growth.level)"]
            ),
            cursors: growth
        )
    }

    private func say(_ event: String, band: Int?, kind: Int?, level: Int?, fact: String) {
        guard let deps = dependencies, let text = line(event, band: band, kind: kind, level: level) else {
            return
        }
        var line = PiboSpeechLine(text: text, lingerDuration: Self.lineLinger)
        if !fact.isEmpty { line.fact = fact }
        deps.speech().show(line)
    }

    // MARK: - Home hooks

    /// After the pat flow ran: show "+n" if that pat earned experience.
    func afterPat() {
        guard let deps = dependencies, let at = deps.coordinator().lastAwardAt,
              Date().timeIntervalSince(at) < Self.patPopWindow else { return }
        stageEffects.play(.xpPop, value: Double(deps.coordinator().lastAwardXP), source: -1)
    }

    /// A tap on a source row: Pibo explains where that energy came from.
    func explainSource(_ source: Int) {
        guard let deps = dependencies else { return }
        let split = deps.growth().todaySplit
        let values = [split.sleep, split.steps, split.activity]
        let value = values.indices.contains(source) ? Int(values[source].rounded()) : 0
        say("sourceInfo", band: value >= 1 ? 1 : 0, kind: source, level: nil,
            fact: "\(GrowthPresentation.sourceName(source)) +\(value)")
    }

    func onBoProgressMessage(_ message: String) {
        dependencies?.speech().show(PiboSpeechLine(text: message, lingerDuration: Self.shootLinger))
    }

    func onDecorTapped(_ id: Int) {
        guard dependencies != nil,
              PiboCoreDecorID(rawValue: Int32(id)) != nil else { return }
        say("decorTapped", band: nil, kind: id, level: nil, fact: "")
    }

    /// A shared-first marker: Pibo remembers it, with the relationship day as the fact.
    func onFirstMarkerTapped(kind: Int, day: Int) {
        guard (0...3).contains(kind) else { return }
        say("firstMarker", band: nil, kind: kind, level: nil, fact: day > 0 ? "第 \(day) 天" : "")
    }

    @discardableResult
    func purchase(_ id: PiboCoreDecorID) -> Bool {
        guard let deps = dependencies else { return false }
        let growth = deps.growth()
        guard deps.decor().purchase(id, level: growth.level, ledger: deps.ledger()) else {
            return false
        }
        growth.push(GrowthFeedbackEvent(kind: .decor, id: "", decor: Int(id.rawValue)))
        return true
    }

    func shootingStarDue(isNight: Bool) -> Bool {
        guard let deps = dependencies else { return false }
        let growth = deps.growth()
        let nowSeconds = Int64(Date().timeIntervalSince1970.rounded(.down))
        guard PiboCoreGrowth.shootingStarDue(
            seed: UInt64(max(0, deps.dayCount())) * 7919,
            isNight: isNight,
            nowSeconds: nowSeconds,
            lastStarSeconds: Int64(growth.lastStarAt)
        ) else { return false }
        growth.markStarShown(nowSeconds: Double(nowSeconds))
        return true
    }

    func onShootingStarCaught() {
        _ = dependencies?.coordinator().onShootingStar()
        Analytics.track(.shootingStarCaught, screen: "home")
    }

    func onShake(peakAcceleration: Double) {
        guard let deps = dependencies else { return }
        let now = Date()
        let since = lastShakeAt.map { now.timeIntervalSince($0) } ?? 1e9
        guard PiboCoreGrowth.shakeDetected(peakAcceleration: peakAcceleration,
                                           secondsSinceLast: since) else { return }
        guard !deps.overlayOpen() else { return }
        lastShakeAt = now
        Analytics.track(.deviceShake, screen: "home")
        stageEffects.play(.dizzy, value: 0, source: -1)
        if deps.speech().line == nil { say("shake", band: nil, kind: nil, level: nil, fact: "") }
    }

    /// Which workout Pibo imitates now, if Core says the moment is still fresh.
    func mimic() -> Int {
        guard let deps = dependencies, let ended = deps.lastWorkoutEndedAt() else { return 0 }
        // A stable per-workout roll, so the decision does not flicker between renders.
        let seconds = ended.timeIntervalSince1970.rounded(.down)
        let roll = Double(UInt32(truncatingIfNeeded: Int64(seconds) &* 2_654_435_761)) / 4_294_967_296
        guard PiboCoreGrowth.mimicActive(secondsSinceWorkout: Date().timeIntervalSince(ended),
                                         roll: roll) else { return 0 }
        switch deps.lastWorkoutKind() {
        case "run", "walk": return PiboPixelMimic.run.rawValue
        case "swim": return PiboPixelMimic.swim.rawValue
        case "cycle": return PiboPixelMimic.bike.rawValue
        case "yoga": return PiboPixelMimic.yoga.rawValue
        default: return PiboPixelMimic.generic.rawValue
        }
    }

    // MARK: - Debug

    /// Debug dock: plays one growth moment with demo values. Nothing is queued, awarded or
    /// persisted except the copy rotation cursor.
    func debugRun(_ id: String) -> String {
        guard let deps = dependencies else { return "成长未就绪" }
        let growth = deps.growth()
        let now = Date()
        busyUntil = .distantPast
        switch id {
        case "growth:away":
            present(GrowthFeedbackEvent(kind: .away, id: "debug", sleep: 30, steps: 42,
                                        activity: 8, dominant: 1, xp: 80), now: now, preview: true)
            return "已播放离开摘要"
        case "growth:level":
            let level = min(30, growth.level + 1)
            present(GrowthFeedbackEvent(kind: .level, id: "debug", level: level),
                    now: now, preview: true)
            return "已播放升级 Lv.\(level)"
        case "growth:heart":
            present(GrowthFeedbackEvent(kind: .heart, id: "debug", hearts: growth.hearts),
                    now: now, preview: true)
            return "已播放多一颗心"
        case "growth:tone":
            present(GrowthFeedbackEvent(kind: .heart, id: "debug", hearts: growth.hearts,
                                        toneUnlocked: true), now: now, preview: true)
            return "语气档 \(growth.tone)"
        case "growth:wish":
            present(GrowthFeedbackEvent(kind: .wish, id: "debug", wish: 0, xp: 15),
                    now: now, preview: true)
            return "已播放心愿盖章"
        case "growth:patcap":
            present(GrowthFeedbackEvent(kind: .patCap, id: "debug"), now: now, preview: true)
            return "已播放拍一拍上限"
        case "growth:star":
            present(GrowthFeedbackEvent(kind: .star, id: "debug", xp: 5), now: now, preview: true)
            return "已播放流星许愿"
        case "growth:anniversary":
            present(GrowthFeedbackEvent(kind: .anniversary, id: "debug", day: 7),
                    now: now, preview: true)
            return "已播放第 7 天纪念日"
        case "growth:morning":
            let band = debugMorningBand
            debugMorningBand = (band + 1) % 3
            present(GrowthFeedbackEvent(kind: .morningSleep, id: "debug", band: band),
                    now: now, preview: true)
            return "早晨睡眠 band=\(band)"
        case "growth:shake":
            stageEffects.play(.dizzy, value: 0, source: -1)
            say("shake", band: nil, kind: nil, level: nil, fact: "")
            return "已播放摇一摇"
        case "growth:polaroid":
            printPolaroid(now)
            return "正在冲印今天的拍立得（会真的存一张）"
        case "growth:decor":
            deps.decor().debugShowAll.toggle()
            return deps.decor().debugShowAll ? "装饰全部预览中（再点一次收起）" : "已收起装饰预览"
        default:
            return "未知成长调试项"
        }
    }

    // MARK: - Daily polaroid

    private func maybePolaroid(_ now: Date) {
        guard let deps = dependencies, !printing,
              now.timeIntervalSince(homeSince) >= Self.polaroidSettle else { return }
        let hour = Calendar.current.component(.hour, from: now)
        guard PiboCoreGrowth.polaroidDue(localHour: hour,
                                         takenToday: deps.polaroids().takenToday(now)) else { return }
        printPolaroid(now)
    }

    @discardableResult
    func printPolaroid(_ now: Date = .now) -> Bool {
        guard let deps = dependencies, let snapshot = stageEffects.snapshot() else { return false }
        printing = true
        defer { printing = false }
        guard let shot = deps.polaroids().take(snapshot, caption: line("polaroid") ?? "", now: now) else {
            return false
        }
        stageEffects.play(.celebrate, value: 0, source: -1)
        polaroid = shot
        revision += 1
        if !deps.overlayOpen() { polaroidVisible = true }
        busyUntil = Date().addingTimeInterval(1.5)
        return true
    }

    func openPolaroid(_ shot: PolaroidShot) {
        polaroid = shot
        revision += 1
        polaroidVisible = true
    }

    func closePolaroid() {
        polaroidVisible = false
    }

    func closeLevelUp() {
        levelUpVisible = false
    }
}
