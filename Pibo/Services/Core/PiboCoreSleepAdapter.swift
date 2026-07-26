import Foundation
import HealthKit
import PiboCore

enum PiboCoreSleepAdapter {
    enum ResolvedSampleKind {
        case ignored
        case awake
        case legacyAsleep
        case core
        case deep
        case rem
        case unspecified
    }

    /// How complete a sleep session is. Owned by Core so both phone apps agree.
    enum Readiness {
        case notEligible
        case provisional
        case final
    }

    /// What may be done with a summary right now — drives the local notification
    /// *and* the in-app card, so the two can never disagree.
    enum Delivery {
        case hold
        case deliverNow
        case deferToMorning
    }

    static func sampleIsDetailed(_ value: HKCategoryValueSleepAnalysis?) -> Bool {
        PiboCoreSleep.sampleIsDetailed(coreSampleKind(value))
    }

    static func resolveSample(
        _ value: HKCategoryValueSleepAnalysis?,
        hasDetailedSamples: Bool
    ) -> ResolvedSampleKind {
        switch PiboCoreSleep.resolveSample(
            coreSampleKind(value),
            hasDetailedSamples: hasDetailedSamples
        ) {
        case .ignored: .ignored
        case .awake: .awake
        case .legacyAsleep: .legacyAsleep
        case .core: .core
        case .deep: .deep
        case .rem: .rem
        case .unspecified: .unspecified
        }
    }

    static func samplesShareSession(gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.samplesShareSession(gapSeconds: gapSeconds)
    }

    static func segmentsShouldMerge(sameStage: Bool, gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.segmentsShouldMerge(sameStage: sameStage, gapSeconds: gapSeconds)
    }

    // MARK: - Morning summary policy

    /// Local hour a quiet-band delivery is deferred to.
    static var morningDeferredHour: Double { PiboCoreSleep.morningDeferredHour }

    static func morningReadiness(
        totalSeconds: TimeInterval,
        hasInBedSignal: Bool,
        hasTerminalAwakeSignal: Bool,
        secondsSinceSessionEnd: TimeInterval,
        userIsInteracting: Bool
    ) -> Readiness {
        switch PiboCoreSleep.morningReadiness(PiboCoreMorningSleepReadinessInput(
            totalSeconds: totalSeconds,
            hasInBedSignal: hasInBedSignal,
            hasTerminalAwakeSignal: hasTerminalAwakeSignal,
            secondsSinceSessionEnd: secondsSinceSessionEnd,
            userIsInteracting: userIsInteracting
        )) {
        case .notEligible: .notEligible
        case .provisional: .provisional
        case .final:       .final
        }
    }

    /// How long a session must stay quiet before it may count as finished.
    static func morningSettleSeconds(hasTerminalAwakeSignal: Bool) -> TimeInterval {
        PiboCoreSleep.morningSettleSeconds(hasTerminalAwakeSignal: hasTerminalAwakeSignal)
    }

    static func morningDelivery(readiness: Readiness, localHour: Double) -> Delivery {
        let core: PiboCoreMorningSleepReadiness = switch readiness {
        case .notEligible: .notEligible
        case .provisional: .provisional
        case .final:       .final
        }
        return switch PiboCoreSleep.morningDelivery(readiness: core, localHour: localHour) {
        case .hold:           .hold
        case .deliverNow:     .deliverNow
        case .deferToMorning: .deferToMorning
        }
    }

    /// Whether a newly computed summary re-opens a wake-day the user was already
    /// shown or notified about (a provisional night that later filled in).
    static func morningSummarySupersedes(
        previousTotalSeconds: TimeInterval,
        previousWasFinal: Bool,
        nextTotalSeconds: TimeInterval,
        nextIsFinal: Bool
    ) -> Bool {
        PiboCoreSleep.morningSummarySupersedes(
            previousTotalSeconds: previousTotalSeconds,
            previousWasFinal: previousWasFinal,
            nextTotalSeconds: nextTotalSeconds,
            nextIsFinal: nextIsFinal
        )
    }

    /// Whether a summary is still worth surfacing — replaces a strict "must be
    /// today" rule so a notification tapped after midnight still resolves.
    static func morningWithinCatchupWindow(
        secondsSinceWakeDayStart: TimeInterval
    ) -> Bool {
        PiboCoreSleep.morningWithinCatchupWindow(
            secondsSinceWakeDayStart: secondsSinceWakeDayStart
        )
    }

    private static func coreSampleKind(
        _ value: HKCategoryValueSleepAnalysis?
    ) -> PiboCoreSleepSampleKind {
        switch value {
        case .some(.awake): .awake
        case .some(.asleepCore): .core
        case .some(.asleepDeep): .deep
        case .some(.asleepREM): .rem
        // `asleep` was renamed to `asleepUnspecified` in iOS 16 and both share
        // rawValue 1, so HealthKit cannot tell "modern API, stage unknown" from a
        // pre-iOS-16 block that envelopes the real stages. Resolve the ambiguity
        // conservatively as legacy, which means: not proof of detailed staging
        // (so the card hides 阶段/awakenings for a phone-only sleep schedule
        // instead of showing a fake all-浅睡 breakdown), and dropped when the same
        // source *does* carry stages — otherwise the enveloping span would
        // swallow them in `MorningSleepSessionBuilder.normalize`. Core's
        // `unspecified` kind stays reachable for platforms whose API separates
        // the two.
        case .some(.asleepUnspecified): .legacyAsleep
        default: .other
        }
    }
}
