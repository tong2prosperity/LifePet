import Foundation
import UIKit
import Observation
import os

/// One recognised component of a meal (matches the server's `items[]`).
struct FoodItem: Codable, Hashable, Identifiable {
    var name: String
    var calories: Int
    var quantity: String?
    var estimatedGrams: Int?

    var id: String { "\(name)-\(calories)" }
}

/// The backend Kimi VLM result for a meal photo — 菜名 / 热量 / 营养 / 点评.
/// Decoded from the server via `JSONCoding` (snake_case → camelCase), and also
/// round-tripped through a plain coder when cached on `FoodPhoto.analysisJSON`.
struct FoodAnalysis: Codable, Hashable {
    /// Optional only so historical rows written before the food gate keep
    /// decoding. A new server response without this decision is rejected.
    var isFood: Bool?
    var foodPresenceConfidence: Double?
    var dishName: String
    var totalCalories: Int
    var confidence: Double?
    var items: [FoodItem]
    var proteinG: Double?
    var carbG: Double?
    var fatG: Double?
    var assumptions: [String]?
    var note: String?
    var piboObservation: String?
}

/// Request body for `POST /api/v1/food/recognize`. Encoded snake_case by the
/// shared `APIClient` (`image_base64` / `mime_type` / `meal_type` / `hint`).
private struct FoodRecognizeRequest: Encodable {
    var imageBase64: String
    var mimeType: String
    var idempotencyKey: String
    var mealType: String?
    var hint: String?
}

enum FoodRecognitionOutcome: Equatable {
    case food(FoodAnalysis)
    case notFood
    case failed
}

/// Sends a captured meal photo to pibo-server for calorie/nutrition recognition
/// and folds the result back onto the `FoodPhoto` record. The VLM call is slow
/// (kimi-k2.6 reasons for ~1–2 min), so callers should present the meal modal
/// immediately and let `analyzing` drive a spinner until the result lands.
@MainActor
@Observable
final class FoodRecognitionService {
    /// Photo ids with an in-flight recognition request (drives the modal spinner).
    /// A photo with no `analysis` and no in-flight request is treated as failed
    /// by the meal modal — no separate failure set needed.
    private(set) var analyzing: Set<UUID> = []

    @ObservationIgnored private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func isAnalyzing(_ id: UUID) -> Bool { analyzing.contains(id) }

    /// Recognise the full original frame before it becomes a formal history
    /// record. The server is the only food-presence gate; local Vision remains
    /// a best-effort sticker treatment and can never turn a non-food frame into
    /// a successful capture.
    func recognize(
        requestID: UUID,
        fullImage: UIImage,
        hint: String?,
        meal: MealType
    ) async -> FoodRecognitionOutcome {
        guard !analyzing.contains(requestID) else { return .failed }
        analyzing.insert(requestID)
        defer { analyzing.remove(requestID) }

        // Render/encode off-main — a 12MP frame re-render + base64 would hitch
        // the camera-dismiss animation (same pattern as SubjectCutout callers).
        let encoded = await Task.detached { fullImage.jpegForUpload() }.value
        guard let jpeg = encoded else {
            LPLog.food.error("food recognize abort — jpeg encode failed")
            return .failed
        }
        let req = FoodRecognizeRequest(
            imageBase64: jpeg.base64EncodedString(),
            mimeType: "image/jpeg",
            idempotencyKey: requestID.uuidString,
            mealType: meal.title,
            hint: hint)

        let started = ContinuousClock().now
        do {
            // kimi-k2.6 vision reasons for 1–2 min; override the default 60s timeout.
            let resp: FoodAnalysis = try await api.post(
                "/api/v1/food/recognize",
                body: req,
                authed: true,
                timeout: 210
            )
            let ms = (ContinuousClock().now - started).components.seconds
            guard let isFood = resp.isFood else {
                LPLog.food.error("food recognize returned no gate decision")
                return .failed
            }
            LPLog.food.notice(
                "food gate completed result=\(isFood ? "food" : "not_food", privacy: .public) in \(ms, privacy: .public)s"
            )
            Analytics.track(.mealRecognized, screen: "meal",
                            ["meal": .string(meal.rawValue), "ok": true,
                             "result": .string(isFood ? "food" : "not_food"),
                             "duration_s": .int(Int(ms))])
            return isFood ? .food(resp) : .notFood
        } catch {
            LPLog.food.error("food recognize failed: \(String(describing: error), privacy: .public)")
            let ms = (ContinuousClock().now - started).components.seconds
            Analytics.track(.mealRecognized, screen: "meal",
                            ["meal": .string(meal.rawValue), "ok": false, "duration_s": .int(Int(ms))])
            return .failed
        }
    }

    /// Legacy/history retry. New captures call `recognize` before persistence;
    /// this adapter only exists for rows that already reached history.
    func analyze(photoID: UUID, fullImage: UIImage, hint: String?, meal: MealType,
                 history: HealthHistoryStore) async -> Bool {
        guard case .food(let response) = await recognize(
            requestID: photoID,
            fullImage: fullImage,
            hint: hint,
            meal: meal
        ) else { return false }
        let cached = try? JSONEncoder().encode(response)
        history.updateFoodPhoto(id: photoID) { photo in
            photo.dishName = response.dishName
            photo.totalCalories = response.totalCalories
            photo.analysisJSON = cached
            if (photo.subjectLabel ?? "").isEmpty {
                photo.subjectLabel = response.dishName
            }
        }
        return true
    }

    /// Retry an existing record with its original frame. Older rows that predate
    /// source persistence fall back to their displayed image.
    func retry(photo: FoodPhoto, meal: MealType, history: HealthHistoryStore) async -> Bool {
        let data = photo.sourceJPEGData ?? photo.pngData
        guard let image = UIImage(data: data) else {
            LPLog.food.error("food recognize retry abort — stored image decode failed")
            return false
        }
        return await analyze(
            photoID: photo.id,
            fullImage: image,
            hint: photo.subjectLabel,
            meal: meal,
            history: history
        )
    }
}

extension UIImage {
    /// Downscaled JPEG for upload — caps the longest side and compresses so the
    /// base64 payload stays small (the VLM doesn't need full resolution).
    /// `nonisolated` so callers can run it via `Task.detached` off the main
    /// actor (the project defaults new code to MainActor isolation).
    nonisolated func jpegForUpload(maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let longest = max(size.width, size.height)
        let scaled: UIImage
        if longest > maxDimension, longest > 0 {
            let factor = maxDimension / longest
            let target = CGSize(width: size.width * factor, height: size.height * factor)
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                draw(in: CGRect(origin: .zero, size: target))
            }
        } else {
            scaled = self
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
