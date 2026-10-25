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
        /// The forest's light for Pibo's state (2026-09-28).
        let forestMood: ForestMood
        /// VoiceOver: the current state caption and what a pat does.
        let piboAccessibilityLabel: String?
        let piboAccessibilityHint: String?
        let presentedOrnaments: Set<PiboOrnament.ID>
        let unlockedOrnaments: Set<PiboOrnament.ID>
        let litOrnamentLights: [PiboOrnament.ID: Set<Int>]
        let shadowPresentation: ShadowPiboStagePresentation
        let tuning: StageRenderTuning
        let isPaused: Bool
        let isObscured: Bool
        let balanceTarget: CGPoint?
        let companionHotspots: PiboStageScene.CompanionHotspots

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
            shadowPresentation: ShadowPiboStagePresentation = .hidden,
            harvestActive: Bool = false,
            balanceTarget: CGPoint? = nil,
            companionHotspots: PiboStageScene.CompanionHotspots = .none,
            boOverride: BoOverride? = nil,
            stateCaption: PiboStateCaption? = nil
        ) {
            theme = store.currentTheme
            activityState = animationPresentation.state
            // Decision 048: a ripe container (or a collection still playing out)
            // overrides the presentation with the one normal standing pose. The
            // health state itself is untouched.
            self.companionHotspots = companionHotspots
            animationStateID = Self.presentedStateID(
                semantic: animationPresentation.stateID,
                hasRipeBo: boOverride?.hasRipe ?? boLedger.hasRipeBo,
                harvestActive: harvestActive
            )
            self.balanceTarget = balanceTarget
            // The forest head now represents the real `bo` ledger. The old
            // workout-driven mystery/sprouted field remains only for migration.
            growth = .sprouted
            boGrowthStage = boOverride?.stage ?? boLedger.growthStage
            boFillProgress = boOverride?.progress ?? boLedger.growthProgress
            self.environment = environment
            // Debug animation overrides map to their semantic state, so the
            // light and the words follow what the stage shows.
            let presentedState = animationPresentation.patState
            forestMood = ForestMood(state: presentedState)
            if let stateCaption {
                piboAccessibilityLabel = stateCaption.sentence
                piboAccessibilityHint = PiboCoreAnimationAdapter.accessibilityHint(for: presentedState)
            } else {
                piboAccessibilityLabel = nil
                piboAccessibilityHint = nil
            }
            let unlocked = ornamentUnlocks.presentableUnlocked
            unlockedOrnaments = unlocked
            // Keep the forest legible: every owned item plus exactly the next
            // discoverable grey target. Later items stay absent until the chain
            // advances.
            presentedOrnaments = unlocked.union(
                ornamentUnlocks.nextLocked.map { [$0.id] } ?? []
            )
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
        var collectBo: () -> Bool = { false }
        var harvestActiveChanged: (Bool) -> Void = { _ in }
        var harvestHint: (String) -> Void = { _ in }
        var speechAnchorChanged: (CGPoint?) -> Void = { _ in }
        var captionAnchorChanged: (CGPoint?) -> Void = { _ in }
        /// A single tap on Pibo: it has blinked; Home re-shows the caption.
        var glance: () -> Void = {}
        var companionHotspot: (PiboStageScene.CompanionHotspot) -> Void = { _ in }
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
            forestMood: input.forestMood,
            piboAccessibility: input.piboAccessibilityLabel.map { ($0, input.piboAccessibilityHint ?? "") },
            presentedOrnaments: input.presentedOrnaments,
            unlockedOrnaments: input.unlockedOrnaments,
            litOrnamentLights: input.litOrnamentLights,
            shadowPresentation: input.shadowPresentation,
            tuning: input.tuning,
            onPat: handlers.pat,
            onGlance: handlers.glance,
            onSproutTouched: handlers.sproutTouch,
            onOrnamentLightTapped: handlers.ornamentLightTap,
            onOrnamentTapped: handlers.ornamentTap,
            onShadowTapped: handlers.shadowTap,
            onCollectBo: handlers.collectBo,
            onHarvestActiveChanged: handlers.harvestActiveChanged,
            onHarvestHint: handlers.harvestHint,
            onSpeechAnchorChanged: handlers.speechAnchorChanged,
            onCaptionAnchorChanged: handlers.captionAnchorChanged,
            companionHotspots: input.companionHotspots,
            onCompanionHotspot: handlers.companionHotspot,
            balanceTarget: input.balanceTarget,
            isPaused: input.isPaused,
            isObscured: input.isObscured
        )
        .equatable()
        .ignoresSafeArea()
        .allowsHitTesting(!input.isObscured)
        .accessibilityHidden(input.isPaused || input.isObscured)
    }

    #if DEBUG
    /// Debug character previews may bypass the collection pose.
    static var debugBypassesCollectionPose = false
    #endif
}

/// DEBUG temporary container presentation; production passes nil.
struct BoOverride: Equatable {
    let stage: PiboCoreBoGrowthStage
    let progress: Double
    let hasRipe: Bool
}

extension HomeStageSurface.Input {
    static func presentedStateID(semantic: String, hasRipeBo: Bool, harvestActive: Bool) -> String {
        #if DEBUG
        if HomeStageSurface.debugBypassesCollectionPose { return semantic }
        #endif
        guard PiboBoContainer.usesCollectionPose(ripe: hasRipeBo ? 1 : 0, collecting: harvestActive) else {
            return semantic
        }
        return PiboAnimationResourceID.stable
    }
}
