import Foundation
import SwiftUI

/// Owns Home's appearance and soundscape wiring while feature-presentation
/// effects remain supplied by `HomeView`.
@MainActor
struct HomeLifecycleModifier: ViewModifier {
    struct Handlers {
        let speakForWeather: (PiboSpeechTrigger) -> Void
        let refreshAnimation: () -> Void
        let runDebugAutomation: () -> Void
        let presentAchievement: () -> Void
        let presentMorningSleep: () -> Void
        let presentStressCard: () -> Void
        let announceFirstRipeBo: () -> Void
    }

    @Binding private var greetingText: String
    @Binding private var dayLabelText: String

    let currentGreeting: () -> String
    let currentDayLabel: () -> String
    let stageEnvironment: PiboStageEnvironment
    let weather: PiboWeather
    let petID: UUID
    let ambientSoundEnabled: Bool
    let soundscapePresentation: SoundscapePresentation
    let currentHasRipeBo: () -> Bool
    let weatherService: WeatherDataService
    let soundscape: AmbientSoundscapeService
    let currentDate: () -> Date
    let handlers: Handlers

    init(
        greetingText: Binding<String>,
        dayLabelText: Binding<String>,
        currentGreeting: @escaping () -> String,
        currentDayLabel: @escaping () -> String,
        stageEnvironment: PiboStageEnvironment,
        weather: PiboWeather,
        petID: UUID,
        ambientSoundEnabled: Bool,
        soundscapePresentation: SoundscapePresentation,
        currentHasRipeBo: @escaping () -> Bool,
        weatherService: WeatherDataService,
        soundscape: AmbientSoundscapeService,
        currentDate: @escaping () -> Date,
        handlers: Handlers
    ) {
        _greetingText = greetingText
        _dayLabelText = dayLabelText
        self.currentGreeting = currentGreeting
        self.currentDayLabel = currentDayLabel
        self.stageEnvironment = stageEnvironment
        self.weather = weather
        self.petID = petID
        self.ambientSoundEnabled = ambientSoundEnabled
        self.soundscapePresentation = soundscapePresentation
        self.currentHasRipeBo = currentHasRipeBo
        self.weatherService = weatherService
        self.soundscape = soundscape
        self.currentDate = currentDate
        self.handlers = handlers
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                HomeLifecycleCoordinator.appeared(
                    hasRipeBo: currentHasRipeBo(),
                    handlers: appearanceHandlers
                )
            }
            .onDisappear {
                HomeSoundscapeCoordinator.stop(soundscape: soundscape)
            }
            .onChange(of: stageEnvironment) { _, environment in
                updateSoundscape(environment: environment, petID: petID)
            }
            .onChange(of: weather) { _, _ in
                handlers.speakForWeather(.environmentChanged)
            }
            .onChange(of: petID) { _, petID in
                updateSoundscape(environment: stageEnvironment, petID: petID)
            }
            .onChange(of: ambientSoundEnabled) { _, enabled in
                soundscape.setEnabled(enabled)
            }
            .onChange(of: soundscapePresentation) { _, presentation in
                soundscape.setPresentation(presentation)
            }
    }

    private var appearanceHandlers: HomeLifecycleCoordinator.Handlers {
        HomeLifecycleCoordinator.Handlers(
            activateWeather: weatherService.activateForHome,
            cacheGreeting: { greetingText = currentGreeting() },
            cacheDayLabel: { dayLabelText = currentDayLabel() },
            speakForEnteredWeather: { handlers.speakForWeather(.entered) },
            refreshAnimation: handlers.refreshAnimation,
            runDebugAutomation: handlers.runDebugAutomation,
            presentAchievement: handlers.presentAchievement,
            startSoundscape: {
                HomeSoundscapeCoordinator.start(
                    enabled: ambientSoundEnabled,
                    presentation: soundscapePresentation,
                    environment: stageEnvironment,
                    date: currentDate(),
                    petID: petID,
                    soundscape: soundscape
                )
            },
            presentMorningSleep: handlers.presentMorningSleep,
            presentStressCard: handlers.presentStressCard,
            announceFirstRipeBo: handlers.announceFirstRipeBo
        )
    }

    private func updateSoundscape(
        environment: PiboStageEnvironment,
        petID: UUID
    ) {
        HomeSoundscapeCoordinator.update(
            environment: environment,
            date: currentDate(),
            petID: petID,
            soundscape: soundscape
        )
    }
}
