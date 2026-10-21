import Foundation
import Observation
import os
import PiboCore

// Runs Pibo's day on Home (decision 058): feeds Core's choices to the stage director,
// greets you when Home opens, answers taps on places, sends Pibo exploring when your
// steps earn a trip, and tells the away diary. Every rule is a Core call; this class
// only sequences them and speaks the lines.
//
// Ported from HarmonyPibo `services/day/HomeDayController.ets`. Home supplies the facts
// through `HomeDayDependencies`; the season's beats are staged by `HomeSeasonStaging`.

/// The last Core decor id; ids run without gaps from the mushroom stool.
let PIBO_DECOR_LAST = 12

private let tickMs: Double = 2000
private let debugEchoMs: Double = 16000
/// Debug dock: how long a forced stuck form waits for help.
private let debugStuckReleaseMs: Double = 20000
private let debugTryMs: Double = 2000
private let exploreCheckMs: Double = 30000
private let lineLingerMs: Double = 4200
private let storyLingerMs: Double = 5600
private let greetLineDelayMs: Double = 1100
private let dreamEveryMs: Double = 26000
private let dreamShowMs: Double = 4200
/// Pats closer together than this count as one streak (for shyness).
private let patStreakMs: Double = 4000
/// A tap this soon after turning down an invitation reads as sulking.
private let declineSulkMs: Double = 8000
/// Fidgets are asked for on every other tick.
private let fidgetEveryTicks = 2

/// A line Pibo says, with the small fact printed under it.
struct PiboDayLine {
    var text = ""
    var fact = ""
    var lingerMs: Double = lineLingerMs
}

/// A meal that can sit on the mat: its saved photo id, when, and its sticker file.
struct PiboMealSource: Equatable {
    var id = ""
    var capturedAt: Double = 0
    var pngPath = ""
    var mealTypeRaw = ""
}

/// What Home must hand the controller. Every closure is read at the moment it is needed,
/// so a value that changes while Home is up is seen on the next tick.
struct HomeDayDependencies {
    var stateID: () -> String
    var hour: () -> Double
    var weather: () -> PiboWeather
    var ownedDecor: () -> [Int]
    var hammock: () -> Bool
    var observer: () -> Bool
    var growth: () -> GrowthStore
    /// Pibo's own day: scene, trips, finds, the diary.
    var days: () -> PiboDayStore
    /// Relationship day count and today's health facts.
    var dayCount: () -> Int
    var stepsToday: () -> Int
    var hasStepsData: () -> Bool
    var sleepHours: () -> Double
    var mindfulMinutes: () -> Double
    var lastWorkout: () -> (kind: PiboCoreEchoWorkout, endedAt: Double)?
    var overlays: () -> HomeDayOverlays
    var appActive: () -> Bool
    /// Something else owns Pibo's voice right now (a companion question, a story).
    var voiceBusy: () -> Bool
    /// The object's own line when Pibo is already using it (decision 057 decor copy).
    var decorLine: (Int) -> Void
    var speak: (PiboDayLine) -> Void
    /// Season one (decision 059): every `bo` collected so far, Core's body cue bands
    /// [steps, sleep], and the companion's attention budget for a story beat.
    var boCollected: () -> Int
    var bodyBands: () -> [Int]
    var claimStoryLine: () -> Bool
    var setStoryWaiting: (Bool) -> Void
    /// Decision 060: when the newest recognised meal was taken (-1 none), for the picnic echo.
    var lastMealAt: () -> Double
    /// Decision 065: today's meals the server confirmed as food, for the meal mat.
    var mealsToday: () -> [PiboMealSource]
    /// Opens a meal's detail (a sticker on the mat was tapped).
    var openMeal: (_ photoID: String, _ mealTypeRaw: String) -> Void
}

/// The two sheets the day opens from the stage.
@MainActor
struct HomeDayOverlays {
    var anyOpen: () -> Bool = { false }
    var showDayMap: (Bool) -> Void = { _ in }
    var showShelf: (Bool) -> Void = { _ in }
}

struct DayLineNarrowing {
    var kind: Int?
    var band: Int?
}

/// What the day controller needs from the season's staging (decision 059).
@MainActor
protocol HomeSeasonStaging: AnyObject {
    var podFixed: Bool { get }
    var mailbox: Int { get }
    var planks: Int { get }
    var oldPod: Int { get }
    var farLight: Bool { get }
    func sproutStage() -> Int
    /// A tap on one of the story's own things; true when it took the tap.
    func onTapped(_ place: Int) -> Bool
    /// Runs whatever beat is due.
    func check(_ now: Double)
    /// A find carried back that belongs to the story: returns what Pibo should carry.
    func exploreItem(_ item: Int, _ now: Double) -> Int
    func screwBack()
    func plankBack()
}

private func hashDay(_ key: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for unit in key.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16_777_619
    }
    return hash
}

/// Core's `PiboState` raw value from the Home animation state id.
func piboCoreStateRaw(_ animationStateID: String) -> Int {
    let id = animationStateID.lowercased()
    if id.contains("sleeping") { return 1 }
    if id.contains("waking") { return 2 }
    if id.contains("energetic") || id.contains("celebrate") { return 4 }
    if id.contains("tired") || id == "weak" || id.contains("resting") { return 5 }
    if id.contains("data-unknown") { return 0 }
    return 3
}

@MainActor
@Observable
final class HomeDayController: PixelDayBrain {
    let director: PixelDayDirector
    var scene: PiboCoreDayScene = .clearing
    var season: PiboCoreDaySeason = .summer
    var ambient: UInt32 = 0
    var snow = false
    /// A word Pibo mumbles in its sleep, drawn small above it.
    var dream = ""
    var revision = 0
    // Season one's things in the clearing, as the stage draws them.
    var storyPodFixed = false
    var storySprout = 0
    var storyMailbox = 0
    // Season two's things: bridge planks, the old pod (0 none, 1 found, 2 lit), the far light.
    var storyPlanks = 0
    var storyOldPod = 0
    var storyFarLight = false
    /// Decision 065: the stickers on the meal mat now (encoded inks, newest first), and
    /// whether one of them is still new to Pibo.
    var mealStickers: [String] = []
    var mealFresh = false
    /// The season's beats (decision 059); set by Home once it is built.
    var story: HomeSeasonStaging?

    private var mealOnMat: [PiboMealSource] = []
    private var mealKey = ""
    private let stickerPixels = MealStickerPixels()
    private var catalog: GrowthCopyCatalog?
    private var dependencies: HomeDayDependencies?
    private var timer: Timer?
    private var counter = 0
    private var lastState = -1
    private var wasRaining = false
    private var rainEndedAt: Double = -1
    private var lastExploreCheck: Double = 0
    private var lastDreamAt: Double = 0
    private var greetPending = false
    private var layout: PixelForestLayout?
    private var lineTask: Task<Void, Never>?
    // Decision 060: what makes Pibo feel something.
    private var lastTouchAt: Double = 0
    private var idleFelt = false
    private var patStreak = 0
    private var lastPatAt: Double = 0
    private var declinedAt: Double = 0
    private var lastWeather = -1
    private var ticks = 0
    private var targetScene: PiboCoreDayScene?

    init(director: PixelDayDirector) {
        self.director = director
    }

    private var deps: HomeDayDependencies? { dependencies }

    func bind(_ dependencies: HomeDayDependencies) {
        self.dependencies = dependencies
        director.setBrain(self)
        director.events = PixelDayEvents(
            onFindPresented: { [weak self] item in self?.presentFind(item) },
            onHideTimedOut: { [weak self] in
                self?.say("hideGiveUp", DayLineNarrowing(), "")
            },
            onArrivedBack: { [weak self] item in
                guard let self else { return }
                if item == PIXEL_STORY_SCREW { self.story?.screwBack() }
                else if item == PIXEL_STORY_PLANK { self.story?.plankBack() }
                else { self.presentFind(item) }
            },
            onSceneSwitch: { [weak self] in self?.switchScene() },
            onActivityDone: { [weak self] activity in
                self?.feel(.activityDone, count: Int(activity.rawValue))
            },
            onShapeStuck: { [weak self] form in self?.sayNow("shapeStuck", form: form) },
            onShapeBack: { [weak self] form, helped in
                self?.sayNow(helped ? "shapeHelped" : "shapeSelfBack", form: form)
            }
        )
        loadCatalog()
    }

    private func loadCatalog() {
        do {
            catalog = try GrowthCopyCatalog.bundled()
        } catch {
            LPLog.day.error("day copy unavailable: \(String(describing: error), privacy: .public)")
            catalog = nil
        }
    }

    // --- Lifecycle -----------------------------------------------------------------------

    func start() {
        guard let deps, timer == nil else { return }
        scene = PiboCoreDayScene(rawValue: Int32(deps.days().scene)) ?? .clearing
        refreshWorld(nowMs())
        refreshMealMat(nowMs())
        greetPending = true
        if director.isConfigured { greet() }
        let timer = Timer.scheduledTimer(withTimeInterval: tickMs / 1000, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lineTask?.cancel()
        lineTask = nil
        dependencies?.days().noteSeen(nowMs(), flush: true)
    }

    /// The stage knows its size: place Pibo, then greet if Home just opened.
    func onStageLayout(_ layout: PixelForestLayout) {
        self.layout = layout
        director.configure(layout, scene)
        if greetPending && dependencies != nil { greet() }
    }

    // --- Core context ---------------------------------------------------------------------

    private func ownedMask() -> UInt32 {
        var mask: UInt32 = 0
        for id in deps?.ownedDecor() ?? [] where id >= 0 && id <= PIBO_DECOR_LAST {
            mask |= 1 << UInt32(id)
        }
        return mask
    }

    func context() -> PiboCoreDayContext {
        let state = piboCoreStateRaw(deps?.stateID() ?? "")
        return PiboCoreDayContext(
            scene: scene,
            state: state,
            localHour: max(0, Int(deps?.hour() ?? 12)),
            weather: coreWeather(),
            ownedDecorMask: ownedMask(),
            ornamentMask: (deps?.hammock() == true ? PiboCoreDayOrnament.hammock.rawValue : 0) |
                (deps?.observer() == true ? PiboCoreDayOrnament.observer.rawValue : 0),
            // The beetle from Pibo's told story, out at this forest hour.
            beetleOut: false,
            tone: deps?.growth().tone ?? .gentle
        )
    }

    /// Decision 065's facts: the mat, the shelf and this scene's display spot.
    func extras() -> PiboCoreDayExtras {
        guard let days = deps?.days() else { return PiboCoreDayExtras() }
        return PiboCoreDayExtras(mealStickers: mealOnMat.count, freshMeal: mealFresh,
                                 foundMask: days.foundMask(), displayedFind: days.displayedIn(Int(scene.rawValue)))
    }

    private func coreWeather() -> PiboCoreWeather {
        switch deps?.weather() ?? .clear {
        case .clear: return .clear
        case .cloudy: return .cloudy
        case .fog: return .fog
        case .rain: return .rain
        case .thunderstorm: return .thunderstorm
        case .snow: return .snow
        }
    }

    // --- Meal mat (decision 065) -----------------------------------------------------------

    /// Today's food stickers on the mat, as Core counts them; each is shown once its pixels
    /// are ready. Tomorrow the list is empty again on its own.
    func refreshMealMat(_ now: Double) {
        guard let deps else { return }
        var meals = deps.mealsToday().sorted { $0.capturedAt > $1.capturedAt }
        meals = Array(meals.prefix(PiboCoreDayRules.mealMatCount(mealsToday: meals.count)))
        var shown: [PiboMealSource] = []
        var inks: [String] = []
        for meal in meals {
            guard let pixels = stickerPixels.peek(meal.id, meal.pngPath, onReady: { [weak self] in
                guard let self else { return }
                self.refreshMealMat(self.nowMs())
            }) else { continue }
            shown.append(meal)
            inks.append(pixels)
        }
        let days = deps.days()
        let fresh = shown.contains { meal in
            PiboCoreDayRules.mealFresh(minutesSinceSaved: Int((now - meal.capturedAt) / 60000),
                                       sniffed: days.sniffedMeal(meal.id))
        }
        let key = "\(shown.map(\.id).joined(separator: ","))|\(fresh)|\(inks.joined(separator: ","))"
        if key == mealKey { return }
        mealKey = key
        mealOnMat = shown
        mealStickers = inks
        mealFresh = fresh
        revision += 1
    }

    /// Pibo goes over to sniff: every new sticker on the mat counts as sniffed.
    private func sniffMeals() {
        let now = nowMs()
        guard let days = deps?.days() else { return }
        days.noteSniffed(mealOnMat.filter { meal in
            PiboCoreDayRules.mealFresh(minutesSinceSaved: Int((now - meal.capturedAt) / 60000),
                                       sniffed: days.sniffedMeal(meal.id))
        }.map(\.id))
        mealKey = ""
        refreshMealMat(now)
    }

    /// What Pibo holds while it does `activity`: the find it plays with, else nothing.
    private func carryFor(_ activity: PiboDayActivity) -> Int {
        if activity != .playFind { return -1 }
        guard let days = deps?.days() else { return -1 }
        return PiboCoreDayRules.findPlay(foundMask: days.foundMask(), scene: scene,
                                         displayedFind: days.displayedIn(Int(scene.rawValue)), seed: seed())
    }

    private func seed() -> UInt32 {
        counter += 1
        return hashDay(growthDayKey(Date())) ^ (UInt32(truncatingIfNeeded: counter) &* 2_654_435_761)
    }

    // --- PixelDayBrain ---------------------------------------------------------------------

    func next(previous: PiboDayActivity) -> PixelDayPlan? {
        guard dependencies != nil else { return nil }
        let now = nowMs()
        if let echo = nextEcho(now) { return echo }
        let choice = PiboCoreDay.choose(context(), extras: extras(),
                                             previousActivity: coreActivity(previous), seed: seed())
        let plan = PixelDayPlan()
        plan.activity = PiboDayActivity(rawValue: Int(choice.activity.rawValue)) ?? .idle
        plan.place = choice.place
        plan.durationMs = Double(choice.durationSeconds) * 1000
        plan.carry = carryFor(plan.activity)
        if plan.activity == .playFind && plan.carry < 0 { plan.activity = .idle }
        if plan.activity == .sniffMeal { sniffMeals() }
        return plan
    }

    func slow() -> Bool {
        let state = piboCoreStateRaw(deps?.stateID() ?? "")
        return state == 5 || state == 1 || state == 2
    }

    private func coreActivity(_ activity: PiboDayActivity) -> PiboCoreDayActivity {
        PiboCoreDayActivity(rawValue: Int32(activity.rawValue)) ?? .idle
    }

    // --- Life echoes (decision 060) ----------------------------------------------------------

    private func localMinute(_ now: Double) -> Int {
        let hour = max(0, Int(deps?.hour() ?? 0))
        let date = Date(timeIntervalSince1970: now / 1000)
        let minutes = Calendar.current.component(.minute, from: date)
        return hour * 60 + (hour == Calendar.current.component(.hour, from: date) ? minutes : 0)
    }

    /// The plain facts of your day, for Core to decide what Pibo echoes.
    func echoFacts(_ now: Double) -> PiboCoreEchoFacts {
        let context = self.context()
        var facts = PiboCoreEchoFacts()
        facts.scene = context.scene
        facts.state = context.state
        facts.localMinute = localMinute(now)
        facts.ownedDecorMask = context.ownedDecorMask
        facts.ornamentMask = context.ornamentMask
        if let workout = deps?.lastWorkout(), workout.endedAt > 0, workout.endedAt <= now {
            facts.workoutKind = workout.kind
            facts.workoutMinutesAgo = Int((now - workout.endedAt) / 60000)
        }
        facts.stepsToday = deps?.hasStepsData() == true ? (deps?.stepsToday() ?? 0) : 0
        let sleepHours = deps?.sleepHours() ?? 0
        facts.sleepMinutes = sleepHours > 0 ? Int((sleepHours * 60).rounded()) : -1
        let meal = deps?.lastMealAt() ?? -1
        facts.mealMinutesAgo = meal > 0 && meal <= now ? Int((now - meal) / 60000) : -1
        facts.mindfulMinutesToday = max(0, Int(deps?.mindfulMinutes() ?? 0))
        facts.doneMask = deps?.days().echoesToday(now) ?? 0
        facts.seed = seed()
        return facts
    }

    /// Season two reads the same facts as Core's life flags.
    func lifeFlags(_ now: Double) -> UInt32 {
        let facts = echoFacts(now)
        return PiboCoreSeason.lifeFlags(workoutMinutesAgo: facts.workoutMinutesAgo,
                                        stepsToday: facts.stepsToday, sleepMinutes: facts.sleepMinutes,
                                        mealMinutesAgo: facts.mealMinutesAgo).rawValue
    }

    private func nextEcho(_ now: Double) -> PixelDayPlan? {
        let choice = PiboCoreEcho.choose(echoFacts(now))
        if choice.echo == .none { return nil }
        deps?.days().noteEcho(Int(choice.echo.rawValue), now)
        LPLog.day.info("echo=\(choice.echo.rawValue, privacy: .public) activity=\(choice.activity.rawValue, privacy: .public)")
        let plan = PixelDayPlan()
        plan.activity = PiboDayActivity(rawValue: Int(choice.activity.rawValue)) ?? .idle
        plan.place = choice.place
        plan.durationMs = Double(choice.durationSeconds) * 1000
        // Decision 061: from its second day it wants to become what you did.
        let shape = PiboCoreShape.plan(PiboCoreShapeContext(trigger: .echo, count: Int(choice.echo.rawValue),
                                                           daysTogether: deps?.dayCount() ?? 1, seed: seed()))
        armShape(plan, form: Int(shape.form.rawValue), mode: shape.mode, holdMs: Double(shape.holdMilliseconds),
                 stuck: shape.stuck, releaseMs: Double(shape.releaseMilliseconds))
        later({ [weak self] in
            guard let self else { return }
            var narrow = DayLineNarrowing()
            narrow.kind = shape.mode == .none ? Int(choice.echo.rawValue) : Int(shape.form.rawValue)
            self.say(shape.mode == .change ? "shapeOn" : (shape.mode == .attempt ? "shapeTry" : "echo"),
                     narrow, piboEchoFact(Int(choice.echo.rawValue)))
        }, greetLineDelayMs)
        return plan
    }

    // --- Shape (decision 061) ----------------------------------------------------------------

    /// Hands a change (or a try) to the director for the plan's activity. A form that gets
    /// about does it on the ground; only the fish and the bowl keep their spot.
    private func armShape(_ plan: PixelDayPlan, form: Int, mode: PiboCoreShapeMode, holdMs: Double,
                          stuck: Bool, releaseMs: Double) {
        if mode == .none || form <= 0 { return }
        if mode == .change && form != PiboForm.fish.rawValue && form != PiboForm.bowl.rawValue {
            plan.place = .ground
        }
        director.shapeFor(plan.activity, form: form, tryOnly: mode == .attempt, tryMs: holdMs,
                          stuck: stuck, releaseMs: releaseMs)
    }

    /// A sneeze can slip it into a stone or a mushroom for a moment, after the sneeze itself.
    private func sneezeShape(_ now: Double) {
        let plan = PiboCoreShape.plan(PiboCoreShapeContext(trigger: .sneeze, count: 0,
                                                           daysTogether: deps?.dayCount() ?? 1, seed: seed()))
        if plan.mode != .change || plan.form == .none { return }
        let at = now + piboEmoteDuration(.sneeze)
        director.shapeAt(Int(plan.form.rawValue), at, Double(plan.holdMilliseconds))
        LPLog.day.info("sneeze shape=\(plan.form.rawValue, privacy: .public)")
        later({ [weak self] in self?.sayNow("shapeSneeze", form: Int(plan.form.rawValue)) }, at - now + 300)
    }

    private func sayNow(_ event: String, form: Int) {
        var narrow = DayLineNarrowing()
        narrow.kind = form
        say(event, narrow, "")
    }

    // --- Feelings (decision 060) ---------------------------------------------------------------

    /// Asks Core what Pibo feels about a moment and plays it.
    func feel(_ trigger: PiboCoreEmoteTrigger, count: Int) {
        guard dependencies != nil else { return }
        let now = nowMs()
        let context = PiboCoreEmoteContext(trigger: trigger, count: count, season: season,
                                           localHour: max(0, Int(deps?.hour() ?? 12)),
                                           weather: coreWeather(),
                                           state: piboCoreStateRaw(deps?.stateID() ?? ""),
                                           seed: seed())
        let emote = PiboCoreEmote.react(context)
        if emote != .none {
            director.feel(Int(emote.rawValue), now)
            LPLog.day.info("feel trigger=\(trigger.rawValue, privacy: .public) emote=\(emote.rawValue, privacy: .public)")
            if emote == .sneeze { sneezeShape(now) }
        }
    }

    /// A valid double tap on Pibo. Returns true when it was in another shape and the tap
    /// went to that (helping it back, or the shape answering), not to a pat.
    func onPat() -> Bool {
        let now = nowMs()
        touched(now)
        if director.helpBack(now) { return true }
        let form = director.form
        if form > 0 {
            // The shape answers in its own voice: a bell, a blub, a thunk.
            sayNow("shapeTap", form: form)
            return true
        }
        if now - declinedAt < declineSulkMs {
            declinedAt = 0
            feel(.tappedAfterDecline, count: 0)
            return false
        }
        patStreak = now - lastPatAt < patStreakMs ? patStreak + 1 : 1
        lastPatAt = now
        feel(.pat, count: patStreak)
        return false
    }

    private func touched(_ now: Double) {
        lastTouchAt = now
        idleFelt = false
    }

    private func tickFeelings(_ now: Double, _ state: Int) {
        if lastTouchAt <= 0 { lastTouchAt = now }
        let weather = Int(coreWeather().rawValue)
        if lastWeather >= 0 && weather != lastWeather {
            feel(.weatherTurned, count: weather)
        }
        lastWeather = weather
        let director = self.director
        if director.performing || director.hiding || state == 1 || (deps?.overlays().anyOpen() ?? false) {
            return
        }
        let idle = Int((now - lastTouchAt) / 1000)
        if !idleFelt && idle >= PiboCoreEmote.idleSeconds && !director.feeling(now) {
            idleFelt = true
            feel(.idle, count: idle)
            return
        }
        ticks += 1
        if ticks % fidgetEveryTicks != 0 || director.feeling(now) { return }
        let fidget = PiboCoreEmote.fidget(state: state, walking: director.walking, seed: seed())
        director.fidget(Int(fidget.rawValue), now)
    }

    // --- World: season, small life, rainbow -------------------------------------------------

    private func refreshWorld(_ now: Double) {
        let weather = coreWeather()
        let raining = weather == .rain || weather == .thunderstorm
        if wasRaining && !raining { rainEndedAt = now }
        wasRaining = raining
        let month = Calendar.current.component(.month, from: Date(timeIntervalSince1970: now / 1000))
        let season = PiboCoreDayRules.season(month: month)
        let sinceRain = rainEndedAt < 0 ? -1 : Int((now - rainEndedAt) / 60000)
        let ambient = PiboCoreDayRules.ambient(season: season, localHour: Int(deps?.hour() ?? 0),
                                               weather: weather, minutesSinceRain: sinceRain)
        let snow = ambient.contains(.snowGround)
        if season != self.season || ambient.rawValue != self.ambient || snow != self.snow {
            self.season = season
            self.ambient = ambient.rawValue
            self.snow = snow
            revision += 1
        }
    }

    // --- Tick -------------------------------------------------------------------------------

    func tick() {
        guard let deps, deps.appActive() else { return }
        let now = nowMs()
        deps.days().noteSeen(now, flush: false)
        refreshWorld(now)
        let state = piboCoreStateRaw(deps.stateID())
        if state != lastState {
            // Falling asleep, waking up, getting tired: Pibo drops its plan and picks again.
            if lastState >= 0 { director.replan() }
            lastState = state
        }
        if now - lastExploreCheck >= exploreCheckMs {
            lastExploreCheck = now
            if checkExplore(now) && canLeaveNow() {
                let days = deps.days()
                if days.pendingFind >= 0 {
                    let item = days.takePendingFind()
                    if item >= 0 {
                        director.explore(story?.exploreItem(item, now) ?? item)
                        say("exploreLeave", DayLineNarrowing(), "")
                    }
                }
            }
        }
        refreshMealMat(now)
        updateDream(now, state)
        tickFeelings(now, state)
        refreshStory()
        story?.check(now)
    }

    // --- Season one (decision 059) ----------------------------------------------------------

    /// The season controller checks the scene each beat needs (season two plays at the creek too).
    private func canStageStory() -> Bool {
        guard let deps else { return false }
        return deps.appActive() && scene != .hill && !director.hiding && !director.busyScripted &&
            !deps.overlays().anyOpen() && !deps.voiceBusy() && piboCoreStateRaw(deps.stateID()) != 1
    }

    private func refreshStory() {
        guard let story else { return }
        let fixed = story.podFixed
        let sprout = story.sproutStage()
        let mailbox = story.mailbox
        let planks = story.planks
        let oldPod = story.oldPod
        let farLight = story.farLight
        director.setBridge(planks >= 5)
        if fixed == storyPodFixed && sprout == storySprout && mailbox == storyMailbox &&
            planks == storyPlanks && oldPod == storyOldPod && farLight == storyFarLight {
            return
        }
        storyPodFixed = fixed
        storySprout = sprout
        storyMailbox = mailbox
        storyPlanks = planks
        storyOldPod = oldPod
        storyFarLight = farLight
        revision += 1
    }

    private func canLeaveNow() -> Bool {
        guard let deps else { return false }
        return !director.hiding && !director.busyScripted && !deps.overlays().anyOpen() &&
            piboCoreStateRaw(deps.stateID()) != 1
    }

    private func updateDream(_ now: Double, _ state: Int) {
        if state != 1 {
            if !dream.isEmpty { dream = "" }
            return
        }
        if !dream.isEmpty && now - lastDreamAt > dreamShowMs { dream = "" }
        if now - lastDreamAt < dreamEveryMs { return }
        lastDreamAt = now
        dream = line("sleepTalk", DayLineNarrowing()) ?? ""
    }

    /// Records every trip today's steps earned and Core says is due. Returns true if any.
    @discardableResult
    func checkExplore(_ now: Double) -> Bool {
        guard let deps, deps.hasStepsData() else { return false }
        let days = deps.days()
        var recorded = false
        for _ in 0..<4 {
            let trip = PiboCoreExplore.trip(stepsToday: deps.stepsToday(), tripsToday: days.tripsToday(now),
                                            foundMask: days.foundMask(), season: season,
                                            daySeed: hashDay(growthDayKey(Date())))
            if !trip.due || trip.item < 0 { break }
            days.recordTrip(PiboTripRecord(tripIndex: trip.tripIndex,
                                           destination: Int(trip.destination.rawValue),
                                           item: trip.item, stepsThreshold: trip.stepsThreshold),
                            dayCount: deps.dayCount(), now: now)
            LPLog.day.info("explore trip=\(trip.tripIndex, privacy: .public) destination=\(trip.destination.rawValue, privacy: .public) item=\(trip.item, privacy: .public)")
            recorded = true
        }
        return recorded
    }

    // --- Greeting ----------------------------------------------------------------------------

    private func greet() {
        greetPending = false
        guard let deps else { return }
        let days = deps.days()
        let now = nowMs()
        days.rollDay(now)
        checkExplore(now)
        lastExploreCheck = now
        let away = days.awayMinutes(now)
        let find = days.pendingFind
        let state = piboCoreStateRaw(deps.stateID())
        lastState = state
        director.settle()
        let style = PiboCoreDayRules.greet(tone: deps.growth().tone, state: state, awayMinutes: away,
                                           hasNewFind: find >= 0, hiddenToday: days.hiddenToday(now),
                                           seed: seed())
        touched(now)
        if style != .hide { feel(.returned, count: away) }
        LPLog.day.info("greet style=\(style.rawValue, privacy: .public) away=\(away, privacy: .public) find=\(find, privacy: .public)")
        if style == .none && find < 0 {
            refreshStory()
            story?.check(now)
            return
        }
        var hide: PiboCoreDayPlace = .tallGrass
        var disguise = 0
        var decoys = 0
        if style == .hide {
            days.noteHidden(now)
            hide = PiboCoreDayRules.hideSpot(context(), seed: seed())
            // Decision 065: once it can really change, half its hides are as a forest thing.
            let shape = PiboCoreDayRules.hideDisguise(scene: scene,
                                                      shapeStage: PiboCoreShape.stage(daysTogether: deps.dayCount()),
                                                      seed: seed())
            disguise = Int(shape.form.rawValue)
            decoys = shape.decoys
            LPLog.day.info("hide disguise=\(disguise, privacy: .public) decoys=\(decoys, privacy: .public)")
        }
        let carried = find >= 0 ? days.takePendingFind() : -1
        director.greet(style, find: carried, hideSpot: hide,
                       hideMs: Double(PiboCoreDayRules.hideSeconds()) * 1000,
                       disguise: disguise, decoys: decoys, seed: Int(seed()))
        refreshStory()
        story?.check(now)
        if style == .peek || style == .runOver || style == .sleepyStir {
            later({ [weak self] in
                guard let self else { return }
                var narrow = DayLineNarrowing()
                narrow.kind = Int(style.rawValue)
                self.say("dayGreet", narrow, "")
            }, greetLineDelayMs)
        }
    }

    private func presentFind(_ item: Int) {
        let count = deps?.days().count(item) ?? 0
        if count == 1, (PiboCoreExplore.item(at: item).rare) {
            feel(.rareFind, count: 0)
        }
        var narrow = DayLineNarrowing()
        narrow.kind = item
        narrow.band = count > 1 ? 1 : 0
        let fact = count > 1 ? "\(piboFindName(item)) · 第 \(count) 个" : piboFindName(item)
        say(count > 1 ? "findAgain" : "findShow", narrow, fact)
    }

    /// The away summary's diary line, once per trip: where Pibo went and what came back.
    func awayDiary() -> PiboDayLine? {
        guard let deps, let entry = deps.days().unreadDiary() else { return nil }
        let days = deps.days()
        var narrow = DayLineNarrowing()
        narrow.kind = entry.destination
        let text = line("diary", narrow, ["item": piboFindName(entry.item)])
        days.markDiaryRead()
        guard let text else { return nil }
        var line = PiboDayLine(text: text)
        line.lingerMs = lineLingerMs + 800
        line.fact = "\(entry.steps) 步 · \(piboDestinationName(entry.destination))"
        return line
    }

    // --- Taps ----------------------------------------------------------------------------------

    /// A tap on a place in the scene. Returns true when it found a hiding Pibo.
    func onPlaceTapped(_ place: Int) -> Bool {
        guard let deps else { return false }
        touched(nowMs())
        if place >= PixelHotspot.mealSticker.rawValue &&
            place < PixelHotspot.mealSticker.rawValue + mealOnMat.count {
            let meal = mealOnMat[place - PixelHotspot.mealSticker.rawValue]
            deps.openMeal(meal.id, meal.mealTypeRaw)
            return false
        }
        if director.hiding {
            if place == director.hidingPlace {
                director.found()
                feel(.found, count: 0)
                say("hideFound", DayLineNarrowing(), "")
                return true
            }
            // A look-alike: it is just a stone (or a mushroom…), and Pibo giggles.
            var narrow = DayLineNarrowing()
            if place >= PixelHotspot.decoy.rawValue && place < PixelHotspot.mealSticker.rawValue {
                narrow.kind = director.disguise
            }
            say(narrow.kind != nil ? "hideDecoy" : "hideWrong", narrow, "")
            return false
        }
        if story?.onTapped(place) == true { return false }
        if place == PiboCoreDayPlace.trailSign.rawValue {
            deps.overlays().showDayMap(true)
            return false
        }
        if place == PixelHotspot.basket.rawValue {
            deps.overlays().showShelf(true)
            return false
        }
        if director.doingAt == place && place != PiboCoreDayPlace.ground.rawValue {
            // Already there: the place's own line.
            let decor = pixelDecorForPlace(PiboCoreDayPlace(rawValue: Int32(place)) ?? .ground)
            if decor >= 0 && decor <= 9 {
                deps.decorLine(decor)
            } else {
                var narrow = DayLineNarrowing()
                narrow.kind = place
                say("placeTapped", narrow, "")
            }
            return false
        }
        invite(PiboCoreDayPlace(rawValue: Int32(place)) ?? .ground)
        return false
    }

    private func invite(_ place: PiboCoreDayPlace) {
        guard let deps else { return }
        let days = deps.days()
        let now = nowMs()
        let answer = PiboCoreDay.invite(context(), extras: extras(), place: place,
                                             invitesToday: days.invitesToday(now), seed: seed())
        LPLog.day.info("invite place=\(place.rawValue, privacy: .public) accepted=\(answer.accepted, privacy: .public) reason=\(answer.reason.rawValue, privacy: .public)")
        var narrow = DayLineNarrowing()
        if !answer.accepted {
            if answer.reason == .notHere { return }
            if answer.reason != .asleep {
                director.refuse(place)
                declinedAt = now
            }
            narrow.band = Int(answer.reason.rawValue)
            say("inviteNo", narrow, "")
            return
        }
        days.noteInvite(now)
        if answer.activity == coreActivity(director.lastFinished) && answer.activity != .idle {
            feel(.invitedAgain, count: 0)
        }
        let plan = PixelDayPlan()
        plan.activity = PiboDayActivity(rawValue: Int(answer.activity.rawValue)) ?? .idle
        plan.place = place
        plan.durationMs = Double(answer.durationSeconds) * 1000
        plan.eager = answer.eager
        plan.carry = carryFor(plan.activity)
        if plan.activity == .sniffMeal { sniffMeals() }
        director.go(plan)
        narrow.kind = Int(answer.activity.rawValue)
        narrow.band = answer.grudging ? 1 : 0
        say("inviteYes", narrow, "")
    }

    // --- Scenes ----------------------------------------------------------------------------------

    func sceneUnlocked(_ scene: PiboCoreDayScene) -> Bool {
        PiboCoreDayRules.sceneUnlocked(scene, level: deps?.growth().level ?? 1)
    }

    func sceneMinLevel(_ scene: PiboCoreDayScene) -> Int {
        PiboCoreDayRules.sceneMinLevel(scene)
    }

    /// Walk to another scene. Pibo leaves through the edge; the scene changes off-screen.
    @discardableResult
    func travelTo(_ scene: PiboCoreDayScene) -> Bool {
        guard let deps, scene != self.scene, sceneUnlocked(scene) else { return false }
        targetScene = scene
        deps.overlays().showDayMap(false)
        director.travel()
        LPLog.day.info("travel scene=\(scene.rawValue, privacy: .public)")
        return true
    }

    private func switchScene() {
        guard let targetScene else { return }
        scene = targetScene
        self.targetScene = nil
        deps?.days().setScene(Int(scene.rawValue))
        revision += 1
        if let layout { director.configure(layout, scene) }
        director.arrive()
        later({ [weak self] in
            guard let self else { return }
            var narrow = DayLineNarrowing()
            narrow.kind = Int(scene.rawValue)
            self.say("sceneArrive", narrow, piboSceneName(Int(scene.rawValue)))
        }, 2600)
    }

    // --- Lines -------------------------------------------------------------------------------------

    private func later(_ body: @escaping () -> Void, _ delayMs: Double) {
        lineTask?.cancel()
        lineTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delayMs) * 1_000_000))
            if Task.isCancelled { return }
            self.lineTask = nil
            body()
        }
    }

    func line(_ event: String, _ narrow: DayLineNarrowing, _ extra: [String: String] = [:]) -> String? {
        guard let catalog, let deps else { return nil }
        let growth = deps.growth()
        var values = extra
        values["day"] = "\(deps.dayCount())"
        let query = GrowthCopyQuery(event: event, tone: growth.tone, band: narrow.band,
                                    kind: narrow.kind, values: values)
        return catalog.select(query, cursors: growth)
    }

    private func say(_ event: String, _ narrow: DayLineNarrowing, _ fact: String) {
        guard let deps, !deps.voiceBusy() else { return }
        guard let text = line(event, narrow) else { return }
        var line = PiboDayLine(text: text)
        line.lingerMs = lineLingerMs
        if !fact.isEmpty { line.fact = fact }
        deps.speak(line)
    }

    private func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}
