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
/// so differencing across it is meaningless), and compute RMSSD (root-mean-square
/// of successive RR differences) per segment. RMSSD is the short-window HRV
/// metric most sensitive to acute stress, which is why it fits near-real-time
/// monitoring better than SDNN.
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
    /// One computed HRV reading + the context needed to judge it: when it was
    /// measured and whether the wearer was at rest (no overlapping workout).
    /// Only resting readings should enter the personal baseline — active-time
    /// HRV runs naturally low and would poison it.
    struct StressSample: Sendable {
        /// Stable identity of the underlying heartbeat series, so callers can
        /// dedup repeated processing of the same series (observer + reconcile
        /// both re-fetch the newest one).
        var seriesID: UUID
        var rmssd: Double
        var date: Date
        var isResting: Bool
    }

    /// The newest heartbeat series as a `StressSample`, or `nil` if none is
    /// readable (no series in the store, too few beats, too many artifacts, or
    /// the type isn't authorized).
    static func latestSample(store: HKHealthStore) async -> StressSample? {
        guard let series = await latestSeries(store: store) else { return nil }
        let measurement = HRVAnalysis.measure(await rrSegments(for: series, store: store))
        let trusted = HRVAnalysis.isTrustworthy(measurement)
        // Diagnostic: our RMSSD next to Apple's SDNN for the *same* window, plus
        // how much of the window survived artifact rejection. This is what tells
        // "our filter is eating real signal" apart from "the other app is simply
        // showing SDNN". Cheap — one extra query per series (every 2–5h).
        //
        // Logged for **rejected** windows too, and before the gate: the trust
        // gates are strict enough to drop a real reading, and a rejection that
        // leaves no trace makes "为什么压力记录是空的" unanswerable — the counts
        // here are exactly what says whether it was artifacts or a short series.
        let sdnn = await sdnnMs(around: series, store: store)
        LPLog.healthKit.notice("""
            hrv \(trusted ? "ok" : "rejected", privacy: .public) \
            rmssd=\(measurement.rmssd, format: .fixed(precision: 1), privacy: .public)ms \
            sdnn=\(sdnn ?? -1, format: .fixed(precision: 1), privacy: .public)ms \
            meanRR=\(measurement.meanRR, format: .fixed(precision: 0), privacy: .public)ms \
            rr=\(measurement.rrCount, privacy: .public) \
            flagged=\(measurement.flagged, privacy: .public) \
            diffs=\(measurement.diffs, privacy: .public)
            """)
        guard trusted else { return nil }
        let resting = await isEligibleResting(during: series, store: store)
        return StressSample(seriesID: series.uuid, rmssd: measurement.rmssd,
                            date: series.startDate, isResting: resting)
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
        let (hasWorkout, hasSleep) = await (workoutOverlap, sleepOverlap)
        return !hasWorkout && !hasSleep
    }

    private static func hasWorkoutOverlap(during series: HKHeartbeatSeriesSample,
                                          store: HKHealthStore) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(query)
        }
    }

    private static func hasSleepOverlap(during series: HKHeartbeatSeriesSample,
                                        store: HKHealthStore) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let overlapsSleep = (samples as? [HKCategorySample])?.contains {
                    sleepValueMeansAsleep($0.value)
                } ?? false
                continuation.resume(returning: overlapsSleep)
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
    private static func rrSegments(for series: HKHeartbeatSeriesSample,
                                   store: HKHealthStore) async -> [[Double]] {
        await withCheckedContinuation { continuation in
            var segments: [[Double]] = []
            var current: [Double] = []
            var previous: TimeInterval?
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
                    continuation.resume(returning: segments)
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
    /// **series** exist + yield a usable RMSSD. A series count of 0 while SDNN
    /// has data almost always means the series type was never authorized.
    struct StressProbe: Sendable {
        var healthAvailable: Bool
        var hrvCount: Int
        var hrvLatest: Date?
        var seriesCount: Int
        var seriesLatest: Date?
        var rrCount: Int
        var rmssd: Double?
        /// RR intervals the newest series had rejected as artifacts, and the
        /// successive differences that survived. When `rmssd` is nil these two
        /// say *which* gate failed — noisy data vs. too short a series.
        var flagged: Int
        var diffs: Int
    }

    static func diagnose(store: HKHealthStore) async -> StressProbe {
        guard HKHealthStore.isHealthDataAvailable() else {
            return StressProbe(healthAvailable: false, hrvCount: 0, hrvLatest: nil,
                               seriesCount: 0, seriesLatest: nil, rrCount: 0, rmssd: nil,
                               flagged: 0, diffs: 0)
        }
        let (hrvCount, hrvLatest) = await countAndLatest(HKQuantityType(.heartRateVariabilitySDNN), store: store)
        let (seriesCount, seriesLatest) = await countAndLatest(HKSeriesType.heartbeat(), store: store)

        var segments: [[Double]] = []
        if let series = await latestSeries(store: store) {
            segments = await rrSegments(for: series, store: store)
        }
        let analysis = HRVAnalysis.analyze(segments)
        let measurement = HRVAnalysis.measure(segments)
        return StressProbe(healthAvailable: true,
                           hrvCount: hrvCount, hrvLatest: hrvLatest,
                           seriesCount: seriesCount, seriesLatest: seriesLatest,
                           rrCount: segments.reduce(0) { $0 + $1.count },
                           rmssd: analysis?.rmssd,
                           flagged: measurement.flagged,
                           diffs: measurement.diffs)
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
