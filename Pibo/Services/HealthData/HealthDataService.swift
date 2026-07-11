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

    init(metrics: Set<HealthMetric> = Set(HealthMetric.allCases)) {
        self.metrics = metrics
        self.store = HKHealthStore()
        self.workoutAnchor = Self.loadAnchor()

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
        } else if Self.loadAuthorizedFlag() {
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
                read: metrics.hkReadTypes.union([HKObjectType.activitySummaryType()]))
            authState = .granted
            Self.persistAuthorizedFlag(true)
            LPLog.healthKit.notice("Auth granted (HK doesn't disclose per-type grants — verify via query results)")
            startObservers()
            await reconcile()
        } catch {
            authState = .denied
            LPLog.healthKit.error("Auth threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Foreground reconciliation: re-fetch every metric's current snapshot.
    /// Cheap because all queries are bounded windows; safe to run unconditionally.
    func reconcile() async {
        LPLog.healthKit.debug("Reconcile begin (\(self.metrics.count, privacy: .public) metrics)")
        for metric in metrics {
            await refresh(metric)
        }
        LPLog.healthKit.debug("Reconcile end")
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
                await self?.refresh(metric)
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

    /// Compute RMSSD from the newest heartbeat series (Pibo's own HRV, not
    /// Apple's SDNN), fold it into the personal baseline, classify stress, drive
    /// the high-stress notification, and post the RMSSD upstream for the 压力卡.
    ///
    /// Runs on background HK wakes too — the notifier only reads system auth, so
    /// a stress spike can push even while the app is backgrounded. No-ops on the
    /// simulator / any device without a readable heartbeat series (RMSSD `nil`).
    private func postStress() async {
        // Cheap pre-check: the observer (fires on registration) and every
        // foreground `reconcile()` re-fetch the same newest series. Peek its id
        // first — a single `limit:1` query — and skip the expensive per-beat RR
        // enumeration + workout-overlap read when we've already processed it. The
        // synchronous check+set below still guards the rare concurrent race.
        if let newestID = await HeartbeatSeriesReader.latestSeriesID(store: store),
           newestID == StressLogStore.lastProcessedSeriesID {
            LPLog.healthKit.debug("postStress: newest series already processed, skipping enumeration")
            return
        }
        guard let sample = await HeartbeatSeriesReader.latestSample(store: store) else {
            LPLog.healthKit.debug("postStress: no readable heartbeat series")
            return
        }
        // Dedup: the observer (fires on registration) and every foreground
        // `reconcile()` both re-fetch this same newest series. Re-recording it
        // would over-weight it in the day's baseline median and append a
        // duplicate stress-log row each time, so process each series once. The
        // marker is App-Group-persisted so the dedup also holds across a
        // background-wake process being killed before the next foreground.
        // Check + set are synchronous with no `await` between them, so the
        // observer/reconcile pair can't both pass on the MainActor.
        guard sample.seriesID != StressLogStore.lastProcessedSeriesID else {
            LPLog.healthKit.debug("postStress: series already processed, skipping")
            return
        }
        StressLogStore.lastProcessedSeriesID = sample.seriesID
        // Only resting readings fold into the personal baseline; active-time HRV
        // is naturally low and would poison it. Non-resting readings still get
        // classified + logged (against the existing baseline) for display.
        let baseline = StressBaselineStore.record(
            rmssd: sample.rmssd, isResting: sample.isResting, date: sample.date)
        let rawLevel = StressModel.level(rmssd: sample.rmssd, baseline: baseline, restingHR: lastRestingHR)
        // N=2 hysteresis: a lone noisy spike/dip must not move the *alert* tier.
        // Always fold the reading in (tracks the stream even in diagnostic mode);
        // the confirmed tier drives the smart push, the raw tier drives the log
        // and the every-reading diagnostic (which reports the actual measurement).
        let confirmedLevel = StressHysteresis.confirm(rawLevel)
        LPLog.healthKit.debug("postStress rmssd=\(sample.rmssd, privacy: .public)ms resting=\(sample.isResting, privacy: .public) raw=\(rawLevel.displayName, privacy: .public) confirmed=\(confirmedLevel.displayName, privacy: .public)")
        // Only *fresh* readings warrant a smart push. `latestSeries` returns the
        // newest series across all time, so on a cold launch / after the app was
        // off for a while it can surface a series measured hours ago (even
        // overnight). A "你压力偏高，歇会儿" push about a stale reading reads as
        // wrong, so a series older than the anchor-freshness bound still records
        // to the baseline + log but skips the transition notification. (The
        // common background-delivery path always has a fresh series, so this only
        // suppresses the stale-catch-up case.) The diagnostic "每次测量都提醒"
        // mode is exempt: it reports the raw RMSSD of *every* computation (a
        // measurement readout, not a "stressed now" alert), so a stale catch-up
        // is exactly the kind of compute it exists to surface.
        let everyMode = StressNotifier.shared.notifyEveryReading
        let notifyLevel = everyMode ? rawLevel : confirmedLevel
        let fresh = Date().timeIntervalSince(sample.date) <= DerivedStressModel.maxAnchorAge
        let notified = (fresh || everyMode)
            ? await StressNotifier.shared.maybeNotify(level: notifyLevel, rmssd: sample.rmssd)
            : false
        if !fresh {
            LPLog.healthKit.debug("postStress: series is stale (\(Int(Date().timeIntervalSince(sample.date) / 60), privacy: .public)min old) — recorded, smart-notify skipped")
        }
        // Log every computation (even quiet ones) so the user can confirm the
        // background measure ran — the "有没有在算" question the log view answers.
        // The log records the *raw* measured tier (what was actually measured).
        StressLogStore.record(rmssd: sample.rmssd, baseline: baseline, level: rawLevel,
                              notified: notified, isResting: sample.isResting)
        continuation.yield(.hrvRMSSD(value: sample.rmssd, measuredAt: sample.date))
    }

    // MARK: - Sleep

    /// Sum sleep stages across the most recent overnight window.
    ///
    /// Window: 36h back from `now`. Loose enough to catch last night even when
    /// the user opens the app late in the evening — stage samples are tiny
    /// (often < 1 min each) and `predicateForSamples` matches on overlap, so
    /// the early portion of a 23:00–07:00 sleep would fall outside an 18h
    /// window if the user opened the app at 22:00.
    ///
    /// Counting (prefer stages, fall back to legacy):
    /// - If the window contains **any** stage-style sample
    ///   (`.asleepCore/.asleepDeep/.asleepREM/.asleepUnspecified`), the watch
    ///   is considered authoritative — sum stage samples for `total` and
    ///   ignore legacy `.asleep` (raw = 1). This prevents the very common
    ///   double-count where Apple Watch writes per-stage segments AND a
    ///   third-party tracker (Withings / Mi Band / some iCloud imports)
    ///   writes a covering whole-night `.asleep` block on the same range.
    /// - If no stage samples exist, fall back to summing legacy `.asleep`,
    ///   so old devices / third-party-only setups still produce a card.
    /// - `.asleepDeep` and `.asleepREM` additionally feed their own buckets.
    ///   Legacy `.asleep` has no stage info, so even in fallback mode the
    ///   deep/rem terms degrade to 0 (energy formula handles that).
    ///
    /// Sessioning: a 36h window can hold *two* nights when the user opens
    /// the app between morning and night — e.g. 04-24 morning sleep ends
    /// 09:28, 04-25 morning sleep starts 03:59 (~18.5h gap). Summing every
    /// asleep* sample double-reports yesterday's sleep on top of last
    /// night's. Group asleep* samples into sessions by gap (>4h between an
    /// asleep sample's start and the previous asleep endDate starts a new
    /// session), and report only the latest session — that's "last night".
    private func postSleep() async {
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            let hasStages = samples.contains { s in
                switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                case .some(.asleepCore), .some(.asleepDeep), .some(.asleepREM), .some(.asleepUnspecified):
                    return true
                default:
                    return false
                }
            }
            // Group asleep* samples into sessions; pick the most recent.
            // 4h gap is comfortably larger than any normal mid-night arousal
            // and small enough to split a same-day nap from overnight sleep.
            struct SleepSession {
                var start: Date
                var end: Date
                var total: TimeInterval = 0
                var deep: TimeInterval = 0
                var rem: TimeInterval = 0
            }
            let sessionGap: TimeInterval = 4 * 3600
            var sessions: [SleepSession] = []
            for s in samples {
                let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
                let counts: Bool
                switch v {
                case .some(.asleepCore), .some(.asleepDeep), .some(.asleepREM), .some(.asleepUnspecified):
                    counts = true
                case .some(.asleep):
                    counts = !hasStages
                default:
                    counts = false
                }
                guard counts else { continue }
                let dur = s.endDate.timeIntervalSince(s.startDate)
                let deepDur: TimeInterval = v == .some(.asleepDeep) ? dur : 0
                let remDur: TimeInterval  = v == .some(.asleepREM)  ? dur : 0
                if var last = sessions.last,
                   s.startDate.timeIntervalSince(last.end) < sessionGap {
                    last.end = max(last.end, s.endDate)
                    last.total += dur
                    last.deep += deepDur
                    last.rem += remDur
                    sessions[sessions.count - 1] = last
                } else {
                    sessions.append(SleepSession(start: s.startDate, end: s.endDate,
                                                 total: dur, deep: deepDur, rem: remDur))
                }
            }
            let latest = sessions.max(by: { $0.end < $1.end })
            let total = latest?.total ?? 0
            let deep = latest?.deep ?? 0
            let rem = latest?.rem ?? 0
            let earliestAsleep = latest?.start
            // Per-sample full dump at .debug level — read top to bottom in
            // Console.app (filter on category `HealthKit.Sleep`). Every field
            // reachable via `HKCategorySample` → `HKSample` → `HKObject` is
            // emitted so a duplicated total can be traced back to a specific
            // sample / source / metadata key without round-tripping through
            // the debugger. Look for:
            // (a) overlapping ranges from different `src=` values → multi-source
            //     double count (already mitigated by `hasStages` for legacy
            //     `.asleep`, but two stage-writing sources would still overlap);
            // (b) `awake` / `inBed` (we exclude these — sanity check);
            // (c) entries far from "last night" — may be a daytime nap;
            // (d) suspicious metadata (timezone shift, external UUID
            //     patterns) when overlap looks like it came from re-imports.
            LPLog.sleep.debug("=== \(samples.count, privacy: .public) samples · window=36h · hasStages=\(hasStages, privacy: .public) · sessions=\(sessions.count, privacy: .public) ===")
            #if DEBUG
            // Per-sample dump eagerly builds DateFormatter / metadata strings for
            // *every* stage sample (a night can be dozens–hundreds) on the
            // MainActor — a pure diagnostic, so keep it out of Release entirely.
            for (idx, s) in samples.enumerated() {
                Self.dumpSleepSample(s, index: idx)
            }
            #endif
            let startStr = earliestAsleep.map { LPLog.dateFormatter.string(from: $0) } ?? "nil"
            LPLog.sleep.info(">>> total=\(Int(total/60), privacy: .public)min deep=\(Int(deep/60), privacy: .public)min rem=\(Int(rem/60), privacy: .public)min start=\(startStr, privacy: .public)")
            continuation.yield(.sleep(total: total, deep: deep, rem: rem, start: earliestAsleep))
        } catch {
            LPLog.sleep.error("postSleep threw: \(error.localizedDescription, privacy: .public)")
        }
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
        // (see `Self.loadAnchor` / `Self.persistAnchor`) so subsequent cold
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
            Self.persistAnchor(result.newAnchor)
            if !result.addedSamples.isEmpty {
                LPLog.workout.info("Fetched \(result.addedSamples.count, privacy: .public) workout(s)")
            }
            for workout in result.addedSamples {
                guard emittedWorkoutUUIDs.insert(workout.uuid).inserted else {
                    LPLog.workout.debug("dedup skip uuid=\(workout.uuid.uuidString, privacy: .public) — already emitted this session")
                    continue
                }
                let kind = Self.bucket(workout.workoutActivityType)
                // iOS 18 deprecated `HKWorkout.totalEnergyBurned` in favor of
                // per-statistics access; pull kcal out via the activity sum.
                let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?
                    .doubleValue(for: .kilocalorie())
                let durMin = Int(workout.duration / 60)
                let endStr = LPLog.dateFormatter.string(from: workout.endDate)
                let src = workout.sourceRevision.source.name
                LPLog.workout.debug("  \(kind.rawValue, privacy: .public) \(durMin, privacy: .public)min ended \(endStr, privacy: .public) kcal=\(kcal ?? 0, privacy: .public) src=\(src, privacy: .public)")
                continuation.yield(.workoutFinished(
                    kind: kind,
                    duration: workout.duration,
                    kcal: kcal,
                    end: workout.endDate
                ))
            }
        } catch {
            LPLog.workout.error("postWorkouts threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Anchor persistence

    /// `HKQueryAnchor` is `NSSecureCoding`. We archive into UserDefaults so
    /// every cold launch resumes from the last delivered sample instead of
    /// replaying the 36h first-run window over and over.
    private static let anchorKey = PiboPersistenceKeys.Defaults.workoutAnchor

    private static func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else {
            LPLog.workout.debug("No persisted anchor — first launch path")
            return nil
        }
        do {
            let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            LPLog.workout.debug("Anchor loaded from UserDefaults")
            return anchor
        } catch {
            LPLog.workout.error("Anchor unarchive failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Auth flag persistence

    /// Mirrors "the user said yes once" across process restarts. HealthKit
    /// has no read-side `authorizationStatus` we can trust (privacy: it
    /// returns `.notDetermined` for read scopes regardless of what was
    /// granted), and `RootView` only routes through `HealthAuthView` on the
    /// first launch — so without this flag we lose the signal entirely on
    /// the second cold launch and the home screen renders from the cold-start
    /// `demoStats` floor. Cleared implicitly: if the user revoked permission
    /// in Settings, snapshot queries simply return no data on next reconcile,
    /// so we degrade visibly rather than silently — that's the right read.
    private static let authorizedKey = PiboPersistenceKeys.Defaults.healthKitAuthorized

    private static func loadAuthorizedFlag() -> Bool {
        UserDefaults.standard.bool(forKey: authorizedKey)
    }

    private static func persistAuthorizedFlag(_ granted: Bool) {
        UserDefaults.standard.set(granted, forKey: authorizedKey)
    }

    private static func persistAnchor(_ anchor: HKQueryAnchor?) {
        let defaults = UserDefaults.standard
        guard let anchor else {
            defaults.removeObject(forKey: anchorKey)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            defaults.set(data, forKey: anchorKey)
        } catch {
            LPLog.workout.error("Anchor archive failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Coarse bucketing for the home screen. We don't need fine-grained
    /// activity types — just enough to flip a matching "建议: 跑步" card to done.
    static func bucket(_ type: HKWorkoutActivityType) -> HealthEvent.WorkoutKind {
        switch type {
        case .running:                                  return .run
        case .walking, .hiking:                         return .walk
        case .cycling, .handCycling:                    return .cycle
        case .highIntensityIntervalTraining,
             .functionalStrengthTraining,
             .traditionalStrengthTraining,
             .crossTraining:                            return .hiit
        case .yoga, .pilates, .flexibility,
             .mindAndBody, .barre:                      return .yoga
        default:                                        return .other
        }
    }
}
