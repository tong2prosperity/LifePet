import Foundation
import PiboCore
import os

/// Coordinates the platform side effects of a completed Walk Doodle. The
/// geometry and authored speech decisions remain in their existing owners.
@MainActor
enum HomeWalkDoodleSaveCoordinator {
    static func run(
        result: WalkDoodleCompletionResult,
        history: HealthHistoryStore,
        ledger: BoLedgerStore,
        progress: WalkDoodleProgressStore,
        speech: PiboSpeechService,
        show: (PiboSpeech) -> Void
    ) {
        run(
            result: result,
            persist: { history.addWalkDoodle($0) },
            applyReward: { eventID, energy in
                ledger.grantBonusEnergy(eventID: eventID, grantedEnergy: energy)
                    || ledger.hasProcessedBonusEnergy(eventID: eventID)
            },
            acknowledgeReward: progress.acknowledgeReward,
            resolveSpeech: { cues, context in
                speech.resolve(cues: cues, context: context)
            },
            show: show
        )
    }

    static func run(
        result: WalkDoodleCompletionResult,
        persist: (WalkDoodleCompletionResult) -> Void,
        applyReward: (String, Double) -> Bool,
        acknowledgeReward: (String) -> Void,
        resolveSpeech: ([PiboSpeechCue], PiboSpeechContext) -> PiboSpeech?,
        show: (PiboSpeech) -> Void
    ) {
        Analytics.track(
            .walkDoodleSaved,
            screen: "walk_doodle",
            [
                "distance_m": .int(Int(result.distanceMeters)),
                "area_m2": .int(Int(result.areaSquareMeters)),
                "duration_s": .int(Int(result.duration)),
                "score": .int(result.evaluation.score.score),
                "completed": .bool(result.evaluation.score.isCompleted),
                "bonus_energy": .double(result.evaluation.reward.grantedEnergy),
            ]
        )
        if !result.rewardEventID.isEmpty,
           applyReward(result.rewardEventID, result.evaluation.reward.grantedEnergy) {
            acknowledgeReward(result.rewardEventID)
        }
        persist(result)
        if let line = resolveSpeech(
            [
                .walkCompleted(
                    distanceMeters: result.distanceMeters,
                    duration: result.duration
                ),
            ],
            .home(trigger: .completed)
        ) {
            show(line)
        }
        LPLog.walkDoodle.notice("saved: \(Int(result.distanceMeters), privacy: .public)m \(Int(result.areaSquareMeters), privacy: .public)m²")
    }
}
