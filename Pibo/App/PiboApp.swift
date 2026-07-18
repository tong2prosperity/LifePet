import SwiftUI
import SwiftData
import os

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
        AppNotificationRouter.shared.install()
        let h = HealthDataService(morningSleepCoordinator: morning)
        let s = PetStateStore(identity: id, snapshots: snaps, events: h.events)
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
        _piboSpeech = State(initialValue: PiboSpeechService(
            narrativeProgress: { s.story.revealedCount }
        ))

        modelContainer = Self.makeModelContainer()
        let hist = HealthHistoryStore(context: modelContainer.mainContext)
        _history = State(initialValue: hist)

        let a = AuthService()
        let e = EconomyService()
        _auth = State(initialValue: a)
        _economy = State(initialValue: e)
        _coordinator = State(initialValue: EconomySyncCoordinator(auth: a, economy: e, history: hist))
        _membership = State(initialValue: MembershipService())
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
                .environment(piboSpeech)
                .environment(history)
                .environment(auth)
                .environment(economy)
                .environment(coordinator)
                .environment(membership)
                .environment(StressNotifier.shared)
                .modelContainer(modelContainer)
                .preferredColorScheme(.light)   // LP palette is light-only paper
                .task {
                    // Lifetime StoreKit transaction listener + entitlement hydrate.
                    membership.start()
                    // Set up foreground presentation + quiet provisional auth so
                    // passive users are covered without a prompt.
                    await StressNotifier.shared.start()
                    morningSleep.setAppActive(scenePhase == .active)
                    if scenePhase == .active, health.authState == .granted {
                        await health.requestMorningSleepEnrichmentAuthorizationIfNeeded()
                        await health.refreshMorningSleep()
                    }
                    morningSleep.presentLatestIfEligible()
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
                    if health.authState == .granted {
                        let values = await health.fetchDailyHistory()
                        history.ingest(values)
                        let workouts = await health.fetchWorkoutHistory()
                        history.ingestWorkouts(workouts)
                    }
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
                                await health.requestMorningSleepEnrichmentAuthorizationIfNeeded()
                                await health.reconcile()
                                morningSleep.presentLatestIfEligible()
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
        }
    }
}
