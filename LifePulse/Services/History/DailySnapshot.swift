import Foundation

/// One day's "what did Pibo make of this pet's life" record. Persisted by
/// `DailySnapshotStore`. One row per `(petId, date)`.
///
/// **What it stores** — the Pibo-derived view of a day:
/// - The three end-of-day stats (`vitality / energy / mood`) and the resolved
///   `stateTag` — these are what the home screen would render at that point.
/// - The raw HK aggregates that fed the formulas — `steps`, `sleepTotal`,
///   `hrv`, etc. Kept so the HRV 7-day baseline + death-trigger judgments
///   (PRD §6) can recompute against the same numbers the user actually saw.
/// - The kinds of step cards the user / sensor closed today — drives "首次
///   EXCITED" / "第一次冥想" moment detection in the catalog.
///
/// **What it does NOT store** — by design:
/// - HK raw samples (HK already keeps those; we'd duplicate).
/// - Per-event timestamps (this is a *daily* record, not an event log).
/// - Pet metadata (name, deathType, deathDate) — that's `PetIdentityStore`'s
///   job (and the future per-pet catalog store's).
/// `nonisolated` overrides the project's default `@MainActor` so the
/// `Codable` conformances can be exercised from `DailySnapshotStore` (an
/// actor) without crossing isolation. Pure value type with no shared state,
/// safe to construct / encode anywhere.
nonisolated struct DailySnapshot: Codable, Equatable, Sendable {
    let petId: UUID
    /// Always `Calendar.current.startOfDay(for:)`. Used as the file-name key.
    let date: Date

    // — Final stats at end of day (PRD §3 outputs) —
    let vitality: Int
    let energy: Int
    let mood: Int
    /// `PetState.tag` — `"NORMAL"`, `"EXCITED"`, etc. String rather than the
    /// enum so storage doesn't break if `PetState` cases shift. Round-trip
    /// via `PetState.init(tag:)`.
    let stateTag: String

    // — Raw HK aggregates (PRD §3 inputs) —
    let steps: Int
    let exerciseMinutes: Int
    let activeEnergy: Double
    let standMinutes: Int
    let hrv: Double
    let restingHR: Double
    let sleepTotal: TimeInterval
    let sleepDeep: TimeInterval
    let sleepREM: TimeInterval
    let mindfulMinutes: Int

    /// `StepKind.rawValue` for every `已完成` card on the home screen at write
    /// time. Order is presentation order (most recently completed first, per
    /// `PetStateStore` insertion). Used by the catalog moment detector.
    let completedStepKinds: [String]

    /// Wall-clock of the most recent write. Lets readers tell "today's
    /// snapshot is from 30 min ago" vs "from this morning."
    let updatedAt: Date
}
