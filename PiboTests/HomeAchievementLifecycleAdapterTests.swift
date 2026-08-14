import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeAchievementLifecycleAdapterTests {
    @Test func blockedPresentationReadsPolicyBeforeSheetAndKeepsInputsLazy() {
        let store = PetStateStore(demoMode: true)
        var destination: HomeSheetDestination?
        var events: [String] = []
        let adapter = HomeAchievementLifecycleAdapter(
            store: store,
            currentPolicy: {
                events.append("policy")
                return blockedPolicy
            },
            currentAnimationStateID: {
                events.append("animation")
                return "default"
            },
            withSheet: { update in
                events.append("sheet")
                update(&destination)
            },
            dismissSheet: { events.append("dismiss") },
            applyDebugReward: { _ in events.append("debug-reward") },
            refreshAnimationState: { events.append("refresh") },
            beginSheetDismissal: { events.append("begin-dismissal") }
        )

        adapter.presentIfPossible()

        #expect(events == ["policy", "sheet"])
        #expect(destination == nil)
    }

    private var blockedPolicy: HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: false,
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
