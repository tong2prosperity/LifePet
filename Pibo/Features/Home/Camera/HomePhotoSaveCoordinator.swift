import Foundation
import UIKit
import os

/// Owns the asynchronous work that follows a successful Home camera capture.
/// Home keeps presentation state; this coordinator performs cut-out persistence
/// and, for meal captures, returns a food projection to the forest before
/// starting background analysis.
@MainActor
enum HomePhotoSaveCoordinator {
    enum Failure: Equatable {
        case saving
        case recognition
    }

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
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void
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
                    presentFailure(.saving)
                },
                process: { image in
                    Self.process(
                        image: image,
                        subjectLabel: subjectLabel,
                        meal: meal,
                        history: history,
                        recognizer: recognizer,
                        isCameraPresented: isCameraPresented,
                        presentProjection: presentProjection,
                        presentFailure: presentFailure
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
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void
    ) -> Task<Void, Never> {
        process(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            history: history,
            isCameraPresented: isCameraPresented,
            presentProjection: presentProjection,
            presentFailure: presentFailure,
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
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void,
        analyze: @escaping @MainActor (
            UUID,
            UIImage,
            String?,
            MealType
        ) async -> Bool,
        makeStickerPNG: @escaping @Sendable (UIImage) -> Data? = {
            SubjectCutout.stickerPNG($0)
        },
        makeSourceJPEG: @escaping @Sendable (UIImage) -> Data? = {
            $0.jpegData(compressionQuality: 0.90)
        }
    ) -> Task<Void, Never> {
        let capturedAt = Date()
        return Task {
            // Show the user the Vision-processed cut-out; send the FULL frame to the VLM.
            async let cutout = Task.detached { makeStickerPNG(image) }.value
            async let source = Task.detached { makeSourceJPEG(image) }.value
            let (cutoutPNG, sourceJPEG) = await (cutout, source)
            guard let displayedData = cutoutPNG ?? sourceJPEG else {
                LPLog.cutout.error("贴纸与原图编码均失败 — FoodPhoto not persisted")
                presentFailure(.saving)
                return
            }
            // Vision cut-out is presentation enhancement, not a persistence
            // gate. If it fails, the original frame still completes the loop.
            if cutoutPNG == nil {
                LPLog.cutout.notice("贴纸生成失败 — using original photo fallback")
            }
            let photo = history.addFoodPhoto(
                pngData: displayedData,
                sourceJPEGData: sourceJPEG,
                capturedAt: capturedAt,
                subjectLabel: subjectLabel,
                mealType: meal
            )
            LPLog.cutout.notice("FoodPhoto persisted \(displayedData.count / 1024, privacy: .public)KB label=\(subjectLabel ?? "—", privacy: .public) at \(LPLog.dateFormatter.string(from: capturedAt), privacy: .public)")

            // Meal capture → return to the forest first. Recognition continues
            // behind the projection and never blocks the primary pet loop.
            guard let meal else { return }
            // Wait until the full-screen camera is gone before putting the cut-out
            // into the forest, plus a short grace for the dismissal animation.
            while isCameraPresented() {
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .milliseconds(420))
            presentProjection(HomeFoodProjection(
                id: photo.id,
                pngData: displayedData,
                meal: meal,
                subjectLabel: subjectLabel
            ))
            let recognized = await analyze(photo.id, image, subjectLabel, meal)
            if !recognized { presentFailure(.recognition) }
        }
    }
}
