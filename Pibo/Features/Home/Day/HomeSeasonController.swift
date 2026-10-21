import Foundation
import os
import PiboCore

// Season one, 落脚 (decision 059), and season two, 小溪那边 (decision 062). Core says which
// beat is due and how far the seed has grown; this class stages each beat on the day
// director — walk there, act it out, slip inside the pod, say the line — and remembers
// what happened in `PiboSeasonStore`.
//
// Ported from HarmonyPibo `services/day/HomeSeasonController.ets`.

private let storyCopyResource = "pibo-story.zh-Hans"
/// Planks the creek bridge needs before it reaches the far bank.
let PIBO_SEASON_TWO_PLANKS = 5
/// Season two's letter from home (beat seven): a fixed text outside the rotation.
private let seasonTwoLetter = 20
/// The letters that arrive between seasons are kinds 1… in the story copy; kind 0 answers
/// the first report.
private let firstEchoLetter = 1
private let seasonTwoThread = "season2"
private let seasonOneThread = "season1"

/// One page of Pibo's paper for the sheet: the report, a letter, or the old notebook.
final class PiboStoryPaper {
    var title = ""
    var lines: [String] = []
    var signature = ""
    var letter = false
    /// A find drawn at the top instead (the old notebook); −1 uses `letter`.
    var icon = -1
    /// Lines crossed out.
    var struck: [Int] = []
}

/// What a plank trip is bringing back.
private enum PlankTrip {
    case none
    case first
    case plank
}

/// What a season beat needs from Home. Every closure is read when the beat needs it.
@MainActor
struct HomeSeasonHost {
    var director: () -> PixelDayDirector
    var layout: () -> PixelForestLayout?
    var scene: () -> Int
    var tone: () -> PiboCoreGrowthTone
    var cursors: () -> GrowthCopyCursorStore
    var dayCount: () -> Int
    /// The forest's hour (debug overrides included), for night beats.
    var hour: () -> Double
    /// Every `bo` collected so far, for how far the seed has grown.
    var boCollected: () -> Int
    /// [steps band, sleep band] from Core's body cues; −1 unknown.
    var bodyBands: () -> [Int]
    /// Pibo is awake, nothing covers Home and no scripted moment is playing.
    var canStage: () -> Bool
    /// Core's attention budget: true (and counted) when a beat may play now.
    var claim: () -> Bool
    /// A beat is due on this entry; the companion's return line steps aside.
    var setWaiting: (Bool) -> Void
    var speak: (String) -> Void
    /// Shows the report, a letter or the old notebook.
    var showStoryPaper: (PiboStoryPaper) -> Void
    /// The story things changed (the seed went in, the antenna stood up, a letter came).
    var changed: () -> Void
    /// Season two: Core's life flags (what in your recent days can prove the notebook wrong).
    var lifeFlags: () -> UInt32
    /// A story moment Pibo feels something about (decision 060).
    var feel: (PiboCoreEmoteTrigger) -> Void
    /// The beat was told: the recap threads (`piboTimelineStore`) mark it here. A no-op
    /// until the iOS timeline store lands.
    var onBeatTold: (_ thread: String, _ beat: Int) -> Void = { _, _ in }
}

/// Letters are fixed texts: no rotation cursor.
@MainActor
private final class SeasonFixedCursor: GrowthCopyCursorStore {
    func copyCursor(key: String) -> Int { 0 }
    func setCopyCursor(key: String, cursor: Int) {}
}

@MainActor
final class HomeSeasonController: HomeSeasonStaging {
    private var catalog: GrowthCopyCatalog?
    private var host: HomeSeasonHost?
    private var playing = false
    /// The beat the lost screw is carried back for, set when the trip leaves.
    private var screwTrip = false
    private var plankTrip: PlankTrip = .none
    private(set) var paper = PiboStoryPaper()

    private let store: PiboSeasonStore

    init(store: PiboSeasonStore) {
        self.store = store
    }

    func bind(_ host: HomeSeasonHost) {
        self.host = host
    }

    func loadCatalog(bundle: Bundle = .main) {
        do {
            catalog = try GrowthCopyCatalog.bundled(bundle: bundle, resource: storyCopyResource)
        } catch {
            LPLog.day.error("story copy unavailable: \(String(describing: error), privacy: .public)")
            catalog = nil
        }
    }

    // --- What the stage shows ----------------------------------------------------------

    var podFixed: Bool { store.podFixed }

    func sproutStage() -> Int { sproutStage(nowMs()) }

    func sproutStage(_ now: Double) -> Int {
        if store.plantedDay < 0 { return 0 }
        let since = max(0, (host?.boCollected() ?? 0) - store.boAtPlanting)
        return PiboCoreSeason.sproutStage(daysSincePlanted: piboLocalDay(now) - store.plantedDay,
                                          boCollected: UInt32(clamping: since))
    }

    /// 0 no mailbox, 1 empty, 2 a letter waiting.
    var mailbox: Int {
        if !store.hasMailbox { return 0 }
        return store.unreadLetter != nil ? 2 : 1
    }

    var performing: Bool { playing }

    // Season two's things, as the stage draws them.
    var planks: Int { store.planks }

    /// 0 not found, 1 found in the moss, 2 its lamp works again.
    var oldPod: Int {
        store.oldPodLit ? 2 : (store.oldPodFound ? 1 : 0)
    }

    var farLight: Bool { store.farLight }

    private var seasonOneDone: Bool { store.completedBeats >= PiboCoreSeason.beatCount }

    // --- Beats --------------------------------------------------------------------------

    private func facts(_ trigger: PiboCoreSeasonTrigger, _ now: Double) -> PiboCoreSeasonFacts {
        var facts = PiboCoreSeasonFacts()
        facts.completedBeats = store.completedBeats
        facts.lastBeatDay = store.lastBeatDay
        facts.today = piboLocalDay(now)
        facts.dayCount = host?.dayCount() ?? 0
        let hour = max(0, Int(floor(host?.hour() ?? 12)))
        let date = Date(timeIntervalSince1970: now / 1000)
        let minute = Calendar.current.component(.minute, from: date)
        facts.localMinute = hour * 60 + (hour == Calendar.current.component(.hour, from: date) ? minute : 0)
        facts.trigger = trigger
        facts.plantedDay = store.plantedDay
        facts.boCollectedSincePlanting = UInt32(clamping: max(0, (host?.boCollected() ?? 0) - store.boAtPlanting))
        return facts
    }

    /// Home is open: play the beat Core says is due, once the stage is free and the budget
    /// allows. Called when Home opens and on every day tick, so a beat held back by the
    /// daily guide or a bubble plays as soon as it can.
    func check(_ now: Double = Date().timeIntervalSince1970 * 1000) {
        guard let host, catalog != nil, !playing else { return }
        if seasonOneDone {
            checkTwo(now)
            return
        }
        guard host.scene() == Int(PiboCoreDayScene.clearing.rawValue), host.layout() != nil else {
            host.setWaiting(false)
            return
        }
        let decision: PiboCoreSeasonBeatDecision
        do {
            decision = try seasonDecision { PiboCoreSeason.nextBeat(facts(.homeOpen, now)) }
        } catch {
            LPLog.day.error("season beat failed: \(String(describing: error), privacy: .public)")
            return
        }
        let beat = decision.beat
        if beat == .none {
            host.setWaiting(false)
            checkLetter(now)
            return
        }
        host.setWaiting(true)
        guard host.canStage(), host.claim() else { return }
        let fallbackBeat = fallback(decision)
        if stage(beat, fallbackBeat, now) {
            host.setWaiting(false)
            LPLog.day.info("season beat=\(beat.rawValue, privacy: .public) fallback=\(fallbackBeat, privacy: .public)")
        }
    }

    /// Core's rules cannot fail in practice; this keeps a bad record from taking Home down.
    private func seasonDecision(_ run: () -> PiboCoreSeasonBeatDecision) throws -> PiboCoreSeasonBeatDecision {
        run()
    }

    private func fallback(_ decision: PiboCoreSeasonBeatDecision) -> Bool {
        decision.variant == .fallback
    }

    /// A trip is leaving. Returns the lost screw (season one) or a bridge plank (season two)
    /// when Core says this trip brings it back.
    func exploreItem(_ item: Int, _ now: Double = Date().timeIntervalSince1970 * 1000) -> Int {
        guard host != nil, catalog != nil else { return item }
        if seasonOneDone { return exploreItemTwo(item, now) }
        let decision = PiboCoreSeason.nextBeat(facts(.exploreReturn, now))
        if decision.beat == .lostScrew && !fallback(decision) {
            screwTrip = true
            return PIXEL_STORY_SCREW
        }
        return item
    }

    /// Back from a trip with a plank under its arm.
    func plankBack() {
        guard let host, plankTrip != .none else { return }
        let trip = plankTrip
        plankTrip = .none
        _ = host.claim()
        let now = Date().timeIntervalSince1970 * 1000
        if trip == .first {
            _ = stageTwo(.firstPlank, false, now, interrupt: true)
        } else {
            _ = stagePlank(found: false, now, interrupt: true)
        }
    }

    /// Back from the trip with the screw in hand: fix the antenna.
    func screwBack() {
        guard let host, screwTrip else { return }
        screwTrip = false
        _ = host.claim()
        _ = stage(.lostScrew, false, Date().timeIntervalSince1970 * 1000, interrupt: true)
    }

    @discardableResult
    private func stage(_ beat: PiboCoreSeasonBeat, _ fallback: Bool, _ now: Double,
                       interrupt: Bool = false) -> Bool {
        guard let host, let layout = host.layout() else { return false }
        let today = piboLocalDay(now)
        let pod = pixelSeasonSpot(layout, PIXEL_SEASON_POD)
        let seed = pixelSeasonSpot(layout, PIXEL_SEASON_SPROUT)
        let mail = pixelSeasonSpot(layout, PIXEL_SEASON_MAILBOX)
        let bounds = pixelWalkBounds(layout, .clearing)
        let front = [Int((Double(layout.width) / 2).rounded()), min(layout.groundY + 22, bounds.maxY)]
        // Beside the pod's door, in the open, where it writes and waves.
        let side = [pod[0] + 20, min(pod[1] + 6, bounds.maxY)]
        let antenna = pixelSeasonAntennaSpot(layout)
        func line(_ event: String, _ kind: Int, _ band: Int? = nil) -> PixelStoryStep {
            pixelStoryCall { [weak self] in self?.say(event, kind, band) }
        }
        func done() -> PixelStoryStep {
            pixelStoryCall { [weak self] in self?.complete(beat, today) }
        }
        var steps: [PixelStoryStep] = []
        switch beat {
        case .tiltedPod:
            steps = [
                pixelStoryWalk(Double(pod[0]), Double(pod[1])),
                pixelStoryInside(1600),
                pixelStoryAct(.patPod, 1600, facing: 1),
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                pixelStoryAct(.beckon, 600),
                done(),
                line("beat", 1),
                pixelStoryAct(.beckon, 2400),
            ]
        case .planting:
            steps = [
                pixelStoryWalk(Double(pod[0]), Double(pod[1])),
                pixelStoryInside(2200, carry: PIXEL_STORY_SEED),
                pixelStoryWalk(Double(seed[0]), Double(seed[1])),
                line("beat", 2),
                pixelStoryAct(.dig, 2600, facing: 1, carry: -1),
                pixelStoryCall { [weak self, bo = host.boCollected()] in
                    self?.store.plant(today: today, boLifetime: bo)
                    self?.host?.changed()
                },
                done(),
                pixelStoryAct(.patPod, 1200, facing: 1),
                line("beatAfter", 2),
                pixelStoryAct(.crouch, 1800, facing: 1),
            ]
        case .dimStar:
            steps = [
                pixelStoryWalk(Double(front[0]), Double(front[1])),
                line("beat", 3, fallback ? 1 : 0),
                pixelStoryAct(.point, 4800, facing: -1),
                done(),
            ]
        case .lostScrew:
            if fallback {
                steps = [
                    pixelStoryWalk(Double(side[0] + 8), Double(min(side[1] + 6, bounds.maxY))),
                    pixelStoryAct(.crouch, 1400, facing: -1),
                    pixelStoryAct(.beckon, 300, facing: 0, carry: PIXEL_STORY_SCREW),
                    line("beat", 4, 1),
                ]
            } else {
                steps = [line("beat", 4, 0),
                         pixelStoryAct(.beckon, 1800, facing: 0, carry: PIXEL_STORY_SCREW)]
            }
            steps += [
                pixelStoryWalk(Double(antenna[0]), Double(antenna[1])),
                pixelStoryAct(.reach, 2600, facing: -1, carry: -1),
                done(),
                pixelStoryAct(.beckon, 800),
                line("beatAfter", 4),
                pixelStoryAct(.beckon, 1600),
                // Decision 062: the badge's lens was loose too; with the pod fixed it stops cracking.
                line("badgeFixed", 4),
                pixelStoryAct(.beckon, 1600),
            ]
        case .firstReport:
            steps = [
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                pixelStoryAct(.write, 4200, facing: -1, carry: PIXEL_STORY_REPORT),
                pixelStoryWalk(Double(antenna[0]), Double(antenna[1])),
                pixelStoryAct(.reach, 1800, facing: -1, carry: -1),
                pixelStoryCall { [weak self] in self?.writeReport() },
                done(),
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                line("beat", 5),
                pixelStoryAct(.beckon, 2400),
            ]
        case .mailbox:
            steps = [
                pixelStoryCall { [weak self] in
                    self?.store.receiveLetter(0, today: today)
                    self?.host?.changed()
                },
                done(),
                pixelStoryAct(.point, 900, facing: -1),
                pixelStoryWalk(Double(mail[0]), Double(mail[1]), gait: .run),
                line("beat", 6),
                pixelStoryAct(.beckon, 3000),
            ]
        case .firstLeaf:
            steps = [
                pixelStoryWalk(Double(seed[0]), Double(seed[1])),
                pixelStoryAct(.crouch, 4200, facing: 1, carry: PIXEL_STORY_LETTER),
                pixelStoryAct(.dig, 900, facing: 1, carry: -1),
                done(),
                line("beat", 7),
                pixelStoryAct(.crouch, 2600, facing: 1),
            ]
        default:
            return false
        }
        steps.append(pixelStoryCall { [weak self] in self?.playing = false })
        guard host.director().perform(steps, interrupt: interrupt) else { return false }
        playing = true
        return true
    }

    private func complete(_ beat: PiboCoreSeasonBeat, _ today: Int) {
        store.completeBeat(Int(beat.rawValue), today: today)
        host?.onBeatTold(seasonOneThread, Int(beat.rawValue))
        if Int(beat.rawValue) >= PiboCoreSeason.beatCount {
            store.finishSeason(today: today)
            host?.onBeatTold(seasonOneThread, 0)
        }
        host?.changed()
    }

    /// Between seasons: a letter now and then, on Core's rhythm. Pibo mentions it only when
    /// the budget allows; the raised flag says it either way. Letters pause while season two
    /// runs (Core's anchor is −1 then).
    private func checkLetter(_ now: Double) {
        guard let host else { return }
        let today = piboLocalDay(now)
        let anchor = PiboCoreSeason.letterAnchor(seasonOneDoneDay: store.seasonDoneDay,
                                                 seasonTwoCompleted: store.twoCompleted > 0,
                                                 seasonTwoDoneDay: store.twoDoneDay)
        guard PiboCoreSeason.letterDue(seasonDoneDay: anchor, lastLetterDay: store.lastLetterDay, today: today)
        else { return }
        let echoes = letterCount() - firstEchoLetter
        if echoes <= 0 { return }
        let index = firstEchoLetter + PiboCoreSeason.letterIndex(lettersReceived: max(0, store.lettersReceived - 1),
                                                                 count: echoes)
        store.receiveLetter(index, today: today)
        host.changed()
        LPLog.day.info("season letter=\(index, privacy: .public)")
        if host.canStage() && host.claim() { say("letterArrived", -1) }
    }

    private func letterCount() -> Int {
        var count = 0
        while count < 32 && text("letter", count, nil, rotate: false) != nil { count += 1 }
        return count
    }

    /// Debug dock: play a beat now (spacing and conditions skipped), a letter, or start over.
    @discardableResult
    func debugRun(_ id: String) -> String {
        guard let host, catalog != nil else { return "第一季未就绪" }
        let now = Date().timeIntervalSince1970 * 1000
        if id == "season:reset" {
            store.reset()
            host.changed()
            return "第一季已清空"
        }
        if id == "season:letter" {
            let echoes = letterCount() - firstEchoLetter
            store.receiveLetter(firstEchoLetter + store.lettersReceived % max(1, echoes),
                                today: piboLocalDay(now))
            host.changed()
            return "信箱来了一封信"
        }
        if id.hasPrefix("season2:") { return debugRunTwo(id) }
        let beat = Int(id.replacingOccurrences(of: "season:beat-", with: "")) ?? -1
        guard beat >= 1, beat <= PiboCoreSeason.beatCount,
              let seasonBeat = PiboCoreSeasonBeat(rawValue: Int32(beat)) else { return "未知节拍" }
        if playing || host.scene() != Int(PiboCoreDayScene.clearing.rawValue) {
            return "先回到空地，等 Pibo 空下来"
        }
        store.debugRewind(beat: beat, today: piboLocalDay(now))
        host.changed()
        // The lost screw plays its at-home version: a trip cannot be summoned.
        return stage(seasonBeat, seasonBeat == .lostScrew, now) ? "正在播放第 \(beat) 拍" : "Pibo 正忙，稍后再试"
    }

    // --- Taps on the story things -------------------------------------------------------

    /// Returns true when the tap was a story thing's.
    func onTapped(_ place: Int) -> Bool {
        guard let host else { return false }
        switch place {
        case PIXEL_SEASON_POD:
            if store.hasNotebook {
                openNotebook()
            } else if !store.report.isEmpty {
                openReport()
            } else {
                say("podTap", store.podFixed ? 1 : 0)
            }
            return true
        case PIXEL_SEASON_OLD_POD:
            say("oldPodTap", store.oldPodLit ? 1 : 0)
            return true
        case PIXEL_SEASON_SPROUT:
            let stage = sproutStage()
            if !playing, let layout = host.layout(), host.canStage() {
                let seed = pixelSeasonSpot(layout, PIXEL_SEASON_SPROUT)
                _ = host.director().perform([
                    pixelStoryWalk(Double(seed[0]), Double(seed[1])),
                    pixelStoryAct(.crouch, 600, facing: 1),
                    pixelStoryCall { [weak self] in self?.say("sproutTap", stage) },
                    pixelStoryAct(.crouch, 2000, facing: 1),
                ])
            } else {
                say("sproutTap", stage)
            }
            return true
        case PIXEL_SEASON_MAILBOX:
            openLetter()
            return true
        default:
            return false
        }
    }

    private func openReport() {
        let page = PiboStoryPaper()
        page.title = "第一份报告"
        page.lines = store.report
        page.signature = "—— Pibo"
        paper = page
        host?.showStoryPaper(page)
    }

    private func openLetter() {
        guard let letter = store.unreadLetter ?? store.latestLetter else { return }
        let body = text("letter", letter.index, nil, rotate: false) ?? ""
        if !letter.read && letter.index == seasonTwoLetter { host?.feel(.letter) }
        let page = PiboStoryPaper()
        page.title = "家里的来信"
        page.lines = body.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        page.signature = "—— 引路者"
        page.letter = true
        paper = page
        store.markLettersRead()
        host?.changed()
        host?.showStoryPaper(page)
    }

    /// The report: what Pibo saw of Earth, of the forest and, only in words, of you.
    private func writeReport() {
        let bands = host?.bodyBands() ?? []
        let steps = bands.count > 0 ? bands[0] : -1
        let sleep = bands.count > 1 ? bands[1] : -1
        var you = 3
        if steps == 2 {
            you = 0
        } else if sleep == 2 {
            you = 2
        } else if steps == 0 {
            you = 1
        } else if steps >= 0 || sleep >= 0 {
            you = 4
        }
        let lines = [text("reportEarth", -1), text("reportForest", -1), text("reportYou", -1, you)]
            .compactMap { $0 }
        store.writeReport(lines)
    }

    // --- Season two, 小溪那边 -------------------------------------------------------------

    private func factsTwo(_ trigger: PiboCoreSeasonTrigger, _ now: Double) -> PiboCoreSeasonTwoFacts {
        var facts = PiboCoreSeasonTwoFacts()
        facts.completedBeats = store.twoCompleted
        facts.lastBeatDay = store.twoLastBeatDay
        facts.today = piboLocalDay(now)
        let hour = max(0, Int(floor(host?.hour() ?? 12)))
        let date = Date(timeIntervalSince1970: now / 1000)
        let minute = Calendar.current.component(.minute, from: date)
        facts.localMinute = hour * 60 + (hour == Calendar.current.component(.hour, from: date) ? minute : 0)
        facts.trigger = trigger
        facts.seasonOneDoneDay = store.seasonDoneDay
        facts.planks = store.planks
        facts.lastPlankDay = store.lastPlankDay
        facts.corrections = store.pages.count
        return facts
    }

    /// Beats that happen by the creek can be staged from the clearing too (Pibo walks off to
    /// the creek and comes back); the rest need the clearing.
    private func sceneFits(_ beat: PiboCoreSeasonBeat, _ scene: Int) -> Bool {
        if scene == Int(PiboCoreDayScene.clearing.rawValue) { return true }
        return scene == Int(PiboCoreDayScene.creek.rawValue) && (beat == .firstPlank || beat == .crossing)
    }

    private func checkTwo(_ now: Double) {
        guard let host else { return }
        let scene = host.scene()
        guard host.layout() != nil else { return }
        let facts = factsTwo(.homeOpen, now)
        if PiboCoreSeason.twoPlankDue(facts) {
            // No trip for a few days: a plank has washed up by the stones.
            host.setWaiting(true)
            guard sceneFits(.firstPlank, scene), host.canStage(), host.claim() else { return }
            if stagePlank(found: true, now) { host.setWaiting(false) }
            return
        }
        let decision = PiboCoreSeason.nextTwoBeat(facts)
        let beat = decision.beat
        if beat == .none {
            host.setWaiting(false)
            if scene == Int(PiboCoreDayScene.clearing.rawValue) {
                checkLetter(now)
                checkReread(now)
            }
            return
        }
        guard sceneFits(beat, scene) else {
            host.setWaiting(false)
            return
        }
        host.setWaiting(true)
        guard host.canStage(), host.claim() else { return }
        let fallbackBeat = fallback(decision)
        if stageTwo(beat, fallbackBeat, now) {
            host.setWaiting(false)
            LPLog.day.info("season two beat=\(beat.rawValue, privacy: .public) fallback=\(fallbackBeat, privacy: .public)")
        }
    }

    private func exploreItemTwo(_ item: Int, _ now: Double) -> Int {
        let facts = factsTwo(.exploreReturn, now)
        let decision = PiboCoreSeason.nextTwoBeat(facts)
        if decision.beat == .firstPlank && !fallback(decision) {
            plankTrip = .first
            return PIXEL_STORY_PLANK
        }
        if PiboCoreSeason.twoPlankDue(facts) {
            plankTrip = .plank
            return PIXEL_STORY_PLANK
        }
        return item
    }

    /// Off to the creek and back, from the clearing: out through the left edge, a while out
    /// of sight doing `away` there, and back in to `back`.
    private func viaEdge(_ layout: PixelForestLayout, awayMs: Double, back: [Int],
                         carryBack: Int = -2, away: @escaping () -> Void = {}) -> [PixelStoryStep] {
        let edgeY = pixelEdgeY(layout, .clearing)
        return [
            pixelStoryWalk(-24, Double(edgeY)),
            pixelStoryAct(.none, awayMs, facing: -1, carry: carryBack),
            pixelStoryCall(away),
            pixelStoryWalk(Double(back[0]), Double(back[1])),
        ]
    }

    /// A plank comes home (from a trip, or washed up when `found`) and goes onto the bridge.
    @discardableResult
    private func stagePlank(found: Bool, _ now: Double, interrupt: Bool = false) -> Bool {
        guard let host, let layout = host.layout() else { return false }
        let today = piboLocalDay(now)
        let next = min(PIBO_SEASON_TWO_PLANKS, store.planks + 1)
        let nail = { [weak self] in
            self?.store.addPlank(today)
            self?.host?.changed()
        }
        let steps = plankSteps(layout, found: found, nail: nail, event: "plank", kind: next,
                               band: found ? 1 : 0)
        return run(steps, interrupt)
    }

    /// Bringing a plank and nailing it on: at the creek it is done in front of you; from the
    /// clearing Pibo shows it, walks off to the creek and comes back.
    private func plankSteps(_ layout: PixelForestLayout, found: Bool, nail: @escaping () -> Void,
                            event: String, kind: Int, band: Int) -> [PixelStoryStep] {
        guard let host else { return [] }
        func line(_ event: String, _ kind: Int, _ band: Int? = nil) -> PixelStoryStep {
            pixelStoryCall { [weak self] in self?.say(event, kind, band) }
        }
        let front = frontSpot(layout)
        if host.scene() == Int(PiboCoreDayScene.creek.rawValue) {
            let work = pixelBridgeWorkSpot(layout, store.planks)
            let pick: [PixelStoryStep] = found ? [
                pixelStoryWalk(Double(pixelBridgeX(layout) + 18), Double(pixelCreekBand(layout)[0] - 4)),
                pixelStoryAct(.crouch, 1200, facing: -1),
                pixelStoryAct(.beckon, 300, facing: 0, carry: PIXEL_STORY_PLANK),
            ] : [pixelStoryAct(.beckon, 900, facing: 0, carry: PIXEL_STORY_PLANK)]
            return pick + [
                line(event, kind, band),
                pixelStoryWalk(Double(work[0]), Double(work[1])),
                pixelStoryAct(.hammer, 2600, facing: 1, carry: -1),
                pixelStoryCall(nail),
                pixelStoryAct(.beckon, 1600),
            ]
        }
        let fetch: [PixelStoryStep] = found
            ? viaEdge(layout, awayMs: 2200, back: front, carryBack: PIXEL_STORY_PLANK)
            : [pixelStoryAct(.beckon, 900, facing: 0, carry: PIXEL_STORY_PLANK)]
        return fetch + [
            pixelStoryAct(.beckon, 600),
            line(event, kind, band),
        ] + viaEdge(layout, awayMs: 2600, back: front, carryBack: -1, away: nail) + [
            pixelStoryAct(.beckon, 1400),
        ]
    }

    private func frontSpot(_ layout: PixelForestLayout) -> [Int] {
        guard let host else { return [layout.width / 2, layout.groundY] }
        let scene = PiboCoreDayScene(rawValue: Int32(host.scene())) ?? .clearing
        let bounds = pixelWalkBounds(layout, scene)
        let offset = host.scene() == Int(PiboCoreDayScene.creek.rawValue) ? 6 : 22
        return [Int((Double(layout.width) / 2).rounded()), min(layout.groundY + offset, bounds.maxY)]
    }

    @discardableResult
    private func stageTwo(_ beat: PiboCoreSeasonBeat, _ fallback: Bool, _ now: Double,
                          interrupt: Bool = false) -> Bool {
        guard let host, let layout = host.layout() else { return false }
        let today = piboLocalDay(now)
        let pod = pixelSeasonSpot(layout, PIXEL_SEASON_POD)
        let mail = pixelSeasonSpot(layout, PIXEL_SEASON_MAILBOX)
        let bounds = pixelWalkBounds(layout, .clearing)
        let side = [pod[0] + 20, min(pod[1] + 6, bounds.maxY)]
        let antenna = pixelSeasonAntennaSpot(layout)
        let front = frontSpot(layout)
        func line(_ event: String, _ kind: Int, _ band: Int? = nil) -> PixelStoryStep {
            pixelStoryCall { [weak self] in self?.say(event, kind, band) }
        }
        func done() -> PixelStoryStep {
            pixelStoryCall { [weak self] in self?.completeTwo(beat, today) }
        }
        var steps: [PixelStoryStep] = []
        switch beat {
        case .otherLight:
            steps = [
                pixelStoryWalk(Double(antenna[0]), Double(antenna[1])),
                pixelStoryAct(.point, 1400, facing: 1),
                done(),
                line("beat", Int(beat.rawValue), fallback ? 1 : 0),
                pixelStoryAct(.point, 3600, facing: 1),
                pixelStoryAct(.beckon, 1400),
            ]
        case .firstPlank:
            let nail = { [weak self] in
                self?.store.addPlank(today)
                self?.host?.changed()
            }
            steps = plankSteps(layout, found: fallback, nail: nail, event: "beat",
                               kind: Int(beat.rawValue), band: fallback ? 1 : 0) + [
                done(),
                line("beatAfter", Int(beat.rawValue),
                     host.scene() == Int(PiboCoreDayScene.creek.rawValue) ? 0 : 1),
            ]
        case .crossing:
            if host.scene() == Int(PiboCoreDayScene.creek.rawValue) {
                let there = pixelOldPodSpot(layout)
                host.director().setBridge(true)
                steps = [
                    pixelStoryWalk(Double(pixelBridgeX(layout)), Double(pixelCreekBand(layout)[0] - 3)),
                    pixelStoryAct(.beckon, 900),
                    pixelStoryWalk(Double(there[0]), Double(there[1])),
                    done(),
                    pixelStoryAct(.crouch, 2400, facing: 1),
                    line("beat", Int(beat.rawValue), 0),
                    pixelStoryAct(.patPod, 1800, facing: 1),
                    pixelStoryWalk(Double(front[0]), Double(front[1])),
                    pixelStoryAct(.beckon, 1400),
                ]
            } else {
                steps = [pixelStoryAct(.beckon, 800)] + viaEdge(layout, awayMs: 5200, back: front) {
                    [weak self] in self?.completeTwo(beat, today)
                } + [
                    line("beat", Int(beat.rawValue), 1),
                    pixelStoryAct(.beckon, 2400),
                ]
            }
        case .oldNotebook:
            let backed = (host.lifeFlags() & 1) != 0
            steps = viaEdge(layout, awayMs: 3000, back: side, carryBack: PIXEL_STORY_NOTEBOOK) + [
                pixelStoryAct(.read, 2600, facing: -1, carry: -1),
                pixelStoryCall { [weak self] in self?.store.setFirstPageBacked(backed) },
                done(),
                line("beat", Int(beat.rawValue), backed ? 1 : 0),
                pixelStoryAct(.read, 3200, facing: -1),
            ]
        case .correction:
            let used = Set(store.pages.compactMap { PiboCoreSeasonPage(rawValue: Int32($0.page)) })
            let choice = PiboCoreSeason.twoPage(used: used,
                                                life: PiboCoreSeasonLifeFlags(rawValue: host.lifeFlags()))
            steps = [
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                pixelStoryAct(.read, 1600, facing: -1),
                pixelStoryAct(.correct, 2600, facing: -1),
                pixelStoryCall { [weak self] in
                    guard let self else { return }
                    self.store.addPage(Int(choice.page.rawValue), backed: choice.backed, today: today)
                    if PiboCoreSeason.twoBeatCompletes(beat: beat, correctionsAfter: self.store.pages.count) {
                        self.completeTwo(beat, today)
                    } else {
                        self.store.noteTwoBeatDay(today)
                    }
                    self.host?.changed()
                },
                line("beat", Int(beat.rawValue), Int(choice.page.rawValue) * 2 + (choice.backed ? 1 : 0)),
                pixelStoryAct(.read, 2400, facing: -1),
            ]
        case .askHome:
            steps = [
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                pixelStoryAct(.write, 3600, facing: -1, carry: PIXEL_STORY_REPORT),
                pixelStoryWalk(Double(antenna[0]), Double(antenna[1])),
                pixelStoryAct(.reach, 1800, facing: -1, carry: -1),
                done(),
                pixelStoryWalk(Double(side[0]), Double(side[1])),
                line("beat", Int(beat.rawValue)),
                pixelStoryAct(.beckon, 2400),
            ]
        case .twoLights:
            steps = [
                pixelStoryCall { [weak self] in
                    self?.store.receiveLetter(seasonTwoLetter, today: today)
                    self?.host?.changed()
                },
                pixelStoryAct(.point, 900, facing: -1),
                pixelStoryWalk(Double(mail[0]), Double(mail[1]), gait: .run),
                pixelStoryAct(.crouch, 1600, facing: 0, carry: PIXEL_STORY_LETTER),
                line("beat", Int(beat.rawValue), fallback ? 1 : 0),
                pixelStoryAct(.beckon, 1200, facing: 0, carry: -1),
            ] + viaEdge(layout, awayMs: 3600, back: antenna) {
                [weak self] in self?.completeTwo(beat, today)
            } + [
                pixelStoryAct(.point, 1400, facing: 1),
                pixelStoryCall { [weak self] in self?.host?.feel(.storyMoment) },
                line("beatAfter", Int(beat.rawValue), fallback ? 1 : 0),
                pixelStoryAct(.point, 2600, facing: 1),
            ]
        default:
            return false
        }
        return run(steps, interrupt)
    }

    @discardableResult
    private func run(_ steps: [PixelStoryStep], _ interrupt: Bool) -> Bool {
        var steps = steps
        steps.append(pixelStoryCall { [weak self] in self?.playing = false })
        guard let host, host.director().perform(steps, interrupt: interrupt) else { return false }
        playing = true
        return true
    }

    private func completeTwo(_ beat: PiboCoreSeasonBeat, _ today: Int) {
        let index = Int(beat.rawValue) - Int(PiboCoreSeasonBeat.tiltedPod.rawValue) - PiboCoreSeason.beatCount + 1
        store.completeTwoBeat(index, today: today)
        host?.onBeatTold(seasonTwoThread, index)
        if index >= 7 {
            store.finishSeasonTwo(today)
            host?.onBeatTold(seasonTwoThread, 0)
        }
        host?.changed()
    }

    /// After season two: now and then Pibo rereads a page of the old notebook (Core's weekly
    /// rhythm, the same as letters).
    private func checkReread(_ now: Double) {
        guard let host, store.twoDoneDay >= 0 else { return }
        let today = piboLocalDay(now)
        let anchor = max(store.twoDoneDay, store.lastRereadDay)
        guard PiboCoreSeason.letterDue(seasonDoneDay: anchor, lastLetterDay: store.lastRereadDay, today: today)
        else { return }
        guard host.canStage(), host.claim(), let layout = host.layout() else { return }
        let pod = pixelSeasonSpot(layout, PIXEL_SEASON_POD)
        store.noteReread(today)
        run([
            pixelStoryWalk(Double(pod[0] + 20), Double(pod[1] + 6)),
            pixelStoryAct(.read, 1800, facing: -1),
            pixelStoryCall { [weak self] in self?.say("notebookReread", -1) },
            pixelStoryAct(.read, 3000, facing: -1),
        ], false)
    }

    /// The old notebook: its three wrong pages, each crossed out once corrected, with the
    /// line Pibo wrote under it.
    private func openNotebook() {
        guard let host else { return }
        let page = PiboStoryPaper()
        page.title = "旧笔记"
        page.icon = PIXEL_STORY_NOTEBOOK
        var lines: [String] = []
        var struck: [Int] = []
        for index in 0..<3 {
            guard let wrong = text("notebookWrong", index, nil, rotate: false) else { continue }
            let fixed = store.pages.first { $0.page == index }
            if fixed != nil { struck.append(lines.count) }
            lines.append(wrong)
            if let fixed, let fix = text("notebookFix", index, fixed.backed ? 1 : 0, rotate: false) {
                lines.append(fix)
            }
        }
        // Decision 065: from the second awakening stage, a last page in Pibo's own hand about
        // its shape-shifting. Read only: nothing on it is corrected and season two's beats do
        // not count it.
        let stage = PiboCoreShape.stage(daysTogether: host.dayCount())
        if stage.rawValue >= PiboCoreShapeStage.trying.rawValue {
            lines.append("变形笔记")
            for note in PiboCoreShapeStage.leaking.rawValue...stage.rawValue {
                if let line = text("shapeNote", Int(note), nil, rotate: false) { lines.append(line) }
            }
        }
        page.lines = lines
        page.struck = struck
        page.signature = store.pages.isEmpty ? "—— 不知道是谁写的" : "—— 改过的地方由 Pibo 负责"
        paper = page
        host.showStoryPaper(page)
    }

    private func debugRunTwo(_ id: String) -> String {
        guard let host else { return "第二季未就绪" }
        let now = Date().timeIntervalSince1970 * 1000
        let today = piboLocalDay(now)
        if id == "season2:reset" {
            store.resetTwo()
            host.changed()
            return "第二季已清空"
        }
        if playing { return "Pibo 正忙，稍后再试" }
        if id == "season2:plank" {
            // Back to building: the first plank down, the bridge one short of the next.
            store.debugRewindTwo(beat: 3, today: today)
            store.debugSetPlanks(max(1, min(4, store.planks - 1)))
            host.changed()
            return stagePlank(found: false, now) ? "正在钉一块木板" : "Pibo 正忙，稍后再试"
        }
        let index = Int(id.replacingOccurrences(of: "season2:beat-", with: "")) ?? -1
        guard index >= 1, index <= 7,
              let beat = PiboCoreSeasonBeat(rawValue: Int32(index + PiboCoreSeason.beatCount))
        else { return "未知节拍" }
        if !sceneFits(beat, host.scene()) { return "先回到空地" }
        store.debugRewindTwo(beat: index, today: today)
        host.changed()
        return stageTwo(beat, false, now) ? "正在播放第二季第 \(index) 拍" : "Pibo 正忙，稍后再试"
    }

    // --- Lines --------------------------------------------------------------------------

    private func text(_ event: String, _ kind: Int, _ band: Int? = nil, rotate: Bool = true) -> String? {
        guard let catalog, let host else { return nil }
        var query = GrowthCopyQuery(event: event,
                                    tone: rotate ? host.tone() : .gentle,
                                    band: band,
                                    kind: kind >= 0 ? kind : nil,
                                    values: [:])
        // Letters are fixed texts: no cursor, the line written for exactly this one.
        query.closestTone = true
        if rotate {
            return catalog.select(query, cursors: host.cursors())
        }
        return catalog.select(query, cursors: SeasonFixedCursor())
    }

    private func say(_ event: String, _ kind: Int, _ band: Int? = nil) {
        guard let line = text(event, kind, band) else { return }
        host?.speak(line)
    }

    private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
}
