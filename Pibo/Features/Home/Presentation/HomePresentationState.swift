import Observation
import SwiftUI

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
    var showWalkDoodle = false
    /// A meal passed by the detail sheet's “重拍” action. Normal home entry leaves
    /// this nil and lets the camera own purpose + meal selection.
    var cameraInitialMeal: MealType?
    /// A camera request made from inside a sheet. It is consumed only after the
    /// sheet dismissal finishes so SwiftUI never has to overlap two presenters.
    var queuedCameraMeal: MealType?
    var activeSheet: HomeSheetDestination?
    /// A verified meal can finish while the full-screen camera still covers the
    /// forest. Keep it prepared until camera dismissal so the 6.08 s performance
    /// never elapses invisibly behind the cover.
    var pendingFoodProjection: HomeFoodProjection?
    var foodProjection: HomeFoodProjection?
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

    @discardableResult
    func presentQueuedCameraIfNeeded() -> Bool {
        guard let meal = queuedCameraMeal else { return false }
        queuedCameraMeal = nil
        cameraInitialMeal = meal
        showCamera = true
        return true
    }

    func prepareFoodProjection(_ projection: HomeFoodProjection) {
        if showCamera {
            pendingFoodProjection = projection
        } else {
            foodProjection = projection
        }
    }

    func presentPreparedFoodProjection() {
        guard let projection = pendingFoodProjection else { return }
        pendingFoodProjection = nil
        foodProjection = projection
    }
}
