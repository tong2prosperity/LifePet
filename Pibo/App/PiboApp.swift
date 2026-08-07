import SwiftUI
import SwiftData
import os
import PiboCore

@main
struct PiboApp: App {
    /// In-app SwiftData store of complete per-day HealthKit history (the 二楼's
    /// source for past days + the month heat-map).
    private let modelContainer: ModelContainer
    @State private var history: HealthHistoryStore
    /// Persisted pet identity (UUID, name, birthDate). Lives for the lifetime
    /// of the process so day-count derivations stay stable across views.
    @State private var identity: PetIdentityStore
    /// On-disk daily history. App-owned so future views (catalog detail, HRV
    /// baseline, death judgments) can read it without spinning up their own
    /// instance pointing at the same files.
    private let snapshots: DailySnapshotStore
    /// Single HealthKit pipeline for the app. Lives for the lifetime of the
    /// process; `RootView` reads it from the environment.
    @State private var health: HealthDataService
    /// Cross-process sleep notification state + the one-shot morning sheet item.
    @State private var morningSleep: MorningSleepCoordinator
    /// Sole consumer of `health.events`. The store is the only thing that
    /// mutates pet state; views observe it via `@Environment`.
    @State private var store: PetStateStore
    /// Versioned first-run, story-consent and events 01–03 facts.
    @State private var onboarding: OnboardingStateStore
    /// Coalesced, durable presentation request for the latest crossed bo
    /// milestone. The local ledger writes committed balances into this seam.
    @State private var boProgressFeedback: BoProgressFeedbackStore
    /// 本地优先的 `bo` 账本 —— 健康数据经 `pibo-core` 计分、成熟、拔取、消费的
    /// 唯一真源。不依赖登录，也不依赖 `pibo-server`（决定 031）。
    @State private var boLedger: BoLedgerStore
    /// 已解锁的森林物件。与账本分开：余额可增可减，解锁是只增不减的既成事实。
    @State private var ornamentUnlocks: OrnamentUnlockStore
    /// 物件身上被亲手点亮的灯。与解锁再分开一层：解锁是永久的，点灯天亮就作废。
    @State private var ornamentLights = OrnamentLightStore()
    /// One app-wide resolver for all contextual Pibo copy. Views submit cues;
    /// the service owns scarcity, deduplication, and authored-line selection.
    @State private var piboSpeech: PiboSpeechService
    /// Backend auth + economy clients (pibo-server). App-owned so any screen can
    /// drive login / sync via `@Environment`. The demo runs without a server;
    /// these only do work once the user logs in (see `BackendLoginView`).
    @State private var auth: AuthService
    @State private var economy: EconomyService
    /// Bridges the HealthKit history into `EconomyService.sync` (today's samples).
    @State private var coordinator: EconomySyncCoordinator
    /// StoreKit 2 会员订阅 (Pibo 会员 monthly/yearly) + server registration.
    @State private var membership: MembershipService
    /// WeatherKit + coarse foreground location, cached across launches.
    @State private var weather: WeatherDataService

    @Environment(\.scenePhase) private var scenePhase

    init() {
        PiboPersistenceMigrator.runIfNeeded()
        LPLog.app.notice("App launched")
        Analytics.start()
        Analytics.track(.appLaunch)
        let id = PetIdentityStore()
        let snaps = DailySnapshotStore()
        let morning = MorningSleepCoordinator()
        AppNotificationRouter.shared.onMorningSleepOpened = { [weak morning] wakeDay, isMock in
            morning?.handleNotificationOpen(wakeDayKey: wakeDay, isMock: isMock)
        }
        // Tapping a stress push lands on the 压力卡. Raised here rather than
        // presented directly because the tap can arrive on a cold launch, before
        // any view exists — `HomeView` drains the flag once it's on screen.
        AppNotificationRouter.shared.onStressOpened = {
            StressNotifier.shared.pendingCardOpen = true
        }
        AppNotificationRouter.shared.install()
        let h = HealthDataService(morningSleepCoordinator: morning)
        // A night that is still settling gets a second look while the app stays
        // open — once the last sample lands, no further observer wake-up comes.
        morning.onRecheckNeeded = { [weak h] in
            await h?.refreshMorningSleep()
        }
        let s = PetStateStore(identity: id, snapshots: snaps, events: h.events)
        AppNotificationRouter.shared.onAchievementOpened = { [weak s] in
            s?.animationExperience.requestNotificationPresentation()
        }
        // Wire rollover → reconcile. The store doesn't know about
        // HealthDataService; this closure is the only seam.
        s.onDayRollover = { [h] in
            Task { @MainActor in
                guard h.authState == .granted else { return }
                LPLog.app.notice("post-rollover reconcile triggered")
                await h.reconcile()
            }
        }
        _identity = State(initialValue: id)
        self.snapshots = snaps
        _health = State(initialValue: h)
        _morningSleep = State(initialValue: morning)
        _store = State(initialValue: s)
        let onboardingState = OnboardingStateStore()
        _onboarding = State(initialValue: onboardingState)
        let boFeedback = BoProgressFeedbackStore()
        _boProgressFeedback = State(initialValue: boFeedback)

        modelContainer = Self.makeModelContainer()
        let hist = HealthHistoryStore(context: modelContainer.mainContext)
        _history = State(initialValue: hist)

        // 账本从「它自己被创建的那天」起算，不追溯 —— 老用户升级上来时，之前几十天
        // 的健康记录不会被扫进来（那只会被冻结规则一次性烧掉，见 `BoLedgerStore.init`）。
        let boEligibilityStartAt = PiboReleaseScope.temporaryCooperationOnboarding
            ? onboardingState.acceptedAt
            : onboardingState.snapshot.completedAt
        let boEligibilitySource: BoEligibilitySource? = if PiboReleaseScope.temporaryCooperationOnboarding {
            boEligibilityStartAt == nil ? nil : .temporaryCooperation
        } else {
            switch onboardingState.completionTimeBasis {
            case .legacyMigrationFallback:
                .legacyOnboardingMigration
            case .recorded:
                .legacyOnboarding
            case nil:
                nil
            }
        }
        let ledger = BoLedgerStore(
            acceptedAt: boEligibilityStartAt,
            eligibilitySource: boEligibilitySource,
            eligibilityEnabled: boEligibilityStartAt != nil,
            progressFeedback: boFeedback
        )
        _boLedger = State(initialValue: ledger)
        onboardingState.configureTemporaryCooperation(
            enabled: PiboReleaseScope.temporaryCooperationOnboarding,
            boLifetimeMinted: ledger.lifetimeMinted,
            boLifetimeCollected: ledger.lifetimeCollected
        )
        _piboSpeech = State(initialValue: PiboSpeechService(
            narrativeProgress: {
                guard PiboReleaseScope.temporaryCooperationOnboarding else {
                    return Int(PiboCoreStorySpeechStage.unresponded.rawValue)
                }
                return Int(onboardingState.eventProjection().speechStage.rawValue)
            }
        ))
        let inventory = OrnamentUnlockStore()
        inventory.recoverPendingPurchase(using: ledger)
        morning.configureCapabilities(
            sleepReview: { [weak inventory] in
                inventory?.grants(.sleepReview) == true
            },
            wakeNotification: { [weak inventory] in
                inventory?.grants(.wakeNotification) == true
            }
        )
        _ornamentUnlocks = State(initialValue: inventory)

        let a = AuthService()
        let e = EconomyService()
        _auth = State(initialValue: a)
        _economy = State(initialValue: e)
        _coordinator = State(initialValue: EconomySyncCoordinator(auth: a, economy: e, history: hist))
        _membership = State(initialValue: MembershipService())
        _weather = State(initialValue: WeatherDataService())
    }

    /// Build the on-disk history store. If the store can't open (usually an
    /// incompatible schema left by an older build — SwiftData can't always
    /// lightweight-migrate), delete the store files and recreate it fresh on
    /// disk so history *persists* going forward, rather than silently dropping
    /// to an in-memory store that loses everything on every relaunch. Only if
    /// even a fresh on-disk store fails do we use in-memory as a last resort.
    private static func makeModelContainer() -> ModelContainer {
        let models: [any PersistentModel.Type] = [
            HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self,
        ]
        let schema = Schema(models)
        // Explicit store URL under Application Support — created up front, because
        // SwiftData's default configuration can fail with `loadIssueModelContainer`
        // when that directory doesn't yet exist in the app container.
        let storeURL = Self.historyStoreURL()
        Self.migrateLegacyDefaultStoreIfNeeded(to: storeURL)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            LPLog.app.error("History store open failed, resetting on-disk store: \(String(reflecting: error), privacy: .public)")
            Self.removeStoreFiles(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                LPLog.app.error("History store still failing, using in-memory: \(String(reflecting: error), privacy: .public)")
                return try! ModelContainer(for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            }
        }
    }

    /// The on-disk history store URL, with its parent directory created.
    private static func historyStoreURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL.applicationSupportDirectory
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "PiboHistory.store")
    }

    /// One-time adoption of SwiftData's old default-location store. Earlier
    /// builds used the default configuration (Application Support/default.store);
    /// on devices where that store opened fine it holds real history. Copy it to
    /// the new explicit URL rather than orphaning it — if the copy turns out
    /// schema-incompatible, the delete-and-retry path above resets only the copy,
    /// leaving the legacy files untouched.
    private static func migrateLegacyDefaultStoreIfNeeded(to url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        let dir = url.deletingLastPathComponent()
        let legacy = dir.appending(path: "default.store")
        guard fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            try? fm.copyItem(at: dir.appending(path: "default.store" + suffix),
                             to: dir.appending(path: url.lastPathComponent + suffix))
        }
        LPLog.app.notice("migrated legacy default.store → \(url.lastPathComponent, privacy: .public)")
    }

    /// Delete a SwiftData store (+ its -wal / -shm sidecars).
    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: url.deletingLastPathComponent()
                .appending(path: url.lastPathComponent + suffix))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(identity)
                .environment(health)
                .environment(morningSleep)
                .environment(store)
                .environment(onboarding)
                .environment(boProgressFeedback)
                .environment(boLedger)
                .environment(ornamentUnlocks)
                .environment(ornamentLights)
                .environment(piboSpeech)
                .environment(history)
                .environment(auth)
                .environment(economy)
                .environment(coordinator)
                .environment(membership)
                .environment(weather)
                .environment(StressNotifier.shared)
                .environment(WorkoutCompletionNotifier.shared)
                .modelContainer(modelContainer)
                .preferredColorScheme(.light)   // LP palette is light-only paper
                .task {
                    // Lifetime StoreKit transaction listener + entitlement hydrate.
                    membership.start()
                    weather.start()
                    // Set up foreground presentation + quiet provisional auth so
                    // passive users are covered without a prompt.
                    await StressNotifier.shared.start()
                    await WorkoutCompletionNotifier.shared.start()
                    morningSleep.setAppActive(scenePhase == .active)
                    if scenePhase == .active, health.authState == .granted {
                        await health.refreshMorningSleep()
                    }
                    morningSleep.presentLatestIfEligible()
                    // The enrichment prompt is a system modal; asking for it
                    // while a morning card is queued would either race the sheet
                    // or bury it. It can wait for a launch with nothing pending.
                    if scenePhase == .active,
                       health.authState == .granted,
                       morningSleep.pendingPresentation == nil {
                        await health.requestWellnessAuthorizationIfNeeded()
                        await health.requestMorningSleepEnrichmentAuthorizationIfNeeded()
                    }
                    // Backfill the SwiftData history once per launch. On a real
                    // authorized device this is HK data; on a simulator with no
                    // HK, DEBUG-seed so the 二楼 is demonstrable.
                    #if DEBUG
                    let forceHistoryDemo = ProcessInfo.processInfo.arguments
                        .contains("-PiboHistoryDemoContent")
                    if health.authState != .granted || forceHistoryDemo {
                        // Let Home commit its first frame before optional demo
                        // data maintenance. Image generation inside the seeder
                        // runs off the main actor and is versioned per day.
                        await Task.yield()
                        await history.seedSampleAllIfEmpty(
                            forceMaintenance: forceHistoryDemo
                        )
                        store.debugSeedStressIfNeeded()
                    }
                    #endif
                    await backfillHealthHistoryIfAuthorized()
                    if PiboReleaseScope.temporaryCooperationOnboarding {
                        onboarding.observeHealth(in: history)
                    }
                    // 健康历史落定之后重算 `bo`。放在这里而不是 HK 事件流里，是因为
                    // 账本要的是「已窗口化的每日真相」，而重算本身是幂等的 ——
                    // 多跑一次只会补差额。DEBUG 示例历史会被来源标记过滤。
                    recomputeBoLedger()
                    #if DEBUG
                    applyDebugBoOverrides()
                    #endif
                    // If already logged in, push today's health to the server.
                    if auth.phase == .loggedIn {
                        await coordinator.syncToday()
                    }
                    #if DEBUG
                    // Headless connectivity check (launch arg -PiboBackendSelfTest).
                    if BackendSelfTest.isEnabled {
                        await BackendSelfTest.run(auth: auth, economy: economy, coordinator: coordinator)
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    LPLog.app.debug("scenePhase → \(String(describing: phase), privacy: .public)")
                    morningSleep.setAppActive(phase == .active)
                    // 打点: session boundaries (the SDK itself also flushes +
                    // persists its queue on backgrounding).
                    if phase == .active { Analytics.track(.appForeground) }
                    if phase == .background { Analytics.track(.appBackground) }
                    // Foreground reconciliation per the plan: catch anything
                    // background delivery missed (cheap, anchors persist).
                    // Day rollover runs *before* reconcile so a same-foreground
                    // midnight crossing clears yesterday's state before the
                    // refetch slams new values into a stale `RawMetrics`.
                    if phase == .active {
                        weather.refreshIfStale()
                        // Order matters: rollover first (clears stale day-bound
                        // state), decay catchup second (applies any 4h ticks
                        // that elapsed in the background), reconcile last
                        // (paints fresh HK values on top — recompute then
                        // subtracts the new decay buffer, so the bars settle
                        // at "today's HK reality, minus elapsed pressure").
                        store.checkDayRollover()
                        store.applyDecayCatchup()
                        // Server-side reconciliation: push today's health so the
                        // server re-mints any bo earned while we were away.
                        if auth.phase == .loggedIn {
                            Task { await coordinator.syncToday() }
                        }
                        if health.authState == .granted {
                            LPLog.app.debug("Foreground reconcile triggered")
                            Task {
                                await health.reconcile()
                                morningSleep.presentLatestIfEligible()
                                if morningSleep.pendingPresentation == nil {
                                    await health.requestMorningSleepEnrichmentAuthorizationIfNeeded()
                                }
                                // Keep today's hourly-step grass fresh; the full
                                // history backfill only runs once at launch.
                                let hourly = await health.fetchTodayHourlySteps()
                                if !hourly.isEmpty {
                                    history.upsert(day: .now) { $0.hourlySteps = hourly }
                                }
                            }
                        } else {
                            morningSleep.presentLatestIfEligible()
                        }
                    }
                }
                // 历史被写过之后再算一次。前台的增量刷新（今日小时步数、
                // reconcile 落库）不会经过启动那一段，靠这个兜住。
                .onChange(of: history.revision) { _, _ in
                    if PiboReleaseScope.temporaryCooperationOnboarding {
                        onboarding.observeHealth(in: history)
                    }
                    recomputeBoLedger()
                }
                .onChange(of: health.authState) { _, state in
                    guard state == .granted else { return }
                    Task {
                        await backfillHealthHistoryIfAuthorized()
                        if PiboReleaseScope.temporaryCooperationOnboarding {
                            onboarding.observeHealth(in: history)
                        }
                        recomputeBoLedger()
                    }
                }
        }
    }

    private func backfillHealthHistoryIfAuthorized() async {
        guard health.authState == .granted else { return }
        let values = await health.fetchDailyHistory()
        history.ingest(values)
        let workouts = await health.fetchWorkoutHistory()
        history.ingestWorkouts(workouts)
        history.recomputeWellness()
    }

    private func recomputeBoLedger() {
        boLedger.recompute(history: history)
        if PiboReleaseScope.temporaryCooperationOnboarding {
            onboarding.observeBoProgress(
                lifetimeMinted: boLedger.lifetimeMinted,
                lifetimeCollected: boLedger.lifetimeCollected
            )
        }
    }

    #if DEBUG
    /// 免真实健康数据地把账本摆到某个状态，用于模拟器截图验证：
    /// `-PiboBoBalance=8`（余额）/ `-PiboBoRipe`（有一枚熟了）/
    /// `-PiboBoGrowth=0.6`（当前这枚的成熟进度）。需要全解锁共同物件时另加
    /// `-PiboUnlockAllCommonItems`；该覆盖只在读取时生效，不会写入本地库存。
    private func applyDebugBoOverrides() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.first { $0.hasPrefix(flag + "=") }
                .map { String($0.dropFirst(flag.count + 1)) }
        }
        // 模拟器里合成不了点击，所以点亮态只能从启动参数进来：`-PiboLanternLit=0,2`。
        ornamentLights.applyDebugLaunchArguments(arguments)
        let balance = value("-PiboBoBalance").flatMap(Int.init)
        let growth = value("-PiboBoGrowth").flatMap(Double.init)
        let ripe = arguments.contains("-PiboBoRipe") ? 1 : nil
        guard balance != nil || growth != nil || ripe != nil else { return }
        boLedger.debugSet(balance: balance, ripe: ripe, progress: growth)
        LPLog.bo.notice("debug override applied balance=\(balance ?? -1, privacy: .public) ripe=\(ripe ?? -1, privacy: .public)")
    }
    #endif
}
