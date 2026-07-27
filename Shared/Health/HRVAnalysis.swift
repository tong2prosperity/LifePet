import Foundation

/// RMSSD from beat-to-beat RR intervals — the shared, platform-free core of
/// Pibo's own HRV, used by both the phone's periodic stress reading
/// (`HeartbeatSeriesReader`) and the watch's post-session breathing report
/// (`CRCHeartbeatSeriesReader`).
///
/// It lives here rather than in either target because both compute the *same
/// measurement from the same kind of data* — a complete `HKHeartbeatSeriesSample`
/// — and they must not disagree: a breathing session and the next background
/// reading would otherwise report two different HRVs for the same wearer minutes
/// apart. The HealthKit enumeration stays per-target (this file is Foundation-only
/// so the widget extension doesn't drag in HealthKit), but the arithmetic and
/// every threshold live in exactly one place.
///
/// **Not in `pibo-core`, deliberately.** HarmonyOS has no raw beat-series data
/// type — Health Service Kit hands over an already-computed HRV value, which it
/// defines as RMSSD. So there is no second platform to share RR→RMSSD with; Core
/// takes `rmssd` as an input and that boundary is correct. Same reasoning as
/// logging: platform data acquisition stays native.
///
/// **RMSSD ≠ SDNN.** Apple's `heartRateVariabilitySDNN` measures the *total*
/// variability of a window (slow components included); RMSSD only sees
/// beat-to-beat. SDNN therefore reads systematically higher, and the gap widens
/// as HRV rises — comparing the two numbers directly is a category error.
enum HRVAnalysis {
    /// One window's HRV, plus the numbers needed to judge whether to trust it.
    struct Measurement: Sendable, Equatable {
        /// Root mean square of successive RR differences, ms. 0 when no
        /// difference survived artifact rejection.
        var rmssd: Double
        /// Mean RR over the window, ms. RMSSD is uninterpretable without it.
        var meanRR: Double
        /// Total RR intervals across all segments.
        var rrCount: Int
        /// RR intervals flagged as artifacts.
        var flagged: Int
        /// Successive differences that actually entered the sum.
        var diffs: Int
    }

    /// RMSSD over the artifact-free (**NN**) portion of a gap-split RR series.
    ///
    /// The standard definition is `sqrt(1/(N-1) · Σ (NN[i+1] − NN[i])²)` over
    /// *normal-to-normal* intervals — i.e. after ectopic/misdetected beats have
    /// been removed. Everything interesting is in how you decide what's an
    /// artifact.
    ///
    /// **The rule this replaced was self-referential**: it dropped a successive
    /// difference whenever the difference itself exceeded 20% of the preceding RR.
    /// That filters on the very quantity being measured, so it can only bias RMSSD
    /// downward, and it bites harder the higher the true HRV (the threshold is a
    /// shrinking multiple of the signal). It was also asymmetric — with `a` as the
    /// denominator, an 800→1000 ms swing was rejected while 1000→800 was kept, so
    /// half of every large oscillation was deleted — and it scaled with heart rate,
    /// tightening exactly when RR shortens.
    ///
    /// The rule here instead asks whether **an RR interval is an outlier against
    /// its own neighbourhood**: flag it when it deviates from the median of the
    /// surrounding intervals by more than a fixed absolute threshold (the
    /// Kubios-style criterion; 250 ms is its recommended default level). A smooth
    /// respiratory oscillation tracks its local median and survives intact; a
    /// premature beat or a dropped detection does not. Differences that *touch* a
    /// flagged interval are then excluded from the sum — deleting the two bad
    /// differences rather than interpolating, since interpolation would replace
    /// them with artificially smooth values and pull RMSSD down again.
    ///
    /// Input is **segments**, not one flat array: a run has to be cut wherever the
    /// recording lost beats, because the intervals on either side of a hole are not
    /// temporally adjacent and differencing across them is meaningless.
    ///
    /// This applies **no trust gates** — see `isTrustworthy` / `analyze`. Callers
    /// that want to report on a window they're about to reject (the diagnostic log)
    /// need its numbers either way.
    static func measure(_ segments: [[Double]]) -> Measurement {
        var sumSq = 0.0
        var diffs = 0
        var rrCount = 0
        var flaggedCount = 0
        var sumRR = 0.0

        for rr in segments {
            rrCount += rr.count
            sumRR += rr.reduce(0, +)
            let flags = artifactFlags(rr)
            flaggedCount += flags.lazy.filter { $0 }.count
            guard rr.count >= 2 else { continue }
            for i in 0..<(rr.count - 1) where !flags[i] && !flags[i + 1] {
                let d = rr[i + 1] - rr[i]
                sumSq += d * d
                diffs += 1
            }
        }

        return Measurement(rmssd: diffs > 0 ? (sumSq / Double(diffs)).squareRoot() : 0,
                           meanRR: rrCount > 0 ? sumRR / Double(rrCount) : 0,
                           rrCount: rrCount,
                           flagged: flaggedCount,
                           diffs: diffs)
    }

    /// Whether a measurement describes its window well enough to classify.
    ///
    /// Two gates. **Artifact budget** — too much of the window was artifact and the
    /// survivors aren't a fair sample of it. Short recordings are conventionally
    /// discarded past ~5% corrected, and here the discarded beats are exactly the
    /// extreme ones, so a heavily-filtered window doesn't just read noisy, it reads
    /// low. The absolute floor inside `artifactBudget` matters: a single premature
    /// beat costs about four flags, not one — the short interval, the compensatory
    /// long one, and the two neighbours whose local median they drag far enough to
    /// trip. On a ~60-beat window a bare 5% sits below that, so one ectopic would
    /// discard the whole reading; readings arrive every 2–5h and occasional
    /// ectopics are common in healthy wearers, so that would quietly starve the
    /// feature. Two such events still fail, which is the intent.
    ///
    /// **Difference count** — enough genuinely-adjacent pairs must remain to
    /// average over. A ~1-min series yields dozens; a handful would put the whole
    /// reading at the mercy of one or two beats.
    static func isTrustworthy(_ measurement: Measurement) -> Bool {
        measurement.rrCount > 0
            && measurement.flagged <= artifactBudget(measurement.rrCount)
            && measurement.diffs >= minValidDiffs
    }

    /// `measure` plus the trust gates — `nil` when the window can't be classified.
    static func analyze(_ segments: [[Double]]) -> Measurement? {
        let measurement = measure(segments)
        return isTrustworthy(measurement) ? measurement : nil
    }

    /// Convenience for a single contiguous run — tests, and any caller holding a
    /// plain RR array with no gap information.
    static func rmssd(_ rrMs: [Double]) -> Double? { analyze([rrMs])?.rmssd }

    // MARK: - Artifact detection

    /// Per-interval artifact verdicts for one contiguous run.
    ///
    /// An interval is an artifact when it's physiologically impossible, or when it
    /// sits further than `artifactThresholdMs` from the median of its immediate
    /// neighbours (±2, itself excluded — including itself would let a bad beat
    /// drag its own reference toward it). Comparing against a *local median*
    /// rather than the single preceding interval is what lets a genuine
    /// respiratory oscillation through: the median rides the oscillation, so only
    /// a beat that breaks the local pattern is flagged.
    ///
    /// **±2 is an upper bound, not a tuning knob.** The window has to stay
    /// shorter than the respiratory period (~4–7 beats): widen it to ±3 and the
    /// median stops tracking the oscillation and settles near its mean instead, at
    /// which point every peak and trough reads as an outlier. Measured on a clean
    /// 48-interval RSA fixture, ±2 flags nothing and ±3 flags 29.
    private static func artifactFlags(_ rr: [Double]) -> [Bool] {
        rr.indices.map { i in
            guard plausibleRR(rr[i]) else { return true }
            let low = max(0, i - 2)
            let high = min(rr.count - 1, i + 2)
            let neighbours = (low...high).filter { $0 != i }.map { rr[$0] }
            guard let m = median(neighbours) else { return false }
            return abs(rr[i] - m) > artifactThresholdMs
        }
    }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    // MARK: - Thresholds

    /// How far an RR interval may sit from its local median before it counts as an
    /// artifact. **Absolute, not a fraction of RR** — a relative threshold shrinks
    /// with heart rate and starts deleting real variability exactly when RR gets
    /// short. 250 ms is the Kubios "medium" level, its recommended default.
    private static let artifactThresholdMs = 250.0

    /// Above this share of flagged intervals the whole window is discarded, with
    /// an absolute floor so one ectopic beat never costs a whole reading.
    private static func artifactBudget(_ rrCount: Int) -> Int {
        max(minArtifactAllowance, Int(Double(rrCount) * maxArtifactFraction))
    }
    private static let maxArtifactFraction = 0.05
    private static let minArtifactAllowance = 4

    /// Minimum artifact-free successive differences for a trustworthy RMSSD.
    /// A 60 s window at 40 bpm still clears this.
    private static let minValidDiffs = 20

    /// Physiologically plausible RR interval in ms: ~30–200 bpm. Anything outside
    /// is a dropped/spurious beat, not a real heartbeat interval.
    private static func plausibleRR(_ ms: Double) -> Bool { ms >= 300 && ms <= 2000 }
}
