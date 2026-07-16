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
    static let maxAnchorAge: TimeInterval = PiboCoreDerivedStressAdapter.maxAnchorAge

    /// The HR modulation term also expires — a "latest" HR sample that's really a
    /// workout peak from before the wearer went back to rest would otherwise read
    /// as current tension (worst on the pure-HR estimate, where it drives the
    /// whole score). Short window: the watch samples HR every few minutes at rest,
    /// so 20 min covers normal gaps while cutting off a stale post-exercise peak.
    static let maxHRAge: TimeInterval = PiboCoreDerivedStressAdapter.maxHRAge

    static func compute(rmssd: Double?,
                        baseline: StressBaseline?,
                        restingHR: Double,
                        currentHR: Double,
                        currentHRAt: Date?,
                        rmssdAt: Date?,
                        isMoving: Bool,
                        now: Date = Date()) -> DerivedStress? {
        PiboCoreDerivedStressAdapter.compute(
            rmssd: rmssd,
            baseline: baseline,
            restingHR: restingHR,
            currentHR: currentHR,
            currentHRAt: currentHRAt,
            rmssdAt: rmssdAt,
            isMoving: isMoving,
            now: now
        )
    }
}
