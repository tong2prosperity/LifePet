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

/// Request body for `POST /api/v1/food/recognize` by uploaded-object reference.
/// Encoded snake_case by the shared `APIClient` (`object_key` /
/// `upload_session_id` / `mime_type` / `idempotency_key` / `meal_type` / `hint`).
/// There is intentionally no `image_base64` path any more: every recognition
/// goes through the bounded COS derivative.
struct FoodRecognizeRequest: Encodable, Equatable {
    var objectKey: String
    var uploadSessionId: String
    var mimeType: String
    var idempotencyKey: String
    var mealType: String?
    var hint: String?
}

/// `POST /api/v1/food/uploads` body.
struct FoodUploadCreateRequest: Encodable, Equatable {
    var contentType: String
    var contentLength: Int
}

/// `POST /api/v1/food/uploads/{session_id}/complete` body.
struct FoodUploadCompleteRequest: Encodable, Equatable {
    var objectKey: String
}

/// Signed upload session. Decoded with explicit keys and a plain decoder so the
/// signed header names (`Content-Type`, `x-cos-...`) are never key-transformed.
struct FoodUploadSession: Decodable, Equatable {
    let sessionID: String
    let objectKey: String
    let uploadURL: String
    let headers: [String: String]
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case objectKey = "object_key"
        case uploadURL = "upload_url"
        case headers
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        objectKey = try c.decode(String.self, forKey: .objectKey)
        uploadURL = try c.decode(String.self, forKey: .uploadURL)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

/// Paths of the food upload/recognition contract (pibo-server
/// `internal/food/transport/rest/router.go`).
enum FoodAPIPaths {
    static let uploads = "/api/v1/food/uploads"
    static let recognize = "/api/v1/food/recognize"

    static func uploadComplete(sessionID: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let segment = sessionID.addingPercentEncoding(withAllowedCharacters: allowed) ?? sessionID
        return "/api/v1/food/uploads/\(segment)/complete"
    }
}

/// The model-upload derivative. History keeps the original frame; recognition
/// only ever sees this bounded copy (longest edge 1280 px, JPEG quality 0.72),
/// regenerated from the kept original on every retry.
nonisolated enum FoodUploadImage {
    static let maxPixelDimension: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.72
    static let mimeType = "image/jpeg"

    /// Target pixel size for a source of `width` x `height` pixels.
    static func targetPixelSize(width: CGFloat, height: CGFloat) -> CGSize {
        let longest = max(width, height)
        guard longest > maxPixelDimension, longest > 0 else {
            return CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
        }
        let scale = maxPixelDimension / longest
        return CGSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )
    }

    /// Renders at 1x so the pixel size is exactly the target (the default
    /// renderer format would multiply by the screen scale), which also bakes
    /// the orientation into the pixels.
    static func jpegData(from image: UIImage) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let target = targetPixelSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }
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
    @ObservationIgnored private let makeUploadJPEG: @Sendable (UIImage) -> Data?

    init(
        api: APIClient = .shared,
        makeUploadJPEG: @escaping @Sendable (UIImage) -> Data? = { FoodUploadImage.jpegData(from: $0) }
    ) {
        self.api = api
        self.makeUploadJPEG = makeUploadJPEG
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

        // Render/encode off-main — a 12MP frame re-render would hitch the
        // camera-dismiss animation (same pattern as SubjectCutout callers).
        // A derivative failure fails the request: never fall back to uploading
        // the original resolution.
        let makeJPEG = makeUploadJPEG
        let encoded = await Task.detached { makeJPEG(fullImage) }.value
        guard let jpeg = encoded, !jpeg.isEmpty else {
            LPLog.food.error("food recognize abort — upload derivative encode failed")
            return .failed
        }

        let started = ContinuousClock().now
        do {
            let upload = try await uploadDerivative(jpeg)
            let req = FoodRecognizeRequest(
                objectKey: upload.objectKey,
                uploadSessionId: upload.sessionID,
                mimeType: FoodUploadImage.mimeType,
                idempotencyKey: String(requestID.uuidString.prefix(64)),
                mealType: meal.title,
                hint: hint)
            // kimi-k2.6 vision reasons for 1–2 min; override the default 60s timeout.
            let resp: FoodAnalysis = try await api.post(
                FoodAPIPaths.recognize,
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

    /// Signed-session upload: create, PUT bytes, complete. Any step failing
    /// throws, so no recognition request is made for a missing object.
    private func uploadDerivative(_ jpeg: Data) async throws -> FoodUploadSession {
        let raw = try await api.postData(
            FoodAPIPaths.uploads,
            body: FoodUploadCreateRequest(
                contentType: FoodUploadImage.mimeType,
                contentLength: jpeg.count
            ),
            authed: true,
            timeout: 60
        )
        let session: FoodUploadSession
        do {
            session = try JSONDecoder().decode(FoodUploadSession.self, from: raw)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
        guard let url = URL(string: session.uploadURL) else {
            throw APIError.invalidRequest
        }
        var headers = session.headers
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers["Content-Type"] = FoodUploadImage.mimeType
        }
        try await api.putBytes(url, data: jpeg, headers: headers, timeout: 120)
        try await api.postNoContent(
            FoodAPIPaths.uploadComplete(sessionID: session.sessionID),
            body: FoodUploadCompleteRequest(objectKey: session.objectKey),
            authed: true
        )
        return session
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
