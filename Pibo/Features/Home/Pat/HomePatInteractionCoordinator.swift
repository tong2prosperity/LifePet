import Foundation
import PiboCore

/// Sequences one Home pat. The production entry adapts Home services into the
/// handler-based core so state reads and effects retain their established order.
@MainActor
enum HomePatInteractionCoordinator {
    struct Handlers {
        let registerActualPat: (_ localHour: Double, _ countsTowardAngry: Bool) -> Bool
        let refreshAnimationState: () -> Void
        let currentAnimationStateID: () -> String
        let transitionAnimation: (
            _ targetStateID: String,
            _ intent: PiboCoreAnimationAdapter.TransitionIntent
        ) -> Void
        let performAnimationEvent: (_ stateID: String) -> Void
        let resolvePatSpeech: (
            _ context: HomePatInteractionPolicy.StateContext
        ) -> PiboHomePatResolution
        let showAnimationLine: (PiboSpeechLine) -> Void
        let showResolvedSpeech: (PiboSpeech) -> Void
        let trackReaction: (HomePatInteractionPolicy.Reaction) -> Void
    }

    static func run(
        store: PetStateStore,
        history: HealthHistoryStore,
        animationPresentation: HomeAnimationPresentationController,
        stageCommands: PiboStageCommandController,
        speech: PiboSpeechService,
        storyStage: @escaping () -> PiboCoreStorySpeechStage,
        facts: @escaping () -> PiboHomeSpeechFacts,
        neutralLegacyMode: @escaping () -> Bool,
        showAnimationLine: @escaping (PiboSpeechLine) -> Void,
        showResolvedSpeech: @escaping (PiboSpeech) -> Void
    ) {
        LPHaptics.tap()
        let now = Date()
        let localHour = HomeAtmosphereClock.localHour(at: now)
        let sourceStateID = animationPresentation.stateID
        run(
            localHour: localHour,
            sourceStateID: sourceStateID,
            handlers: Handlers(
                registerActualPat: { localHour, countsTowardAngry in
                    store.animationExperience.registerActualPat(
                        localHour: localHour,
                        countsTowardAngry: countsTowardAngry,
                        now: now
                    )
                },
                refreshAnimationState: {
                    animationPresentation.refresh(
                        store: store,
                        history: history,
                        now: now
                    )
                },
                currentAnimationStateID: { animationPresentation.stateID },
                transitionAnimation: { targetStateID, intent in
                    stageCommands.transitionAnimation(to: targetStateID, intent: intent)
                },
                performAnimationEvent: stageCommands.performAnimationEvent,
                resolvePatSpeech: { context in
                    speech.resolvePat(
                        storyStage: storyStage(),
                        restingState: context.resting,
                        sleepingState: context.sleeping,
                        facts: facts(),
                        neutralLegacyMode: neutralLegacyMode()
                    )
                },
                showAnimationLine: showAnimationLine,
                showResolvedSpeech: showResolvedSpeech,
                trackReaction: { reaction in
                    Analytics.track(
                        .pat,
                        screen: "home",
                        ["reaction": .string(reaction.rawValue)]
                    )
                }
            )
        )
    }

    static func run(
        localHour: Double,
        sourceStateID: String,
        handlers: Handlers
    ) {
        let context = HomePatInteractionPolicy.stateContext(for: sourceStateID)
        let enteredAngry = handlers.registerActualPat(
            localHour,
            context.countsTowardAngry
        )
        handlers.refreshAnimationState()

        let transitionTargetStateID = handlers.currentAnimationStateID()
        if enteredAngry {
            handlers.performAnimationEvent("angry")
        } else if transitionTargetStateID != sourceStateID {
            let intent = PiboCoreAnimationAdapter.transitionIntent(
                stateID: sourceStateID,
                angryEntered: enteredAngry
            )
            handlers.transitionAnimation(transitionTargetStateID, intent)
        }

        // The transition callback may synchronously update presentation state,
        // so speech routes from a fresh read just as HomeView did inline.
        let speechTargetStateID = handlers.currentAnimationStateID()
        let route = HomePatInteractionPolicy.speechRoute(
            sourceStateID: sourceStateID,
            targetStateID: speechTargetStateID,
            angryEntered: enteredAngry
        )
        switch route {
        case .immediateAnimation(let contentID, let reaction):
            if let line = HomeSpeechPresentationPolicy.animationPatLine(
                contentID: contentID,
                angry: enteredAngry
            ) {
                handlers.showAnimationLine(line)
            }
            handlers.trackReaction(reaction)
        case .conditionalAnimation(let contentID, let presentsWhenAllowed):
            let resolution = handlers.resolvePatSpeech(context)
            let shouldPresent = presentsWhenAllowed && resolution.shouldSpeak
            if shouldPresent, let line = HomeSpeechPresentationPolicy.animationPatLine(
                contentID: contentID,
                angry: enteredAngry
            ) {
                handlers.showAnimationLine(line)
            }
            handlers.trackReaction(
                HomePatInteractionPolicy.conditionalReaction(
                    shouldPresent: shouldPresent
                )
            )
        case .resolvedSpeech:
            let resolution = handlers.resolvePatSpeech(context)
            if let speech = resolution.speech {
                handlers.showResolvedSpeech(speech)
            }
            handlers.trackReaction(
                HomePatInteractionPolicy.resolvedSpeechReaction(
                    hasSpeech: resolution.speech != nil
                )
            )
        case .silent:
            handlers.trackReaction(.silent)
        }
    }
}
