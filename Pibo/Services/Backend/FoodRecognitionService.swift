import Foundation
import UIKit
import Observation
import os

/// One recognised component of a meal (matches the server's `items[]`).
struct FoodItem: Codable, Hashable, Identifiable {
    var name: String
    var calories: Int
    var quantity: String?

    var id: String { "\(name)-\(calories)" }
}

/// The backend Kimi VLM result for a meal photo — 菜名 / 热量 / 营养 / 点评.
/// Decoded from the server via `JSONCoding` (snake_case → camelCase), and also
/// round-tripped through a plain coder when cached on `FoodPhoto.analysisJSON`.
struct FoodAnalysis: Codable, Hashable {
    var dishName: String
    var totalCalories: Int
    var confidence: Double?
    var items: [FoodItem]
    var proteinG: Double?
    var carbG: Double?
    var fatG: Double?
    var note: String?
}

/// Request body for `POST /api/v1/food/recognize`. Encoded snake_case by the
/// shared `APIClient` (`image_base64` / `mime_type` / `meal_type` / `hint`).
private struct FoodRecognizeRequest: Encodable {
    var imageBase64: String
    var mimeType: String
    var mealType: String?
    var hint: String?
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

    /// Recognise `fullImage` (the FULL original frame, not the cut-out) for the
    /// given meal and persist the analysis onto the photo. Best-effort: on any
    /// failure the photo keeps its cut-out + label and the modal offers 重拍.
    func analyze(photoID: UUID, fullImage: UIImage, hint: String?, meal: MealType,
                 history: HealthHistoryStore) async {
        analyzing.insert(photoID)
        defer { analyzing.remove(photoID) }

        // Render/encode off-main — a 12MP frame re-render + base64 would hitch
        // the camera-dismiss animation (same pattern as SubjectCutout callers).
        let encoded = await Task.detached { fullImage.jpegForUpload() }.value
        guard let jpeg = encoded else {
            LPLog.food.error("food recognize abort — jpeg encode failed")
            return
        }
        let req = FoodRecognizeRequest(
            imageBase64: jpeg.base64EncodedString(),
            mimeType: "image/jpeg",
            mealType: meal.title,
            hint: hint)

        let started = ContinuousClock().now
        do {
            // kimi-k2.6 vision reasons for 1–2 min; override the default 60s timeout.
            let resp: FoodAnalysis = try await api.post("/api/v1/food/recognize", body: req, authed: false, timeout: 210)
            let cached = try? JSONEncoder().encode(resp)
            history.updateFoodPhoto(id: photoID) { photo in
                photo.dishName = resp.dishName
                photo.totalCalories = resp.totalCalories
                photo.analysisJSON = cached
                if (photo.subjectLabel ?? "").isEmpty { photo.subjectLabel = resp.dishName }
            }
            let ms = (ContinuousClock().now - started).components.seconds
            LPLog.food.notice("food recognized \(resp.dishName, privacy: .public) \(resp.totalCalories, privacy: .public)kcal in \(ms, privacy: .public)s")
        } catch {
            LPLog.food.error("food recognize failed: \(String(describing: error), privacy: .public)")
        }
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
