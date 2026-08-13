import Observation
import SwiftUI

/// Owns Home's feature-navigation state. Product availability remains outside
/// this type; the gated bindings preserve each existing presentation contract.
@MainActor
@Observable
final class HomeFeaturePresentationState {
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
}
