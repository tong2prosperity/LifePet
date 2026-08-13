import Foundation
import XCTest
@testable import Pibo

@MainActor
final class HomeSpeechInputResolverTests: XCTestCase {
    func testFactsPreserveAvailabilityAndPositiveValueRules() {
        let unavailable = facts(hasStepsData: false, rawSteps: 42, rawSleepHours: -1)
        XCTAssertFalse(unavailable.hasSteps)
        XCTAssertFalse(unavailable.hasSleepDuration)

        let empty = facts(hasStepsData: true, rawSteps: 0, rawSleepHours: 0)
        XCTAssertFalse(empty.hasSteps)
        XCTAssertFalse(empty.hasSleepDuration)

        let available = facts(hasStepsData: true, rawSteps: 42, rawSleepHours: 7.25)
        XCTAssertTrue(available.hasSteps)
        XCTAssertTrue(available.hasSleepDuration)
        XCTAssertTrue(available.hasWorkoutType)
        XCTAssertEqual(available.pendingBoCount, 3)
        XCTAssertTrue(available.connectionAccepted)
    }

    func testFactsDoNotReadUnavailableStepOrDisabledConnectionInputs() {
        var stepsRead = false
        var connectionRead = false

        let result = HomeSpeechInputResolver.facts(
            hasStepsData: false,
            rawSteps: read(&stepsRead, value: 42),
            rawSleepHours: 0,
            hasWorkoutToday: false,
            pendingBoCount: 0,
            cooperationEnabled: false,
            connectionAccepted: read(&connectionRead, value: true)
        )

        XCTAssertFalse(result.hasSteps)
        XCTAssertFalse(result.connectionAccepted)
        XCTAssertFalse(stepsRead)
        XCTAssertFalse(connectionRead)
    }

    func testValuesPreserveKeysAndFormatting() {
        let values = HomeSpeechInputResolver.values(
            hasStepsData: true,
            rawSteps: 42,
            rawSleepHours: 7.25,
            sleepDurationUnit: "unit"
        )

        XCTAssertEqual(values["steps"], 42.formatted())
        XCTAssertEqual(values["sleepDuration"], String(format: "%.1f %@", 7.25, "unit"))
        XCTAssertEqual(values.count, 2)
    }

    func testValuesOmitUnavailableAndNonpositiveMeasurementsLazily() {
        var stepsRead = false
        var unitRead = false

        let values = HomeSpeechInputResolver.values(
            hasStepsData: false,
            rawSteps: read(&stepsRead, value: 42),
            rawSleepHours: 0,
            sleepDurationUnit: read(&unitRead, value: "unit")
        )

        XCTAssertTrue(values.isEmpty)
        XCTAssertFalse(stepsRead)
        XCTAssertFalse(unitRead)
    }

    private func facts(
        hasStepsData: Bool,
        rawSteps: Int,
        rawSleepHours: Double
    ) -> PiboHomeSpeechFacts {
        HomeSpeechInputResolver.facts(
            hasStepsData: hasStepsData,
            rawSteps: rawSteps,
            rawSleepHours: rawSleepHours,
            hasWorkoutToday: true,
            pendingBoCount: 3,
            cooperationEnabled: true,
            connectionAccepted: true
        )
    }

    private func read<T>(_ didRead: inout Bool, value: T) -> T {
        didRead = true
        return value
    }
}
