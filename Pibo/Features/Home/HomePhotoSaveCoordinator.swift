import Foundation
import UIKit
import os

/// Owns the asynchronous work that follows a successful Home camera capture.
/// Home keeps presentation state; this coordinator performs cut-out persistence
/// and, for meal captures, waits for the camera cover before starting analysis.
@MainActor
enum HomePhotoSaveCoordinator {
    struct SavedPhotoHandlers {
        let logSaved: () -> Void
        let clearInitialMeal: () -> Void
        let trackSaved: () -> Void
        let logMissingImage: () -> Void
        let process: (UIImage) -> Void
    }

    static func handleSavedPhoto(
        image: UIImage?,
        subjectLabel: String?,
        meal: MealType?,
        clearInitialMeal: @escaping () -> Void,
        history: HealthHistoryStore,
        recognizer: FoodRecognitionService,
        isCameraPresented: @escaping () -> Bool,
        presentMeal: @escaping (MealType) -> Void
    ) {
        handleSavedPhoto(
            image: image,
            handlers: SavedPhotoHandlers(
                logSaved: {
                    LPLog.cutout.notice(
                        "photo saved → post-processing (hasImage=\(image != nil, privacy: .public) label=\(subjectLabel ?? "—", privacy: .public) meal=\(meal?.rawValue ?? "—", privacy: .public))"
                    )
                },
                clearInitialMeal: clearInitialMeal,
                trackSaved: {
                    Analytics.track(
                        .photoSaved,
                        screen: "camera",
                        [
                            "meal": .string(meal?.rawValue ?? "none"),
                            "has_subject": .bool(subjectLabel != nil),
                        ]
                    )
                },
                logMissingImage: {
                    LPLog.cutout.info(
                        "no captured image (placeholder device) — skipping 抠图/persist"
                    )
                },
                process: { image in
                    Self.process(
                        image: image,
                        subjectLabel: subjectLabel,
                        meal: meal,
                        history: history,
                        recognizer: recognizer,
                        isCameraPresented: isCameraPresented,
                        presentMeal: presentMeal
                    )
                }
            )
        )
    }

    static func handleSavedPhoto(
        image: UIImage?,
        handlers: SavedPhotoHandlers
    ) {
        handlers.logSaved()
        handlers.clearInitialMeal()
        handlers.trackSaved()
        guard let image else {
            handlers.logMissingImage()
            return
        }
        handlers.process(image)
    }

    @discardableResult
    static func process(
        image: UIImage,
        subjectLabel: String?,
        meal: MealType?,
        history: HealthHistoryStore,
        recognizer: FoodRecognitionService,
        isCameraPresented: @escaping () -> Bool,
        presentMeal: @escaping (MealType) -> Void
    ) -> Task<Void, Never> {
        process(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            history: history,
            isCameraPresented: isCameraPresented,
            presentMeal: presentMeal,
            analyze: { photoID, fullImage, hint, meal in
                await recognizer.analyze(
                    photoID: photoID,
                    fullImage: fullImage,
                    hint: hint,
                    meal: meal,
                    history: history
                )
            }
        )
    }

    @discardableResult
    static func process(
        image: UIImage,
        subjectLabel: String?,
        meal: MealType?,
        history: HealthHistoryStore,
        isCameraPresented: @escaping () -> Bool,
        presentMeal: @escaping (MealType) -> Void,
        analyze: @escaping @MainActor (
            UUID,
            UIImage,
            String?,
            MealType
        ) async -> Void,
        makeStickerPNG: @escaping @Sendable (UIImage) -> Data? = {
            SubjectCutout.stickerPNG($0)
        }
    ) -> Task<Void, Never> {
        let capturedAt = Date()
        return Task {
            // Show the user the Vision-processed cut-out; send the FULL frame to the VLM.
            let png = await Task.detached { makeStickerPNG(image) }.value
            guard let png else {
                LPLog.cutout.error("贴纸 PNG nil — FoodPhoto not persisted")
                return
            }
            let photo = history.addFoodPhoto(
                pngData: png,
                capturedAt: capturedAt,
                subjectLabel: subjectLabel,
                mealType: meal
            )
            LPLog.cutout.notice("FoodPhoto persisted \(png.count / 1024, privacy: .public)KB label=\(subjectLabel ?? "—", privacy: .public) at \(LPLog.dateFormatter.string(from: capturedAt), privacy: .public)")

            // Meal capture → 卡路里 识别. Pop the modal (spinner), analyze async.
            guard let meal else { return }
            // The camera fullScreenCover may still be animating out; presenting a
            // sheet mid-dismissal can get silently dropped. Wait out the flag plus
            // a short grace for the dismiss animation.
            while isCameraPresented() {
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .milliseconds(420))
            presentMeal(meal)
            await analyze(photo.id, image, subjectLabel, meal)
        }
    }
}
