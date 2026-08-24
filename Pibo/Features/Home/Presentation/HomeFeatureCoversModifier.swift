import SwiftUI
import UIKit

/// Keeps Home's full-screen feature destinations and their environment wiring
/// together. Presentation policy and dismissal choreography remain owned by
/// `HomeView` and arrive through the existing bindings and callbacks.
@MainActor
struct HomeFeatureCoversModifier: ViewModifier {
    let presentation: HomePresentationState
    let cameraPresented: Binding<Bool>
    let gamesPresented: Binding<Bool>
    let walkDoodlePresented: Binding<Bool>
    let walkDoodleEnabled: Bool
    let walkDoodleRouteEchoEnabled: Bool
    let store: PetStateStore
    let history: HealthHistoryStore
    let resumePendingFlows: () -> Void
    let historyDismissed: () -> Void
    let photoSaved: (UIImage?, String?, MealType?) -> Void
    let doodleSaved: (WalkDoodleCompletionResult) -> Void

    func body(content: Content) -> some View {
        content
            // Participating feature flows resume from `onDismiss`, once the
            // dismissal animation has finished. Watching a binding instead can
            // race the outgoing modal and make SwiftUI drop the next one.
            .fullScreenCover(
                isPresented: cameraPresented,
                onDismiss: resumePendingFlows
            ) {
                PiboCameraView(
                    initialMeal: presentation.cameraInitialMeal,
                    onPhotoSaved: photoSaved
                )
                .environment(store)
            }
            .fullScreenCover(
                isPresented: gamesPresented,
                onDismiss: resumePendingFlows
            ) {
                GameListView(
                    walkDoodleEnabled: walkDoodleEnabled,
                    walkDoodleRouteEchoEnabled: walkDoodleRouteEchoEnabled,
                    onWalkDoodleSaved: doodleSaved
                )
                .environment(store)
                .environment(history)
            }
            .fullScreenCover(
                isPresented: presentation.historyBinding,
                onDismiss: historyDismissed
            ) {
                HistoryScreen(focus: presentation.historyFocus)
                    .environment(store)
                    .environment(history)
            }
            .fullScreenCover(isPresented: presentation.storyRecoveryBinding) {
                HealthAuthView(mode: .storyRecovery) {
                    presentation.completeStoryRecovery()
                }
            }
            .fullScreenCover(
                isPresented: walkDoodlePresented,
                onDismiss: resumePendingFlows
            ) {
                WalkDoodleView(
                    routeEchoEnabled: walkDoodleRouteEchoEnabled,
                    onSaved: doodleSaved
                )
            }
    }
}
