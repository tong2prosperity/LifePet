import AVFAudio
import Foundation
import PiboCore
import SwiftUI

/// Owns Home's view-bound async tasks and system notification subscriptions.
/// SwiftUI still supplies task cancellation when the modified view disappears.
@MainActor
struct HomeTaskModifier: ViewModifier {
    struct SpeechInput {
        let speechIsAbsent: () -> Bool
        let sproutIsIdle: () -> Bool
        let stageIsPaused: () -> Bool
        let context: () -> PiboCoreHomeSpeechContext?
        let storyStage: () -> PiboCoreStorySpeechStage
        let facts: () -> PiboHomeSpeechFacts
        let values: () -> [String: String]
        let speech: PiboSpeechService
        let show: (PiboSpeech) -> Void
    }

    struct Handlers {
        let refreshAnimation: () -> Void
        let refreshAnimationAt: (Date) -> Void
    }

    let angryUntil: Date?
    let atmosphereClock: HomeAtmosphereClock
    let ornamentLights: OrnamentLightStore
    let soundscape: AmbientSoundscapeService
    let speechInput: SpeechInput
    let handlers: Handlers

    func body(content: Content) -> some View {
        content
            .task {
                await HomeSpeechOpportunityCoordinator.runIdleLoop(
                    speechIsAbsent: speechInput.speechIsAbsent,
                    sproutIsIdle: speechInput.sproutIsIdle,
                    stageIsPaused: speechInput.stageIsPaused,
                    context: speechInput.context,
                    storyStage: speechInput.storyStage,
                    facts: speechInput.facts,
                    values: speechInput.values,
                    speech: speechInput.speech,
                    show: speechInput.show
                )
            }
            .task {
                await atmosphereClock.run { date in
                    HomeTaskCoordinator.minuteElapsed(
                        at: date,
                        handlers: coordinatorHandlers
                    )
                }
            }
            .task(id: angryUntil) {
                guard let expiry = angryUntil else { return }
                let delay = max(0, expiry.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                HomeTaskCoordinator.angryStateExpired(
                    at: expiry,
                    handlers: coordinatorHandlers
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )) { _ in
                HomeTaskCoordinator.systemDateChanged(
                    handlers: coordinatorHandlers
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSCalendarDayChanged
            )) { _ in
                HomeTaskCoordinator.systemDateChanged(
                    handlers: coordinatorHandlers
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.interruptionNotification
            )) { notification in
                soundscape.handleInterruption(notification)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.silenceSecondaryAudioHintNotification
            )) { notification in
                soundscape.handleSecondaryAudioHint(notification)
            }
    }

    private var coordinatorHandlers: HomeTaskCoordinator.Handlers {
        HomeTaskCoordinator.Handlers(
            refreshClock: atmosphereClock.refresh,
            refreshAnimation: handlers.refreshAnimation,
            refreshAnimationAt: handlers.refreshAnimationAt,
            refreshOrnamentLights: ornamentLights.refresh
        )
    }
}
