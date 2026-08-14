import PiboCore
import XCTest
@testable import Pibo

final class HomeIdleSpeechContextResolverTests: XCTestCase {
    func testEveryShippedAnimationStateKeepsItsIdleSpeechContext() {
        let expectations: [String: PiboCoreHomeSpeechContext?] = [
            "pibo-state-stable-forest-idle": .idle,
            "pibo-event-activity-milestone-celebrate": .idle,
            "pibo-event-workout-celebrate": .idle,
            "pibo-state-sleeping-hammock-idle-a": nil,
            "pibo-state-sleeping-hammock-idle-b": nil,
            "pibo-state-waking-hammock-idle": .waking,
            "weak": .idle,
            "angry": nil,
            "boring": .idle,
            "pibo-state-tired-forest-idle": .lowSleep,
            "dive": .idle,
            "coolhide": .idle,
        ]

        XCTAssertEqual(Set(expectations.keys), PiboAnimationStateMap.available)
        for (stateID, expected) in expectations {
            XCTAssertEqual(
                HomeIdleSpeechContextResolver.resolve(
                    animationStateID: stateID,
                    hasRealHealthData: true
                ),
                expected,
                "Unexpected speech context for \(stateID)"
            )
        }
    }

    func testAwakeUsesOneNeutralWakingContext() {
        XCTAssertEqual(resolveAwake(), .waking)
    }

    func testFallbackDistinguishesRealFromMissingHealthData() {
        XCTAssertEqual(resolveUnknown(hasRealHealthData: true), .idle)
        XCTAssertEqual(resolveUnknown(hasRealHealthData: false), .missingDataPibo)
    }

    func testHealthInputsRemainLazyForStatesThatDoNotNeedThem() {
        var healthRead = false

        let context = HomeIdleSpeechContextResolver.resolve(
            animationStateID: "pibo-state-sleeping-hammock-idle-a",
            hasRealHealthData: read(&healthRead, value: true)
        )

        XCTAssertNil(context)
        XCTAssertFalse(healthRead)
    }

    private func resolveAwake() -> PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: "pibo-state-waking-hammock-idle",
            hasRealHealthData: false
        )
    }

    private func resolveUnknown(hasRealHealthData: Bool) -> PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: "future-state",
            hasRealHealthData: hasRealHealthData
        )
    }

    private func read<T>(_ didRead: inout Bool, value: T) -> T {
        didRead = true
        return value
    }
}
