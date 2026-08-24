import Foundation
import os

/// Unified logging entry point for Pibo. Wraps `os.Logger` with one
/// category per subsystem so live-device logs in Console.app can be filtered
/// by area (e.g., `subsystem:fun.tiebao.co.Pibo category:HealthKit.Sleep`).
///
/// Lives in `Shared/`, so the iOS app, the watch app, and the widget extension
/// all log through the same table. `subsystem` is read from the *running*
/// bundle, so each process files its lines under its own identifier
/// (`…Pibo` / `…Pibo.watchkitapp` / `…Pibo.PiboWidgets`) — the three surfaces
/// stay separable in Console.app while sharing one category vocabulary.
///
/// Why `os.Logger` instead of `print`:
/// - Categorized + filterable in Console.app and Xcode's filter bar.
/// - Persistent ring buffer — failures from yesterday are still readable
///   via `log show --predicate ...` even after relaunch.
/// - Levels survive in production; Debug-only `print` doesn't.
/// - Cheap when the level is off (no string interpolation cost).
///
/// Levels — pick by reader, not by author:
/// - `.debug`   — high-volume diagnostics (per-sample HK dumps, per-event
///                ingest, recompute outputs). Hidden from Console.app's
///                default filter; visible in Xcode console always.
/// - `.info`    — routine events worth seeing during normal debugging
///                (refresh outcomes, summary stats per ingest).
/// - `.notice`  — milestone events that explain the app's narrative
///                (auth transitions, app launch, user onboarding decisions,
///                state-machine transitions, demoMode flips, reset).
/// - `.error`   — recoverable failures (HK query threw, anchor archive
///                failed, background delivery rejected). Persisted.
/// - `.fault`   — programmer errors / invariant violations. Used sparingly.
///
/// Category naming: a dotted prefix groups a family, so one predicate can pull
/// a whole area (`category BEGINSWITH "Backend."`) or a single noisy leaf
/// (`category:Vision.Cutout`). Add to this table rather than constructing a
/// `Logger` at a call site — an ad-hoc logger re-declares the subsystem and
/// drifts out of the naming scheme, which is exactly what makes a log
/// unfilterable. HarmonyPibo mirrors these category names in its own
/// `PiboLog`, so keep the two vocabularies in step.
///
/// Privacy: `os.Logger` redacts string interpolations in production unless
/// marked `.public`. We're not a user-facing logging product — these logs
/// only exist for developers reading Xcode/Console, so most labels are
/// marked `.public`. Numbers are public by default.
/// `nonisolated` overrides the project's default `@MainActor` isolation —
/// `os.Logger` is thread-safe, and callers like `PetIdentityStore`
/// (nonisolated) need to log without hopping actors.
nonisolated enum LPLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "fun.tiebao.co.Pibo"

    // MARK: - App shell

    static let app          = Logger(subsystem: subsystem, category: "App")
    static let onboarding   = Logger(subsystem: subsystem, category: "Onboarding")
    static let identity     = Logger(subsystem: subsystem, category: "Identity")
    static let snapshot     = Logger(subsystem: subsystem, category: "Snapshot")
    static let petState     = Logger(subsystem: subsystem, category: "PetState")
    static let bo           = Logger(subsystem: subsystem, category: "Bo")
    static let speech       = Logger(subsystem: subsystem, category: "Speech")
    static let audio        = Logger(subsystem: subsystem, category: "Audio.Soundscape")
    static let weather      = Logger(subsystem: subsystem, category: "Weather")

    // MARK: - HealthKit

    static let healthKit    = Logger(subsystem: subsystem, category: "HealthKit")
    /// Split out so the verbose per-sample dump can be filtered on its own
    /// without drowning the rest of `HealthKit`'s output.
    static let sleep        = Logger(subsystem: subsystem, category: "HealthKit.Sleep")
    static let workout      = Logger(subsystem: subsystem, category: "HealthKit.Workout")

    // MARK: - 拍照 pipeline

    /// `camera` = capture session + shutter + save; the two on-device Vision
    /// passes are split — `Vision.Classify` (识图 subject label) and
    /// `Vision.Cutout` (抠图 mask + 贴纸白描边 + persist) — so each verbose dump
    /// can be filtered apart from the other.
    static let camera       = Logger(subsystem: subsystem, category: "Camera")
    static let classify     = Logger(subsystem: subsystem, category: "Vision.Classify")
    static let cutout       = Logger(subsystem: subsystem, category: "Vision.Cutout")

    // MARK: - Backend (pibo-server)

    /// Transport layer — request plumbing and token refresh, not endpoints.
    static let api          = Logger(subsystem: subsystem, category: "Backend.API")
    static let auth         = Logger(subsystem: subsystem, category: "Backend.Auth")
    static let economy      = Logger(subsystem: subsystem, category: "Backend.Economy")
    /// The health-sample → sync scheduler sitting above `Backend.Economy`;
    /// separate because its cadence chatter would bury the economy's results.
    static let economySync  = Logger(subsystem: subsystem, category: "Backend.EconomySync")
    /// 拍照识别卡路里 — the backend Kimi VLM round-trip for meal photos.
    static let food         = Logger(subsystem: subsystem, category: "Backend.Food")

    // MARK: - StoreKit

    /// Deliberately not under `Backend.` — the entitlement's source of truth is
    /// StoreKit on-device, and the server round-trip is only one step inside it.
    static let membership   = Logger(subsystem: subsystem, category: "Membership")

    // MARK: - watchOS

    /// The watch's only live feature: the CRC breathing trainer.
    static let watchBreathing = Logger(subsystem: subsystem, category: "Watch.Breathing")
    /// `HKWorkoutSession` lifecycle backing that trainer. Split from
    /// `Watch.Breathing` because state transitions arrive on a delegate,
    /// interleaved with — but not part of — the training flow.
    static let watchWorkout   = Logger(subsystem: subsystem, category: "Watch.Workout")

    /// Shared "MM-dd HH:mm:ss" formatter for log timestamps. Local-time
    /// output reads more naturally than `Date`'s default UTC `description`.
    /// Built once — `DateFormatter` init is non-trivial.
    static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss"
        fmt.timeZone = .current
        return fmt
    }()

    /// Monotonic elapsed milliseconds since `start`, for timing the Vision
    /// passes (the heavy part of the 拍照 pipeline). `ContinuousClock` is
    /// immune to wall-clock / NTP jumps, so a logged duration never goes
    /// negative or spikes. Format at the call site, e.g.
    /// `\(LPLog.elapsedMs(since: start), format: .fixed(precision: 1))`.
    static func elapsedMs(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock().now - start
        return Double(d.components.seconds) * 1_000
            + Double(d.components.attoseconds) / 1_000_000_000_000_000
    }
}
