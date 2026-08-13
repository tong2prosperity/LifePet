import Foundation
import Observation
import SwiftUI
import UIKit

/// Owns the phase transitions and playback timing of Home's workout sprout
/// choreography. Eligibility stays in `HomeSproutFlowStartResolver`; concrete
/// SpriteKit commands and store mutations arrive through explicit handlers.
@MainActor
@Observable
final class HomeSproutFlowController {
    typealias CompletionScheduler = @MainActor (
        _ delay: TimeInterval,
        _ completion: @escaping @MainActor () -> Void
    ) -> Void

    struct Handlers {
        let playCloseup: (
            _ growthStart: Double,
            _ growthTarget: Double,
            _ onPhase: @escaping (SproutCloseupPhase) -> Void
        ) -> Void
        let playGrowth: (_ growthStart: Double, _ growthTarget: Double) -> Void
        let markSprouted: () -> Void
        let currentPendingWorkoutID: () -> UUID?
    }

    private(set) var phase: SproutFlowPhase = .idle
    @ObservationIgnored private let scheduleCompletion: CompletionScheduler

    init(
        scheduleCompletion: @escaping CompletionScheduler = { delay, completion in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                completion()
            }
        }
    ) {
        self.scheduleCompletion = scheduleCompletion
    }

    func startIfPossible(
        store: PetStateStore,
        sheetPresented: @autoclosure () -> Bool,
        fullScreenFeaturePresented: @autoclosure () -> Bool,
        stageCommands: PiboStageCommandController
    ) {
        // The close-up runs on the SpriteKit stage, which presentation state
        // freezes. Starting behind a sheet or cover would play the whole beat
        // where nobody can see it.
        let request = HomeSproutFlowStartResolver.resolve(
            pendingWorkout: store.pendingWorkout,
            phase: phase,
            sheetPresented: sheetPresented(),
            fullScreenFeaturePresented: fullScreenFeaturePresented(),
            growthStart: store.headSproutGrowthProgress,
            growthTarget: { store.sproutGrowthTarget(for: $0) },
            canSprout: store.growthStage == .mystery
                && store.currentTheme.sproutedHeadSprite != nil,
            animationStyle: SproutAnimationStyle.current
        )
        start(
            request: request,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            handlers: Handlers(
                playCloseup: { start, target, onPhase in
                    stageCommands.playSproutCloseup(
                        growthFrom: start,
                        growthTo: target,
                        onPhase: onPhase
                    )
                },
                playGrowth: { start, target in
                    stageCommands.playSproutGrowth(from: start, to: target)
                },
                markSprouted: { store.markSprouted() },
                currentPendingWorkoutID: { store.pendingWorkout?.id }
            )
        )
    }

    func start(
        request: HomeSproutFlowStartResolver.Request?,
        reduceMotion: Bool,
        handlers: Handlers
    ) {
        guard let request else { return }

        setPhase(.collecting)
        switch request.animation {
        case .stageCloseup, .lottieCloseup:
            // Both routes use the stage placeholder until the Lottie asset lands.
            handlers.playCloseup(request.growthStart, request.growthTarget) { [self] phase in
                handleCloseupPhase(phase, markSprouted: handlers.markSprouted)
            }
        case .inPlaceGrowth:
            handlers.playGrowth(request.growthStart, request.growthTarget)
            let delay = reduceMotion ? 0.15 : 1.35
            scheduleCompletion(delay) { [self] in
                guard handlers.currentPendingWorkoutID() == request.workoutID,
                      phase == .collecting
                else { return }
                setPhase(.pop)
            }
        }
    }

    func handleCloseupPhase(
        _ closeupPhase: SproutCloseupPhase,
        markSprouted: () -> Void
    ) {
        switch closeupPhase {
        case .shaking:
            break
        case .sprouted:
            markSprouted()
            setPhase(.sprouted)
        case .finished:
            setPhase(.pop)
        }
    }

    func finishPop() {
        setPhase(.idle)
    }

    private func setPhase(_ phase: SproutFlowPhase) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            self.phase = phase
        }
    }
}
