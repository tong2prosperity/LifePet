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
        /// Exact Core-ledger progress rendered as a bottom-up `bo` fill.
        let boFillProgress: Double
        let environment: PiboStageEnvironment
        let presentedOrnaments: Set<PiboOrnament.ID>
        let unlockedOrnaments: Set<PiboOrnament.ID>
        let litOrnamentLights: [PiboOrnament.ID: Set<Int>]
        let shadowPresentation: ShadowPiboStagePresentation
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
            isObscured: Bool,
            shadowPresentation: ShadowPiboStagePresentation = .hidden
        ) {
            theme = store.currentTheme
            activityState = animationPresentation.state
            animationStateID = animationPresentation.stateID
            // The forest head now represents the real `bo` ledger. The old
            // workout-driven mystery/sprouted field remains only for migration.
            growth = .sprouted
            boGrowthStage = boLedger.growthStage
            boFillProgress = boLedger.growthProgress
            self.environment = environment
            let unlocked = ornamentUnlocks.unlocked
            unlockedOrnaments = unlocked
            // Common objects belong to the shared forest from the beginning.
            // Ownership changes their material and behavior, not whether they
            // exist in a separate catalogue or progress window.
            presentedOrnaments = Set(PiboOrnament.ordered.map(\.id))
            litOrnamentLights = ornamentLights.lit
            self.shadowPresentation = shadowPresentation
            self.tuning = tuning
            self.isPaused = isPaused
            self.isObscured = isObscured
        }
    }

    struct Handlers {
        let pat: () -> Void
        let sproutTouch: () -> Void
        let ornamentLightTap: (PiboOrnament.ID, Int) -> Void
        let ornamentTap: (PiboOrnament.ID) -> Void
        let shadowTap: () -> Void
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
            boFillProgress: input.boFillProgress,
            environment: input.environment,
            presentedOrnaments: input.presentedOrnaments,
            unlockedOrnaments: input.unlockedOrnaments,
            litOrnamentLights: input.litOrnamentLights,
            shadowPresentation: input.shadowPresentation,
            tuning: input.tuning,
            onPat: handlers.pat,
            onSproutTouched: handlers.sproutTouch,
            onOrnamentLightTapped: handlers.ornamentLightTap,
            onOrnamentTapped: handlers.ornamentTap,
            onShadowTapped: handlers.shadowTap,
            isPaused: input.isPaused,
            isObscured: input.isObscured
        )
        .equatable()
        .ignoresSafeArea()
        .allowsHitTesting(!input.isObscured)
        .accessibilityHidden(input.isPaused || input.isObscured)
    }
}
