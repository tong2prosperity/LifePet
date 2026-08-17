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
    var activeSheet: HomeSheetDestination?
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
}
