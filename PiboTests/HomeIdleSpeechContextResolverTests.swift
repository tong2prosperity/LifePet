import PiboCore
import XCTest
@testable import Pibo

final class HomeIdleSpeechContextResolverTests: XCTestCase {
    func testEveryShippedAnimationStateKeepsItsIdleSpeechContext() {
        let expectations: [String: PiboCoreHomeSpeechContext?] = [
            "default": .idle,
            "muscle": .idle,
            "pigu": .idle,
            "sleep-1": nil,
            "sleep-2": nil,
            "awake": .waking,
            "weak": .lowSleepAndActivity,
            "angry": nil,
            "boring": .lowActivity,
            "tired": .lowSleep,
            "dive": .dive,
            "coolhide": .coolhide,
        ]

        XCTAssertEqual(Set(expectations.keys), PiboAnimationStateMap.available)
        for (stateID, expected) in expectations {
            XCTAssertEqual(
                HomeIdleSpeechContextResolver.resolve(
                    animationStateID: stateID,
                    wakingSleptEnough: true,
                    hasRealHealthData: true
                ),
                expected,
                "Unexpected speech context for \(stateID)"
            )
        }
    }

    func testAwakeUsesLowSleepContextOnlyForExplicitlyInsufficientSleep() {
        XCTAssertEqual(resolveAwake(wakingSleptEnough: false), .wakingLowSleep)
        XCTAssertEqual(resolveAwake(wakingSleptEnough: true), .waking)
        XCTAssertEqual(resolveAwake(wakingSleptEnough: nil), .waking)
    }

    func testFallbackDistinguishesRealFromMissingHealthData() {
        XCTAssertEqual(resolveUnknown(hasRealHealthData: true), .idle)
        XCTAssertEqual(resolveUnknown(hasRealHealthData: false), .missingDataPibo)
    }

    func testHealthInputsRemainLazyForStatesThatDoNotNeedThem() {
        var wakingRead = false
        var healthRead = false

        let context = HomeIdleSpeechContextResolver.resolve(
            animationStateID: "sleep-1",
            wakingSleptEnough: read(&wakingRead, value: false),
            hasRealHealthData: read(&healthRead, value: true)
        )

        XCTAssertNil(context)
        XCTAssertFalse(wakingRead)
        XCTAssertFalse(healthRead)
    }

    private func resolveAwake(wakingSleptEnough: Bool?) -> PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: "awake",
            wakingSleptEnough: wakingSleptEnough,
            hasRealHealthData: false
        )
    }

    private func resolveUnknown(hasRealHealthData: Bool) -> PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: "future-state",
            wakingSleptEnough: nil,
            hasRealHealthData: hasRealHealthData
        )
    }

    private func read<T>(_ didRead: inout Bool, value: T) -> T {
        didRead = true
        return value
    }
}
