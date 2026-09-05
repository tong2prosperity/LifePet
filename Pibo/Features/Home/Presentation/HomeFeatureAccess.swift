import PiboCore
import SwiftUI

/// Resolves Home's release scope and the remaining common-item gates once, then
/// exposes presentation bindings through the same availability decisions.
/// The base meal camera is intentionally release-gated only: it is part of the
/// first-day experience and no longer waits for the chime entitlement.
@MainActor
struct HomeFeatureAccess {
    let presentation: HomePresentationState
    let cameraEnabled: Bool
    let walkDoodleEnabled: Bool
    let walkDoodleRouteEchoEnabled: Bool
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
        cameraEnabled = cameraReleased
        // 散步涂鸦 is a release capability, not an item gate. The chime grants
        // the deeper three-part route echo instead of hiding the whole task.
        walkDoodleEnabled = walkDoodleReleased
        walkDoodleRouteEchoEnabled = ornamentUnlocks.grants(.walkEchoCollection)
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
