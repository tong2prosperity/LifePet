import PiboCore
import SwiftUI

/// Home's complete SpriteKit bridge configuration. SwiftUI overlays remain in
/// `HomeView`; this surface owns only stage inputs, callbacks, and visibility.
struct HomeStageSurface: View {
    struct Input: Equatable {
        let theme: PiboTheme
        let activityState: PiboActivityState
        let animationStateID: String
        let growth: PiboGrowthStage
        let boGrowthStage: PiboCoreBoGrowthStage
        let sproutGrowthProgress: Double
        let environment: PiboStageEnvironment
        let presentedOrnaments: Set<PiboOrnament.ID>
        let unlockedOrnaments: Set<PiboOrnament.ID>
        let litOrnamentLights: [PiboOrnament.ID: Set<Int>]
        let tuning: StageRenderTuning
        let isPaused: Bool
        let isObscured: Bool

        init(
            store: PetStateStore,
            boLedger: BoLedgerStore,
            animationPresentation: HomeAnimationPresentationController,
            environment: PiboStageEnvironment,
            ornamentUnlocks: OrnamentUnlockStore,
            ornamentLights: OrnamentLightStore,
            tuning: StageRenderTuning,
            isPaused: Bool,
            isObscured: Bool
        ) {
            theme = store.currentTheme
            activityState = animationPresentation.state
            animationStateID = animationPresentation.stateID
            // The forest head now represents the real `bo` ledger. The old
            // workout-driven mystery/sprouted field remains only for migration.
            growth = .sprouted
            boGrowthStage = boLedger.growthStage
            sproutGrowthProgress = boLedger.growthProgress
            self.environment = environment
            let unlocked = ornamentUnlocks.unlocked
            unlockedOrnaments = unlocked
            // Common objects belong to the shared forest from the beginning.
            // Ownership changes their material and behavior, not whether they
            // exist in a separate catalogue or progress window.
            presentedOrnaments = Set(PiboOrnament.ordered.map(\.id))
            litOrnamentLights = ornamentLights.lit
            self.tuning = tuning
            self.isPaused = isPaused
            self.isObscured = isObscured
        }
    }

    struct Handlers {
        let pat: () -> Void
        let hairPull: () -> Void
        let ornamentLightTap: (PiboOrnament.ID, Int) -> Void
        let ornamentTap: (PiboOrnament.ID) -> Void
    }

    let input: Input
    let commandController: PiboStageCommandController
    let handlers: Handlers

    var body: some View {
        PiboStageView(
            theme: input.theme,
            state: input.activityState,
            animationStateID: input.animationStateID,
            commandController: commandController,
            growth: input.growth,
            boGrowthStage: input.boGrowthStage,
            sproutGrowthProgress: input.sproutGrowthProgress,
            environment: input.environment,
            presentedOrnaments: input.presentedOrnaments,
            unlockedOrnaments: input.unlockedOrnaments,
            litOrnamentLights: input.litOrnamentLights,
            tuning: input.tuning,
            onPat: handlers.pat,
            onHairPulled: handlers.hairPull,
            onOrnamentLightTapped: handlers.ornamentLightTap,
            onOrnamentTapped: handlers.ornamentTap,
            isPaused: input.isPaused,
            isObscured: input.isObscured
        )
        .equatable()
        .ignoresSafeArea()
        .allowsHitTesting(!input.isObscured)
        .accessibilityHidden(input.isPaused || input.isObscured)
    }
}
