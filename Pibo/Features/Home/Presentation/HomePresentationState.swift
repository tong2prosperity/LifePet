import Observation
import SwiftUI

/// What the meal camera reopens after its on-demand login succeeds.
enum CameraLoginResume: Equatable {
    /// The corner camera asked before the meal picker.
    case mealSelection
    /// A queued camera request (e.g. 重拍) asked with its meal.
    case camera(MealType?)
}

/// Owns every presentation slot attached to Home. Product availability remains
/// outside this type; the gated bindings preserve each existing presentation
/// contract while sheets share one exclusive destination.
@MainActor
@Observable
final class HomePresentationState {
    var showCamera = false
    var showGames = false
    var showHistory = false
    var showSettings = false
    var showStoryRecovery = false
    var storyRecoveryDismissed = false
    /// Card the history cover should land on. Set only by the stress-notification
    /// deep link; the 足迹 icon opens with `nil` (top of the 足迹 tab).
    var historyFocus: HistoryFocus?
    /// Date the history cover should land on. Set by the stress-notification
    /// deep link if the alert arrived with a date timestamp.
    var historyInitialDate: Date?
    var showWalkDoodle = false
    /// A meal passed by the detail sheet's “重拍” action. Normal home entry leaves
    /// this nil and lets the camera own purpose + meal selection.
    var cameraInitialMeal: MealType?
    /// A camera request made from inside a sheet. It is consumed only after the
    /// sheet dismissal finishes so SwiftUI never has to overlap two presenters.
    var queuedCameraMeal: MealType?
    var activeSheet: HomeSheetDestination?
    /// On-demand login (2026-09-28). Only the meal camera needs an account.
    var showLogin = false
    var loginPurpose: LoginPurpose = .account
    var cameraResumeAfterLogin: CameraLoginResume?
    /// A verified meal can finish while the full-screen camera still covers the
    /// forest. Keep it prepared until camera dismissal so the 6.08 s performance
    /// never elapses invisibly behind the cover.
    var pendingFoodProjection: HomeFoodProjection?
    var foodProjection: HomeFoodProjection?
    /// Verified capture result waits here through competing sheets/covers, consumed only on presentation.
    private(set) var pendingMealResult: HomeSheetDestination?
    var transientNotice: String?
    /// `activeSheet` becomes nil at the start of dismissal, while its pixels are
    /// still covering Home. Pending feedback waits for `onDismiss` before it can
    /// claim the presentation slot.
    var sheetDismissalInProgress = false

    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        transientNotice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.transientNotice == text else { return }
            self?.transientNotice = nil
        }
    }

    func cameraBinding(isEnabled: Bool) -> Binding<Bool> {
        Binding(
            get: { self.showCamera && isEnabled },
            set: { self.showCamera = $0 && isEnabled }
        )
    }

    func gamesBinding(isEnabled: Bool) -> Binding<Bool> {
        Binding(
            get: { self.showGames && isEnabled },
            set: { self.showGames = $0 }
        )
    }

    func walkDoodleBinding(isEnabled: Bool) -> Binding<Bool> {
        Binding(
            get: { self.showWalkDoodle && isEnabled },
            set: { self.showWalkDoodle = $0 && isEnabled }
        )
    }

    var historyBinding: Binding<Bool> {
        Binding(get: { self.showHistory }, set: { self.showHistory = $0 })
    }

    var settingsBinding: Binding<Bool> {
        Binding(get: { self.showSettings }, set: { self.showSettings = $0 })
    }

    var loginBinding: Binding<Bool> {
        Binding(get: { self.showLogin }, set: { self.showLogin = $0 })
    }

    var storyRecoveryBinding: Binding<Bool> {
        Binding(
            get: { self.showStoryRecovery },
            set: { self.showStoryRecovery = $0 }
        )
    }

    var sheetBinding: Binding<HomeSheetDestination?> {
        Binding(
            get: { self.activeSheet },
            set: { self.activeSheet = $0 }
        )
    }

    func completeStoryRecovery() {
        showStoryRecovery = false
        storyRecoveryDismissed = true
    }

    func queueCameraAfterSheet(_ meal: MealType) {
        queuedCameraMeal = meal
        activeSheet = nil
    }

    /// The corner camera opens directly; meal metadata belongs to the captured result.
    func openMealCapture(isLoggedIn: Bool) {
        guard isLoggedIn else {
            requestCameraLogin(resume: .camera(nil))
            return
        }
        cameraInitialMeal = nil
        showCamera = true
    }

    /// Consumes a camera request queued behind a closing sheet. Without an
    /// account it becomes a login request that resumes with the same meal.
    @discardableResult
    func presentQueuedCameraIfNeeded(isLoggedIn: Bool) -> Bool {
        guard let meal = queuedCameraMeal else { return false }
        queuedCameraMeal = nil
        guard isLoggedIn else {
            requestCameraLogin(resume: .camera(meal))
            return true
        }
        cameraInitialMeal = meal
        showCamera = true
        return true
    }

    /// The user left the login page without an account; forget the camera.
    func cancelLogin() {
        cameraResumeAfterLogin = nil
        showLogin = false
    }

    /// Runs from the login cover's `onDismiss`, after its pixels are gone, so
    /// the camera or picker never has to overlap it. Only a real login resumes.
    func resumeAfterLogin(isLoggedIn: Bool) {
        let resume = cameraResumeAfterLogin
        cameraResumeAfterLogin = nil
        guard isLoggedIn, let resume else { return }
        switch resume {
        case .mealSelection:
            cameraInitialMeal = nil
            showCamera = true
        case .camera(let meal):
            cameraInitialMeal = meal
            showCamera = true
        }
    }

    /// Logout or an expired session closes only what needs an account; Home,
    /// Settings and everything local stay where the user left them.
    func closeAccountSurfacesForSessionEnd() {
        showLogin = false
        showCamera = false
        cameraResumeAfterLogin = nil
        cameraInitialMeal = nil
        queuedCameraMeal = nil
        pendingFoodProjection = nil
        foodProjection = nil
        pendingMealResult = nil
        switch activeSheet {
        case .shadow, .mealCaptureSelection: activeSheet = nil
        default: break
        }
    }

    func openAccountLogin() {
        cameraResumeAfterLogin = nil
        loginPurpose = .account
        showLogin = true
    }

    private func requestCameraLogin(resume: CameraLoginResume) {
        cameraResumeAfterLogin = resume
        loginPurpose = .mealCamera
        showLogin = true
    }

    func prepareFoodProjection(_ projection: HomeFoodProjection) {
        pendingMealResult = .meal(projection.meal, photoId: projection.id.uuidString)
        if showCamera {
            pendingFoodProjection = projection
        } else {
            foodProjection = projection
        }
    }

    @discardableResult
    func presentPendingMealResultIfPossible(canPresent: Bool) -> Bool {
        guard canPresent, !showCamera, !showLogin, !showHistory, !showSettings,
              !showGames, !showWalkDoodle, !showStoryRecovery,
              !sheetDismissalInProgress, activeSheet == nil,
              pendingFoodProjection == nil, foodProjection == nil,
              let result = pendingMealResult else { return false }
        activeSheet = result
        pendingMealResult = nil
        return true
    }

    func presentPreparedFoodProjection() {
        guard let projection = pendingFoodProjection else { return }
        pendingFoodProjection = nil
        foodProjection = projection
    }
}
