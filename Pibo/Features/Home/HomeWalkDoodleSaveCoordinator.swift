import Foundation
import os

/// Coordinates the platform side effects of a completed Walk Doodle. The
/// geometry and authored speech decisions remain in their existing owners.
@MainActor
enum HomeWalkDoodleSaveCoordinator {
    static func run(
        result: WalkDoodleResult,
        history: HealthHistoryStore,
        speech: PiboSpeechService,
        show: (PiboSpeech) -> Void
    ) {
        run(
            result: result,
            persist: { history.addWalkDoodle($0) },
            resolveSpeech: { cues, context in
                speech.resolve(cues: cues, context: context)
            },
            show: show
        )
    }

    static func run(
        result: WalkDoodleResult,
        persist: (WalkDoodleResult) -> Void,
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
            ]
        )
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
        LPLog.app.notice("walk doodle saved: \(Int(result.distanceMeters), privacy: .public)m \(Int(result.areaSquareMeters), privacy: .public)m²")
    }
}
