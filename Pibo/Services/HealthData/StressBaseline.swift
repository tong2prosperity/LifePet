import Foundation

/// The wearer's personal HRV baseline — the statistical description of "your own
/// normal", against which a fresh RMSSD reading is judged.
///
/// HRV (RMSSD) is right-skewed (log-normal), so the baseline is built on
/// **ln(RMSSD)**: `meanLn` / `sdLn` are the mean & sample SD of the log of each
/// past day's median resting reading (see `StressBaselineStore`). A reading is
/// then scored by its **z-distance** from that personal mean — far more faithful
/// than a raw ratio, because `sdLn` encodes *this person's* day-to-day spread
/// (some people swing ±5ms, some ±20ms).
///
/// `dayCount` is the number of distinct past days the baseline covers — it
/// drives cold start (see `StressScore`): a baseline built from a single busy
/// day is not trustworthy, so stress remains unclassified until seven eligible
/// *calendar days* accumulate.
struct StressBaseline: Sendable, Equatable {
    /// Mean of ln(daily median RMSSD) over the historical window.
    var meanLn: Double
    /// Sample SD (n-1) of ln(daily median RMSSD), floored so z never explodes.
    var sdLn: Double
    /// Distinct past days the window covers. Drives cold-start readiness.
    var dayCount: Int
    /// exp(meanLn) — the geometric mean, a display-friendly "你的常态 ≈ X ms".
    var geoMean: Double

    /// z-distance of a reading from the personal mean, on the log scale.
    /// Negative = below your normal (more stressed); positive = above (calmer).
    func z(for rmssd: Double) -> Double {
        PiboCoreStressAdapter.baselineZ(rmssd: rmssd, baseline: self)
    }
}

/// The single source of truth turning a raw RMSSD + personal baseline into a
/// continuous 0…1 stress score. **Both** the tier classifier (`StressModel`)
/// and the display-layer derived value (`DerivedStress`) call `anchor(...)`, so
/// the two can never drift apart (the earlier code duplicated the bucket logic
/// in three places).
///
/// Score convention: 0 = calm, 1 = tense. Tier boundaries (0.30 / 0.50 / 0.70)
/// are shared via `tier(for:)`.
enum StressScore {
    /// Below this many covered days, HRV is visible but stress is unclassified.
    static let coldStartDays = PiboCoreStressAdapter.coldStartDays
    /// Compatibility alias. Personal scoring becomes fully available on day 7.
    static let fullPersonalDays = PiboCoreStressAdapter.fullPersonalDays

    /// Continuous 0…1 stress from RMSSD relative to the personal baseline.
    /// Returns `nil` for invalid RMSSD or before the seven-day personal baseline
    /// is ready; otherwise returns the pure personal z-score mapping.
    static func anchor(rmssd: Double?, baseline: StressBaseline?) -> Double? {
        PiboCoreStressAdapter.anchor(rmssd: rmssd, baseline: baseline)
    }

    /// Personal z-score → 0…1 score. Linear map aligned so the z tier edges land
    /// on the shared score boundaries: z=0→0.30, z=−1.0→0.50, z=−2.0→0.70.
    ///
    /// The band was deliberately widened (was z=−0.5/−1.5 for the notice/overload
    /// edges): judging against one's *own* mean, ~half of readings sit below it by
    /// construction, so the old edges flagged ~31% of perfectly normal readings as
    /// 偏高. Now 注意 needs today's RMSSD >1 SD below your personal normal and 超载
    /// >2 SD — genuinely unusual dips (≈16% notice+overload, ≈2% overload), so the
    /// push actually means something.
    static func personalScore(_ rmssd: Double, baseline: StressBaseline) -> Double {
        PiboCoreStressAdapter.personalScore(rmssd: rmssd, baseline: baseline)
    }

    /// Legacy population reference retained for diagnostics/compatibility. It is
    /// not used to classify users before a personal baseline exists. Piecewise
    /// linear on the classic RMSSD thresholds, aligned to the same boundaries:
    /// 50ms→0.30, 30ms→0.50, 20ms→0.70 (higher RMSSD = calmer = lower score).
    static func absoluteScore(_ rmssd: Double) -> Double {
        PiboCoreStressAdapter.absoluteScore(rmssd: rmssd)
    }

    /// Shared four-tier boundaries — the ONE place score → `StressLevel` lives.
    static func tier(for score: Double) -> StressLevel {
        PiboCoreStressAdapter.tier(for: score)
    }

    /// The 0…1 stress score projected onto the widget's 0–100 心情 bar.
    ///
    /// A presentation mapping, not scoring — it adds no thresholds of its own,
    /// it just mirrors the anchor so "calm" reads high. It lives here rather
    /// than in `PetStateStore` so 心情 and `tier(for:)` can be read side by side:
    /// they must never contradict each other, and the boundaries line up on
    /// purpose (score 0.70, the 超载 edge, lands on 心情 30, the `derivePetState`
    /// 生病 edge — the worst stress tier is exactly when the widget's Pibo looks
    /// unwell).
    static func moodPoints(forAnchor anchor: Double) -> Int {
        Int(((1 - clamp(anchor)) * 100).rounded())
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
