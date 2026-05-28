import Foundation

/// Maps the active pet's `PetState` to a `SpriteSequence` for the home stage.
///
/// PRD priority states (sick / sleeping / tired / excited / blissful) keep
/// their direct mapping — those are *concrete* signals from the stat machine
/// and shouldn't be overridden by ambient context.
///
/// `.normal` is the "ambient" state and gets contextual treatment so the pet
/// mirrors what the user is doing instead of always lying:
///   1. **Recently exercised** (workout ended within `recentWorkoutWindow`)
///      → `blobRun`. Strong signal — wins over time-of-day.
///   2. **Daytime** (`now` inside `daytimeHours`) → `blobWalk`. The pet is
///      "out and about" alongside the user during waking hours.
///   3. **Nighttime** → `blobLying`. The pet rests when the user normally
///      would.
///
/// We have only 4 idle anims (lying / walk / run / sleep) for 6 PRD states.
/// The two gaps (`.sick` / `.blissful`) reuse the closest idle for now —
/// when the designer ships specific frames, just point the cases at new
/// sequences.
enum SpriteCatalog {
    /// "刚刚运动过" window. End-of-workout within this many seconds of `now`
    /// counts as "fresh enough to still be in run mode."
    static let recentWorkoutWindow: TimeInterval = 30 * 60

    /// Hour range treated as daytime: `[start, end)`. 9:00–24:00 mirrors the
    /// product spec — pet stays in walk during the user's awake hours and
    /// switches to lying overnight.
    static let daytimeHours: Range<Int> = 9 ..< 24

    static func idle(
        for state: PetState,
        lastWorkoutAt: Date? = nil,
        now: Date = Date()
    ) -> SpriteSequence {
        switch state {
        case .normal:
            if let last = lastWorkoutAt, now.timeIntervalSince(last) < recentWorkoutWindow {
                return .blobRun
            }
            let hour = Calendar.current.component(.hour, from: now)
            return daytimeHours.contains(hour) ? .blobWalk : .blobLying
        case .excited:  return .blobRun
        case .tired:    return .blobWalk
        case .sleeping: return .blobSleep
        case .sick:     return .blobLying    // TODO: bespoke sprite when art lands
        case .blissful: return .blobRun      // TODO: bespoke sprite when art lands
        }
    }
}
