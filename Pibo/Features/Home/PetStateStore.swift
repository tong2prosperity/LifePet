import SwiftUI
import os
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Pet state machine (PRD §5)

/// 6-state pet visual machine. MVP only animates `.normal` and `.excited`;
/// the other four resolve to label-only placeholders so the rule layer can
/// already produce them once HealthKit data is wired.
enum PetState: String {
    case sick, sleeping, tired, normal, excited, blissful

    var tag: String {
        switch self {
        case .sick:     return "SICK"
        case .sleeping: return "SLEEPING"
        case .tired:    return "TIRED"
        case .normal:   return "NORMAL"
        case .excited:  return "EXCITED"
        case .blissful: return "BLISSFUL"
        }
    }

    var showsSparkles: Bool { self == .excited || self == .blissful }
}

// MARK: - Stats

enum StatKind: Hashable {
    case vitality   // 💪 体力
    case energy     // ⚡ 精力
    case mood       // ❤️ 心情

    var label: String {
        switch self {
        case .vitality: return AppLocalization.text("✦ 活力星光")
        case .energy:   return AppLocalization.text("☾ 静息星光")
        case .mood:     return AppLocalization.text("❤️ 心绪回声")
        }
    }

    var sourceCopy: String {
        switch self {
        case .vitality: return AppLocalization.text("步数 · 运动分钟 · 活动卡路里")
        case .energy:   return AppLocalization.text("睡眠 · 深睡 · REM")
        case .mood:     return AppLocalization.text("HRV · 心率稳定度")
        }
    }

    var supplementCopy: String {
        switch self {
        case .vitality: return AppLocalization.text("走 1000 步 +4 星光 / 运动 10 分钟 +10")
        case .energy:   return AppLocalization.text("每睡 1 小时 +6 星光 / 深睡多 30 分钟 +15")
        case .mood:     return AppLocalization.text("冥想 5 分钟 +15 / 深呼吸 1 次 +3")
        }
    }
}

struct Stat: Identifiable {
    let id = UUID()
    let kind: StatKind
    var value: Int  // 0...100
}

/// One stat's change between two recomputes — used by `HomeView` to fire a
/// sparkle burst + toast when HealthKit pushes new data.
///
/// `id` makes every emit unique even when two consecutive deltas have the
/// same `(kind, delta)` — without it, SwiftUI's `onChange` would skip the
/// second sparkle because `Equatable` would call them equal.
struct StatDelta: Equatable, Sendable {
    let id: UUID
    let kind: StatKind
    let delta: Int
    let reason: String?

    init(kind: StatKind, delta: Int, reason: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.delta = delta
        self.reason = reason
    }
}

// MARK: - Pending workout (PRD §4 — 新事件通知)

/// 一次"刚同步过来的运动"待用户确认。`HealthDataService` 检测到 fresh
/// workout（≤5 min ago）→ `PetStateStore` 把它装进 `pendingWorkout` 而不
/// 立刻 applyGain；`HomeView` 看到非 nil 时弹 `WorkoutAlertSheet`。用户点
/// 「喂养」→ `consume(...)` 真正应用增益、插 done 卡、触发动画；用户划
/// 走 / 点 backdrop → `dismiss(...)` 静默应用增益（不丢数据）。
///
/// Replay workouts（>5min 旧）走老路径：直接插展示卡，**不**入这个队列，
/// 因为它们的 vitality 已经被 aggregate snapshot 吸收过。
struct PendingWorkout: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let kind: HealthEvent.WorkoutKind
    /// "跑步" / "走路" / …
    let label: String
    /// 「跑步完成」 / 「走路完成」 — sheet 的标题
    var titleLabel: String { AppLocalization.format("%@完成", label) }
    let durationMin: Int
    let kcal: Double?
    let endedAt: Date
    /// PRD §3：workout 仅入 vitality。其他两栏在 sheet 上显示 —。
    let gainVitality: Int
}

// MARK: - Step cards (PRD §4)

enum StepStatus: Hashable { case done, suggest }

enum StepKind: String, Hashable {
    case run, sleep, breath, meditate, walk

    var quitLabel: String {
        switch self {
        case .run:      return AppLocalization.text("跑步")
        case .sleep:    return AppLocalization.text("睡眠")
        case .breath:   return AppLocalization.text("深呼吸")
        case .meditate: return AppLocalization.text("冥想")
        case .walk:     return AppLocalization.text("走路")
        }
    }
}

struct StepItem: Identifiable, Hashable {
    let id = UUID()
    var status: StepStatus
    var kind: StepKind
    var actionLabel: String
    var titleValue: String
    var affects: StatKind
    var gain: Int
    var time: String
    var fromAutoSensor: Bool

    var displayTitleLead: String {
        switch status {
        case .suggest: return AppLocalization.format("建议: %@", actionLabel)
        case .done:    return actionLabel
        }
    }
}

// MARK: - Raw HealthKit snapshot

/// Latest known reading per metric. The PRD §3 formulas read from here.
private struct RawMetrics {
    var steps: Int = 0
    var exerciseMinutes: Int = 0
    var activeEnergy: Double = 0
    var standMinutes: Int = 0
    var heartRate: Double = 0
    var hrv: Double = 0
    /// 7-day rolling baseline for HRV. `nil` until we accumulate enough
    /// readings — until then we treat today's HRV as its own baseline so
    /// 心情 sits at its 50 floor instead of swinging on a single sample.
    var hrvBaseline: Double? = nil
    var restingHR: Double = 0
    var sleepTotal: TimeInterval = 0
    var sleepDeep: TimeInterval = 0
    var sleepREM: TimeInterval = 0
    /// The earliest `asleep*` startDate in the latest sleep snapshot, used to
    /// label the home-screen sleep card ("昨 23:30"). `nil` when no asleep
    /// samples exist yet.
    var sleepStart: Date? = nil
    var mindfulMinutes: Int = 0
    /// Latest blood-oxygen (SpO2) reading as a fraction 0–1.
    var oxygen: Double = 0
}

// MARK: - Store

/// Replaces the old hand-set `HomeModel`. Sources of truth, in order of
/// authority:
///
/// 1. `RawMetrics` — latest HealthKit readings per metric.
/// 2. PRD §3 formulas — computed `stats` from raw.
/// 3. PRD §5 priority ladder — derived `state`.
///
/// The home view never reads from `RawMetrics` directly; it reads `stats` /
/// `state` / `steps`. Mutations come from two sides:
///
/// - **HealthKit ingest** — `ingest(_:)` fed by a `Task` consuming
///   `HealthDataService.events`. Updates `RawMetrics`, recomputes, and
///   posts `lastDelta` so the UI can run the same toast / stat-bar / sparkle
///   flow that manual `markDone` already triggers.
/// - **User taps** — `markDone(_:)` and `quit(_:)` flip suggest cards.
///
/// `demoMode = true` short-circuits HealthKit ingest entirely, so the
/// hackathon presentation device can run without HK data and still show
/// `BEAN / D07 / 88·74·82`.
@MainActor
@Observable
final class PetStateStore {

    // — Identity —
    /// Owns persisted identity (UUID, name, birthDate). `PetStateStore`
    /// proxies the user-visible bits so views can keep reading from a single
    /// `@Environment(PetStateStore.self)`.
    let identity: PetIdentityStore

    var ownerName: String {
        get { identity.ownerName }
        set { identity.ownerName = newValue }
    }
    var petName: String {
        get { identity.petName }
        set { identity.petName = newValue }
    }
    /// "已陪伴第 N 天" — derived from `identity.birthDate` so every Date()
    /// recomputation auto-advances. Demo mode keeps this at 7 by re-seeding
    /// `birthDate` at every day rollover (see `performRollover`).
    var dayCount: Int { identity.daysSinceBirth }

    // — Derived state (writable so demo + manual paths can mutate) —
    var stats: [Stat]
    var state: PetState
    var steps: [StepItem]
    private(set) var quitCounts: [StepKind: Int] = [:]
    /// Per-kind cooldown timestamps. Set on `markDone` *or* `quit` — both
    /// signal "user has engaged with this kind recently, don't push the same
    /// thing again immediately." 2h is the cooldown window.
    private var lastInteractionAt: [StepKind: Date] = [:]

    /// Per-stat downward pressure accumulated by `applyDecayCatchup()` and
    /// subtracted in `recompute()`. PRD §3: each stat naturally drops 5 every
    /// 4h (floor 10); 精力 does not decay during sleep. We model this as a
    /// buffer rather than mutating `stats` directly so HK ingest can still
    /// paint formula values on top — final = max(10, formula − pending).
    /// Resets at day rollover so the user starts each morning fresh; the
    /// buffer therefore caps at ~30 within a single day (6 ticks × 5).
    private var decayPending: [StatKind: Int] = [:]

    /// Hard-coded values for the hackathon demo device. Both modes use
    /// `demoStats` as a cold-start floor (until first ingest, gated by
    /// `hasIngestedAny`); only demo mode seeds `demoSteps` — non-demo starts
    /// with an empty step list so HK-driven workout/sleep cards never collide
    /// with stale narrative entries.
    private static let demoStats: [Stat] = [
        Stat(kind: .vitality, value: 88),
        Stat(kind: .energy,   value: 74),
        Stat(kind: .mood,     value: 82),
    ]
    private static let demoSteps: [StepItem] = [
        StepItem(status: .done,    kind: .run,      actionLabel: AppLocalization.text("跑步"),   titleValue: AppLocalization.format("%d 分钟", 28),     affects: .vitality, gain: 32, time: "07:30",    fromAutoSensor: true),
        StepItem(status: .done,    kind: .sleep,    actionLabel: AppLocalization.text("入睡"),   titleValue: AppLocalization.format("%d 小时 %d 分", 6, 12), affects: .energy,   gain: 24, time: AppLocalization.format("昨 %@", "23:30"), fromAutoSensor: true),
        StepItem(status: .done,    kind: .breath,   actionLabel: AppLocalization.text("深呼吸"), titleValue: AppLocalization.format("%d 次", 3),        affects: .mood,     gain: 9,  time: "15:30",    fromAutoSensor: false),
        StepItem(status: .suggest, kind: .walk,     actionLabel: AppLocalization.text("再走"),   titleValue: AppLocalization.format("%d 步", 1500),     affects: .vitality, gain: 6,  time: "",         fromAutoSensor: false),
        StepItem(status: .suggest, kind: .meditate, actionLabel: AppLocalization.text("冥想"),   titleValue: AppLocalization.format("%d 分钟", 5),      affects: .mood,     gain: 15, time: "",         fromAutoSensor: false),
    ]

    // — Transient feedback —
    var toast: String? = nil
    /// Rotates Pibo's front-page line when the user taps the pet. Kept as a
    /// simple counter instead of random state so the same day/stat combination
    /// renders predictably until the user explicitly interacts.
    var speechCursor: Int = 0

    // MARK: - 魔丸态 (new model — raw-data-driven, no three-stat layer)
    //
    // The new home reads these straight off raw HealthKit + time of day. The
    // derived API (greeting pools, 6-state machine, 拍一拍 caps, 拔毛) lives in
    // `PetStateStore+Mowan.swift`; these are the stored/accessor hooks it needs.

    /// Timestamps of 拍一拍 lines Pibo actually spoke — drives the speech caps
    /// in `pat()` (≤3 / 10 min, ≤9 / 24h). In-memory only.
    var patSpeechTimes: [Date] = []
    /// Set when Pibo enters the post-拔毛 5-minute 深眠. `nil` otherwise.
    var pluckSleepUntil: Date? = nil
    /// Flipped true on the first foreground open in the 06:00–10:00 window so
    /// the 初醒 state only greets once per morning. Reset at day rollover.
    var sawMorningOpen: Bool = false

    private static let lastPluckedKey = "pibo.mowan.lastPluckedDay"
    /// Day (startOfDay) the user last collected 花籽. Persisted so the
    /// 22:00–02:00 拔毛 window fires once per night.
    var lastPluckedDay: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: Self.lastPluckedKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.lastPluckedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastPluckedKey)
            }
        }
    }

    private static let selectedThemeKey = "pibo.theme.selected.v1"
    /// User-picked 关于毛的主题 id (settings gear → 主题). `nil` = default 魔丸.
    /// Loaded in `init`, persisted on change; `currentTheme`
    /// (`PetStateStore+Mowan`) resolves it against `PiboTheme.selectable`.
    var selectedThemeID: String? = nil {
        didSet {
            if let selectedThemeID {
                UserDefaults.standard.set(selectedThemeID, forKey: Self.selectedThemeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedThemeKey)
            }
        }
    }

    private static let growthStageKey = "pibo.growth.v1"
    /// 魔丸 head growth — the 「?」卷芽 until the first collected 运动能量,
    /// then 发芽带叶 (Figma《识别到用户的活动》74:6102: 播完缩回主页面,
    /// pibo头顶发生变化). Loaded in `init`; per-pet, so `reset()` wipes it.
    var growthStage: PiboGrowthStage = .mystery {
        didSet { UserDefaults.standard.set(growthStage.rawValue, forKey: Self.growthStageKey) }
    }

    private static let appearanceKey = "pibo.appearance.v1"
    /// User-customized 形象 DNA — the component-separated look edited in
    /// `CustomPiboPage` and rendered by `PiboPortraitView`. Persisted as JSON;
    /// loaded in `init`, wiped by `reset()` (per-pet). Defaults to the Figma
    /// `1855:4343` 魔丸 look so a fresh pet already matches the design spec.
    var appearance: PiboAppearance = .default {
        didSet { UserDefaults.standard.set(appearance.encoded, forKey: Self.appearanceKey) }
    }

    private static let weatherKey = "pibo.weather.v1"
    /// 当前天气 — 驱动首页 SpriteKit 场景的氛围(雨幕 / 地面水花 / 滴在 Pibo 上)。
    /// v1 由设置页的 DEBUG 开关手动切换;接入 WeatherKit 后改由 WeatherService 写入
    /// (`WeatherCondition.piboWeather`,见 `PiboWeather.swift`)。持久化便于演示跨重启
    /// 保持;`reset()` 清回 `.clear`。
    var weather: PiboWeather = .clear {
        didSet {
            guard weather != oldValue else { return }
            UserDefaults.standard.set(weather.rawValue, forKey: Self.weatherKey)
            LPLog.petState.notice("weather → \(self.weather.rawValue, privacy: .public)")
        }
    }

    /// First 运动能量 collected — the 毛 sprouts its leaf. Idempotent.
    func markSprouted() {
        guard growthStage == .mystery else { return }
        growthStage = .sprouted
        LPLog.petState.notice("growth → sprouted")
    }

    /// Pibo 故事线 progress — 拍一拍 can surface the next clue of the current
    /// chapter (app 叙事). Owned here so `pat()` and `reset()` reach it.
    let story = PiboStorylineStore()

    #if DEBUG
    /// Dev/demo helper (settings sheet): inject a fake "刚跑完步" so the 发芽
    /// energy-collection flow can be rehearsed without a real HKWorkout.
    func debugInjectWorkout() {
        pendingWorkout = PendingWorkout(
            id: UUID(), kind: .run, label: AppLocalization.text("跑步"),
            durationMin: 24, kcal: 186, endedAt: Date(), gainVitality: 18)
    }
    #endif

    // Raw HealthKit readings, exposed for the direct-data UI (state machine +
    // 上滑 Dashboard). The home no longer surfaces the three derived stats.
    var rawSteps: Int { raw.steps }
    var rawExerciseMinutes: Int { raw.exerciseMinutes }
    var rawActiveEnergy: Double { raw.activeEnergy }
    var rawStandMinutes: Int { raw.standMinutes }
    var rawHeartRate: Double { raw.heartRate }
    var rawHRV: Double { raw.hrv }
    var rawRestingHR: Double { raw.restingHR }
    /// Latest blood-oxygen (SpO2) as a fraction 0–1 (0 when none recorded).
    var rawOxygen: Double { raw.oxygen }
    var rawSleepHours: Double { raw.sleepTotal / 3600 }
    var rawSleepDeepHours: Double { raw.sleepDeep / 3600 }
    var rawSleepREMHours: Double { raw.sleepREM / 3600 }
    var rawSleepStart: Date? { raw.sleepStart }
    var rawMindfulMinutes: Int { raw.mindfulMinutes }
    /// True when the latest ingested workout ended today.
    var hasWorkoutToday: Bool {
        lastWorkoutEndedAt.map { Calendar.current.isDateInToday($0) } ?? false
    }
    /// False until the first real HealthKit snapshot lands. The 魔丸态 state
    /// machine falls back to a time-only read until then so an empty device
    /// (or demo) doesn't read as 烦躁 (steps < 3000).
    var hasRealHealthData: Bool { hasIngestedAny }
    /// The latest stat change. Set on every recompute / `markDone` /
    /// `applyGain`. The home view watches this with `.onChange` to fire a
    /// sparkle burst on the pet stage.
    var lastDelta: StatDelta? = nil
    /// Set by `handleNewWorkout` when a fresh workout lands. `HomeView`
    /// observes this and pops `WorkoutAlertSheet` from the bottom. Single-slot
    /// — if a second fresh workout arrives while one is still pending, the
    /// previous gets silently consumed first (rare in practice; only happens
    /// on cold launch with two unfetched workouts).
    ///
    /// `didSet` mirrors changes to `UserDefaults` so a force-quit while the
    /// sheet is up doesn't lose the workout's done card on next launch (B3
    /// fix). Restore on init has a freshness cap to avoid showing stale
    /// notifications hours later.
    var pendingWorkout: PendingWorkout? = nil {
        didSet {
            guard pendingWorkout != oldValue else { return }
            persistPendingWorkout()
            publishWidgetSnapshot()
            if let oldValue, let pendingWorkout, oldValue.id != pendingWorkout.id {
                finishPendingWorkoutActivity(for: oldValue, completed: false)
            }
            if let pendingWorkout {
                startOrUpdatePendingWorkoutActivity(for: pendingWorkout)
            }
        }
    }
    /// Bumped each time the user taps 「喂养」. `HomeView` watches this with
    /// `.onChange` to spawn particles + run the pet vibrate effect. Separate
    /// from `lastDelta` so the celebration scales (vibrate + particles) only
    /// fire on user-confirmed feeds, not on every silent stat update.
    var feedToken: UUID? = nil
    /// EndDate of the latest workout we've ingested (HK or otherwise).
    /// Marks the "刚刚运动" window — consumers react to a just-finished workout
    /// (e.g. the 发芽 energy-collection flow / ACTIVE state). Set in
    /// `handleNewWorkout`, cleared on
    /// `reset()`. Survives only in-memory; on cold launch the workout
    /// reconciliation pass replays any sample within the last 36h, so the
    /// "刚刚运动" window naturally re-establishes itself if it's still active.
    private(set) var lastWorkoutEndedAt: Date? = nil

    // — Mode —
    /// `true` → ignore HealthKit events; keep demo defaults. Bound to a
    /// UserDefaults flag so the launcher can flip it without recompiling.
    ///
    /// `didSet` rehydrates `steps` / `stats` on a false→true flip so the
    /// hackathon demo path (`HealthAuthView` → "用 Demo 数据继续") gets the
    /// 5-card narrative even though the store was constructed with
    /// `demoMode: false`. didSet does not fire from `init`, so the initial
    /// path stays controlled by the init body.
    var demoMode: Bool {
        didSet {
            guard demoMode != oldValue else { return }
            LPLog.petState.notice("demoMode \(oldValue, privacy: .public) → \(self.demoMode, privacy: .public)")
            guard demoMode else { return }
            steps = Self.demoSteps
            stats = Self.demoStats
            state = .excited
            // Backdate birth so 已陪伴第 N 天 reads as 7 — matches PRD demo
            // copy. Re-applied on every day rollover so it stays at 7 forever
            // in demo mode.
            identity.seedDemoBirth()
            publishWidgetSnapshot()
        }
    }

    // — Day rollover —
    /// Called after `performRollover()` finishes so the App layer can trigger
    /// `HealthDataService.reconcile()` — repopulates `RawMetrics` for the new
    /// day from HK. Kept as a closure (not a HealthDataService injection) so
    /// the store stays unaware of HK plumbing.
    var onDayRollover: (() -> Void)?

    private static let lastSeenDateKey = PiboPersistenceKeys.Defaults.lastSeenDate
    private static let lastDecayAtKey = PiboPersistenceKeys.Defaults.lastDecayAt
    private static let pendingWorkoutKey = PiboPersistenceKeys.Defaults.pendingWorkout
    /// 持久化恢复 pendingWorkout 时的最大保鲜期。超过这个窗口的运动通知
    /// 即使 UserDefaults 里有，也丢弃 —— 用户夜里关 app 第二天打开看到的
    /// 不应该是昨天的 sheet。
    private static let pendingWorkoutMaxAge: TimeInterval = 60 * 60

    // — Internals —
    private var raw = RawMetrics()
    /// Becomes true on the first non-workout ingest. Until then we keep the
    /// demo defaults instead of slamming the bars to formula-zero values
    /// (e.g. `vitality = 20` when the steps stat hasn't arrived yet).
    private var hasIngestedAny = false
    private var ingestTask: Task<Void, Never>?
    /// On-disk daily history. Written every meaningful state change so the
    /// catalog / HRV baseline / death-trigger consumers always see "what the
    /// home screen would have shown" for any past day.
    private let snapshots: DailySnapshotStore

    /// `identity` and `snapshots` default to freshly-constructed instances so
    /// SwiftUI `#Preview` blocks can keep calling `PetStateStore()` without
    /// every caller threading them through. Production / app launch always
    /// passes the App-owned instances explicitly (see `PiboApp.init`).
    init(identity: PetIdentityStore = PetIdentityStore(),
         snapshots: DailySnapshotStore = DailySnapshotStore(),
         events: AsyncStream<HealthEvent>? = nil,
         demoMode: Bool = false) {
        self.identity = identity
        self.snapshots = snapshots
        self.demoMode = demoMode
        self.stats = Self.demoStats
        self.state = .excited
        self.steps = demoMode ? Self.demoSteps : []
        // Theme + growth persistence (didSet doesn't fire from init).
        self.selectedThemeID = UserDefaults.standard.string(forKey: Self.selectedThemeKey)
        self.growthStage = PiboGrowthStage(
            rawValue: UserDefaults.standard.string(forKey: Self.growthStageKey) ?? "") ?? .mystery
        self.appearance = PiboAppearance.decoded(from: UserDefaults.standard.data(forKey: Self.appearanceKey))
        self.weather = PiboWeather(rawValue: UserDefaults.standard.string(forKey: Self.weatherKey) ?? "") ?? .clear
        LPLog.petState.notice("PetStateStore init demoMode=\(demoMode, privacy: .public) eventsBound=\(events != nil, privacy: .public) day=\(identity.daysSinceBirth, privacy: .public)")

        // Cold-launch rollover catch-up. If the app was killed across one or
        // more midnights, this clears yesterday's in-memory state before the
        // first reconcile fires from `PiboApp`'s scenePhase handler.
        checkDayRollover()

        // In-foreground midnight crossings. Fires while the app is active —
        // background-only crossings are caught by the `scenePhase == .active`
        // path in `PiboApp`, and cold-launch is caught above.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDayRollover()
            }
        }

        // Cold-launch HRV baseline load — reads up to 7 prior days of
        // snapshots from disk and publishes `raw.hrvBaseline` so the first
        // recompute that follows HK ingest derives mood against the right
        // baseline instead of self-flooring at 50.
        Task { [weak self] in
            await self?.refreshBaseline()
        }

        // Cold-launch decay catchup. If app was killed for hours, this
        // applies the elapsed 4h ticks before the first ingest paints
        // formula values on top.
        applyDecayCatchup()

        // 恢复上次未消费完的 workout 通知（B3：force-quit 时 sheet 还挂着的
        // 场景）。两道闸：
        // 1. 1h 保鲜期 —— 超期一律丢，避免昨天 sheet 今天还在弹。
        // 2. **必须是今天**的运动 —— 跨天 init 时 `performRollover` 在 init
        //    内部赋值不会触发 didSet（Swift 语义），UserDefaults 还留着旧
        //    数据；如果只看 age cap，11:55 跑 + 00:25 开 app 这类场景会把昨
        //    天的运动算进今天。data 丢比错算好。
        // Demo mode 一律不恢复（demo 不会写入，但保险起见）。
        if !demoMode, let restored = Self.loadPendingWorkout() {
            let age = Date().timeIntervalSince(restored.endedAt)
            let sameDay = Calendar.current.isDate(restored.endedAt, inSameDayAs: Date())
            if age <= Self.pendingWorkoutMaxAge && sameDay {
                self.pendingWorkout = restored
                LPLog.petState.notice("Restored pendingWorkout: \(restored.label, privacy: .public) \(restored.durationMin, privacy: .public)min (age \(Int(age/60), privacy: .public)min)")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingWorkoutKey)
                LPLog.petState.notice("Discarded stale persisted pendingWorkout (age=\(Int(age/60), privacy: .public)min sameDay=\(sameDay, privacy: .public))")
            }
        }

        publishWidgetSnapshot()
        if let pendingWorkout {
            startOrUpdatePendingWorkoutActivity(for: pendingWorkout)
        }

        guard let events else { return }
        ingestTask = Task { [weak self] in
            for await event in events {
                self?.ingest(event)
            }
        }
    }
    // No `deinit` cleanup — the store is owned by `PiboApp` and lives
    // for the lifetime of the process. The Task auto-cancels when the
    // continuation finishes (which happens never, in practice). The
    // NSCalendarDayChanged observer leaks too, for the same reason.

    // MARK: - Greeting / date

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case ..<5:  return "深夜"
        case ..<11: return "早上好"
        case ..<13: return "午安"
        case ..<18: return "下午好"
        case ..<22: return "晚上好"
        default:    return "夜深了"
        }
    }

    var dateLabel: String {
        let d = Date()
        let cal = Calendar.current
        let weekdays = ["SUN","MON","TUE","WED","THU","FRI","SAT"]
        let wd = weekdays[cal.component(.weekday, from: d) - 1]
        return "\(wd) · \(cal.component(.month, from: d))/\(cal.component(.day, from: d))"
    }

    var doneCount: Int    { steps.filter { $0.status == .done    }.count }
    var suggestCount: Int { steps.filter { $0.status == .suggest }.count }

    // MARK: - User-driven mutations

    func markDone(_ id: StepItem.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }), steps[i].status == .suggest else { return }
        steps[i].status = .done
        steps[i].time = "刚刚"
        let gain = steps[i].gain
        let stat = steps[i].affects
        let kind = steps[i].kind
        LPLog.petState.notice("user markDone kind=\(kind.rawValue, privacy: .public) +\(gain, privacy: .public) → \(stat.label, privacy: .public)")
        applyGain(to: stat, by: gain, reason: steps[i].actionLabel)
        showToast(AppLocalization.format("完成！+%d 星光落下", gain))
        lastInteractionAt[kind] = Date()
        regenerateSuggestions()
    }

    func nudgePibo() {
        speechCursor += 1
        showToast(AppLocalization.text("Pibo 抬头看了你一眼"))
    }

    /// 调试用：把某个 stat 当前值往下扣 `amount` 点（默认 5），并且在非
    /// demo 模式里同步把扣减累计进 `decayPending`，避免下一次 HK ingest 触
    /// 发的 `recompute()` 又把数据按公式拉回去。Demo 模式直接改 `stats`
    /// 即可（demo 不走 ingest 路径）。
    func debugDecrement(_ kind: StatKind, by amount: Int = 5) {
        applyGain(to: kind, by: -amount, reason: "调试")
        if !demoMode {
            decayPending[kind, default: 0] += amount
        }
    }

    func quit(_ id: StepItem.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }), steps[i].status == .suggest else { return }
        let kind = steps[i].kind
        steps.remove(at: i)
        let count = (quitCounts[kind] ?? 0) + 1
        quitCounts[kind] = count
        let label = kind.quitLabel
        LPLog.petState.notice("user quit kind=\(kind.rawValue, privacy: .public) count=\(count, privacy: .public)")
        if count >= 3 {
            showToast(AppLocalization.format("📍 %@ 已被 quit %d 次，偏好已更新", AppLocalization.text(label), count))
        } else {
            showToast(AppLocalization.format("已跳过 · 下次少推%@", AppLocalization.text(label)))
        }
        lastInteractionAt[kind] = Date()
        regenerateSuggestions()
    }

    // MARK: - Reset

    /// Wipe in-memory state back to first-launch defaults. Called from the
    /// home screen's "重置" button after the user confirms. UserDefaults
    /// flags (`pibo.hatched`, `pibo.onboardingDone`) are the caller's
    /// responsibility — this method only touches store state.
    ///
    /// `hasIngestedAny` flips back to `false` so the demo-floor stats show
    /// again until the next HK snapshot lands; `demoMode` is set to `false`
    /// so the next launch starts from a neutral position (the user picks
    /// Demo / HK / later again on the auth screen).
    func reset() {
        LPLog.petState.notice("reset() — wiping in-memory state + minting new pet")
        // Seal the old pet's final snapshot before we mint a new UUID — this
        // is the last chance to preserve "where they were" under the *old*
        // identity. Skipped in demo / when nothing was ingested.
        recordSnapshot()
        raw = RawMetrics()
        hasIngestedAny = false
        quitCounts = [:]
        lastInteractionAt = [:]
        stats = Self.demoStats
        state = .excited
        steps = []
        demoMode = false
        lastDelta = nil
        lastWorkoutEndedAt = nil
        toast = nil
        speechCursor = 0
        if let pendingWorkout {
            finishPendingWorkoutActivity(for: pendingWorkout, completed: false)
        }
        pendingWorkout = nil
        feedToken = nil
        // New pet = back to 魔丸 D1: 「?」卷芽, default theme, fresh story.
        growthStage = .mystery
        UserDefaults.standard.removeObject(forKey: Self.growthStageKey)
        appearance = .default
        UserDefaults.standard.removeObject(forKey: Self.appearanceKey)
        weather = .clear
        UserDefaults.standard.removeObject(forKey: Self.weatherKey)
        selectedThemeID = nil
        story.reset()
        // New pet UUID + name + birth=today. Hackathon semantics: reset means
        // "start fresh" — when snapshot persistence ships, the previous pet's
        // history will still be addressable via its old `currentPetId`.
        identity.resetToFreshPet()
        // Also stamp `lastSeenDate` to today so the next checkDayRollover
        // doesn't fire spuriously off a stale value.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSeenDateKey)
        // Decay buffer is per-pet — wipe and re-anchor the tick clock so the
        // new pet doesn't inherit accumulated pressure or get hit by ticks
        // dated against the old pet's session.
        decayPending = [:]
        saveLastDecayAt(Date())
        // Drop the inherited HRV baseline — the new pet's UUID points at an
        // empty snapshots dir, so any cached value from the old pet is
        // meaningless. `refreshBaseline()` will publish `nil` and mood will
        // floor at 50 until a few days of data accumulate under the new id.
        Task { [weak self] in
            await self?.refreshBaseline()
        }
        publishWidgetSnapshot()
    }

    // MARK: - Day rollover

    /// Compare today vs the persisted `lastSeenDate`. If we've crossed
    /// midnight one or more times, run `performRollover()` and stamp the new
    /// `lastSeenDate`. Idempotent: same-day calls are no-ops.
    ///
    /// Triggered from three places to cover every overnight scenario:
    /// 1. `init` — cold launch after the app was killed across midnight.
    /// 2. `PiboApp`'s `scenePhase == .active` — backgrounded across
    ///    midnight.
    /// 3. `.NSCalendarDayChanged` — app held in foreground across midnight.
    ///
    /// The store doesn't reconcile HK itself; after rollover it fires
    /// `onDayRollover` so the App layer can call `HealthDataService.reconcile()`
    /// and refill `RawMetrics` for the new day.
    func checkDayRollover() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let defaults = UserDefaults.standard
        let lastSeenTs = defaults.double(forKey: Self.lastSeenDateKey)
        let lastSeen = lastSeenTs > 0
            ? cal.startOfDay(for: Date(timeIntervalSince1970: lastSeenTs))
            : today
        if today > lastSeen {
            let days = cal.dateComponents([.day], from: lastSeen, to: today).day ?? 1
            LPLog.petState.notice("day rollover: \(days, privacy: .public) day(s) elapsed since lastSeen=\(LPLog.dateFormatter.string(from: lastSeen), privacy: .public)")
            performRollover(closing: lastSeen)
        }
        defaults.set(today.timeIntervalSince1970, forKey: Self.lastSeenDateKey)
    }

    /// Wipe day-bound in-memory state so the next reconcile rebuilds today
    /// from scratch.
    ///
    /// What we clear and why:
    /// - `raw` + `hasIngestedAny` → next ingest starts fresh; until then,
    ///   `recompute()` short-circuits and the bars carry yesterday's values.
    ///   That's the right UX: the user sees their "last known" stats briefly,
    ///   then watches them animate to today's reality once HK delivers.
    /// - `steps` → both done + suggest cards. Done cards are yesterday's
    ///   accomplishments (stale); suggest cards depended on yesterday's raw
    ///   metrics (stale rationale). The suggestion engine will re-emit fresh
    ///   ones once `regenerateSuggestions()` runs after the next ingest.
    /// - `quitCounts` → "下次少推" is a per-day signal; reset on rollover so
    ///   yesterday's quits don't suppress today's suggestions forever.
    /// - `lastInteractionAt` → cooldown is hours-scale; cross-day doesn't
    ///   carry meaning.
    /// - `lastWorkoutEndedAt` → drives the run-sprite "刚刚运动" window; safe
    ///   to clear because workout reconcile re-replays the last 36h on cold
    ///   launch and re-establishes it if still active.
    ///
    /// Demo mode short-circuits everything (demo data is fixed) but still
    /// re-seeds `birthDate` so `daysSinceBirth` stays at 7 forever — without
    /// this the demo would drift to "第 8 天" overnight.
    private func performRollover(closing closingDate: Date) {
        guard !demoMode else {
            identity.seedDemoBirth()
            publishWidgetSnapshot()
            LPLog.petState.notice("rollover (demo) — re-anchored birth to keep day=7")
            return
        }
        // Seal the closing day's snapshot *before* clearing — otherwise raw
        // is gone and the snapshot would be all zeros. `recordSnapshot` no-ops
        // when `hasIngestedAny == false` (cold-launch rollover after kill →
        // nothing meaningful to write anyway).
        let closeWrite = recordSnapshot(for: closingDate)
        raw = RawMetrics()
        hasIngestedAny = false
        quitCounts = [:]
        lastInteractionAt = [:]
        lastWorkoutEndedAt = nil
        steps = []
        lastDelta = nil
        toast = nil
        // 跨天时把挂着的 sheet 状态清掉。如果用户夜里把 sheet 留着不管，
        // 过了凌晨 pendingWorkout.endedAt 还是昨天的；保留它会让今天点喂养
        // 时插出 `time: "刚刚"` 的卡（实际是昨天的运动）。aggregate 路径已
        // 经把昨天的 vitality 写进 closingDate 的 snapshot 里了，clear 不会
        // 丢数据。
        if let pendingWorkout {
            finishPendingWorkoutActivity(for: pendingWorkout, completed: false)
        }
        pendingWorkout = nil
        feedToken = nil
        // Decay buffer is per-day — clear it and restart the 4h tick clock
        // from "now" so the new day starts with zero pending pressure and
        // its first tick fires 4h into the morning, not immediately.
        decayPending = [:]
        saveLastDecayAt(Date())
        LPLog.petState.notice("rollover — cleared day-bound state, awaiting reconcile (day=\(self.identity.daysSinceBirth, privacy: .public))")
        // Refresh HRV baseline once the closing-day snapshot has landed —
        // chaining via the same Task ensures the actor's serial queue
        // executes the write before the read, so the new day picks up
        // yesterday's HRV as part of its 7-day window.
        Task { [weak self] in
            await closeWrite?.value
            await self?.refreshBaseline()
        }
        publishWidgetSnapshot()
        onDayRollover?()
    }

    // MARK: - Snapshot persistence

    /// Build a `DailySnapshot` from current in-memory state and dispatch it
    /// to `DailySnapshotStore`. Fire-and-forget — disk write is async, the
    /// snapshot value is captured by value, so post-call mutations to `raw` /
    /// `stats` (e.g. rollover clearing) don't affect the persisted record.
    ///
    /// Suppression rules:
    /// - Demo mode → never write. Demo data is fixed and would pollute the
    ///   user's real history under `identity.currentPetId`.
    /// - `!hasIngestedAny` → never write. The bars are still on the
    ///   `demoStats` cold-start floor; persisting them would record fake
    ///   88/74/82 as "today's" stats.
    ///
    /// `date` defaults to today; `performRollover(closing:)` overrides with
    /// the day being closed.
    ///
    /// Returns the spawned write Task so callers that need to chain other
    /// actor work after the write lands (e.g. rollover refreshing the HRV
    /// baseline once yesterday's snapshot is on disk) can `await` it. Most
    /// callers ignore the return — `@discardableResult` keeps them clean.
    @discardableResult
    private func recordSnapshot(for date: Date = Date()) -> Task<Void, Never>? {
        guard !demoMode, hasIngestedAny else { return nil }
        let snap = currentSnapshot(for: date)
        return Task { [snapshots] in
            await snapshots.write(snap)
        }
    }

    private func currentSnapshot(for date: Date) -> DailySnapshot {
        DailySnapshot(
            petId: identity.currentPetId,
            date: Calendar.current.startOfDay(for: date),
            vitality: stats.first(where: { $0.kind == .vitality })?.value ?? 0,
            energy:   stats.first(where: { $0.kind == .energy   })?.value ?? 0,
            mood:     stats.first(where: { $0.kind == .mood     })?.value ?? 0,
            stateTag: state.tag,
            steps: raw.steps,
            exerciseMinutes: raw.exerciseMinutes,
            activeEnergy: raw.activeEnergy,
            standMinutes: raw.standMinutes,
            hrv: raw.hrv,
            restingHR: raw.restingHR,
            sleepTotal: raw.sleepTotal,
            sleepDeep: raw.sleepDeep,
            sleepREM: raw.sleepREM,
            mindfulMinutes: raw.mindfulMinutes,
            completedStepKinds: steps.filter { $0.status == .done }.map { $0.kind.rawValue },
            updatedAt: Date()
        )
    }

    // MARK: - Widget / Live Activity bridge

    private func publishWidgetSnapshot() {
        let snapshot = PiboWidgetSnapshot(
            petName: petName,
            dayCount: dayCount,
            stateTag: state.tag,
            stateLabel: activityState.displayName,
            vitality: statValue(.vitality),
            energy: statValue(.energy),
            mood: statValue(.mood),
            updatedAt: Date(),
            pendingWorkoutTitle: pendingWorkout?.titleLabel,
            pendingWorkoutGain: pendingWorkout?.gainVitality
        )

        if !PiboWidgetSnapshotStore.save(snapshot) {
            LPLog.petState.error("widget snapshot save failed")
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: PiboWidgetConstants.homeWidgetKind)
        #endif
    }

    #if canImport(ActivityKit)
    private func startOrUpdatePendingWorkoutActivity(for workout: PendingWorkout) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LPLog.petState.notice("Live Activity skipped — activities disabled")
            return
        }

        let attributes = PiboFeedActivityAttributes(
            petName: petName,
            workoutID: workout.id
        )
        let contentState = pendingActivityState(for: workout)
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(Self.pendingWorkoutMaxAge)
        )

        Task { @MainActor in
            let activities = Activity<PiboFeedActivityAttributes>.activities
            if let existing = activities.first(where: { $0.attributes.workoutID == workout.id }) {
                await existing.update(content)
                return
            }

            for activity in activities where activity.attributes.workoutID != workout.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            do {
                _ = try Activity<PiboFeedActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                LPLog.petState.notice("Live Activity started for pending workout \(workout.id.uuidString, privacy: .public)")
            } catch {
                LPLog.petState.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func finishPendingWorkoutActivity(for workout: PendingWorkout, completed: Bool) {
        let contentState = finishedActivityState(for: workout, completed: completed)
        let content = ActivityContent(state: contentState, staleDate: Date())

        Task { @MainActor in
            let activities = Activity<PiboFeedActivityAttributes>.activities
                .filter { $0.attributes.workoutID == workout.id }
            guard !activities.isEmpty else { return }

            for activity in activities {
                await activity.end(
                    content,
                    dismissalPolicy: completed ? .after(Date().addingTimeInterval(8)) : .immediate
                )
            }
            LPLog.petState.notice("Live Activity ended for pending workout \(workout.id.uuidString, privacy: .public)")
        }
    }

    private func pendingActivityState(for workout: PendingWorkout) -> PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: workout.titleLabel,
            message: "可喂给 \(petName)，活力星光正在落下",
            vitalityGain: workout.gainVitality,
            stateTag: state.tag,
            endedAt: workout.endedAt,
            isComplete: false
        )
    }

    private func finishedActivityState(
        for workout: PendingWorkout,
        completed: Bool
    ) -> PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: completed ? "已喂给 \(petName)" : "\(workout.titleLabel)已记录",
            message: completed ? "今日运动已变成活力星光" : "运动已记录到今日星光",
            vitalityGain: workout.gainVitality,
            stateTag: state.tag,
            endedAt: workout.endedAt,
            isComplete: true
        )
    }
    #else
    private func startOrUpdatePendingWorkoutActivity(for workout: PendingWorkout) {}
    private func finishPendingWorkoutActivity(for workout: PendingWorkout, completed: Bool) {}
    #endif

    // MARK: - HRV baseline (PRD §3 心情)

    /// Compute the HRV baseline from the last 7 prior days of snapshots and
    /// publish it via `raw.hrvBaseline`. Triggers a `recompute()` so the
    /// mood bar re-derives against the new baseline.
    ///
    /// Window choice — last 7 days *excluding today*:
    /// - "Baseline" = "what's normal for you," not "what you're doing now."
    ///   Including today self-references and pulls mood toward 50.
    /// - 7 days is enough to absorb a single bad night without flattening the
    ///   signal.
    ///
    /// Sample threshold — ≥ 3 prior days with `hrv > 0`:
    /// - HRV requires the watch to be worn during sleep; users skip nights.
    /// - With 1-2 samples the average is noisy enough to swing mood ±20
    ///   between days. 3 is the smallest count that smooths that out.
    /// - When the threshold isn't met, baseline stays `nil` → `computeMood`
    ///   floors at 50 (its existing fallback).
    ///
    /// Idempotent + safe to call repeatedly. Demo mode short-circuits — we
    /// don't want demo to carry baseline noise from a real prior session.
    func refreshBaseline() async {
        guard !demoMode else { return }
        let petId = identity.currentPetId
        // 8 = 7 prior days + today. We discard today below.
        let entries = await snapshots.recent(petId: petId, days: 8)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let priorHRVs = entries
            .filter { cal.startOfDay(for: $0.date) < today && $0.hrv > 0 }
            .map(\.hrv)
        let baseline: Double?
        if priorHRVs.count >= 3 {
            baseline = priorHRVs.reduce(0, +) / Double(priorHRVs.count)
        } else {
            baseline = nil
        }
        raw.hrvBaseline = baseline
        let baselineStr = baseline.map { String(format: "%.1fms", $0) } ?? "nil"
        LPLog.petState.notice("HRV baseline refreshed: \(baselineStr, privacy: .public) from \(priorHRVs.count, privacy: .public)/7 prior day(s)")
        // Re-derive mood against the new baseline. Guarded by hasIngestedAny
        // so we don't run the formula against an empty `RawMetrics` and slam
        // the bars to 20/0/50 cold-start values.
        if hasIngestedAny {
            recompute()
        }
    }

    // MARK: - Decay (PRD §3)

    /// Catch up on any decay ticks that have elapsed since `lastDecayAt`.
    /// PRD §3: each stat naturally drops 5 every 4h (floor 10). 精力 does
    /// not decay during sleep — modeled here as "skip ticks whose timestamp
    /// falls in local 0–7am" (the watch-wear gap most users have).
    ///
    /// Catchup, not scheduling: we don't run a timer. Every entry point
    /// (init, scenePhase=active, post-rollover) just asks "how many full 4h
    /// windows have elapsed since the last tick?" and applies that many to
    /// `decayPending`. Same shape as `checkDayRollover` — robust to app
    /// kills, backgrounding, and clock changes.
    ///
    /// Pressure model: decay is added to `decayPending`, not subtracted from
    /// `stats` directly. `recompute()` does `max(10, formula − pending)` so
    /// fresh HK data continues to drive the bar up while pending tracks the
    /// downward force. `decayPending` resets at day rollover, capping
    /// intra-day decay at ~30 (6 ticks). This is a deliberate softening of
    /// the PRD's "continuous decay forever" — chronic neglect is captured
    /// instead by the death-trigger judgments reading snapshot history.
    func applyDecayCatchup() {
        guard !demoMode else { return }
        let now = Date()
        let last = loadLastDecayAt()
        let interval: TimeInterval = 4 * 3600
        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= interval else { return }
        let ticks = Int(elapsed / interval)

        let cal = Calendar.current
        var energyTicks = 0
        for t in 1...ticks {
            let tickTime = last.addingTimeInterval(TimeInterval(t) * interval)
            // 0–7am local = "user is asleep" — energy doesn't decay.
            let hour = cal.component(.hour, from: tickTime)
            if hour >= 7 { energyTicks += 1 }
        }
        let dropPerTick = 5
        decayPending[.vitality, default: 0] += ticks * dropPerTick
        decayPending[.mood,     default: 0] += ticks * dropPerTick
        decayPending[.energy,   default: 0] += energyTicks * dropPerTick

        // Stamp `lastDecayAt` forward by *consumed* ticks only — preserve the
        // fractional remainder so a tick that's 3h59m old doesn't get
        // accidentally double-applied on the next call 1m later.
        let consumed = TimeInterval(ticks) * interval
        saveLastDecayAt(last.addingTimeInterval(consumed))

        LPLog.petState.notice("decay catchup: \(ticks, privacy: .public) tick(s) → vitality+\(ticks * dropPerTick, privacy: .public) energy+\(energyTicks * dropPerTick, privacy: .public) mood+\(ticks * dropPerTick, privacy: .public) (pending v=\(self.decayPending[.vitality] ?? 0, privacy: .public) e=\(self.decayPending[.energy] ?? 0, privacy: .public) m=\(self.decayPending[.mood] ?? 0, privacy: .public))")

        // Re-derive stats so the bars actually drop. Guarded by hasIngestedAny
        // so cold-launch decay catchup doesn't slam the demo floor with
        // `formula(empty raw) − pending` = floor 10.
        if hasIngestedAny {
            recompute()
        }
    }

    private func loadLastDecayAt() -> Date {
        let ts = UserDefaults.standard.double(forKey: Self.lastDecayAtKey)
        if ts > 0 { return Date(timeIntervalSince1970: ts) }
        // First-ever launch — stamp now so we don't immediately decay against
        // epoch (which would land every stat at 10).
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastDecayAtKey)
        return now
    }

    private func saveLastDecayAt(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastDecayAtKey)
    }

    // MARK: - HealthKit ingest

    /// Single entry point for every `HealthEvent` from `HealthDataService`.
    ///
    /// The two ingest *kinds* take different paths:
    ///
    /// - **Aggregate snapshots** (steps, sleep, HRV, …) update `RawMetrics`
    ///   and trigger a full recompute. The home view animates the affected
    ///   stat bar to its new value.
    /// - **Discrete events** (workout finished) are side-effect-only:
    ///   they prepend a `已完成` card and apply a one-shot gain via
    ///   `applyGain`. They deliberately *do not* recompute, otherwise the
    ///   formula would slam vitality back to its raw-metrics value while
    ///   the corresponding `activeEnergy` / `exerciseMinutes` snapshots
    ///   are still propagating from HealthKit.
    func ingest(_ event: HealthEvent) {
        guard !demoMode else {
            LPLog.petState.debug("ingest skipped (demoMode)")
            return
        }
        switch event {
        case .steps(let n):
            raw.steps = n
            LPLog.petState.debug("ingest steps=\(n, privacy: .public)")
        case .exerciseMinutes(let m):
            raw.exerciseMinutes = m
            LPLog.petState.debug("ingest exerciseMinutes=\(m, privacy: .public)")
        case .activeEnergy(let kcal):
            raw.activeEnergy = kcal
            LPLog.petState.debug("ingest activeEnergy=\(kcal, privacy: .public)kcal")
        case .standMinutes(let m):
            raw.standMinutes = m
            LPLog.petState.debug("ingest standMinutes=\(m, privacy: .public)")
        case .heartRate(let hr):
            raw.heartRate = hr
            LPLog.petState.debug("ingest heartRate=\(hr, privacy: .public)")
        case .hrv(let ms):
            raw.hrv = ms
            LPLog.petState.debug("ingest hrv=\(ms, privacy: .public)ms")
        case .restingHR(let rhr):
            raw.restingHR = rhr
            LPLog.petState.debug("ingest restingHR=\(rhr, privacy: .public)")
        case .oxygen(let frac):
            raw.oxygen = frac
            LPLog.petState.debug("ingest oxygen=\(Int(frac * 100), privacy: .public)%")
        case .sleep(let total, let d, let r, let start):
            raw.sleepTotal = total
            raw.sleepDeep = d
            raw.sleepREM = r
            raw.sleepStart = start
            LPLog.petState.debug("ingest sleep total=\(Int(total/60), privacy: .public)min deep=\(Int(d/60), privacy: .public)min rem=\(Int(r/60), privacy: .public)min")
        case .mindfulMinutes(let m):
            // Snapshot only — the auto-tick path for mindful sessions needs
            // anchored detection (today's total alone can't tell us which
            // session is "new"). Until then the user can tap the suggest
            // card manually.
            raw.mindfulMinutes = m
            LPLog.petState.debug("ingest mindfulMinutes=\(m, privacy: .public)")
        case .workoutFinished(let kind, let duration, let kcal, let end):
            handleNewWorkout(kind: kind, duration: duration, end: end, kcal: kcal)
            return  // discrete event — skip recompute
        }
        hasIngestedAny = true
        recompute()
        // Sleep also drives a "已完成" card on the home screen. Done after
        // recompute so the card's display gain reflects the same energy value
        // the bar just animated to.
        if case .sleep = event { upsertSleepCard() }
    }

    /// Two distinct paths based on `end`:
    ///
    /// - **Fresh** (≤ 5 min ago) — set `pendingWorkout` and **wait for user
    ///   confirmation** before applying gain or inserting a done card. The
    ///   `WorkoutAlertSheet` pops up; tapping 「喂养」 calls
    ///   `consumePendingWorkout()`, dismissing it via backdrop calls
    ///   `dismissPendingWorkout()`. Either way, gain ultimately lands —
    ///   the sheet only controls celebration intensity (particles +
    ///   vibrate vs. silent).
    /// - **Replay** (> 5 min ago, e.g. last night's run on first launch) —
    ///   display only. Insert a done card immediately; do NOT applyGain
    ///   (aggregate `exerciseMinutes` / `activeEnergy` already absorbed it,
    ///   double-counting would slam vitality), do NOT pop the sheet (the
    ///   "ritual" makes no sense for an event from yesterday).
    ///
    /// Suggest-card dedup runs in both paths — a finished run still claims a
    /// running suggest card.
    private func handleNewWorkout(kind: HealthEvent.WorkoutKind, duration: TimeInterval, end: Date, kcal: Double? = nil) {
        // Only run / walk are "matchable" against suggest cards. Other
        // activities (yoga, cycle, hiit, other) feed vitality but never
        // claim a running suggest as completed.
        let suggestMatch: StepKind? = {
            switch kind {
            case .run:  return .run
            case .walk: return .walk
            case .cycle, .hiit, .yoga, .other: return nil
            }
        }()
        if let mk = suggestMatch {
            steps.removeAll { $0.status == .suggest && $0.kind == mk }
        }

        let durMin = max(1, Int(duration / 60))
        // PRD: 运动 10 分钟 +10
        let gain = min(60, durMin)
        let label = workoutLabel(kind)
        let isFresh = Date().timeIntervalSince(end) < 5 * 60

        // Track the latest endDate so the sprite picker can show `run` while
        // the workout is still "fresh" in the user's mind. Use max() because
        // workouts can arrive out of order (anchored replay batches them by
        // insertion order, not chronologically). Done in both paths —
        // sprite override applies regardless of who applied gain.
        if lastWorkoutEndedAt.map({ end > $0 }) ?? true {
            lastWorkoutEndedAt = end
        }

        if isFresh {
            // If a previous pending workout never got consumed (e.g. user
            // killed app with sheet open), silently apply its gain + insert
            // its done card before overwriting — never lose data.
            if pendingWorkout != nil {
                LPLog.petState.notice("new fresh workout arrived while one was pending — silent-consuming the previous one")
                dismissPendingWorkout()
            }
            let pw = PendingWorkout(
                id: UUID(),
                kind: kind,
                label: label,
                durationMin: durMin,
                kcal: kcal,
                endedAt: end,
                gainVitality: gain
            )
            pendingWorkout = pw
            LPLog.petState.notice("workout fresh → pendingWorkout: \(label, privacy: .public) \(durMin, privacy: .public)min +\(gain, privacy: .public) (awaiting user 喂养)")
            return
        }

        // Replay path — display only.
        let item = StepItem(
            status: .done,
            kind: suggestMatch ?? .run,
            actionLabel: label,
            titleValue: AppLocalization.format("%d 分钟", durMin),
            affects: .vitality,
            gain: gain,
            time: relativeTimeLabel(end),
            fromAutoSensor: true
        )
        steps.insert(item, at: 0)
        LPLog.petState.info("workout replay: \(label, privacy: .public) \(durMin, privacy: .public)min ended \(LPLog.dateFormatter.string(from: end), privacy: .public) — display only")
    }

    // MARK: - Pending workout consumption

    /// User tapped 「喂养」 in `WorkoutAlertSheet`. Apply the deferred gain,
    /// insert a fresh done card, fire the celebration animation token, and
    /// clear the pending slot. No-op if there's nothing pending.
    ///
    /// 顺序：**先**置 `pendingWorkout = nil` —— didSet 同步抹掉 UserDefaults 的
    /// 持久化 key。如果在剩下的 side-effect 期间 app 崩了，最坏的结果是这一
    /// 笔的 gain / 卡丢失（aggregate 路径会迟到补 vitality）；不会因为持久化
    /// 还在导致下次启动恢复同一笔再喂养一次而被算两份。
    func consumePendingWorkout() {
        guard let pw = pendingWorkout else { return }
        LPLog.petState.notice("consume pending: \(pw.label, privacy: .public) \(pw.durationMin, privacy: .public)min +\(pw.gainVitality, privacy: .public) (user-confirmed)")
        pendingWorkout = nil
        insertDoneCard(for: pw, time: AppLocalization.text("刚刚"))
        applyGain(to: .vitality, by: pw.gainVitality, reason: pw.label)
        showToast(AppLocalization.format("%@ 醒过来一点！+%d 活力星光", petName, pw.gainVitality))
        feedToken = UUID()
        finishPendingWorkoutActivity(for: pw, completed: true)
    }

    /// User dismissed the sheet without tapping 「喂养」 (backdrop tap, swipe
    /// down). Silently apply the gain + insert the card so we don't lose
    /// the data — but skip the celebration token so no particles / vibrate.
    func dismissPendingWorkout() {
        guard let pw = pendingWorkout else { return }
        LPLog.petState.notice("dismiss pending: \(pw.label, privacy: .public) \(pw.durationMin, privacy: .public)min +\(pw.gainVitality, privacy: .public) (silent)")
        pendingWorkout = nil
        insertDoneCard(for: pw, time: "刚刚")
        applyGain(to: .vitality, by: pw.gainVitality, reason: pw.label)
        finishPendingWorkoutActivity(for: pw, completed: false)
    }

    private func insertDoneCard(for pw: PendingWorkout, time: String) {
        let suggestMatch: StepKind? = {
            switch pw.kind {
            case .run:  return .run
            case .walk: return .walk
            case .cycle, .hiit, .yoga, .other: return nil
            }
        }()
        let item = StepItem(
            status: .done,
            kind: suggestMatch ?? .run,
            actionLabel: pw.label,
            titleValue: "\(pw.durationMin) 分钟",
            affects: .vitality,
            gain: pw.gainVitality,
            time: time,
            fromAutoSensor: true
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            steps.insert(item, at: 0)
        }
    }

    private func workoutLabel(_ kind: HealthEvent.WorkoutKind) -> String {
        switch kind {
        case .run:   return AppLocalization.text("跑步")
        case .walk:  return AppLocalization.text("走路")
        case .cycle: return AppLocalization.text("骑行")
        case .hiit:  return AppLocalization.text("高强度训练")
        case .yoga:  return AppLocalization.text("瑜伽")
        case .other: return AppLocalization.text("运动")
        }
    }

    // MARK: - Pending workout persistence

    /// `pendingWorkout` 的 `didSet` 会调到这里。non-nil → 编码进
    /// UserDefaults；nil → 抹掉 key。强杀场景里至少能保住"用户没来得及确认
    /// 的那一笔运动通知"。失败场景（极罕见）记 error 并抹掉 key，避免脏数
    /// 据卡在那里下次还把同一个 sheet 弹出来。
    private func persistPendingWorkout() {
        let defaults = UserDefaults.standard
        guard let pw = pendingWorkout else {
            defaults.removeObject(forKey: Self.pendingWorkoutKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(pw)
            defaults.set(data, forKey: Self.pendingWorkoutKey)
        } catch {
            LPLog.petState.error("persistPendingWorkout encode failed: \(error.localizedDescription, privacy: .public) — clearing key")
            defaults.removeObject(forKey: Self.pendingWorkoutKey)
        }
    }

    private static func loadPendingWorkout() -> PendingWorkout? {
        guard let data = UserDefaults.standard.data(forKey: pendingWorkoutKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PendingWorkout.self, from: data)
        } catch {
            LPLog.petState.error("loadPendingWorkout decode failed: \(error.localizedDescription, privacy: .public) — discarding")
            UserDefaults.standard.removeObject(forKey: pendingWorkoutKey)
            return nil
        }
    }

    // MARK: - Recompute

    /// Plug `raw` into PRD §3, clamp, set `state` per §5 priority. Posts the
    /// largest single-stat change as `lastDelta` so the home view can react.
    private func recompute() {
        guard hasIngestedAny else { return }
        let oldValues: [StatKind: Int] = Dictionary(uniqueKeysWithValues: stats.map { ($0.kind, $0.value) })
        let oldState = state
        // Subtract the accumulated decay buffer (PRD §3, see
        // `applyDecayCatchup`) and clamp to floor 10. Formula values that
        // would otherwise put a stat at e.g. 80 still drive upward — decay
        // is a counter-pressure, not a hard cap.
        let v = max(10, computeVitality() - (decayPending[.vitality] ?? 0))
        let e = max(10, computeEnergy()   - (decayPending[.energy]   ?? 0))
        let m = max(10, computeMood()     - (decayPending[.mood]     ?? 0))
        stats = [
            Stat(kind: .vitality, value: v),
            Stat(kind: .energy,   value: e),
            Stat(kind: .mood,     value: m),
        ]
        if let delta = largestChange(old: oldValues, new: [.vitality: v, .energy: e, .mood: m]) {
            lastDelta = delta
        }
        state = derivePetState(v: v, e: e, m: m)
        LPLog.petState.info("recompute v=\(v, privacy: .public) e=\(e, privacy: .public) m=\(m, privacy: .public) state=\(self.state.tag, privacy: .public)")
        if state != oldState {
            LPLog.petState.notice("state transition: \(oldState.tag, privacy: .public) → \(self.state.tag, privacy: .public)")
        }
        regenerateSuggestions()
        recordSnapshot()
        publishWidgetSnapshot()
    }

    private func computeVitality() -> Int {
        let base = 20.0
        let stepC = Double(raw.steps) / 10000 * 40
        let exC   = Double(raw.exerciseMinutes) / 30 * 30
        let kcalC = raw.activeEnergy / 300 * 10
        return clamp(Int(base + stepC + exC + kcalC))
    }

    private func computeEnergy() -> Int {
        let totalH = raw.sleepTotal / 3600
        let deepH  = raw.sleepDeep / 3600
        let remH   = raw.sleepREM / 3600
        let base = totalH/8*50 + deepH/2*30 + remH/1.5*20
        // PRD §3 公式只看时长加权；这里再叠一层 Pibo 内部 sleep score 的修正
        // (-21…+9)，让"评分高"用户得到额外奖励、"评分差"获得轻微惩罚。
        // Apple iOS 26 的 Sleep Score 没有公开 HealthKit type 可读，所以
        // score 由 `computeSleepScore()` 自行从 stages 重算。
        let modifier = (Double(computeSleepScore()) - 70) * 0.3
        return clamp(Int(base + modifier))
    }

    /// Pibo 内部的睡眠评分 [0, 100]。仅基于已读到的 sleep stages —
    /// duration / deep / REM / 连续性近似，**不**等同 Apple Health 的 Sleep
    /// Score（那个分数 watchOS 26 起在系统里展示但 HealthKit 不暴露）。
    private func computeSleepScore() -> Int {
        let totalH = raw.sleepTotal / 3600
        let deepH  = raw.sleepDeep / 3600
        let remH   = raw.sleepREM / 3600
        let duration   = min(1, totalH / 8)   * 50  // 时长 — 8h 满分
        let deep       = min(1, deepH  / 1.5) * 25  // 深睡 — 1.5h 满分
        let rem        = min(1, remH   / 1.5) * 15  // REM  — 1.5h 满分
        let continuity = min(1, totalH / 6)   * 10  // 连续性近似（暂用总时长，待接入 awake 段后改真实）
        return clamp(Int(duration + deep + rem + continuity))
    }

    private func computeMood() -> Int {
        // PRD §3 心情 = 50 + (HRV_今 - HRV_基线)·0.8.
        //
        // `raw.hrvBaseline` is populated by `refreshBaseline()` from the last
        // 7 prior days of snapshots (≥3 valid samples required, else nil).
        // Until enough history accumulates we fall back to today's own HRV
        // as the baseline → contribution = 0 → mood floors at 50. That's the
        // right cold-start behavior: a brand-new pet has no "normal" to
        // compare against, so we don't pretend.
        guard raw.hrv > 0 else { return 50 }
        let baseline = raw.hrvBaseline ?? raw.hrv
        return clamp(50 + Int((raw.hrv - baseline) * 0.8))
    }

    private func derivePetState(v: Int, e: Int, m: Int) -> PetState {
        if m < 30 { return .sick }
        if e < 30 { return .sleeping }
        if v < 30 { return .tired }
        if m > 85 { return .blissful }
        if v > 85 { return .excited }
        return .normal
    }

    private func clamp(_ x: Int) -> Int { min(100, max(0, x)) }

    private func largestChange(old: [StatKind: Int], new: [StatKind: Int]) -> StatDelta? {
        let candidates: [(StatKind, Int)] = new.map { kind, value in (kind, value - (old[kind] ?? value)) }
            .filter { $0.1 != 0 }
        guard let max = candidates.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        return StatDelta(kind: max.0, delta: max.1, reason: nil)
    }

    // MARK: - Helpers

    private func applyGain(to kind: StatKind, by gain: Int, reason: String? = nil) {
        guard let i = stats.firstIndex(where: { $0.kind == kind }) else { return }
        let before = stats[i].value
        let after = clamp(before + gain)
        guard after != before else {
            LPLog.petState.debug("applyGain noop \(kind.label, privacy: .public) +\(gain, privacy: .public) (clamped at \(before, privacy: .public))")
            return
        }
        stats[i].value = after
        lastDelta = StatDelta(kind: kind, delta: after - before, reason: reason)
        let oldState = state
        state = derivePetState(v: stats[0].value, e: stats[1].value, m: stats[2].value)
        LPLog.petState.info("applyGain \(kind.label, privacy: .public) \(before, privacy: .public)→\(after, privacy: .public) (+\(gain, privacy: .public)) reason=\(reason ?? "-", privacy: .public)")
        if state != oldState {
            LPLog.petState.notice("state transition: \(oldState.tag, privacy: .public) → \(self.state.tag, privacy: .public)")
        }
        // applyGain mutates stats outside `recompute()` — without this write,
        // a manual markDone bump wouldn't be persisted until the next HK
        // ingest fires recompute (could be hours later).
        recordSnapshot()
        publishWidgetSnapshot()
    }

    // MARK: - Sleep card upsert

    /// Maintain a single `已完成 · 入睡` card driven by the latest sleep
    /// snapshot. snapshot 路径里没有"新事件"概念，所以每次 ingest 都把这张卡
    /// 更新到位（标题 / 时间 / 显示用 gain），不会越积越多。
    ///
    /// 关键：卡片上的 `+gain` 是**展示用**当下精力贡献（即 `computeEnergy()`），
    /// **不**调用 `applyGain` —— 精力 bar 已经由 `recompute()` 从 sleep snapshot
    /// 直接计算。再 applyGain 会让睡眠贡献被算两次、必定撞顶。
    private func upsertSleepCard() {
        // 30 分钟以下大概率是误分类小睡或残留样本，不展示。同时把过去可能存在的
        // 卡片清掉，避免空数据残留 stale gain。
        guard raw.sleepTotal >= 30 * 60 else {
            steps.removeAll { $0.kind == .sleep && $0.fromAutoSensor }
            return
        }
        let energy = computeEnergy()  // 已 clamp 到 0...100
        let title = sleepDurationLabel(raw.sleepTotal)
        let time = sleepStartLabel(raw.sleepStart)

        if let i = steps.firstIndex(where: { $0.kind == .sleep && $0.fromAutoSensor }) {
            steps[i].titleValue = title
            steps[i].time = time
            steps[i].gain = energy
            steps[i].status = .done
        } else {
            let item = StepItem(
                status: .done,
                kind: .sleep,
                actionLabel: AppLocalization.text("入睡"),
                titleValue: title,
                affects: .energy,
                gain: energy,
                time: time,
                fromAutoSensor: true
            )
            steps.insert(item, at: 0)
        }
    }

    private func sleepDurationLabel(_ seconds: TimeInterval) -> String {
        let totalMin = Int(seconds / 60)
        let h = totalMin / 60
        let m = totalMin % 60
        if h == 0 { return AppLocalization.format("%d 分", m) }
        if m == 0 { return AppLocalization.format("%d 小时", h) }
        return AppLocalization.format("%d 小时 %d 分", h, m)
    }

    private func sleepStartLabel(_ start: Date?) -> String {
        guard let start else { return "" }
        return relativeTimeLabel(start)
    }

    /// Shared "今 HH:MM / 昨 HH:MM / M/D HH:MM" formatter. Used by sleep cards
    /// (driven by the asleep* sample's start) and historical workout replay
    /// cards (driven by the workout's endDate).
    private func relativeTimeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let hh = cal.component(.hour, from: d)
        let mm = cal.component(.minute, from: d)
        let timeStr = String(format: "%02d:%02d", hh, mm)
        if cal.isDateInYesterday(d) { return AppLocalization.format("昨 %@", timeStr) }
        if cal.isDateInToday(d)     { return AppLocalization.format("今 %@", timeStr) }
        let md = "\(cal.component(.month, from: d))/\(cal.component(.day, from: d))"
        return "\(md) \(timeStr)"
    }

    // MARK: - Suggest cards (PRD §4 — 建议卡)

    /// One rule that knows whether and how to suggest a given `StepKind`.
    /// Closures capture the *type* of dependency on store state, not state
    /// itself — they're invoked with `self` at decision time.
    private struct SuggestionRule {
        let kind: StepKind
        /// Which stat this rule's gain feeds — also the priority key when we
        /// have to pick which `n` of `m` eligible rules to surface.
        let affects: StatKind
        let eligible: (PetStateStore) -> Bool
        let make: (PetStateStore) -> StepItem
    }

    /// Static rule table. Rule order is *not* the priority order at runtime —
    /// `regenerateSuggestions` re-sorts eligible rules by lowest stat.
    private static let suggestionRules: [SuggestionRule] = [
        SuggestionRule(kind: .walk, affects: .vitality,
            eligible: { s in s.raw.steps < 8000 && s.statValue(.vitality) < 85 && s.isWakingHour },
            make: { s in
                // Stretch goal toward 8k, capped 500…2000, rounded up to nearest 500.
                let needed = max(500, min(2000, 8000 - s.raw.steps))
                let deficit = ((needed + 499) / 500) * 500
                let gain = max(2, deficit / 1000 * 4)   // PRD: 走 1000 步 +4
                return StepItem(status: .suggest, kind: .walk, actionLabel: AppLocalization.text("再走"),
                                titleValue: AppLocalization.format("%d 步", deficit), affects: .vitality,
                                gain: gain, time: "", fromAutoSensor: false)
            }),
        SuggestionRule(kind: .run, affects: .vitality,
            eligible: { s in s.raw.exerciseMinutes < 20 && s.statValue(.vitality) < 75 && s.isWakingHour },
            make: { _ in
                StepItem(status: .suggest, kind: .run, actionLabel: AppLocalization.text("去跑"),
                         titleValue: AppLocalization.format("%d 分钟", 20), affects: .vitality,
                         gain: 20, time: "", fromAutoSensor: false)
            }),
        SuggestionRule(kind: .meditate, affects: .mood,
            eligible: { s in s.raw.mindfulMinutes < 5 && s.statValue(.mood) < 85 },
            make: { _ in
                StepItem(status: .suggest, kind: .meditate, actionLabel: AppLocalization.text("冥想"),
                         titleValue: AppLocalization.format("%d 分钟", 5), affects: .mood,
                         gain: 15, time: "", fromAutoSensor: false)
            }),
        SuggestionRule(kind: .breath, affects: .mood,
            eligible: { s in s.statValue(.mood) < 65 },
            make: { _ in
                StepItem(status: .suggest, kind: .breath, actionLabel: AppLocalization.text("深呼吸"),
                         titleValue: AppLocalization.format("%d 次", 3), affects: .mood,
                         gain: 9, time: "", fromAutoSensor: false)
            }),
    ]

    private var isWakingHour: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 6 && h < 22
    }

    private func statValue(_ k: StatKind) -> Int {
        stats.first(where: { $0.kind == k })?.value ?? 50
    }

    /// Reconcile suggest cards with what the rule table currently wants.
    ///
    /// Called from:
    /// - end of `recompute()` — HK snapshot landed, stats moved.
    /// - end of `markDone` / `quit` — user freed a slot or signaled disinterest.
    ///
    /// Suppression:
    /// - Skipped in `demoMode` — `demoSteps` already paints the screen.
    /// - Skipped before `hasIngestedAny` — avoid slamming the demo
    ///   `BEAN/D07/88·74·82` floor with formula-derived suggestions.
    /// - Per-kind 2h cooldown after the user marks done OR quits that kind.
    /// - `quitCounts >= 3` → hard block (PRD §4 "下次少推").
    ///
    /// Cap: at most 2 active suggest cards. When more than 2 rules are
    /// eligible, the lowest-stat ones win — the home screen surfaces what's
    /// most needed.
    private func regenerateSuggestions() {
        guard !demoMode, hasIngestedAny else { return }
        let maxSuggestions = 2
        let cooldown: TimeInterval = 2 * 60 * 60
        let now = Date()

        let eligible = Self.suggestionRules.filter { rule in
            if (quitCounts[rule.kind] ?? 0) >= 3 { return false }
            if let last = lastInteractionAt[rule.kind],
               now.timeIntervalSince(last) < cooldown { return false }
            return rule.eligible(self)
        }
        let prioritized = eligible.sorted { lhs, rhs in
            statValue(lhs.affects) < statValue(rhs.affects)
        }
        let winners = prioritized.prefix(maxSuggestions)
        let winningKinds = Set(winners.map(\.kind))

        // Drop suggest cards no longer wanted.
        steps.removeAll { $0.status == .suggest && !winningKinds.contains($0.kind) }

        // Append new suggestions (don't replace ones already shown — keeps id stable).
        let present = Set(steps.filter { $0.status == .suggest }.map(\.kind))
        for rule in winners where !present.contains(rule.kind) {
            steps.append(rule.make(self))
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.toast == msg { self?.toast = nil }
        }
    }
}
