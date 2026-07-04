import Foundation

/// A **display-only** stress read that refreshes far more often than the raw
/// HRV cadence. StressWatch-style: the true physiological anchor is the sparse
/// RMSSD (measured every 2–5h when the watch happens to sample HRV), but between
/// those measurements we modulate it with the **per-minute heart rate**'s
/// elevation over resting HR — a signal that updates every time the HR observer
/// fires. So the card can move minute-to-minute without ever pretending we
/// re-measured HRV.
///
/// Deliberately **not** wired to notifications: HR elevation can be exercise,
/// not stress, so pushes stay on the real RMSSD tier (`StressModel`). This is
/// purely the "看起来在实时更新" surface.
struct DerivedStress: Sendable, Equatable {
    /// 0 (calm) … 1 (tense).
    var score: Double
    /// The four-tier bucket the score falls in.
    var level: StressLevel
    /// Minutes since the RMSSD anchor was measured — `nil` when there's no HRV
    /// yet (a pure HR estimate). Lets the UI say "测于 N 分钟前".
    var hrvAgeMinutes: Int?
    /// True when there's no HRV anchor at all and the score is a coarse
    /// HR-only guess (lower confidence — the UI should say so).
    var isEstimated: Bool

    /// 0–100 for display ("压力指数").
    var index: Int { Int((score * 100).rounded()) }
}

enum DerivedStressModel {
    /// Blend the sparse HRV anchor with the live HR-over-resting signal.
    /// Returns `nil` only when neither input is usable (no HRV, no HR) — the
    /// card then shows nothing.
    ///
    /// - `isMoving`: when the user is active/working out, HR elevation is
    ///   exercise not stress, so the HR term is dropped and we fall back to the
    ///   HRV anchor alone (or nothing).
    ///
    /// The HRV anchor **expires**: `raw.rmssd` is never cleared, so without a
    /// cutoff a reading from days ago would keep anchoring 60% of a card that
    /// claims to be live. Past `maxAnchorAge` (well beyond the normal 2–5h HRV
    /// cadence) we drop the anchor and fall back to the HR-only estimate, which
    /// the card honestly labels as such.
    static let maxAnchorAge: TimeInterval = 6 * 60 * 60

    /// The HR modulation term also expires — a "latest" HR sample that's really a
    /// workout peak from before the wearer went back to rest would otherwise read
    /// as current tension (worst on the pure-HR estimate, where it drives the
    /// whole score). Short window: the watch samples HR every few minutes at rest,
    /// so 20 min covers normal gaps while cutting off a stale post-exercise peak.
    static let maxHRAge: TimeInterval = 20 * 60

    static func compute(rmssd: Double?,
                        baseline: StressBaseline?,
                        restingHR: Double,
                        currentHR: Double,
                        currentHRAt: Date?,
                        rmssdAt: Date?,
                        isMoving: Bool,
                        now: Date = Date()) -> DerivedStress? {
        // Only trust the anchor while it's still fresh.
        let anchorFresh = rmssdAt.map { now.timeIntervalSince($0) <= maxAnchorAge } ?? false
        let anchor = anchorFresh ? StressScore.anchor(rmssd: rmssd, baseline: baseline) : nil
        // Drop the HR term when moving (exercise ≠ stress) or when the HR reading
        // is stale (a lingering workout peak).
        let hrFresh = currentHRAt.map { now.timeIntervalSince($0) <= maxHRAge } ?? false
        let hrTerm = (isMoving || !hrFresh) ? nil : hrElevation(currentHR: currentHR, restingHR: restingHR)

        let score: Double
        let estimated: Bool
        switch (anchor, hrTerm) {
        case let (a?, h?):  score = 0.6 * a + 0.4 * h; estimated = false
        case let (a?, nil): score = a;                 estimated = false   // moving / no HR
        case let (nil, h?): score = h;                 estimated = true    // HR-only guess
        case (nil, nil):    return nil
        }

        let clamped = clamp(score)
        let age = (anchor != nil) ? rmssdAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) } : nil
        return DerivedStress(score: clamped,
                             level: StressScore.tier(for: clamped),
                             hrvAgeMinutes: age,
                             isEstimated: estimated)
    }

    /// HR elevation over resting → 0 … 1. `+60%` over resting reads as full
    /// tension. `nil` when either HR is unusable.
    private static func hrElevation(currentHR: Double, restingHR: Double) -> Double? {
        guard restingHR > 0, currentHR > 0 else { return nil }
        return clamp((currentHR - restingHR) / restingHR / 0.6)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
