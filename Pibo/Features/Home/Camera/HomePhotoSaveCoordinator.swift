import Foundation
import UIKit
import os

/// Owns the asynchronous gate after a Home camera capture. A meal does not
/// become a successful photo, history row, or forest projection until the
/// backend explicitly confirms that food is present.
@MainActor
enum HomePhotoSaveCoordinator {
    enum Outcome: Equatable {
        case saved
        case notFood
        case failed
    }

    enum Failure: Equatable {
        case saving
        case recognition
    }

    static func handleSavedPhoto(
        image: UIImage?,
        subjectLabel: String?,
        meal: MealType?,
        clearInitialMeal: @escaping () -> Void,
        history: HealthHistoryStore,
        recognizer: FoodRecognitionService,
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void
    ) async -> Outcome {
        LPLog.cutout.notice(
            "photo captured → food gate (hasImage=\(image != nil, privacy: .public) hasLabel=\(subjectLabel != nil, privacy: .public) meal=\(meal?.rawValue ?? "—", privacy: .public))"
        )
        guard let image else {
            LPLog.cutout.info("no captured image — skipping recognition and persistence")
            presentFailure(.saving)
            return .failed
        }
        let outcome = await process(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            history: history,
            recognizer: recognizer,
            presentProjection: presentProjection,
            presentFailure: presentFailure
        )
        if outcome == .saved { clearInitialMeal() }
        return outcome
    }

    static func process(
        image: UIImage,
        subjectLabel: String?,
        meal: MealType?,
        history: HealthHistoryStore,
        recognizer: FoodRecognitionService,
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void
    ) async -> Outcome {
        await process(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            history: history,
            presentProjection: presentProjection,
            presentFailure: presentFailure,
            analyze: { requestID, fullImage, hint, meal in
                await recognizer.recognize(
                    requestID: requestID,
                    fullImage: fullImage,
                    hint: hint,
                    meal: meal
                )
            }
        )
    }

    static func process(
        image: UIImage,
        subjectLabel: String?,
        meal: MealType?,
        history: HealthHistoryStore,
        presentProjection: @escaping (HomeFoodProjection) -> Void,
        presentFailure: @escaping (Failure) -> Void,
        analyze: @escaping @MainActor (
            UUID,
            UIImage,
            String?,
            MealType
        ) async -> FoodRecognitionOutcome,
        makeSticker: @escaping @Sendable (UIImage) -> SubjectCutout.Sticker? = {
            SubjectCutout.sticker($0)
        },
        makeSourceJPEG: @escaping @Sendable (UIImage) -> Data? = {
            $0.jpegData(compressionQuality: 0.90)
        }
    ) async -> Outcome {
        let capturedAt = Date()
        let requestID = UUID()
        let analysis: FoodAnalysis?
        if let meal {
            switch await analyze(requestID, image, subjectLabel, meal) {
            case .food(let recognized):
                analysis = recognized
            case .notFood:
                LPLog.food.notice("meal capture rejected by food-presence gate")
                return .notFood
            case .failed:
                presentFailure(.recognition)
                return .failed
            }
        } else {
            // Free camera records remain a local collection path and do not
            // claim to be a recognized meal.
            analysis = nil
        }

        // Only verified food reaches the expensive presentation treatment.
        // Send the full frame to recognition; store a bounded source copy.
        async let cutout = Task.detached { makeSticker(image) }.value
        async let source = Task.detached { makeSourceJPEG(image) }.value
        let (sticker, sourceJPEG) = await (cutout, source)
        guard !Task.isCancelled else { return .failed }
        guard let displayedData = sticker?.pngData ?? sourceJPEG else {
            LPLog.cutout.error("贴纸与原图编码均失败 — FoodPhoto not persisted")
            presentFailure(.saving)
            return .failed
        }
        // Vision cut-out is presentation enhancement, not a persistence
        // gate. If it fails, the original frame still completes the loop.
        if sticker == nil {
            LPLog.cutout.notice("贴纸生成失败 — using original photo fallback")
        }
        let photo = history.addFoodPhoto(
            id: requestID,
            pngData: displayedData,
            sourceJPEGData: sourceJPEG,
            capturedAt: capturedAt,
            subjectLabel: subjectLabel ?? analysis?.dishName,
            mealType: meal,
            analysis: analysis
        )
        LPLog.cutout.notice(
            "verified FoodPhoto persisted \(displayedData.count / 1024, privacy: .public)KB at \(LPLog.dateFormatter.string(from: capturedAt), privacy: .public)"
        )
        Analytics.track(
            .photoSaved,
            screen: "camera",
            [
                "meal": .string(meal?.rawValue ?? "none"),
                "has_subject": .bool(subjectLabel != nil),
            ]
        )

        guard let meal, let analysis else { return .saved }
        presentProjection(HomeFoodProjection(
            id: photo.id,
            pngData: displayedData,
            meal: meal,
            dishName: analysis.dishName,
            observation: analysis.piboObservation?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).nonEmpty ?? AppLocalization.text("我先记下它的样子。"),
            isCutout: sticker?.isCutout == true
        ))
        return .saved
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
