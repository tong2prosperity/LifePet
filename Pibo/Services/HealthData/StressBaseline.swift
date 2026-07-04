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
/// drives the cold-start blend (see `StressScore`): a baseline built from a
/// single busy day is not yet trustworthy, so we lean on absolute thresholds
/// until enough *calendar days* accumulate.
struct StressBaseline: Sendable, Equatable {
    /// Mean of ln(daily median RMSSD) over the historical window.
    var meanLn: Double
    /// Sample SD (n-1) of ln(daily median RMSSD), floored so z never explodes.
    var sdLn: Double
    /// Distinct past days the window covers. Drives cold-start → personal blend.
    var dayCount: Int
    /// exp(meanLn) — the geometric mean, a display-friendly "你的常态 ≈ X ms".
    var geoMean: Double

    /// z-distance of a reading from the personal mean, on the log scale.
    /// Negative = below your normal (more stressed); positive = above (calmer).
    func z(for rmssd: Double) -> Double {
        guard rmssd > 0, sdLn > 0 else { return 0 }
        return (Foundation.log(rmssd) - meanLn) / sdLn
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
    /// Below this many covered days, the baseline is untrustworthy → use
    /// absolute thresholds only.
    static let coldStartDays = 7
    /// At/above this many days, use the personal z-score fully. Between the two
    /// we blend, weighting toward personal as days accumulate.
    static let fullPersonalDays = 14

    /// Continuous 0…1 stress from RMSSD relative to the personal baseline.
    /// Returns `nil` only when there's no usable RMSSD. Graduated:
    /// - `dayCount ≥ fullPersonalDays` → pure personal z-score.
    /// - `coldStartDays ≤ dayCount < fullPersonalDays` → z ⨯ absolute blend.
    /// - otherwise → absolute thresholds (population defaults).
    static func anchor(rmssd: Double?, baseline: StressBaseline?) -> Double? {
        guard let rmssd, rmssd > 0 else { return nil }
        let absolute = absoluteScore(rmssd)
        guard let b = baseline, b.dayCount >= coldStartDays, b.sdLn > 0 else {
            return absolute
        }
        let personal = personalScore(rmssd, baseline: b)
        if b.dayCount >= fullPersonalDays { return personal }
        // Transition: weight toward personal by how far past cold-start we are.
        let w = Double(b.dayCount - coldStartDays) / Double(fullPersonalDays - coldStartDays)
        return clamp(personal * w + absolute * (1 - w))
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
        clamp(0.30 - 0.20 * baseline.z(for: rmssd))
    }

    /// Population-default score before a personal baseline exists. Piecewise
    /// linear on the classic RMSSD thresholds, aligned to the same boundaries:
    /// 50ms→0.30, 30ms→0.50, 20ms→0.70 (higher RMSSD = calmer = lower score).
    static func absoluteScore(_ rmssd: Double) -> Double {
        let pts: [(r: Double, s: Double)] = [(65, 0.10), (50, 0.30), (30, 0.50), (20, 0.70), (12, 0.90)]
        if rmssd >= pts.first!.r { return pts.first!.s }
        if rmssd <= pts.last!.r { return pts.last!.s }
        for i in 0..<(pts.count - 1) where rmssd <= pts[i].r && rmssd >= pts[i + 1].r {
            let t = (pts[i].r - rmssd) / (pts[i].r - pts[i + 1].r)
            return pts[i].s + t * (pts[i + 1].s - pts[i].s)
        }
        return 0.5
    }

    /// Shared four-tier boundaries — the ONE place score → `StressLevel` lives.
    static func tier(for score: Double) -> StressLevel {
        switch score {
        case ..<0.30: return .excellent
        case ..<0.50: return .normal
        case ..<0.70: return .notice
        default:      return .overload
        }
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
