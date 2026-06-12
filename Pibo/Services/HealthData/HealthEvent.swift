import Foundation

/// What `HealthDataService` posts upstream when a metric refreshes.
///
/// All values are *current snapshot* numbers — the service has already done
/// the windowing (today's sum, last night's totals, latest reading). The
/// downstream `PetStateStore` just plugs these into the PRD §3 formulas.
///
/// `Sendable` so we can post events across actor boundaries via `AsyncStream`.
enum HealthEvent: Sendable, Equatable {
    /// Today's cumulative step count (00:00 → now).
    case steps(Int)
    /// Today's cumulative Apple-Exercise minutes.
    case exerciseMinutes(Int)
    /// Today's active-energy burn, kcal.
    case activeEnergy(Double)
    /// Today's stand minutes.
    case standMinutes(Int)
    /// Latest single HR reading, bpm. Used as a stability proxy.
    case heartRate(Double)
    /// Latest HRV (SDNN), milliseconds.
    case hrv(Double)
    /// Latest resting HR, bpm. Slow-changing baseline.
    case restingHR(Double)
    /// Latest blood-oxygen (SpO2) reading as a fraction 0–1 (HK `.percent()`).
    case oxygen(Double)
    /// Last-night sleep totals (the watch's interpretation, not raw stages).
    /// `start` is the earliest `asleep*` sample's startDate in the window —
    /// used by the home screen to label the card "昨 23:30".
    case sleep(total: TimeInterval, deep: TimeInterval, rem: TimeInterval, start: Date?)
    /// Today's mindful-minutes total.
    case mindfulMinutes(Int)
    /// A new workout finished. `kind` is a coarse bucket the home screen uses
    /// to decide whether to auto-tick a matching suggest card. `end` is the
    /// workout's actual completion time — used by the home screen to label
    /// historical replay cards ("昨 22:30") and to decide whether to fire the
    /// "just happened" leading-indicator path (gain + toast) vs. display-only.
    case workoutFinished(kind: WorkoutKind, duration: TimeInterval, kcal: Double?, end: Date)

    enum WorkoutKind: String, Sendable, Codable {
        case run, walk, cycle, hiit, yoga, other
    }
}
