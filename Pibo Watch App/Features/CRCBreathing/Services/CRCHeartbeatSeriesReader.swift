import Foundation
import HealthKit

/// Post-session **authoritative** RMSSD for the CRC trainer — the same
/// measurement the phone makes, scoped to a single training window.
///
/// Unlike the live `CRCHRVEstimator` (which reads RSA off averaged BPM), this
/// uses the real `HKHeartbeatSeriesSample`s the watch recorded *during* the
/// session — genuine beat-to-beat timestamps → RR intervals → RMSSD via the
/// shared `HRVAnalysis`. There may be zero or several in a 5-minute window (the
/// system samples opportunistically, favouring calm/still periods — which a
/// breathing session usually is), so callers must handle `nil`.
///
/// The arithmetic is **not** duplicated here: this and the phone's
/// `HeartbeatSeriesReader` both delegate to `HRVAnalysis`, so a session report
/// and the next background stress reading can never disagree about the same
/// wearer. Only the HealthKit enumeration is per-target (`HRVAnalysis` stays
/// Foundation-only so the widget extension doesn't pull in HealthKit).
enum CRCHeartbeatSeriesReader {
    /// Corrected NN-RMSSD (ms) across every readable heartbeat series overlapping
    /// `[start, end]`, or `nil` if none contains a pair. The same shared
    /// Lipponen–Tarvainen correction used by the phone keeps session and passive
    /// Apple measurements comparable. Session display is not a stress decision,
    /// so short evidence remains visible here.
    static func sessionRMSSD(store: HKHealthStore, start: Date, end: Date) async -> Double? {
        let series = await seriesOverlapping(store: store, start: start, end: end)
        guard !series.isEmpty else { return nil }
        var allSegments: [[Double]] = []
        for s in series {
            allSegments.append(contentsOf: await rrSegments(for: s, store: store))
        }
        return HRVAnalysis.analyze(allSegments)?.rmssd
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

    /// Enumerate a series' beat timestamps → **contiguous runs** of RR intervals
    /// (ms), cut at every lost beat. Mirrors the phone's `rrSegments`; the split
    /// is what stops a difference being formed between the interval before a hole
    /// and the one after it, which are not temporally adjacent.
    private static func rrSegments(for series: HKHeartbeatSeriesSample,
                                   store: HKHealthStore) async -> [[Double]] {
        await withCheckedContinuation { continuation in
            var segments: [[Double]] = []
            var current: [Double] = []
            var previous: TimeInterval?
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                if error == nil {
                    if precededByGap {
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
                    // A skipped beat is a hole like any other — drop the anchor too,
                    // or the next good beat differences back across it.
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
}
