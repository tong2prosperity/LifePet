import Foundation
import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeMorningSleepPresentationCoordinatorTests {
    @Test func eligiblePresentationBecomesAConsumableWakeSheet() throws {
        let presentation = morningSleepPresentation()
        var destination: HomeSheetDestination?

        HomeMorningSleepPresentationCoordinator.presentIfPossible(
            policy: policy(),
            sleepReviewGranted: true,
            consumablePresentation: presentation,
            destination: &destination
        )

        let presented = try #require(destination)
        guard case .morningSleep(let value, let consumesPending) = presented else {
            Issue.record("Expected a morning sleep destination")
            return
        }
        #expect(value == presentation)
        #expect(consumesPending)
    }

    @Test func inactiveHomeLeavesAuthorizationAndPresentationUnread() {
        let reads = ReadLog()
        var destination: HomeSheetDestination?

        HomeMorningSleepPresentationCoordinator.presentIfPossible(
            policy: policy(sceneIsActive: false),
            sleepReviewGranted: reads.value(true, named: "grant"),
            consumablePresentation: reads.value(
                morningSleepPresentation(),
                named: "presentation"
            ),
            destination: &destination
        )

        #expect(destination == nil)
        #expect(reads.names == [])
    }

    @Test func deniedReviewLeavesConsumablePresentationUnread() {
        let reads = ReadLog()
        var destination: HomeSheetDestination?

        HomeMorningSleepPresentationCoordinator.presentIfPossible(
            policy: policy(),
            sleepReviewGranted: reads.value(false, named: "grant"),
            consumablePresentation: reads.value(
                morningSleepPresentation(),
                named: "presentation"
            ),
            destination: &destination
        )

        #expect(destination == nil)
        #expect(reads.names == ["grant"])
    }

    private func policy(sceneIsActive: Bool = true) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: sceneIsActive,
            cameraPresented: false,
            gamesPresented: false,
            historyPresented: false,
            walkDoodlePresented: false,
            settingsPresented: false,
            storyRecoveryPresented: false,
            sheetPresented: false,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )
    }

    private func morningSleepPresentation() -> MorningSleepPresentation {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let total: TimeInterval = 7 * 3_600
        return MorningSleepPresentation(
            summary: MorningSleepSummary(
                wakeDay: Calendar.current.startOfDay(for: end),
                generatedAt: end,
                start: end.addingTimeInterval(-total),
                end: end,
                total: total,
                core: total,
                deep: 0,
                rem: 0,
                awake: 0,
                segments: [],
                hasDetailedStages: true,
                hasInBedSignal: true,
                hasTerminalAwakeSignal: true,
                awakeningCount: nil,
                continuity: nil,
                baselineDelta: nil,
                overnightHRV: nil,
                sleepingWristTemperature: nil,
                sleepingWristTemperatureDelta: nil,
                respiratoryRate: nil,
                oxygenSaturation: nil,
                sleepHeartRateAverage: nil,
                sleepHeartRateMin: nil,
                sleepLatency: nil
            ),
            isSettled: true,
            isCatchUp: false
        )
    }
}

private final class ReadLog {
    private(set) var names: [String] = []

    func value<Value>(_ value: Value, named name: String) -> Value {
        names.append(name)
        return value
    }
}
