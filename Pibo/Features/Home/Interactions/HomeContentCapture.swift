import UIKit

/// Adapts Home's camera and Walk Doodle callbacks to their focused
/// coordinators. Availability, persistence order, and asynchronous presentation
/// timing remain owned by those coordinators.
@MainActor
struct HomeContentCapture {
    let currentCameraEnabled: () -> Bool
    let presentation: HomePresentationState
    let history: HealthHistoryStore
    let ledger: BoLedgerStore
    let walkDoodleProgress: WalkDoodleProgressStore
    let recognizer: FoodRecognitionService
    let speech: PiboSpeechService
    let showSpeech: (PiboSpeech) -> Void

    func startMealCapture(_ meal: MealType) {
        HomeCameraPresentationCoordinator.openIfEnabled(
            meal: meal,
            isEnabled: currentCameraEnabled(),
            presentation: presentation
        )
    }

    func savePhoto(
        _ image: UIImage?,
        _ subjectLabel: String?,
        meal: MealType? = nil
    ) async -> HomePhotoSaveCoordinator.Outcome {
        await HomePhotoSaveCoordinator.handleSavedPhoto(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            clearInitialMeal: { presentation.cameraInitialMeal = nil },
            history: history,
            recognizer: recognizer,
            presentProjection: { projection in
                presentation.prepareFoodProjection(projection)
            },
            presentFailure: { _ in }
        )
    }

    /// DEBUG automation keeps a synchronous callback surface while exercising
    /// the same verified-food path as the real camera.
    func handleSavedPhoto(
        _ image: UIImage?,
        _ subjectLabel: String?,
        meal: MealType? = nil
    ) {
        Task {
            let outcome = await savePhoto(image, subjectLabel, meal: meal)
            switch outcome {
            case .saved:
                if !presentation.showCamera {
                    presentation.presentPreparedFoodProjection()
                }
            case .notFood:
                presentation.showNotice(AppLocalization.text("照片里没有识别到餐食，请重新拍摄。"))
            case .failed:
                presentation.showNotice(AppLocalization.text("餐食识别没有完成，请再试一次。"))
            }
        }
    }

    func cameraDismissed() {
        presentation.presentPreparedFoodProjection()
    }

    /// A completed task is persisted before its authored reaction. Any Core-
    /// granted bonus reaches the normal `bo` pool through an idempotent outbox.
    func handleSavedDoodle(_ result: WalkDoodleCompletionResult) {
        HomeWalkDoodleSaveCoordinator.run(
            result: result,
            history: history,
            ledger: ledger,
            progress: walkDoodleProgress,
            speech: speech,
            show: showSpeech
        )
    }
}
