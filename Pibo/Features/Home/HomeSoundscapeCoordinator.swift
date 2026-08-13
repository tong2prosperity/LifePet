import Foundation

@MainActor
protocol HomeSoundscapeControlling: AnyObject {
    func setEnabled(_ enabled: Bool)
    func setPresentation(_ presentation: SoundscapePresentation)
    func refreshExternalAudioSuppression()
    func apply(environment: PiboStageEnvironment, date: Date, petID: UUID)
    func stop()
}

extension AmbientSoundscapeService: HomeSoundscapeControlling {}

/// Owns Home's soundscape lifecycle ordering while the audio service retains
/// profile resolution, playback, interruption handling, and session effects.
@MainActor
enum HomeSoundscapeCoordinator {
    static func start(
        enabled: Bool,
        presentation: SoundscapePresentation,
        environment: PiboStageEnvironment,
        date: Date,
        petID: UUID,
        soundscape: any HomeSoundscapeControlling
    ) {
        soundscape.setEnabled(enabled)
        soundscape.setPresentation(presentation)
        soundscape.refreshExternalAudioSuppression()
        update(
            environment: environment,
            date: date,
            petID: petID,
            soundscape: soundscape
        )
    }

    static func update(
        environment: PiboStageEnvironment,
        date: Date,
        petID: UUID,
        soundscape: any HomeSoundscapeControlling
    ) {
        soundscape.apply(environment: environment, date: date, petID: petID)
    }

    static func stop(soundscape: any HomeSoundscapeControlling) {
        soundscape.setPresentation(.suspended)
        soundscape.stop()
    }
}
