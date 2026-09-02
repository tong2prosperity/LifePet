import SwiftUI
import Testing
@testable import Pibo

@MainActor
struct HomePresentationStateTests {
    @Test func cameraBindingRequiresAvailabilityInBothDirections() {
        let state = HomePresentationState()
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
        let state = HomePresentationState()
        state.showWalkDoodle = true

        let disabled = state.walkDoodleBinding(isEnabled: false)

        #expect(!disabled.wrappedValue)
        disabled.wrappedValue = true
        #expect(!state.showWalkDoodle)
    }

    @Test func gamesBindingPreservesItsUngatedSetter() {
        let state = HomePresentationState()
        let disabled = state.gamesBinding(isEnabled: false)

        disabled.wrappedValue = true

        #expect(state.showGames)
        #expect(!disabled.wrappedValue)
        #expect(state.gamesBinding(isEnabled: true).wrappedValue)
    }

    @Test func directFeatureBindingsRoundTripWithoutExtraMutation() {
        let state = HomePresentationState()
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

    @Test func completingStoryRecoveryDismissesAndRecordsTheChoice() {
        let state = HomePresentationState()
        state.showStoryRecovery = true

        state.completeStoryRecovery()

        #expect(!state.showStoryRecovery)
        #expect(state.storyRecoveryDismissed)
    }

    @Test func queuedCameraWaitsForSheetDismissalAndIsConsumedOnce() {
        let state = HomePresentationState()
        state.activeSheet = .mealCaptureSelection

        state.queueCameraAfterSheet(.lunch)

        #expect(state.activeSheet == nil)
        #expect(state.queuedCameraMeal == .lunch)
        #expect(!state.showCamera)

        #expect(state.presentQueuedCameraIfNeeded())
        #expect(state.cameraInitialMeal == .lunch)
        #expect(state.showCamera)
        #expect(state.queuedCameraMeal == nil)
        #expect(!state.presentQueuedCameraIfNeeded())
    }
}
