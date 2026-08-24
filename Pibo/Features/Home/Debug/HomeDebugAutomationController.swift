#if DEBUG
import Foundation
import PiboCore
import UIKit

/// Owns Home's developer-automation lifetime and adapts concrete app services
/// to the independently tested `HomeDebugLaunchAutomation` scheduler.
@MainActor
final class HomeDebugAutomationController {
    private var gamesAlreadyOpened = false
    private var historyAlreadyOpened = false
    private var workoutID: UUID?

    init(workoutID: UUID? = nil) {
        self.workoutID = workoutID
    }

    func runLaunchAutomation(
        options: HomeDebugLaunchOptions,
        miniGamesEnabled: @autoclosure () -> Bool,
        store: PetStateStore,
        presentation: HomePresentationState,
        morningSleep: MorningSleepCoordinator,
        animationPresentation: HomeAnimationPresentationController,
        stageCommands: PiboStageCommandController,
        boProgressFeedback: BoProgressFeedbackStore,
        stressNotifier: StressNotifier,
        sheetIsAbsent: @escaping () -> Bool,
        presentSheet: @escaping (HomeSheetDestination) -> Void,
        selectAnimationState: @escaping (String?) -> Void,
        photoSaved: @escaping (UIImage?, String?, MealType?) -> Void,
        openBoPanel: @escaping () -> Void
    ) {
        HomeDebugLaunchAutomation.run(
            options: options,
            miniGamesEnabled: miniGamesEnabled(),
            gamesAlreadyOpened: &gamesAlreadyOpened,
            historyAlreadyOpened: &historyAlreadyOpened,
            handlers: .init(
                setForestHour: { store.debugForestHour = $0 },
                simulateLunch: {
                    Self.simulateMeal(.lunch, photoSaved: photoSaved)
                },
                openGames: { presentation.showGames = true },
                openHistory: { presentation.showHistory = true },
                showMorningSleep: { morningSleep.debugPresentFixture() },
                presentAchievementIfAvailable: { payload in
                    guard sheetIsAbsent() else { return }
                    presentSheet(.achievement(payload))
                },
                bounceToAnimationState: { target in
                    // Deterministic Simulator capture hook. The delay leaves
                    // one stable source frame before the exact 710 ms cut.
                    animationPresentation.prepareDebugBounce(to: target)
                    stageCommands.transitionAnimation(to: target, intent: .bounceCut)
                },
                selectAnimationState: selectAnimationState,
                enqueueBoProgress: { milestone in
                    let perBo = PiboCoreBoEconomy.energyPerBo
                    let previous = perBo * Double(max(0, milestone.rawValue - 10)) / 100
                    let current = milestone == .minted
                        ? perBo * 0.08
                        : perBo * Double(milestone.rawValue) / 100
                    boProgressFeedback.enqueue(
                        milestone,
                        previousEnergyPool: previous,
                        newEnergyPool: current,
                        mintedCount: milestone == .minted ? 1 : 0
                    )
                },
                openBoPanel: openBoPanel,
                openStressCard: {
                    // Seed first: the stress card needs a derived score, which
                    // a bare simulator has no heartbeat series to produce.
                    store.debugSeedStressIfNeeded()
                    stressNotifier.pendingCardOpen = true
                }
            )
        )
    }

    /// Close Settings first so Home is visible when the real workout event is
    /// injected. Waiting for the navigation pop keeps the rehearsal deterministic.
    func simulateWorkout(
        store: PetStateStore,
        presentation: HomePresentationState
    ) {
        presentation.showSettings = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            workoutID = store.debugInjectWorkout()
        }
    }

    func applyWorkoutRewardIfMatching(
        _ payload: PiboAnimationAchievementPayload,
        ledger: BoLedgerStore
    ) {
        guard workoutID == payload.id else { return }
        ledger.debugApplyWorkout(
            durationMinutes: payload.workoutDurationMinutes ?? 24
        )
        workoutID = nil
    }

    /// Exercises the full meal-recognition path without camera hardware.
    static func simulateMeal(
        _ meal: MealType,
        photoSaved: (UIImage?, String?, MealType?) -> Void
    ) {
        photoSaved(foodImage("🍜"), nil, meal)
    }

    private static func foodImage(_ emoji: String, size: CGFloat = 512) -> UIImage {
        let imageSize = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
            let string = emoji as NSString
            let font = UIFont.systemFont(ofSize: size * 0.6)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = string.size(withAttributes: attributes)
            string.draw(
                at: CGPoint(
                    x: (size - textSize.width) / 2,
                    y: (size - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
    }
}
#endif
