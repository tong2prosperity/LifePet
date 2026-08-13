import SwiftUI
import Testing
@testable import Pibo

@MainActor
struct HomeFeaturePresentationStateTests {
    @Test func startsWithEveryDestinationDismissed() {
        let state = HomeFeaturePresentationState()

        #expect(!state.showCamera)
        #expect(!state.showGames)
        #expect(!state.showHistory)
        #expect(!state.showSettings)
        #expect(!state.showStoryRecovery)
        #expect(!state.storyRecoveryDismissed)
        #expect(!state.showWalkDoodle)
        #expect(state.historyFocus == nil)
        #expect(state.cameraInitialMeal == nil)
    }

    @Test func cameraBindingRequiresAvailabilityInBothDirections() {
        let state = HomeFeaturePresentationState()
        state.showCamera = true

        let disabled = state.cameraBinding(isEnabled: false)

        #expect(!disabled.wrappedValue)
        disabled.wrappedValue = true
        #expect(!state.showCamera)

        let enabled = state.cameraBinding(isEnabled: true)
        enabled.wrappedValue = true
        #expect(state.showCamera)
        #expect(enabled.wrappedValue)
        enabled.wrappedValue = false
        #expect(!state.showCamera)
    }

    @Test func walkDoodleBindingKeepsTheSameAvailabilityGate() {
        let state = HomeFeaturePresentationState()
        state.showWalkDoodle = true

        let disabled = state.walkDoodleBinding(isEnabled: false)

        #expect(!disabled.wrappedValue)
        disabled.wrappedValue = true
        #expect(!state.showWalkDoodle)
    }

    @Test func gamesBindingPreservesItsUngatedSetter() {
        let state = HomeFeaturePresentationState()
        let disabled = state.gamesBinding(isEnabled: false)

        disabled.wrappedValue = true

        #expect(state.showGames)
        #expect(!disabled.wrappedValue)
        #expect(state.gamesBinding(isEnabled: true).wrappedValue)
    }

    @Test func directFeatureBindingsRoundTripWithoutExtraMutation() {
        let state = HomeFeaturePresentationState()
        state.historyFocus = .stress
        state.storyRecoveryDismissed = true

        state.historyBinding.wrappedValue = true
        state.settingsBinding.wrappedValue = true
        state.storyRecoveryBinding.wrappedValue = true

        #expect(state.showHistory)
        #expect(state.showSettings)
        #expect(state.showStoryRecovery)
        #expect(state.historyFocus == .stress)
        #expect(state.storyRecoveryDismissed)
    }
}
