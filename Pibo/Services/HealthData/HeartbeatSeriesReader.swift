import Foundation
import HealthKit
import os

/// Reads the Apple Watch's beat-to-beat data and computes **RMSSD** — Pibo's own
/// HRV, independent of Apple's precomputed `heartRateVariabilitySDNN`.
///
/// This mirrors how StressWatch actually works: it does **not** trust the SDNN
/// sample. Every periodic HRV measurement the watch records ships with an
/// `HKHeartbeatSeriesSample` — a series of individual beat timestamps. We
/// enumerate those, take successive differences to get **RR intervals (ms)**,
/// **split the run at any beat flagged `precededByGap`** (a dropped/uncertain
/// beat: the intervals on either side of the hole are not temporally adjacent,
/// so differencing across it is meaningless), correct artifacts with the
/// Lipponen–Tarvainen method, and compute standard NN-RMSSD. RMSSD is the
/// short-window HRV metric most sensitive to acute stress, which is why it fits
/// near-real-time monitoring better than SDNN.
///
/// **RMSSD ≠ SDNN.** Apple's `heartRateVariabilitySDNN` measures the *total*
/// variability of the same window (slow components included); RMSSD only sees
/// beat-to-beat. SDNN therefore reads systematically higher, and the gap widens
/// as HRV rises. Comparing the two numbers directly is a category error —
/// `latestSample` logs both precisely so that confusion can be settled with data.
///
/// Availability: heartbeat series only exist on real hardware with a worn Apple
/// Watch — the simulator has none. Callers must handle `nil`.
enum HeartbeatSeriesReader {
    /// One computed HRV reading + its context: when it was measured and whether
    /// the wearer was at rest (no overlapping workout).
    /// Only resting readings should enter the personal baseline — active-time
    /// HRV runs naturally low and would poison it.
    struct StressSample: Sendable {
        /// Stable identity of the underlying heartbeat series, so callers can
        /// dedup repeated processing of the same series (observer + reconcile
        /// both re-fetch the newest one).
        var seriesID: UUID
        var rmssd: Double
        var measurement: HRVAnalysis.Measurement
        var date: Date
        /// Awake/resting context only; measurement evidence is tracked
        /// separately by `measurement.canUpdateTrends`.
        var isResting: Bool

        var canInterpretStress: Bool {
            isResting && measurement.canUpdateTrends
        }
    }

    enum SampleRead: Sendable {
        case computed(StressSample)
        /// The immutable series was read successfully but contains no usable
        /// successive RR pair, so retrying cannot change the result.
        case uncomputable
        /// HealthKit failed during beat enumeration; leave it uncheckpointed so
        /// a later observer/reconcile can retry.
        case unavailable
    }

    /// The newest heartbeat series as a `StressSample`, or `nil` if no series is
    /// readable or it contains no successive RR pair. Pibo does not reject a
    /// series based on its rhythm or an app-defined quality score.
    static func latestSample(store: HKHealthStore) async -> StressSample? {
        guard let series = await latestSeries(store: store) else { return nil }
        return await sample(for: series, store: store)
    }

    /// Converts one known series. Kept separate from the query so the ingestion
    /// layer can backfill every unprocessed series instead of repeatedly reading
    /// only the newest one.
    static func sample(for series: HKHeartbeatSeriesSample,
                       store: HKHealthStore) async -> StressSample? {
        guard case .computed(let sample) = await readSample(for: series, store: store) else {
            return nil
        }
        return sample
    }

    static func readSample(for series: HKHeartbeatSeriesSample,
                           store: HKHealthStore) async -> SampleRead {
        guard case .success(let segments) = await rrSegments(for: series, store: store) else {
            return .unavailable
        }
        guard let measurement = HRVAnalysis.analyze(segments) else {
            let rrCount = segments.reduce(0) { $0 + $1.count }
            LPLog.healthKit.notice("hrv unavailable: no successive RR pair rr=\(rrCount, privacy: .public)")
            return .uncomputable
        }
        // Diagnostic: corrected NN-RMSSD, raw RR-RMSSD and Apple's SDNN. They
        // are different quantities; the comparison is for audit, never a gate.
        let sdnn = await sdnnMs(around: series, store: store)
        LPLog.healthKit.notice("""
            hrv computed \
            rmssd=\(measurement.rmssd, format: .fixed(precision: 1), privacy: .public)ms \
            raw=\(measurement.rawRMSSD, format: .fixed(precision: 1), privacy: .public)ms \
            sdnn=\(sdnn ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
            meanNN=\(measurement.meanNN, format: .fixed(precision: 0), privacy: .public)ms \
            rr=\(measurement.rrCount, privacy: .public) \
            nn=\(measurement.nnCount, privacy: .public) \
            corrected=\(measurement.corrections.total, privacy: .public) \
            eligible=\(measurement.canUpdateTrends, privacy: .public)
            """)
        let resting = await isEligibleResting(during: series, store: store)
        return .computed(StressSample(
            seriesID: series.uuid,
            rmssd: measurement.rmssd,
            measurement: measurement,
            date: series.startDate,
            isResting: resting
        ))
    }

    /// The newest heartbeat series' stable id, without the expensive per-beat RR
    /// enumeration. Lets a caller cheaply short-circuit re-processing the same
    /// series (the observer + every foreground `reconcile()` re-fetch the newest
    /// one) before paying for `latestSample`'s full read.
    static func latestSeriesID(store: HKHealthStore) async -> UUID? {
        await latestSeries(store: store)?.uuid
    }

    /// Core only accepts a resting, awake RMSSD window. Workouts and actual
    /// sleep both alter the signal enough that they must not enter the personal
    /// daytime stress baseline.
    private static func isEligibleResting(during series: HKHeartbeatSeriesSample,
                                          store: HKHealthStore) async -> Bool {
        async let workoutOverlap = hasWorkoutOverlap(during: series, store: store)
        async let sleepOverlap = hasSleepOverlap(during: series, store: store)
        async let mindfulnessOverlap = hasMindfulnessOverlap(during: series, store: store)
        let (workout, sleep, mindfulness) = await (
            workoutOverlap, sleepOverlap, mindfulnessOverlap
        )
        // Unknown acquisition context must be record-only. Treating a failed
        // query as an empty result silently poisons the personal resting baseline.
        return workout == .clear && sleep == .clear && mindfulness == .clear
    }

    private enum OverlapRead: Sendable, Equatable {
        case clear
        case overlap
        case unavailable
    }

    private static func hasWorkoutOverlap(during series: HKHeartbeatSeriesSample,
                                          store: HKHealthStore) async -> OverlapRead {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    LPLog.healthKit.error("workout overlap query threw: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .unavailable)
                } else {
                    continuation.resume(returning: samples?.isEmpty == false ? .overlap : .clear)
                }
            }
            store.execute(query)
        }
    }

    private static func hasSleepOverlap(during series: HKHeartbeatSeriesSample,
                                        store: HKHealthStore) async -> OverlapRead {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    LPLog.healthKit.error("sleep overlap query threw: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .unavailable)
                    return
                }
                let overlapsSleep = (samples as? [HKCategorySample])?.contains {
                    sleepValueMeansAsleep($0.value)
                } ?? false
                continuation.resume(returning: overlapsSleep ? .overlap : .clear)
            }
            store.execute(query)
        }
    }

    /// Excludes Apple Mindfulness sessions. Pibo's CRC watch trainer is already
    /// excluded through its overlapping `.mindAndBody` workout.
    private static func hasMindfulnessOverlap(during series: HKHeartbeatSeriesSample,
                                               store: HKHealthStore) async -> OverlapRead {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.mindfulSession),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    LPLog.healthKit.error("mindfulness overlap query threw: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .unavailable)
                } else {
                    continuation.resume(returning: samples?.isEmpty == false ? .overlap : .clear)
                }
            }
            store.execute(query)
        }
    }

    static func sleepValueMeansAsleep(_ rawValue: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake, .none: false
        @unknown default: false
        }
    }

    /// Fetch the most recent `HKHeartbeatSeriesSample`. Uses the classic
    /// `HKSampleQuery` — heartbeat series predates the typed descriptor API.
    private static func latestSeries(store: HKHealthStore) async -> HKHeartbeatSeriesSample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    LPLog.healthKit.error("heartbeat series query threw: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: samples?.first as? HKHeartbeatSeriesSample)
            }
            store.execute(query)
        }
    }

    /// Recent series in chronological order. HealthKit observer delivery is
    /// coalesced, so one wake can represent several immutable samples; callers
    /// must drain the batch rather than assuming `limit: 1` means no data loss.
    static func recentSeries(store: HKHealthStore,
                             since: Date,
                             limit: Int = 256) async -> [HKHeartbeatSeriesSample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    LPLog.healthKit.error("recent heartbeat series query threw: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                let series = ((samples as? [HKHeartbeatSeriesSample]) ?? [])
                    .sorted { $0.startDate < $1.startDate }
                continuation.resume(returning: series)
            }
            store.execute(query)
        }
    }

    /// Enumerate a series' beat timestamps → **contiguous runs** of RR intervals
    /// (ms). `HKHeartbeatSeriesQuery` still uses the closure-callback API, so wrap
    /// it in a continuation that resumes once, when `done == true`.
    ///
    /// Why segments and not one flat array: a beat flagged `precededByGap` means
    /// the watch lost one or more beats before it. The RR *ending* at that beat is
    /// unusable (we never append it), but so is the **difference** between the
    /// interval before the hole and the interval after it — those two intervals
    /// are not temporally adjacent. A flat array loses that boundary and
    /// `zip(dropLast, dropFirst)` silently differences straight across it. Cutting
    /// a new segment at every gap makes the boundary structural.
    private enum RRRead: Sendable {
        case success([[Double]])
        case unavailable
    }

    private static func rrSegments(for series: HKHeartbeatSeriesSample,
                                   store: HKHealthStore) async -> RRRead {
        await withCheckedContinuation { continuation in
            var segments: [[Double]] = []
            var current: [Double] = []
            var previous: TimeInterval?
            var hadError = false
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                if error == nil {
                    if precededByGap {
                        // Close the run before the hole and re-anchor after it.
                        if current.count > 0 { segments.append(current) }
                        current = []
                        previous = timeSinceStart
                    } else if let prev = previous {
                        current.append((timeSinceStart - prev) * 1000)   // seconds → ms
                        previous = timeSinceStart
                    } else {
                        previous = timeSinceStart
                    }
                } else {
                    hadError = true
                    // A skipped beat is a hole like any other. Dropping the anchor
                    // too is what stops the next good beat from differencing back
                    // to a stale one across it — the same bridging hazard the gap
                    // split exists to prevent.
                    if current.count > 0 { segments.append(current) }
                    current = []
                    previous = nil
                }
                if done {
                    if current.count > 0 { segments.append(current) }
                    continuation.resume(returning: hadError ? .unavailable : .success(segments))
                }
            }
            store.execute(query)
        }
    }

    /// Apple's own `heartRateVariabilitySDNN` for (approximately) the same window
    /// as `series`. Diagnostic only — never feeds the stress tier. A ±60s slack
    /// around the series covers the small offset between when the watch stamps the
    /// series and when it stamps the derived SDNN sample.
    private static func sdnnMs(around series: HKHeartbeatSeriesSample,
                               store: HKHealthStore) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate.addingTimeInterval(-60),
                end: series.endDate.addingTimeInterval(60))
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRateVariabilitySDNN),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    #if DEBUG
    /// One end-to-end probe of the stress data path, for the settings DEV
    /// diagnostic. Answers "为什么压力记录是空的" by checking, in the last 30
    /// days: whether HealthKit is available, whether SDNN HRV samples exist (the
    /// *control* — proves the watch measures HRV at all), and whether heartbeat
    /// **series** exist + yield a calculable RMSSD. A series count of 0 while SDNN
    /// has data almost always means the series type was never authorized.
    struct StressProbe: Sendable {
        var healthAvailable: Bool
        var hrvCount: Int
        var hrvLatest: Date?
        var seriesCount: Int
        var seriesLatest: Date?
        var rrCount: Int
        var rmssd: Double?
        var rawRMSSD: Double?
        var nnCount: Int
        var correctionCount: Int
        var correctionRate: Double
        var durationSeconds: Double
        var canUpdateTrends: Bool
        var diffs: Int
    }

    static func diagnose(store: HKHealthStore) async -> StressProbe {
        guard HKHealthStore.isHealthDataAvailable() else {
            return StressProbe(healthAvailable: false, hrvCount: 0, hrvLatest: nil,
                               seriesCount: 0, seriesLatest: nil, rrCount: 0, rmssd: nil,
                               rawRMSSD: nil, nnCount: 0, correctionCount: 0,
                               correctionRate: 0, durationSeconds: 0, canUpdateTrends: false,
                               diffs: 0)
        }
        let (hrvCount, hrvLatest) = await countAndLatest(HKQuantityType(.heartRateVariabilitySDNN), store: store)
        let (seriesCount, seriesLatest) = await countAndLatest(HKSeriesType.heartbeat(), store: store)

        var segments: [[Double]] = []
        if let series = await latestSeries(store: store) {
            if case .success(let readSegments) = await rrSegments(for: series, store: store) {
                segments = readSegments
            }
        }
        let analysis = HRVAnalysis.analyze(segments)
        return StressProbe(healthAvailable: true,
                           hrvCount: hrvCount, hrvLatest: hrvLatest,
                           seriesCount: seriesCount, seriesLatest: seriesLatest,
                           rrCount: segments.reduce(0) { $0 + $1.count },
                           rmssd: analysis?.rmssd,
                           rawRMSSD: analysis?.rawRMSSD,
                           nnCount: analysis?.nnCount ?? 0,
                           correctionCount: analysis?.corrections.total ?? 0,
                           correctionRate: analysis?.correctionRate ?? 0,
                           durationSeconds: analysis?.durationSeconds ?? 0,
                           canUpdateTrends: analysis?.canUpdateTrends ?? false,
                           diffs: analysis?.diffs ?? 0)
    }

    /// Count samples of a type in the last 30 days + the newest one's start.
    /// Read-type auth is opaque in HealthKit (a denied read just returns
    /// nothing), so a zero here is "no data OR not authorized".
    private static func countAndLatest(_ type: HKSampleType, store: HKHealthStore) async -> (Int, Date?) {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples?.count ?? 0, samples?.first?.startDate))
            }
            store.execute(query)
        }
    }
    #endif
}
