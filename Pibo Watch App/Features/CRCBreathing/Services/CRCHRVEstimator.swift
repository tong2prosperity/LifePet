import Foundation

/// A **live** HRV estimate for the breathing session, updated as often as the
/// workout heart-rate stream fires (~every few seconds).
///
/// Honesty note (important): during a workout the Apple Watch exposes only
/// **averaged BPM** — there is no public live beat-to-beat RR stream. So this is
/// NOT clinical RMSSD. During paced slow breathing, HR oscillates with the
/// breath (respiratory sinus arrhythmia, RSA): it rises on the inhale, falls on
/// the exhale. That oscillation is visible in the BPM series, and this estimator
/// reads it off — an RSA-amplitude proxy that genuinely reflects "how deep the
/// breath is landing" and moves in real time. The **authoritative** RMSSD (from
/// the recorded `HKHeartbeatSeriesSample`) is shown after the session
/// (`CRCHeartbeatSeriesReader`).
///
/// Method: each BPM sample → instantaneous RR (ms) = 60000 / bpm; RMSSD (root
/// mean square of successive RR differences) over a rolling window. Deliberately
/// **no** Malik-style ectopic rejection here — the whole point is to keep the
/// large, legitimate breath-driven swings that a beat-to-beat filter would strip.
struct CRCHRVEstimator {
    private struct Reading { var bpm: Double; var time: Date }
    private var samples: [Reading] = []

    /// Rolling window in seconds — ~two slow-breath cycles at 6 breaths/min, long
    /// enough to hold a full oscillation, short enough to feel live.
    let window: TimeInterval

    init(window: TimeInterval = 60) { self.window = window }

    mutating func append(bpm: Double, at time: Date) {
        guard bpm >= 40, bpm <= 200 else { return }
        samples.append(Reading(bpm: bpm, time: time))
        let cutoff = time.addingTimeInterval(-window)
        samples.removeAll { $0.time < cutoff }
    }

    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    /// Time of the newest sample — lets callers detect a stalled HR stream and
    /// stop showing a frozen estimate.
    var lastSampleTime: Date? { samples.last?.time }

    /// Live HRV in ms — RMSSD over the BPM-derived instantaneous RR window.
    /// `nil` until a few samples have accrued.
    var rmssdMs: Double? {
        guard samples.count >= 4 else { return nil }
        let rr = samples.map { 60_000.0 / $0.bpm }
        var sumSq = 0.0
        var n = 0
        for (a, b) in zip(rr.dropLast(), rr.dropFirst()) {
            let d = b - a
            sumSq += d * d
            n += 1
        }
        guard n >= 3 else { return nil }
        return (sumSq / Double(n)).squareRoot()
    }
}
