import Foundation
import SwiftData

/// A food photo the user captured from the 露珠相机, background-removed (抠图 via
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
    var updatedAt: Date

    init(id: UUID = UUID(), capturedAt: Date, pngData: Data, updatedAt: Date = .now) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: capturedAt)
        self.capturedAt = capturedAt
        self.pngData = pngData
        self.updatedAt = updatedAt
    }
}

extension FoodPhoto {
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
