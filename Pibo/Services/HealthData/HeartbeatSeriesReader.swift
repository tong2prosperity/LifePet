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
/// drop any beat flagged `precededByGap` (a dropped/uncertain beat whose gap
/// would poison the difference), and compute RMSSD (root-mean-square of
/// successive RR differences). RMSSD is the short-window HRV metric most
/// sensitive to acute stress, which is why it fits near-real-time monitoring
/// better than SDNN.
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
    /// readable (no series in the store, too few beats, or the type isn't
    /// authorized).
    static func latestSample(store: HKHealthStore) async -> StressSample? {
        guard let series = await latestSeries(store: store) else { return nil }
        let rr = await rrIntervalsMs(for: series, store: store)
        guard let value = rmssd(rr) else { return nil }
        let resting = await isResting(during: series, store: store)
        return StressSample(seriesID: series.uuid, rmssd: value,
                            date: series.startDate, isResting: resting)
    }

    /// Whether the series was measured at rest — true when **no HKWorkout
    /// overlaps** its time window. A single lightweight query (heartbeat series
    /// arrive only every 2–5h, so the cost is negligible). Read auth for
    /// workouts is opaque; a denied read returns no samples → treated as resting,
    /// the safe default (an occasional active reading slipping in is far less
    /// harmful than dropping every reading).
    private static func isResting(during series: HKHeartbeatSeriesSample,
                                  store: HKHealthStore) async -> Bool {
        await withCheckedContinuation { continuation in
            // No options → matches any workout whose interval overlaps the series.
            let predicate = HKQuery.predicateForSamples(
                withStart: series.startDate, end: series.endDate, options: [])
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples?.isEmpty ?? true))
            }
            store.execute(query)
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

    /// Enumerate a series' beat timestamps → RR intervals (ms).
    /// `HKHeartbeatSeriesQuery` still uses the closure-callback API, so wrap it
    /// in a continuation that resumes once, when `done == true`.
    private static func rrIntervalsMs(for series: HKHeartbeatSeriesSample,
                                      store: HKHealthStore) async -> [Double] {
        await withCheckedContinuation { continuation in
            var rr: [Double] = []
            var previous: TimeInterval?
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                if error == nil {
                    if precededByGap {
                        // The interval from the previous beat is unreliable — reset
                        // the anchor so we never append an RR across the hole.
                        previous = timeSinceStart
                    } else if let prev = previous {
                        rr.append((timeSinceStart - prev) * 1000)   // seconds → ms
                        previous = timeSinceStart
                    } else {
                        previous = timeSinceStart
                    }
                }
                if done {
                    continuation.resume(returning: rr)
                }
            }
            store.execute(query)
        }
    }

    /// RMSSD — root mean square of successive RR-interval differences, in ms.
    /// Same math as the watch's `HRVCalculator`; duplicated here because that
    /// type lives in the watch target and can't be imported across targets.
    ///
    /// Artifact rejection: RMSSD is acutely sensitive to ectopic/misdetected
    /// beats — a single bad beat injects a huge successive difference that swamps
    /// the true value. So a successive difference is only counted when **both**
    /// RR intervals are physiologically plausible (`plausibleRR`, ~30–200 bpm)
    /// **and** they don't jump more than 20% relative to each other (the Malik
    /// criterion for ectopics). Pairs touching an artifact are dropped; because
    /// each counted diff is a genuinely-adjacent pair, dropping one never bridges
    /// two beats across the hole.
    static func rmssd(_ rrMs: [Double]) -> Double? {
        guard rrMs.count >= 2 else { return nil }
        var sumSq = 0.0
        var n = 0
        for (a, b) in zip(rrMs.dropLast(), rrMs.dropFirst()) {
            guard plausibleRR(a), plausibleRR(b) else { continue }
            // Reject ectopic jumps: >20% change from the previous beat.
            guard abs(b - a) <= 0.2 * a else { continue }
            let d = b - a
            sumSq += d * d
            n += 1
        }
        // A genuine ~1-min HRV series yields dozens of successive differences; if
        // artifact rejection leaves only a handful, the series is too noisy to
        // classify — return nil (skip the reading) rather than emit a wild RMSSD
        // off 1–2 beats.
        guard n >= minValidDiffs else { return nil }
        return (sumSq / Double(n)).squareRoot()
    }

    /// Minimum artifact-free successive differences for a trustworthy RMSSD.
    private static let minValidDiffs = 5

    /// Physiologically plausible RR interval in ms: ~30–200 bpm. Anything outside
    /// is a dropped/spurious beat, not a real heartbeat interval.
    private static func plausibleRR(_ ms: Double) -> Bool { ms >= 300 && ms <= 2000 }

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
    }

    static func diagnose(store: HKHealthStore) async -> StressProbe {
        guard HKHealthStore.isHealthDataAvailable() else {
            return StressProbe(healthAvailable: false, hrvCount: 0, hrvLatest: nil,
                               seriesCount: 0, seriesLatest: nil, rrCount: 0, rmssd: nil)
        }
        let (hrvCount, hrvLatest) = await countAndLatest(HKQuantityType(.heartRateVariabilitySDNN), store: store)
        let (seriesCount, seriesLatest) = await countAndLatest(HKSeriesType.heartbeat(), store: store)

        var rr: [Double] = []
        if let series = await latestSeries(store: store) {
            rr = await rrIntervalsMs(for: series, store: store)
        }
        return StressProbe(healthAvailable: true,
                           hrvCount: hrvCount, hrvLatest: hrvLatest,
                           seriesCount: seriesCount, seriesLatest: seriesLatest,
                           rrCount: rr.count, rmssd: rmssd(rr))
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
