import Foundation
import HealthKit
import os

/// Pibo's read-only HealthKit pipeline.
///
/// Ownership: one instance per app launch, vended via SwiftUI environment.
///
/// Lifecycle, in order:
/// 1. `requestAuthorization()` — first launch only, called from the
///    onboarding screen. After it returns, `authState` is `.granted` /
///    `.denied` / `.unavailable`.
/// 2. `startObservers()` — runs an `HKObserverQuery` per metric with
///    `enableBackgroundDelivery(... .immediate)`, so iOS wakes us when the
///    watch syncs new samples even while the app is backgrounded.
/// 3. Each observer fire triggers `refresh(_:)`, which runs the *snapshot*
///    fetch for that metric and posts a `HealthEvent` on `events`.
/// 4. `reconcile()` — called explicitly on `scenePhase == .active` to catch
///    anything the observer missed (e.g. permissions toggled, app was force-
///    quit when delivery was attempted).
///
/// Queries (per PRD §3):
///
/// | Metric           | Window          | Read strategy                |
/// |------------------|-----------------|------------------------------|
/// | steps / exercise / kcal / stand | 00:00 → now | `HKStatisticsQuery cumulativeSum` |
/// | HRV / RHR / HR   | latest sample   | `HKSampleQueryDescriptor limit:1` |
/// | sleep            | last 18h        | sum durations per category   |
/// | mindful          | 00:00 → now     | sum durations of category samples |
/// | workout          | since last anchor | anchored query (delta-only) |
///
/// Workouts use an anchored query because we want the *delta* (a new run just
/// finished) so the home screen can flip a matching suggest card to done.
/// Aggregated metrics use snapshot-style queries because the home screen
/// always shows the current cumulative number — "you're at 8,200 steps right
/// now," not "you walked 1,500 in the last hour."
@MainActor
@Observable
final class HealthDataService {
    /// Coarse view of permission state. HealthKit famously doesn't tell you
    /// *which* read scopes the user granted (privacy), so `.granted` here
    /// just means "the user saw the dialog and we proceeded" — the real
    /// check is whether queries return data.
    enum AuthState: Sendable, Equatable {
        case unavailable    // HealthKit not present (iPad w/o it, etc.)
        case unknown        // never asked
        case requesting     // dialog visible
        case granted
        case denied
    }

    /// HealthKit deliberately hides per-type read authorization. Onboarding
    /// therefore verifies that the three inputs needed by Pibo are actually
    /// readable instead of treating a non-throwing authorization request as
    /// proof that every switch was enabled.
    struct OnboardingReadiness: Sendable, Equatable {
        let hasSleep: Bool
        let hasSteps: Bool
        let hasExercise: Bool

        /// Event 02 needs at least one real `bo`-eligible source, not every
        /// possible source. Phone-only steps and sleep-only users both progress.
        var isReady: Bool { hasSleep || hasSteps || hasExercise }
    }

    // MARK: - Public state

    private(set) var authState: AuthState

    /// Pull events off this stream from one consumer (`PetStateStore`).
    /// Buffered unbounded — events are tiny enums and we never sleep them
    /// long enough to overflow.
    let events: AsyncStream<HealthEvent>

    // MARK: - Private state

    /// Internal (not private) so the history backfill extension in
    /// `HealthDataService+History.swift` can reuse the same authorized store.
    let store: HKHealthStore
    private let metrics: Set<HealthMetric>
    /// Optional app-owned sink for the once-per-wake-day notification + card.
    /// Nil in focused previews/tests that construct a bare HealthDataService.
    private let morningSleepCoordinator: MorningSleepCoordinator?
    private let continuation: AsyncStream<HealthEvent>.Continuation
    /// Anchored only for workouts — those are *discrete events* and we want
    /// just the new ones since last fetch. Aggregate metrics use snapshot
    /// queries instead, so they don't need anchors.
    private var workoutAnchor: HKQueryAnchor?
    /// Per-process dedup of `.workoutFinished` events. The observer fired on
    /// registration *and* `reconcile()` both call `postWorkouts()`; under the
    /// same `workoutAnchor` they return the same workout twice. Anchor
    /// persistence happens after the awaited query resumes, so we can't rely
    /// on it to gate the second fetch. Tracking UUIDs we've already yielded
    /// makes the dedup robust no matter how the two callers interleave.
    private var emittedWorkoutUUIDs: Set<UUID> = []
    /// Coalesces concurrent sleep fetches. On a cold launch the observer fires
    /// on registration while `refreshMorningSleep()` runs from the app's `.task`,
    /// and each pass costs a sleep query plus five windowed quantity queries
    /// (including 21 days of wrist temperature). Running the second pass *after*
    /// the first, rather than alongside it, keeps every update without paying
    /// twice. Mirrors `StressNotifier.isNotifying`.
    private var isFetchingSleep = false
    private var sleepFetchPending = false
    /// HealthKit can coalesce several heartbeat-series writes into one observer
    /// wake. Drain them as one ordered batch and fold a concurrent wake into one
    /// follow-up pass instead of running two overlapping per-beat enumerations.
    private var isFetchingStress = false
    private var stressFetchPending = false
    /// Last resting-HR reading, **App-Group-persisted** so `postStress()` can
    /// factor it into the stress tier even on a background heartbeat-series wake
    /// in a *fresh process* (where no `.restingHR` fetch has run this launch — an
    /// in-memory cache would be 0 there, silently dropping the `restingHR >= 80`
    /// tier bump and making the same reading classify one tier lower in the
    /// background than in the foreground). Updated on every `.restingHR` snapshot.
    private var lastRestingHR: Double {
        get { Self.appGroupDefaults.double(forKey: Self.lastRestingHRKey) }
        set { Self.appGroupDefaults.set(newValue, forKey: Self.lastRestingHRKey) }
    }
    private static let lastRestingHRKey = "pibo.stress.lastRestingHR.v1"
    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }
    /// Guards `startObservers()` so cold-launch restoration + a subsequent
    /// `requestAuthorization()` (e.g. user re-runs onboarding after reset)
    /// don't end up double-registering observer queries.
    private var observersStarted = false

    // MARK: - Init

    init(
        metrics: Set<HealthMetric> = Set(HealthMetric.allCases),
        morningSleepCoordinator: MorningSleepCoordinator? = nil
    ) {
        self.metrics = metrics
        self.morningSleepCoordinator = morningSleepCoordinator
        self.store = HKHealthStore()
        self.workoutAnchor = HealthDataPersistence.loadWorkoutAnchor()

        var cont: AsyncStream<HealthEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont

        // Cold-launch restore. Without this, after the first launch the user
        // never returns to `HealthAuthView`, so `requestAuthorization()` never
        // re-runs, observers never re-register, the scenePhase guard
        // (`authState == .granted`) keeps `reconcile()` from firing, and the
        // home screen falls back to the cold-start `demoStats` floor with an
        // empty `steps` array — read as "睡眠 / 运动数据丢失" by the user.
        if !HKHealthStore.isHealthDataAvailable() {
            self.authState = .unavailable
        } else if HealthDataPersistence.authorizationWasGranted() {
            self.authState = .granted
            LPLog.healthKit.notice("Restored auth from UserDefaults — registering observers on init")
            startObservers()
            // Don't call `reconcile()` here — `PiboApp` triggers it on
            // the first scenePhase=.active right after this init returns.
        } else {
            self.authState = .unknown
        }
    }

    // MARK: - Authorization

    /// Request read auth for every metric in `metrics`. Idempotent — calling
    /// it twice just re-shows the system dialog if any types were never
    /// answered, otherwise it's a no-op.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authState = .unavailable
            LPLog.healthKit.notice("Auth skipped — HealthKit unavailable on this device")
            return
        }
        authState = .requesting
        LPLog.healthKit.notice("Requesting auth for \(self.metrics.count, privacy: .public) metric types")
        do {
            // 活动环目标 (`HKActivitySummary`) 不是 `HealthMetric`，单独并入读权限集。
            try await store.requestAuthorization(
                toShare: [],
                read: metrics.hkReadTypes
                    .union([HKObjectType.activitySummaryType()])
                    .union(MorningSleepHealthTypes.enrichmentReadTypes)
                    .union(WellnessHealthTypes.additionalReadTypes))
            authState = .granted
            HealthDataPersistence.setAuthorizationGranted(true)
            LPLog.healthKit.notice("Auth granted (HK doesn't disclose per-type grants — verify via query results)")
            startObservers()
            await reconcile()
        } catch {
            authState = .denied
            LPLog.healthKit.error("Auth threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Checks for recent readable samples rather than inferred permission.
    /// An empty result covers both cases the onboarding gate cares about:
    /// the user denied that read scope, or the connected data source has not
    /// supplied enough baseline data yet.
    func onboardingReadiness(now: Date = .now) async -> OnboardingReadiness {
        guard authState == .granted, HKHealthStore.isHealthDataAvailable(),
              let start = Calendar.current.date(byAdding: .day, value: -30, to: now)
        else {
            return OnboardingReadiness(hasSleep: false, hasSteps: false, hasExercise: false)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let hasSleep = await hasRecentCategorySample(.sleepAnalysis, predicate: predicate)
        let hasSteps = await hasRecentQuantitySample(.stepCount, predicate: predicate)
        let hasExercise = await hasRecentQuantitySample(.appleExerciseTime, predicate: predicate)
        let readiness = OnboardingReadiness(
            hasSleep: hasSleep,
            hasSteps: hasSteps,
            hasExercise: hasExercise
        )
        LPLog.onboarding.notice(
            "Health baseline ready=\(readiness.isReady, privacy: .public) sleep=\(hasSleep, privacy: .public) steps=\(hasSteps, privacy: .public) exercise=\(hasExercise, privacy: .public)"
        )
        return readiness
    }

    private func hasRecentQuantitySample(
        _ id: HKQuantityTypeIdentifier,
        predicate: NSPredicate
    ) async -> Bool {
        let type = HKQuantityType(id)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await !descriptor.result(for: store).isEmpty
        } catch {
            LPLog.healthKit.error(
                "Onboarding baseline query \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func hasRecentCategorySample(
        _ id: HKCategoryTypeIdentifier,
        predicate: NSPredicate
    ) async -> Bool {
        let type = HKCategoryType(id)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await !descriptor.result(for: store).isEmpty
        } catch {
            LPLog.healthKit.error(
                "Onboarding baseline query \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Foreground reconciliation: re-fetch every metric's current snapshot.
    /// Cheap because all queries are bounded windows; safe to run unconditionally.
    func reconcile() async {
        LPLog.healthKit.debug("Reconcile begin (\(self.metrics.count, privacy: .public) metrics)")
        // Achievement ordering is a product contract: if this reconciliation
        // discovers both a 10k crossing and one or more workouts, the workout
        // (pigu) wins. Set iteration is intentionally unordered, so impose a
        // stable order with steps before workout and keep workout last.
        let orderedMetrics = metrics.sorted {
            Self.reconcilePriority($0) < Self.reconcilePriority($1)
        }
        for metric in orderedMetrics {
            await refresh(metric)
        }
        LPLog.healthKit.debug("Reconcile end")
    }

    /// Refresh only the latest sleep session. Used on foreground activation so
    /// the morning sheet waits for a fresh summary instead of presenting the
    /// payload captured when the background notification was scheduled.
    func refreshMorningSleep() async {
        guard metrics.contains(.sleep) else { return }
        await refresh(.sleep)
    }

    // MARK: - Observer setup

    /// Register one observer + background-delivery pair per metric. Triggers
    /// a `refresh(_:)` whenever new data of that type lands in HealthKit.
    /// Idempotent: callable from both the cold-launch restore path and from
    /// `requestAuthorization()` without double-registering.
    private func startObservers() {
        guard !observersStarted else {
            LPLog.healthKit.debug("startObservers skipped — already registered")
            return
        }
        observersStarted = true
        for metric in metrics {
            registerObserver(for: metric)
        }
    }

    private func registerObserver(for metric: HealthMetric) {
        guard let sampleType = metric.hkType as? HKSampleType else { return }

        let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, _ in
            LPLog.healthKit.debug("Observer fired: \(metric.rawValue, privacy: .public)")
            // Observer callbacks land on a private background queue. Hop to
            // MainActor for the snapshot fetch + state mutation.
            Task { @MainActor [weak self] in
                // Steps and workouts form one achievement acquisition pair.
                // Query steps first so a HealthKit update that contains both
                // facts deterministically ends on the latest pigu workout.
                if metric == .steps || metric == .workout {
                    await self?.refresh(.steps)
                    await self?.refresh(.workout)
                } else {
                    await self?.refresh(metric)
                }
                // Tell HK we've handled this wake-up — required to avoid
                // delivery throttling.
                completionHandler()
            }
        }
        store.execute(observer)

        Task {
            do {
                try await store.enableBackgroundDelivery(for: sampleType, frequency: metric.backgroundDeliveryFrequency)
                LPLog.healthKit.debug("Background delivery enabled: \(metric.rawValue, privacy: .public)")
            } catch {
                LPLog.healthKit.error("Background delivery failed for \(metric.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func reconcilePriority(_ metric: HealthMetric) -> Int {
        switch metric {
        case .steps: 0
        case .workout: 2
        default: 1
        }
    }

    // MARK: - Snapshot dispatch

    private func refresh(_ metric: HealthMetric) async {
        switch metric {
        case .steps:           await postSum(.stepCount,           unit: .count(),                    as: HealthEvent.steps,           cast: { Int($0) })
        case .exerciseMinutes: await postSum(.appleExerciseTime,   unit: .minute(),                   as: HealthEvent.exerciseMinutes, cast: { Int($0) })
        case .activeEnergy:    await postSum(.activeEnergyBurned,  unit: .kilocalorie(),              as: HealthEvent.activeEnergy,    cast: { $0 })
        case .standMinutes:    await postSum(.appleStandTime,      unit: .minute(),                   as: HealthEvent.standMinutes,    cast: { Int($0) })
        case .heartRate:       await postLatest(.heartRate,        unit: .count().unitDivided(by: .minute()), as: { v, at in .heartRate(value: v, measuredAt: at) })
        case .hrv:             await postLatest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), as: { v, _ in .hrv(v) })
        case .heartbeatSeries: await postStress()
        case .restingHR:       await postLatest(.restingHeartRate, unit: .count().unitDivided(by: .minute()), as: { v, _ in self.lastRestingHR = v; return .restingHR(v) })
        case .oxygen:          await postLatest(.oxygenSaturation, unit: .percent(), as: { v, _ in .oxygen(v) })
        case .sleep:           await postSleep()
        case .mindful:         await postMindful()
        case .workout:         await postWorkouts()
        }
    }

    // MARK: - Cumulative sum (today)

    /// Sum a quantity type over today (00:00 → now).
    private func postSum<Out>(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        as wrap: (Out) -> HealthEvent,
        cast: (Double) -> Out
    ) async {
        let type = HKQuantityType(id)
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            guard let stats = try await descriptor.result(for: store) else { return }
            let raw = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
            LPLog.healthKit.debug("postSum \(id.rawValue, privacy: .public)=\(raw, privacy: .public)")
            continuation.yield(wrap(cast(raw)))
        } catch {
            // HealthKit returns "no data" as a non-throwing nil; a thrown
            // error usually means the type wasn't authorized.
            LPLog.healthKit.error("postSum \(id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Latest single sample

    /// Pick the most recent sample of a quantity type. We don't bound the
    /// window here — HRV/RHR can be hours-old and still informative.
    private func postLatest(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        as wrap: (Double, Date) -> HealthEvent
    ) async {
        let type = HKQuantityType(id)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            guard let sample = try await descriptor.result(for: store).first else {
                LPLog.healthKit.debug("postLatest \(id.rawValue, privacy: .public): no sample in store")
                return
            }
            let value = sample.quantity.doubleValue(for: unit)
            LPLog.healthKit.debug("postLatest \(id.rawValue, privacy: .public)=\(value, privacy: .public) at \(LPLog.dateFormatter.string(from: sample.startDate), privacy: .public)")
            continuation.yield(wrap(value, sample.startDate))
        } catch {
            LPLog.healthKit.error("postLatest \(id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Stress (RMSSD from heartbeat series)

    /// Compute corrected NN-RMSSD from the newest heartbeat series, always record
    /// the value, and only update trends/classify/notify when both the Apple
    /// evidence and resting context are eligible. Stress remains unavailable
    /// until Core sees seven finalized personal-baseline days.
    ///
    /// Runs on background HK wakes too — the notifier only reads system auth, so
    /// a stress spike can push even while the app is backgrounded. No-ops on the
    /// simulator / any device without a readable heartbeat series (RMSSD `nil`).
    private func postStress() async {
        if isFetchingStress {
            stressFetchPending = true
            return
        }
        isFetchingStress = true
        repeat {
            stressFetchPending = false
            await drainStressSeries()
        } while stressFetchPending
        isFetchingStress = false
    }

    private func drainStressSeries() async {
        let now = Date()
        let since = Calendar.current.date(byAdding: .day, value: -21, to: now)
            ?? now.addingTimeInterval(-21 * 24 * 60 * 60)
        let series = await HeartbeatSeriesReader.recentSeries(store: store, since: since)
        let pending = series.filter { !StressLogStore.hasProcessedSeries($0.uuid) }
        guard !pending.isEmpty else {
            LPLog.healthKit.debug("postStress: no unprocessed heartbeat series")
            return
        }

        var samples: [HeartbeatSeriesReader.StressSample] = []
        for item in pending {
            switch await HeartbeatSeriesReader.readSample(for: item, store: store) {
            case .computed(let sample):
                samples.append(sample)
            case .uncomputable:
                // Immutable and mathematically uncomputable: this is the only
                // case that can be checkpointed without a persisted reading.
                StressLogStore.markProcessedSeries(item.uuid)
            case .unavailable:
                LPLog.healthKit.debug("postStress: heartbeat series read failed; leaving it pending for retry")
            }
        }

        let today = Calendar.current.startOfDay(for: now)
        let historical = samples.compactMap { sample
            -> (seriesID: UUID, rmssd: Double, date: Date)? in
            guard sample.canInterpretStress,
                  StressSampleTiming.age(measuredAt: sample.date, now: now) != nil,
                  sample.date < today else { return nil }
            return (sample.seriesID, sample.rmssd, sample.date)
        }
        StressBaselineStore.backfill(historical, now: now)

        for sample in samples {
            await processStressSample(sample, now: now, today: today)
            // Checkpoint only after the durable baseline/log work, notification
            // attempt and event emission. A termination can now cause a safe,
            // idempotent retry instead of permanently losing the row/event.
            StressLogStore.markProcessedSeries(sample.seriesID)
        }
    }

    private func processStressSample(
        _ sample: HeartbeatSeriesReader.StressSample,
        now: Date,
        today: Date
    ) async {
        let sampleAge = StressSampleTiming.age(measuredAt: sample.date, now: now)
        let interpretationEligible = sample.canInterpretStress && sampleAge != nil
        let isMeasuredToday = sample.date >= today && sample.date <= now
        let classificationEligible = interpretationEligible && isMeasuredToday
        // Visibility and interpretation are separate: every calculable value is
        // logged, while only adequate awake/resting evidence enters the baseline.
        let baseline = StressBaselineStore.record(
            rmssd: sample.rmssd,
            isEligible: classificationEligible,
            date: sample.date,
            now: now,
            seriesID: sample.seriesID
        )
        let rawLevel = classificationEligible
            ? StressModel.level(rmssd: sample.rmssd, baseline: baseline, restingHR: lastRestingHR)
            : nil
        var notified = false
        // Only *fresh* readings warrant a smart push. `latestSeries` returns the
        // newest series across all time, so on a cold launch / after the app was
        // off for a while it can surface a series measured hours ago (even
        // overnight). A "你压力偏高，歇会儿" push about a stale reading reads as
        // wrong, so a series older than the anchor-freshness bound remains
        // visible in the log but skips the transition notification. Same-day
        // eligible values may still join that day's baseline bucket. (The
        // common background-delivery path always has a fresh series, so this only
        // suppresses the stale-catch-up case.) The diagnostic "每次测量都提醒"
        // mode is exempt: it reports the raw RMSSD of *every* computation (a
        // measurement readout, not a "stressed now" alert), so a stale catch-up
        // is exactly the kind of compute it exists to surface.
        let everyMode = StressNotifier.shared.notifyEveryReading
        if let rawLevel {
            // N=2 hysteresis only tracks classified measurements. Record-only
            // values and cold-start values cannot perturb future notification state.
            let confirmedLevel = StressHysteresis.confirm(rawLevel)
            notified = StressSampleTiming.shouldAttemptNotification(
                measuredAt: sample.date,
                now: now,
                everyReading: everyMode
            )
                ? (everyMode
                   ? await StressNotifier.shared.notifyMeasurement(level: rawLevel, rmssd: sample.rmssd)
                   : await StressNotifier.shared.maybeNotify(level: confirmedLevel, rmssd: sample.rmssd))
                : false
            LPLog.healthKit.debug("postStress rmssd=\(sample.rmssd, privacy: .public)ms raw=\(rawLevel.displayName, privacy: .public) confirmed=\(confirmedLevel.displayName, privacy: .public)")
        } else {
            // The user-facing mode says every measurement. A calculable value
            // therefore still reports as 「仅记录」 while the seven-day reference
            // is building or Apple evidence/context is record-only.
            if isMeasuredToday, everyMode,
               StressSampleTiming.shouldAttemptNotification(
                   measuredAt: sample.date,
                   now: now,
                   everyReading: true
               ) {
                notified = await StressNotifier.shared.notifyMeasurement(
                    level: nil,
                    rmssd: sample.rmssd
                )
            }
            LPLog.healthKit.debug("postStress rmssd=\(sample.rmssd, privacy: .public)ms record-only baselineDays=\(baseline?.dayCount ?? 0, privacy: .public)")
        }
        if sampleAge == nil {
            LPLog.healthKit.debug("postStress: series timestamp is in the future — recorded without interpretation")
        } else if !StressSampleTiming.shouldAttemptNotification(
            measuredAt: sample.date,
            now: now,
            everyReading: false
        ) {
            LPLog.healthKit.debug("postStress: series is stale (\(Int((sampleAge ?? 0) / 60), privacy: .public)min old) — recorded, smart-notify skipped")
        }
        // Log every computation (even quiet ones) so the user can confirm the
        // background measure ran — the "有没有在算" question the log view answers.
        // The log records the *raw* measured tier (what was actually measured).
        StressLogStore.record(rmssd: sample.rmssd, baseline: baseline, level: rawLevel,
                              notified: notified, isResting: sample.isResting,
                              date: sample.date, measurement: sample.measurement,
                              measurementEligible: sample.measurement.canUpdateTrends && sampleAge != nil,
                              seriesID: sample.seriesID)
        continuation.yield(.hrvRMSSD(
            value: sample.rmssd,
            measuredAt: sample.date,
            interpretationEligible: interpretationEligible
        ))
    }

    // MARK: - Sleep

    /// Build the complete latest session once, then feed both the existing raw
    /// pet-state event and the persisted morning notification/card pipeline.
    private func postSleep() async {
        if isFetchingSleep {
            // Fold the concurrent caller into the in-flight fetch; it re-runs
            // once so a genuinely newer sample is never dropped.
            sleepFetchPending = true
            LPLog.healthKit.debug("postSleep: fetch already in flight, coalescing")
            return
        }
        isFetchingSleep = true
        defer { isFetchingSleep = false }

        repeat {
            sleepFetchPending = false
            await fetchAndPostSleep()
        } while sleepFetchPending
    }

    private func fetchAndPostSleep() async {
        guard let summary = await fetchLatestMorningSleepSummary() else {
            continuation.yield(.sleep(total: 0, deep: 0, rem: 0, start: nil))
            return
        }
        continuation.yield(.sleep(
            total: summary.total,
            deep: summary.deep,
            rem: summary.rem,
            start: summary.start
        ))
        await morningSleepCoordinator?.receive(summary)
    }

    // MARK: - Sleep sample dump

    /// Dump every reachable field on an `HKCategorySample` (sleep) so log
    /// readers can correlate duplicates / unexpected sources / odd metadata
    /// without attaching a debugger. Each call emits ~6 lines per sample —
    /// at `.debug` level, so default Console.app filters keep it hidden.
    private static func dumpSleepSample(_ s: HKCategorySample, index: Int) {
        let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
        let kind: String = {
            guard let v else { return "raw=\(s.value)" }
            switch v {
            case .inBed:             return "inBed"
            case .asleep:            return "asleep(legacy)"
            case .asleepCore:        return "asleepCore"
            case .asleepDeep:        return "asleepDeep"
            case .asleepREM:         return "asleepREM"
            case .asleepUnspecified: return "asleepUnspecified"
            case .awake:             return "awake"
            @unknown default:        return "raw=\(s.value)"
            }
        }()
        let durSec = Int(s.endDate.timeIntervalSince(s.startDate))
        let durM = durSec / 60
        let durS = durSec % 60
        let startStr = LPLog.dateFormatter.string(from: s.startDate)
        let endStr   = LPLog.dateFormatter.string(from: s.endDate)
        let rev = s.sourceRevision
        let src = rev.source
        let osv = rev.operatingSystemVersion
        // `metadata` is `[String: Any]?`. Stable-sort by key so repeated runs
        // produce diffable output. Empty / nil → "nil" / "{}".
        let metaStr: String = {
            guard let md = s.metadata, !md.isEmpty else {
                return s.metadata == nil ? "nil" : "{}"
            }
            let pairs = md.keys.sorted().map { "\($0)=\(md[$0] ?? "<nil>")" }
            return "{ " + pairs.joined(separator: ", ") + " }"
        }()
        LPLog.sleep.debug("[\(index, privacy: .public)] \(kind, privacy: .public) value=\(s.value, privacy: .public)")
        LPLog.sleep.debug("    range:    \(startStr, privacy: .public) → \(endStr, privacy: .public) (\(durM, privacy: .public)m\(durS, privacy: .public)s)")
        LPLog.sleep.debug("    sample:   uuid=\(s.uuid.uuidString, privacy: .public) type=\(s.sampleType.identifier, privacy: .public) hasUndeterminedDuration=\(s.hasUndeterminedDuration, privacy: .public)")
        LPLog.sleep.debug("    source:   name=\(src.name, privacy: .public) bundle=\(src.bundleIdentifier, privacy: .public)")
        LPLog.sleep.debug("    revision: version=\(rev.version ?? "-", privacy: .public) productType=\(rev.productType ?? "-", privacy: .public) os=\(osv.majorVersion, privacy: .public).\(osv.minorVersion, privacy: .public).\(osv.patchVersion, privacy: .public)")
        LPLog.sleep.debug("    metadata: \(metaStr, privacy: .public)")
    }

    // MARK: - Mindful

    /// Sum mindful-session durations for today.
    private func postMindful() async {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)],
            sortDescriptors: []
        )
        do {
            let samples = try await descriptor.result(for: store)
            let total: TimeInterval = samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            LPLog.healthKit.debug("postMindful sessions=\(samples.count, privacy: .public) total=\(Int(total/60), privacy: .public)min")
            continuation.yield(.mindfulMinutes(Int(total / 60)))
        } catch {
            LPLog.healthKit.error("postMindful threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Workouts (anchored — we only care about new ones)

    private func postWorkouts() async {
        // First-run cap: with `anchor == nil`, an anchored workout query
        // returns *every* HK workout ever recorded. On a longtime watch user
        // that's hundreds of samples — each one becomes a `.workoutFinished`
        // event, each event prepends a step card + applies gain + toggles
        // sparkles, and the home screen freezes mid-launch.
        //
        // So on the first call we constrain to the last 36h — wide enough to
        // catch yesterday-evening's run when the user opens the app this
        // morning, narrow enough that a longtime watch user doesn't pay for
        // a multi-thousand-sample replay. After that we persist the anchor
        // (see `HealthDataPersistence`) so subsequent cold
        // launches only see deltas, not another 36h replay.
        let predicate: HKSamplePredicate<HKWorkout>
        let isFirstRun = workoutAnchor == nil
        if isFirstRun {
            let start = Date().addingTimeInterval(-36 * 3600)
            predicate = .workout(HKQuery.predicateForSamples(withStart: start, end: nil))
            LPLog.workout.info("First-run query (no anchor) — capping window to last 36h")
        } else {
            predicate = .workout()
            LPLog.workout.debug("Delta query (anchor present)")
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: workoutAnchor
        )
        do {
            let result = try await descriptor.result(for: store)
            workoutAnchor = result.newAnchor
            HealthDataPersistence.persistWorkoutAnchor(result.newAnchor)
            if !result.addedSamples.isEmpty {
                LPLog.workout.info("Fetched \(result.addedSamples.count, privacy: .public) workout(s)")
            }
            // Anchored-query result ordering is unspecified. Process oldest to
            // newest so the replaceable pending achievement ends on the latest.
            for workout in result.addedSamples.sorted(by: { $0.endDate < $1.endDate }) {
                guard emittedWorkoutUUIDs.insert(workout.uuid).inserted else {
                    LPLog.workout.debug("dedup skip uuid=\(workout.uuid.uuidString, privacy: .public) — already emitted this session")
                    continue
                }
                let kind = HealthWorkoutKindMapper.kind(
                    for: workout.workoutActivityType
                )
                // iOS 18 deprecated `HKWorkout.totalEnergyBurned` in favor of
                // per-statistics access; pull kcal out via the activity sum.
                let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?
                    .doubleValue(for: .kilocalorie())
                let durMin = PiboCoreWorkoutAdapter.metrics(
                    durationSeconds: workout.duration,
                    distanceMeters: 0
                ).durationMinutes
                let endStr = LPLog.dateFormatter.string(from: workout.endDate)
                let src = workout.sourceRevision.source.name
                LPLog.workout.debug("  \(kind.rawValue, privacy: .public) \(durMin, privacy: .public)min ended \(endStr, privacy: .public) kcal=\(kcal ?? 0, privacy: .public) src=\(src, privacy: .public)")
                continuation.yield(.workoutFinished(
                    id: workout.uuid,
                    kind: kind,
                    duration: workout.duration,
                    kcal: kcal,
                    end: workout.endDate,
                    isHistorical: isFirstRun
                ))
            }
        } catch {
            LPLog.workout.error("postWorkouts threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Coarse bucketing for the home screen. We don't need fine-grained
    /// activity types — just enough to flip a matching "建议: 跑步" card to done.
    static func bucket(_ type: HKWorkoutActivityType) -> HealthEvent.WorkoutKind {
        HealthWorkoutKindMapper.kind(for: type)
    }
}
