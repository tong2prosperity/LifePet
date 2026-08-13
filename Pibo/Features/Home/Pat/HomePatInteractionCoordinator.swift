/// Sequences one Home pat while leaving app state, presentation, and analytics
/// ownership with the injected platform handlers.
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
        let resolvePatSpeech: (
            _ context: HomePatInteractionPolicy.StateContext
        ) -> PiboHomePatResolution
        let showAnimationLine: (PiboSpeechLine) -> Void
        let showResolvedSpeech: (PiboSpeech) -> Void
        let trackReaction: (HomePatInteractionPolicy.Reaction) -> Void
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
        if transitionTargetStateID != sourceStateID {
            let intent = PiboCoreAnimationAdapter.transitionIntent(
                fromStateID: sourceStateID,
                toStateID: transitionTargetStateID,
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
