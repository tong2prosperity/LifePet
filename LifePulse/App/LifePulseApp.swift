import SwiftUI
import os

@main
struct LifePulseApp: App {
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

    @Environment(\.scenePhase) private var scenePhase

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(identity)
                .environment(health)
                .environment(store)
                .preferredColorScheme(.light)   // LP palette is light-only paper
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
                            Task { await health.reconcile() }
                        }
                    }
                }
        }
    }
}
