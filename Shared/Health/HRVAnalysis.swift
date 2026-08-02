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
        /// RR intervals artifact detection could actually reach a verdict on.
        /// Below `rrCount` by up to four per contiguous run — see
        /// `localMedianDeviations`. A window chopped into runs too short to
        /// inspect is one nobody checked, which `isTrustworthy` refuses.
        var judged: Int
        /// The artifact threshold this window derived for itself, ms. Diagnostic:
        /// it says whether the rule adapted to a quiet wearer or saturated at the
        /// ceiling, which is the first thing to look at when a reading disagrees
        /// with a reference device.
        var artifactThresholdMs: Double
    }

    /// RMSSD over the artifact-free (**NN**) portion of a gap-split RR series.
    ///
    /// The standard definition is `sqrt(1/(N-1) · Σ (NN[i+1] − NN[i])²)` over
    /// *normal-to-normal* intervals — i.e. after ectopic/misdetected beats have
    /// been removed. Everything interesting is in how you decide what's an
    /// artifact.
    ///
    /// This rule has now failed in **both** directions, which is why the threshold
    /// is neither a fraction of RR nor a constant.
    ///
    /// The original was self-referential: it dropped a successive difference
    /// whenever the difference itself exceeded 20% of the preceding RR. That
    /// filters on the very quantity being measured, so it could only bias RMSSD
    /// downward, and it bit harder the higher the true HRV (the threshold was a
    /// shrinking multiple of the signal). It was also asymmetric — with `a` as the
    /// denominator, an 800→1000 ms swing was rejected while 1000→800 was kept, so
    /// half of every large oscillation was deleted — and it scaled with heart rate,
    /// tightening exactly when RR shortens.
    ///
    /// Its replacement, a flat 250 ms, fixed the high end and broke the low one:
    /// sized against a normal HRV, it is far too loose for a quiet wearer, and a
    /// single mis-detected beat survives to dominate a root-mean-square built out
    /// of ~17 ms differences. See `artifactThreshold` for the numbers.
    ///
    /// The rule here asks whether **an RR interval is an outlier against its own
    /// neighbourhood**: flag it when it deviates from the median of the
    /// surrounding intervals by more than `artifactThreshold` — a threshold the
    /// window derives from its own dispersion (see there). A smooth respiratory
    /// oscillation tracks its local median and survives intact; a premature beat
    /// or a dropped detection does not. Differences that *touch* a flagged
    /// interval are then excluded from the sum — deleting the two bad differences
    /// rather than interpolating, since interpolation would replace them with
    /// artificially smooth values and pull RMSSD down again.

    ///
    /// Input is **segments**, not one flat array: a run has to be cut wherever the
    /// recording lost beats, because the intervals on either side of a hole are not
    /// temporally adjacent and differencing across them is meaningless.
    ///
    /// This applies **no trust gates** — see `isTrustworthy` / `analyze`. Callers
    /// that want to report on a window they're about to reject (the diagnostic log)
    /// need its numbers either way.
    static func measure(_ segments: [[Double]]) -> Measurement {
        // Deviations first, threshold from all of them pooled, flags last. The
        // threshold is a property of the *window*, not of a run: a short segment
        // on its own carries too few intervals to estimate a dispersion from.
        let deviations = segments.map(localMedianDeviations)
        let threshold = artifactThreshold(segments: segments, deviations: deviations)

        var sumSq = 0.0
        var diffs = 0
        var rrCount = 0
        var flaggedCount = 0
        var judgedCount = 0
        var sumRR = 0.0

        for (rr, deviation) in zip(segments, deviations) {
            rrCount += rr.count
            sumRR += rr.reduce(0, +)
            judgedCount += rr.indices.lazy.filter {
                deviation[$0] != nil || !plausibleRR(rr[$0])
            }.count
            let flags = rr.indices.map {
                isArtifact(rr: rr[$0], deviation: deviation[$0], threshold: threshold)
            }
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
                           diffs: diffs,
                           judged: judgedCount,
                           artifactThresholdMs: threshold)
    }

    /// Whether a measurement describes its window well enough to classify.
    ///
    /// Three gates. **Artifact budget** — too much of the window was artifact and
    /// the survivors aren't a fair sample of it. Short recordings are conventionally
    /// discarded past ~5% corrected, and here the discarded beats are exactly the
    /// extreme ones, so a heavily-filtered window doesn't just read noisy, it reads
    /// low. The absolute floor inside `artifactBudget` matters, because a single
    /// event can cost several flags: a premature beat writes a short interval *and*
    /// a compensatory long one, and on a strongly oscillating window it drags the
    /// neighbours' local medians far enough to trip them too — up to four for one
    /// ectopic. On a ~60-beat window a bare 5% sits below that, so one ectopic would
    /// discard the whole reading; readings arrive every 2–5h and occasional
    /// ectopics are common in healthy wearers, so that would quietly starve the
    /// feature. Four *isolated* mild artifacts also fit, and that is fine — they are
    /// removed from the sum, so the window still reports an honest number.
    ///
    /// **Difference count** — enough genuinely-adjacent pairs must remain to
    /// average over. A ~1-min series yields dozens; a handful would put the whole
    /// reading at the mercy of one or two beats.
    ///
    /// **Inspected share** — artifact detection needs a centred neighbourhood, so
    /// it reaches no verdict on the two intervals at each end of a run. One long
    /// run barely notices; a window the watch chopped into 4-beat fragments is
    /// *entirely* ends, and would otherwise sail through with zero flags precisely
    /// because nothing in it could be checked. Requiring most of the window to have
    /// been inspected turns that silence back into a rejection.
    ///
    /// **Known limit.** All of this rests on an artifact being an outlier against
    /// its neighbours. Past roughly a third of the beats corrupted, the
    /// neighbourhoods are corrupted too, deviations stop looking exceptional, and a
    /// wrecked window can report a plausible-looking number with nothing flagged.
    /// That is the breakdown point of any local-outlier rule (it predates the
    /// adaptive threshold — a fixed one fails there identically); separating signal
    /// from noise at that contamination needs full beat classification, not a
    /// tighter threshold.
    static func isTrustworthy(_ measurement: Measurement) -> Bool {
        measurement.rrCount > 0
            && measurement.flagged <= artifactBudget(measurement.rrCount)
            && measurement.diffs >= minValidDiffs
            && Double(measurement.judged) >= minInspectedFraction * Double(measurement.rrCount)
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

    /// Whether one interval is an artifact: physiologically impossible, or too far
    /// from the median of its own neighbourhood. A `nil` deviation means the run
    /// was too short to have a neighbourhood — no evidence either way, so no flag.
    private static func isArtifact(rr: Double, deviation: Double?, threshold: Double) -> Bool {
        guard plausibleRR(rr) else { return true }
        guard let deviation else { return false }
        return abs(deviation) > threshold
    }

    /// Each interval's signed distance from the median of its immediate
    /// neighbours (±2, itself excluded — including itself would let a bad beat
    /// drag its own reference toward it). `nil` where no such verdict is possible.
    ///
    /// Comparing against a *local median* rather than the single preceding
    /// interval is what lets a genuine respiratory oscillation through: the median
    /// rides the oscillation, so only a beat that breaks the local pattern stands
    /// out.
    ///
    /// **±2 is an upper bound, not a tuning knob.** The window has to stay
    /// shorter than the respiratory period (~4–7 beats): widen it to ±3 and the
    /// median stops tracking the oscillation and settles near its mean instead, at
    /// which point every peak and trough reads as an outlier. Measured on a clean
    /// 48-interval RSA fixture, ±2 flags nothing and ±3 flags 29.
    ///
    /// **The neighbourhood must be centred**, so the first and last two intervals
    /// of a run get no verdict at all. A one-sided reference is a *biased*
    /// predictor: in the interior the median of `i±2` brackets `i`, so the
    /// deviation measures the curve's local curvature and stays small through a
    /// steep ramp; at the edge every neighbour lies on one side, and the same
    /// arithmetic measures its **slope** instead — `1.5 ×` the per-beat change.
    /// During slow deep breathing (the CRC trainer's whole purpose) RR can move
    /// ~60 ms per beat, so the two end intervals of every run would deviate ~90 ms
    /// with nothing wrong with them. The old fixed 250 ms threshold hid that; an
    /// adaptive one does not, and a sweep over breathing periods 6–24 beats found
    /// clean windows losing intervals to it. Four unjudged intervals per run is
    /// the cheaper error — and `judged` reports the cost so `isTrustworthy` can
    /// refuse a window that is nothing *but* edges.
    private static func localMedianDeviations(_ rr: [Double]) -> [Double?] {
        rr.indices.map { i in
            guard i >= 2, i <= rr.count - 3 else { return nil }
            let neighbours = (i - 2...i + 2).filter { $0 != i }.map { rr[$0] }
            guard let m = median(neighbours) else { return nil }
            return rr[i] - m
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
    /// artifact — **derived from the window's own dispersion**, then clamped.
    ///
    /// A constant threshold fails for the same structural reason the original
    /// `0.2 · RR` rule did, just at the other end of the range. 250 ms (Kubios'
    /// "medium" level) is sized against a normal HRV; a resting wearer at
    /// RMSSD ≈ 17 ms has real beat-to-beat differences of ~17 ms, so a mis-detected
    /// beat landing 150 ms off its neighbours sails straight through — and because
    /// RMSSD is a *root-mean-square*, that lone survivor dominates the sum. Two
    /// differences of 150 ms among sixty of 17 ms report ≈ 31 ms: one bad beat
    /// nearly doubles the reading. Observed in the field, against a reference
    /// device reading 17 ms on the same wearer at the same minute.
    ///
    /// So scale the threshold to the wearer: `k · σ̂`, where σ̂ = 1.4826 · MAD of
    /// the local-median deviations. Being **robust** is what makes it safe to
    /// derive this from the measured quantity — a median absolute deviation is
    /// unmoved by the very outliers being hunted (five planted artifacts move it by
    /// single-digit ms), so the threshold tracks the *bulk* of the distribution and
    /// cuts only its far tail. At `k = 5` that lands near 4 × RMSSD, inside the
    /// range Kubios' own adaptive criterion uses (its `5.2 · QD(dRR)` ≈ 3.5 σ).
    ///
    /// The clamp bounds both failure modes. The **ceiling** keeps the old flat
    /// 250 ms as an upper limit, so a high-HRV window saturates it and behaves
    /// exactly as before — this change only ever tightens. The **floor** stops an
    /// unusually rigid series from deriving a threshold so tight that ordinary
    /// variation reads as artifact.
    private static func artifactThreshold(segments: [[Double]],
                                          deviations: [[Double?]]) -> Double {
        var magnitudes: [Double] = []
        for (rr, deviation) in zip(segments, deviations) {
            // Implausible intervals are artifacts on their own evidence; letting
            // them into the dispersion estimate would widen the threshold that is
            // supposed to catch their milder cousins.
            for i in rr.indices where plausibleRR(rr[i]) {
                if let d = deviation[i] { magnitudes.append(abs(d)) }
            }
        }
        guard let mad = median(magnitudes) else { return artifactThresholdCeilingMs }
        let sigma = 1.4826 * mad
        return min(max(artifactSigmaMultiple * sigma, artifactThresholdFloorMs),
                   artifactThresholdCeilingMs)
    }

    /// How many robust standard deviations of slack an interval gets. Wide on
    /// purpose: the job is to remove beats that are not heartbeats, not to trim
    /// the tail of a real distribution.
    private static let artifactSigmaMultiple = 5.0
    /// Kubios' "medium" level, and the rule's previous fixed value.
    private static let artifactThresholdCeilingMs = 250.0
    private static let artifactThresholdFloorMs = 50.0

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

    /// Minimum share of the window artifact detection must have reached a verdict
    /// on. Four intervals per run go uninspected, so this is really a floor on
    /// average run length: at 0.6 a window has to average ~10-beat runs, which is
    /// the shortest stretch worth calling a heart rhythm anyway.
    private static let minInspectedFraction = 0.6

    /// Physiologically plausible RR interval in ms: ~30–200 bpm. Anything outside
    /// is a dropped/spurious beat, not a real heartbeat interval.
    private static func plausibleRR(_ ms: Double) -> Bool { ms >= 300 && ms <= 2000 }
}
