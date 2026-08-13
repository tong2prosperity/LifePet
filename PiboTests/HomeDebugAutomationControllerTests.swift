import Foundation
import Testing
import UIKit
@testable import Pibo

#if DEBUG
@MainActor
struct HomeDebugAutomationControllerTests {
    @Test func workoutRewardRequiresTheMatchingIDAndIsConsumedOnce() throws {
        let matchingID = UUID()
        let controller = HomeDebugAutomationController(workoutID: matchingID)
        let suite = "HomeDebugAutomationControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger"
        )
        let initialEnergy = ledger.state.energyPool

        controller.applyWorkoutRewardIfMatching(
            achievement(id: UUID()),
            ledger: ledger
        )
        #expect(ledger.state.energyPool == initialEnergy)

        controller.applyWorkoutRewardIfMatching(
            achievement(id: matchingID),
            ledger: ledger
        )
        let rewardedEnergy = ledger.state.energyPool
        #expect(rewardedEnergy > initialEnergy)

        controller.applyWorkoutRewardIfMatching(
            achievement(id: matchingID),
            ledger: ledger
        )
        #expect(ledger.state.energyPool == rewardedEnergy)
    }

    @Test func simulatedMealPreservesImageAndCallbackInputs() throws {
        var capturedImage: UIImage? = nil
        var capturedLabel: String? = "unread"
        var capturedMeal: MealType? = nil

        HomeDebugAutomationController.simulateMeal(.dinner) { image, label, meal in
            capturedImage = image
            capturedLabel = label
            capturedMeal = meal
        }

        let image = try #require(capturedImage)
        #expect(image.size == CGSize(width: 512, height: 512))
        #expect(capturedLabel == nil)
        #expect(capturedMeal == .dinner)
    }

    private func achievement(id: UUID) -> PiboAnimationAchievementPayload {
        PiboAnimationAchievementPayload(
            id: id,
            kind: .pigu,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            workoutLabel: "跑步",
            workoutDurationMinutes: 24
        )
    }
}
#endif
