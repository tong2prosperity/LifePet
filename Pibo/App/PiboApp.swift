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
    /// Sole consumer of `health.events`. The store is the only thing that
    /// mutates pet state; views observe it via `@Environment`.
    @State private var store: PetStateStore
    /// Backend auth + economy clients (pibo-server). App-owned so any screen can
    /// drive login / sync via `@Environment`. The demo runs without a server;
    /// these only do work once the user logs in (see `BackendLoginView`).
    @State private var auth = AuthService()
    @State private var economy = EconomyService()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        PiboPersistenceMigrator.runIfNeeded()
        LPLog.app.notice("App launched")
        let id = PetIdentityStore()
        let snaps = DailySnapshotStore()
        let h = HealthDataService()
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
        _store = State(initialValue: s)

        do {
            modelContainer = try ModelContainer(for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self)
        } catch {
            // In-memory fallback so a corrupt store never blocks launch.
            modelContainer = try! ModelContainer(
                for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            LPLog.app.error("History store failed, using in-memory: \(error.localizedDescription, privacy: .public)")
        }
        _history = State(initialValue: HealthHistoryStore(context: modelContainer.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(identity)
                .environment(health)
                .environment(store)
                .environment(history)
                .environment(auth)
                .environment(economy)
                .modelContainer(modelContainer)
                .preferredColorScheme(.light)   // LP palette is light-only paper
                .task {
                    // Backfill the SwiftData history once per launch. On a real
                    // authorized device this is HK data; on a simulator with no
                    // HK, DEBUG-seed so the 二楼 is demonstrable.
                    #if DEBUG
                    if health.authState != .granted { history.seedSampleAllIfEmpty() }
                    #endif
                    if health.authState == .granted {
                        let values = await health.fetchDailyHistory()
                        history.ingest(values)
                        let workouts = await health.fetchWorkoutHistory()
                        history.ingestWorkouts(workouts)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    LPLog.app.debug("scenePhase → \(String(describing: phase), privacy: .public)")
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
                        if health.authState == .granted {
                            LPLog.app.debug("Foreground reconcile triggered")
                            Task {
                                await health.reconcile()
                                // Keep today's hourly-step grass fresh; the full
                                // history backfill only runs once at launch.
                                let hourly = await health.fetchTodayHourlySteps()
                                if !hourly.isEmpty {
                                    history.upsert(day: .now) { $0.hourlySteps = hourly }
                                }
                            }
                        }
                    }
                }
        }
    }
}
