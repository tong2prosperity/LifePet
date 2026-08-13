import Foundation
import Observation
import SwiftUI

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
