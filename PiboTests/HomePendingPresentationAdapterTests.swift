import Testing
@testable import Pibo

@Suite
@MainActor
struct HomePendingPresentationAdapterTests {
    @Test func blockedMorningPresentationReadsPolicyBeforeSheetAndKeepsInputsLazy() {
        var events: [String] = []
        var destination: HomeSheetDestination?
        let adapter = makeAdapter(
            policy: {
                events.append("policy")
                return Self.policy(sceneIsActive: false)
            },
            withSheet: { update in
                events.append("sheet")
                update(&destination)
            },
            sleepReviewGranted: {
                events.append("grant")
                return true
            },
            morningSleepPresentation: {
                events.append("presentation")
                return nil
            }
        )

        adapter.presentMorningSleepIfPossible()

        #expect(events == ["policy", "sheet"])
        #expect(destination == nil)
    }

    @Test func eligibleStressRequestPreservesClearFocusPresentOrder() {
        var events: [String] = []
        let adapter = makeAdapter(
            policy: {
                events.append("policy")
                return Self.policy()
            },
            pendingStressCardOpen: {
                events.append("pending")
                return true
            },
            stressHandlers: .init(
                clearPendingRequest: { events.append("clear") },
                focusStressCard: { events.append("focus") },
                presentHistory: { events.append("present") }
            )
        )

        adapter.presentStressCardIfPossible()

        #expect(events == ["policy", "pending", "clear", "focus", "present"])
    }

    @Test func occupiedSheetStopsResumeAfterAchievementAttempt() {
        var events: [String] = []
        let adapter = makeAdapter(
            policy: { Self.policy() },
            clearSheetDismissal: { events.append("clear-dismissal") },
            presentAchievement: { events.append("achievement") },
            sheetIsAbsent: {
                events.append("sheet")
                return false
            }
        )

        adapter.resumePendingFlows()

        #expect(events == ["clear-dismissal", "achievement", "sheet"])
    }

    private func makeAdapter(
        policy: @escaping () -> HomePresentationPolicy,
        withSheet: @escaping HomePendingPresentationAdapter.SheetMutation = { _ in },
        sleepReviewGranted: @escaping () -> Bool = { false },
        morningSleepPresentation: @escaping () -> MorningSleepPresentation? = { nil },
        pendingStressCardOpen: @escaping () -> Bool = { false },
        stressHandlers: HomeStressCardPresentationCoordinator.Handlers = .init(
            clearPendingRequest: {},
            focusStressCard: {},
            presentHistory: {}
        ),
        clearSheetDismissal: @escaping () -> Void = {},
        presentAchievement: @escaping () -> Void = {},
        sheetIsAbsent: @escaping () -> Bool = { true }
    ) -> HomePendingPresentationAdapter {
        HomePendingPresentationAdapter(
            currentPolicy: policy,
            currentSleepReviewGranted: sleepReviewGranted,
            currentMorningSleepPresentation: morningSleepPresentation,
            withSheet: withSheet,
            currentPendingStressCardOpen: pendingStressCardOpen,
            stressHandlers: stressHandlers,
            clearSheetDismissal: clearSheetDismissal,
            presentAchievement: presentAchievement,
            sheetIsAbsent: sheetIsAbsent,
            announceFirstRipeBo: {}
        )
    }

    private static func policy(
        sceneIsActive: Bool = true
    ) -> HomePresentationPolicy {
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
}
