import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct HomePresentationFlowTests {
    @Test func achievementPresentationDelegatesToTheForestWithoutOpeningASheet() {
        let suiteName = "HomePresentationFlowTests.blocked"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PetStateStore(demoMode: true)
        let presentation = HomePresentationState()
        var events: [String] = []
        let flow = HomePresentationFlow(
            presentation: presentation,
            store: store,
            ornamentUnlocks: OrnamentUnlockStore(
                defaults: defaults,
                debugUnlockOverride: false
            ),
            morningSleep: MorningSleepCoordinator(defaults: defaults),
            stressNotifier: .shared,
            currentPolicy: {
                events.append("policy")
                return blockedPolicy
            },
            presentForestResponse: { events.append("forest") },
            refreshAnimationState: { events.append("refresh") },
            announceFirstRipeBo: { events.append("announce") }
        )

        flow.presentAchievementIfPossible()

        #expect(events == ["forest"])
        #expect(presentation.activeSheet == nil)
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
