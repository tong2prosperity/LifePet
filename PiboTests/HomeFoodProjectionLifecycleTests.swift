import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeFoodProjectionLifecycleTests {
    @Test func verifiedProjectionWaitsForCameraDismissal() {
        let presentation = HomePresentationState()
        let projection = HomeFoodProjection(
            id: UUID(),
            pngData: Data([1, 2, 3]),
            meal: .lunch,
            dishName: "番茄炒蛋",
            observation: "红色和黄色放在了一起。",
            isCutout: true
        )

        presentation.showCamera = true
        presentation.prepareFoodProjection(projection)
        #expect(presentation.pendingFoodProjection == projection)
        #expect(presentation.foodProjection == nil)

        presentation.showCamera = false
        presentation.presentPreparedFoodProjection()
        #expect(presentation.pendingFoodProjection == nil)
        #expect(presentation.foodProjection == projection)
    }
}
