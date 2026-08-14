import PiboCore
import SwiftUI

/// Resolves Home's release-scope and common-item gates once, then exposes the
/// existing presentation bindings through the same availability decisions.
@MainActor
struct HomeFeatureAccess {
    let presentation: HomePresentationState
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let miniGamesEnabled: Bool

    init(
        presentation: HomePresentationState,
        ornamentUnlocks: OrnamentUnlockStore
    ) {
        self.init(
            presentation: presentation,
            ornamentUnlocks: ornamentUnlocks,
            cameraReleased: PiboReleaseScope.camera,
            walkDoodleReleased: PiboReleaseScope.walkDoodle,
            miniGamesReleased: PiboReleaseScope.miniGames
        )
    }

    init(
        presentation: HomePresentationState,
        ornamentUnlocks: OrnamentUnlockStore,
        cameraReleased: Bool,
        walkDoodleReleased: Bool,
        miniGamesReleased: Bool
    ) {
        self.presentation = presentation
        cameraEnabled = cameraReleased && ornamentUnlocks.grants(.dewCamera)
        walkDoodleEnabled = walkDoodleReleased
            && ornamentUnlocks.grants(.walkDoodle)
        miniGamesEnabled = miniGamesReleased
    }

    var cameraPresented: Binding<Bool> {
        presentation.cameraBinding(isEnabled: cameraEnabled)
    }

    var gamesPresented: Binding<Bool> {
        presentation.gamesBinding(isEnabled: miniGamesEnabled)
    }

    var walkDoodlePresented: Binding<Bool> {
        presentation.walkDoodleBinding(isEnabled: walkDoodleEnabled)
    }
}
