import Foundation

/// Latest known reading per metric. Pet-state derivation and daily history
/// both consume the same in-memory value so they cannot drift onto separate
/// HealthKit representations.
struct RawMetrics {
    var steps: Int = 0
    var exerciseMinutes: Int = 0
    var activeEnergy: Double = 0
    var standMinutes: Int = 0
    var heartRate: Double = 0
    /// When `heartRate` was measured (sample time, not ingest). Lets the derived
    /// stress card drop a stale HR (e.g. a workout peak lingering as the latest
    /// sample) instead of reading it as current tension.
    var heartRateAt: Date? = nil
    /// Apple's SDNN. Kept because HealthKit gives it for free and the history
    /// record persists it, but state derivation uses `rmssd` below instead.
    var hrv: Double = 0
    /// Latest RMSSD (ms) computed from the heartbeat series.
    var rmssd: Double? = nil
    /// Measurement time for the current RMSSD value.
    var rmssdAt: Date? = nil
    /// Whether corrected NN evidence and context permit stress interpretation.
    var rmssdInterpretationEligible = false
    var restingHR: Double = 0
    var sleepTotal: TimeInterval = 0
    var sleepDeep: TimeInterval = 0
    var sleepREM: TimeInterval = 0
    /// Earliest asleep-sample start in the latest sleep snapshot.
    var sleepStart: Date? = nil
    var mindfulMinutes: Int = 0
    /// Latest blood-oxygen (SpO2) reading as a fraction 0–1.
    var oxygen: Double = 0
}

/// Projects Home's current value state into the stable daily-history payload.
/// Persistence policy and dispatch remain owned by `PetStateStore`.
enum PetStateDailySnapshotFactory {
    static func make(
        petId: UUID,
        date: Date,
        stats: [Stat],
        state: PetState,
        raw: RawMetrics,
        steps: [StepItem],
        calendar: Calendar = .current,
        now: () -> Date = Date.init
    ) -> DailySnapshot {
        // Keep evaluation order aligned with the former inline projection:
        // normalize the day first and capture the write time last.
        let day = calendar.startOfDay(for: date)
        let vitality = stats.first(where: { $0.kind == .vitality })?.value ?? 0
        let energy = stats.first(where: { $0.kind == .energy })?.value ?? 0
        let mood = stats.first(where: { $0.kind == .mood })?.value ?? 0
        let completedStepKinds = steps
            .filter { $0.status == .done }
            .map { $0.kind.rawValue }

        return DailySnapshot(
            petId: petId,
            date: day,
            vitality: vitality,
            energy: energy,
            mood: mood,
            stateTag: state.tag,
            steps: raw.steps,
            exerciseMinutes: raw.exerciseMinutes,
            activeEnergy: raw.activeEnergy,
            standMinutes: raw.standMinutes,
            hrv: raw.hrv,
            restingHR: raw.restingHR,
            sleepTotal: raw.sleepTotal,
            sleepDeep: raw.sleepDeep,
            sleepREM: raw.sleepREM,
            mindfulMinutes: raw.mindfulMinutes,
            completedStepKinds: completedStepKinds,
            updatedAt: now()
        )
    }
}
