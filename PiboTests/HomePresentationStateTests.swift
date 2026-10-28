import Foundation
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

        #expect(state.presentQueuedCameraIfNeeded(isLoggedIn: true))
        #expect(state.cameraInitialMeal == .lunch)
        #expect(state.showCamera)
        #expect(state.queuedCameraMeal == nil)
        #expect(!state.presentQueuedCameraIfNeeded(isLoggedIn: true))
    }

    // MARK: On-demand login (2026-09-28)

    @Test func cornerCameraOpensCameraWithoutMealQuestion() {
        let state = HomePresentationState()

        state.openMealCapture(isLoggedIn: true)

        #expect(state.activeSheet == nil)
        #expect(state.showCamera)
        #expect(!state.showLogin)
    }

    @Test func cornerCameraAsksForAccountThenResumesCamera() {
        let state = HomePresentationState()

        state.openMealCapture(isLoggedIn: false)

        #expect(state.activeSheet == nil)
        #expect(state.showLogin)
        #expect(state.loginPurpose == .mealCamera)
        #expect(state.cameraResumeAfterLogin == .camera(nil))

        state.showLogin = false
        state.resumeAfterLogin(isLoggedIn: true)

        #expect(state.activeSheet == nil)
        #expect(state.showCamera)
        #expect(state.cameraResumeAfterLogin == nil)
    }

    @Test func queuedRetakeWithoutAccountResumesTheSameMealAfterLogin() {
        let state = HomePresentationState()
        state.queueCameraAfterSheet(.dinner)

        #expect(state.presentQueuedCameraIfNeeded(isLoggedIn: false))
        #expect(!state.showCamera)
        #expect(state.showLogin)
        #expect(state.cameraResumeAfterLogin == .camera(.dinner))

        state.showLogin = false
        state.resumeAfterLogin(isLoggedIn: true)

        #expect(state.showCamera)
        #expect(state.cameraInitialMeal == .dinner)
    }

    @Test func voluntaryAccountLoginDoesNotOpenCameraAfterSuccess() {
        let state = HomePresentationState()
        state.cameraResumeAfterLogin = .camera(.lunch)
        state.openAccountLogin()
        #expect(state.loginPurpose == .account)
        #expect(state.cameraResumeAfterLogin == nil)
        state.showLogin = false
        state.resumeAfterLogin(isLoggedIn: true)
        #expect(!state.showCamera)
        #expect(state.activeSheet == nil)
    }

    @Test func closingLoginForgetsTheCamera() {
        let state = HomePresentationState()
        state.openMealCapture(isLoggedIn: false)

        state.cancelLogin()
        state.resumeAfterLogin(isLoggedIn: false)

        #expect(!state.showLogin)
        #expect(state.activeSheet == nil)
        #expect(!state.showCamera)
        #expect(state.cameraResumeAfterLogin == nil)
    }

    @Test func dismissalWithoutLoginNeverOpensTheCamera() {
        let state = HomePresentationState()
        state.queueCameraAfterSheet(.lunch)
        _ = state.presentQueuedCameraIfNeeded(isLoggedIn: false)

        state.showLogin = false
        state.resumeAfterLogin(isLoggedIn: false)

        #expect(!state.showCamera)
        #expect(state.cameraResumeAfterLogin == nil)
    }

    @Test func sessionEndCancelsOpenAndQueuedCaptureWithoutClosingLocalSettings() {
        let state = HomePresentationState()
        state.showSettings = true
        state.showCamera = true
        state.cameraInitialMeal = .lunch
        state.queuedCameraMeal = .dinner
        state.activeSheet = .mealCaptureSelection
        state.pendingFoodProjection = HomeFoodProjection(
            id: UUID(), pngData: Data([1]), meal: .lunch,
            dishName: "午餐", observation: "先记下来。", isCutout: false)
        state.closeAccountSurfacesForSessionEnd()
        #expect(!state.showCamera)
        #expect(state.showSettings)
        #expect(state.cameraInitialMeal == nil)
        #expect(state.queuedCameraMeal == nil)
        #expect(state.pendingFoodProjection == nil)
        #expect(state.activeSheet == nil)
        #expect(!state.presentQueuedCameraIfNeeded(isLoggedIn: false))
    }

    @Test func sessionEndClosesOnlyAccountSurfaces() {
        let state = HomePresentationState()
        state.showSettings = true
        state.showLogin = true
        state.cameraResumeAfterLogin = .mealSelection
        state.activeSheet = .shadow(manifest: false)

        state.closeAccountSurfacesForSessionEnd()

        #expect(state.showSettings)
        #expect(!state.showLogin)
        #expect(state.cameraResumeAfterLogin == nil)
        #expect(state.activeSheet == nil)

        state.activeSheet = .healthDataStatus
        state.closeAccountSurfacesForSessionEnd()
        #expect(state.activeSheet == .healthDataStatus)
    }
}
