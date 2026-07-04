import Foundation
import HealthKit

/// Post-session **authoritative** RMSSD for the CRC trainer — mirrors the phone's
/// `HeartbeatSeriesReader`, but scoped to a single training window.
///
/// Unlike the live `CRCHRVEstimator` (which reads RSA off averaged BPM), this
/// uses the real `HKHeartbeatSeriesSample`s the watch recorded *during* the
/// session — genuine beat-to-beat timestamps → RR intervals → RMSSD with
/// artifact rejection. There may be zero or several in a 5-minute window (the
/// system samples opportunistically, favouring calm/still periods — which a
/// breathing session usually is), so callers must handle `nil`.
enum CRCHeartbeatSeriesReader {
    /// Median RMSSD (ms) across every readable heartbeat series overlapping
    /// `[start, end]`, or `nil` if none yielded a trustworthy value. Median (not
    /// mean) so one noisy-but-passing series can't skew the session figure.
    static func sessionRMSSD(store: HKHealthStore, start: Date, end: Date) async -> Double? {
        let series = await seriesOverlapping(store: store, start: start, end: end)
        guard !series.isEmpty else { return nil }
        var values: [Double] = []
        for s in series {
            let rr = await rrIntervalsMs(for: s, store: store)
            if let v = rmssd(rr) { values.append(v) }
        }
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Every `HKHeartbeatSeriesSample` whose interval overlaps the window.
    private static func seriesOverlapping(store: HKHealthStore,
                                          start: Date, end: Date) async -> [HKHeartbeatSeriesSample] {
        await withCheckedContinuation { continuation in
            // No options → overlap match (a series straddling the boundary counts).
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Enumerate a series' beat timestamps → RR intervals (ms), dropping any beat
    /// flagged `precededByGap` so we never bridge an interval across a hole.
    private static func rrIntervalsMs(for series: HKHeartbeatSeriesSample,
                                      store: HKHealthStore) async -> [Double] {
        await withCheckedContinuation { continuation in
            var rr: [Double] = []
            var previous: TimeInterval?
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                if error == nil {
                    if precededByGap {
                        previous = timeSinceStart
                    } else if let prev = previous {
                        rr.append((timeSinceStart - prev) * 1000)   // seconds → ms
                        previous = timeSinceStart
                    } else {
                        previous = timeSinceStart
                    }
                }
                if done { continuation.resume(returning: rr) }
            }
            store.execute(query)
        }
    }

    /// RMSSD (ms) with artifact rejection — a successive difference counts only
    /// when both RR intervals are physiologically plausible (~30–200 bpm) and
    /// don't jump >20% (Malik ectopic criterion). Correct for real beat-to-beat
    /// data (unlike the live BPM estimator, which must keep the breath swings).
    static func rmssd(_ rrMs: [Double]) -> Double? {
        guard rrMs.count >= 2 else { return nil }
        var sumSq = 0.0
        var n = 0
        for (a, b) in zip(rrMs.dropLast(), rrMs.dropFirst()) {
            guard plausibleRR(a), plausibleRR(b) else { continue }
            guard abs(b - a) <= 0.2 * a else { continue }
            let d = b - a
            sumSq += d * d
            n += 1
        }
        guard n >= 5 else { return nil }
        return (sumSq / Double(n)).squareRoot()
    }

    /// RR interval within ~30–200 bpm.
    private static func plausibleRR(_ ms: Double) -> Bool { ms >= 300 && ms <= 2000 }
}
