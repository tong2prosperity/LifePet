import SwiftUI

/// Owns Home's sheet attachment and destination construction. The active slot
/// and all business mutations remain supplied by `HomeView`.
@MainActor
struct HomeSheetModifier: ViewModifier {
    let destination: Binding<HomeSheetDestination?>
    let store: PetStateStore
    let history: HealthHistoryStore
    let recognizer: FoodRecognitionService
    let morningSleep: MorningSleepCoordinator
    let onDismiss: () -> Void
    let replayWalkEcho: (WalkDoodleRecord) -> Void
    let startMealCapture: (MealType) -> Void
    let confirmAchievement: (PiboAnimationAchievementPayload) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: destination, onDismiss: onDismiss) { destination in
                sheetContent(destination)
            }
    }

    @ViewBuilder
    private func sheetContent(_ destination: HomeSheetDestination) -> some View {
        switch destination {
        case .mealCaptureSelection:
            MealCaptureSelectionSheet(onSelect: startMealCapture)
        case .meal(let meal):
            MealDetailView(meal: meal, onRecapture: startMealCapture)
                .environment(history)
                .environment(recognizer)
        case .morningSleep(let presentation, let consumesPending):
            MorningSleepCard(
                presentation: presentation,
                appearance: store.appearance,
                weekly: SleepWeeklyReport.make(store: store, history: history)
            )
            .onAppear {
                if consumesPending { morningSleep.markPresented(presentation) }
            }
        case .commonItemStatus(let model):
            CommonItemStatusModal(
                ornamentID: model.ornamentID,
                title: model.title,
                status: model.status,
                message: model.message
            )
        case .achievement(let payload):
            PiboAchievementModal(payload: payload) { confirmAchievement(payload) }
                .interactiveDismissDisabled()
        case .ornamentUnlock(let id):
            OrnamentAwakeningSheet(ornamentID: id)
        case .chimeEcho:
            ChimeEchoSheet(
                petID: store.identity.currentPetId,
                history: history,
                onReplay: replayWalkEcho
            )
        case .healthDataStatus:
            HealthDataStatusSheet()
        case .shadow(let manifest):
            ShadowFriendSheet(ownerName: store.ownerName, manifestMode: manifest)
        }
    }
}
