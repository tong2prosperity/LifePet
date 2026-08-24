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
    let showLine: (PiboSpeechLine) -> Void

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
            presentProjection: { projection in
                presentation.foodProjection = projection
                showLine(PiboSpeechLine(text: AppLocalization.text("我看看。")))
            },
            presentFailure: { failure in
                let message = switch failure {
                case .saving:
                    AppLocalization.text("这次没有保存下来，请再试一次。")
                case .recognition:
                    AppLocalization.text("没有识别成功，照片仍然留在足迹里。")
                }
                presentation.showNotice(message)
            }
        )
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
