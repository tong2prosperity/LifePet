import Foundation
import SwiftData

/// A food photo the user captured from the 餐食相机, background-removed (抠图 via
/// `SubjectCutout`) and kept as a per-day history record for the 今日记录 card on
/// the 历史数据页. Stored as PNG bytes with a transparent background so the
/// cut-out subject floats on the card's paper texture.
///
/// Narrative (home spec §4): the user is Pibo's 地球向导 collecting world samples,
/// so each photo is a "记录" pinned to the day it was taken.
@Model
final class FoodPhoto {
    @Attribute(.unique) var id: UUID
    /// `startOfDay(capturedAt)` — the day-bucket query key.
    var day: Date
    var capturedAt: Date
    /// Cut-out PNG (transparent background). Large enough to warrant external
    /// blob storage rather than inlining into the row.
    @Attribute(.externalStorage) var pngData: Data
    /// 识图 result — best-effort display name of the photo's main subject
    /// (`SubjectClassifier`, on-device). Nil when classification found nothing
    /// or for photos saved before the field existed.
    var subjectLabel: String? = nil

    // MARK: 拍照识别卡路里 (meal captures only)

    /// Which meal slot this photo was captured into (`MealType.rawValue`), or
    /// nil for a free 照相馆 capture that skips calorie recognition.
    var mealTypeRaw: String? = nil
    /// Backend VLM result — 菜名 (quick-access, also drives the caption).
    var dishName: String? = nil
    /// Backend VLM result — 整份估算热量 (kcal). Nil while analysis is pending
    /// or if recognition failed.
    var totalCalories: Int? = nil
    /// Full `FoodAnalysis` JSON (items + macros + note) for the meal detail modal.
    /// Small (<1 KB) — kept inline, no external blob.
    var analysisJSON: Data? = nil

    var updatedAt: Date

    init(id: UUID = UUID(), capturedAt: Date, pngData: Data,
         subjectLabel: String? = nil, mealType: MealType? = nil,
         updatedAt: Date = .now) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: capturedAt)
        self.capturedAt = capturedAt
        self.pngData = pngData
        self.subjectLabel = subjectLabel
        self.mealTypeRaw = mealType?.rawValue
        self.updatedAt = updatedAt
    }
}

extension FoodPhoto {
    /// The meal slot this photo belongs to, if any.
    var meal: MealType? {
        mealTypeRaw.flatMap(MealType.init(rawValue:))
    }

    /// Decoded full analysis (items + macros + note), if recognition succeeded.
    var analysis: FoodAnalysis? {
        analysisJSON.flatMap { try? JSONDecoder().decode(FoodAnalysis.self, from: $0) }
    }

    /// `00:33 AM` capture-time label (history card variant — home spec §4).
    var timeLabel: String {
        let f = FoodPhoto.timeFormatter
        return f.string(from: capturedAt)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "hh:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f
    }()
}
