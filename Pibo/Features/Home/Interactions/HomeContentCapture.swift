import UIKit

/// Adapts Home's camera and Walk Doodle callbacks to their focused
/// coordinators. Availability, persistence order, and asynchronous presentation
/// timing remain owned by those coordinators.
@MainActor
struct HomeContentCapture {
    let currentCameraEnabled: () -> Bool
    let presentation: HomePresentationState
    let history: HealthHistoryStore
    let recognizer: FoodRecognitionService
    let speech: PiboSpeechService
    let presentMeal: (MealType) -> Void
    let showSpeech: (PiboSpeech) -> Void

    func startMealCapture(_ meal: MealType) {
        HomeCameraPresentationCoordinator.openIfEnabled(
            meal: meal,
            isEnabled: currentCameraEnabled(),
            presentation: presentation
        )
    }

    func handleSavedPhoto(
        _ image: UIImage?,
        _ subjectLabel: String?,
        meal: MealType? = nil
    ) {
        HomePhotoSaveCoordinator.handleSavedPhoto(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            clearInitialMeal: { presentation.cameraInitialMeal = nil },
            history: history,
            recognizer: recognizer,
            isCameraPresented: { presentation.showCamera },
            presentMeal: presentMeal
        )
    }

    /// Walk Doodle is persisted content and authored reaction, never a `bo`
    /// source.
    func handleSavedDoodle(_ result: WalkDoodleResult) {
        HomeWalkDoodleSaveCoordinator.run(
            result: result,
            history: history,
            speech: speech,
            show: showSpeech
        )
    }
}
