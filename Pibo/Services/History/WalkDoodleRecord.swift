import Foundation
import CoreLocation
import SwiftData

/// One sampled GPS point on a walk-doodle stroke. Stored raw (lat / lon / time) so
/// the codable layout stays stable across refactors and the doodle can be
/// re-rendered on demand — no map-tile snapshot is persisted. Mirrors the
/// value-type-array pattern `SleepSegmentValue` uses inside `HealthDayRecord`.
struct DoodleCoordinate: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date

    init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Sendable transport of a finished walk doodle — produced by `WalkDoodleSession`
/// on the main actor, handed to `HomeView` and persisted via `HealthHistoryStore`.
/// Kept separate from the `@Model` so the recording layer never touches SwiftData.
struct WalkDoodleResult: Sendable, Equatable {
    var coordinates: [DoodleCoordinate]
    var distanceMeters: Double
    var areaSquareMeters: Double
    var duration: TimeInterval
    /// Challenge title — `nil` = freeform (MVP). Future target-shape doodles
    /// (布置涂鸦) carry their prompt name here for 完成度/面积 comparison.
    var title: String?

    /// A doodle worth keeping: at least a short stroke (filters accidental
    /// "start → stop" taps that recorded nothing).
    var isDrawn: Bool { coordinates.count >= 3 && distanceMeters >= 30 }
}

/// A walk doodle the user traced by walking — Pibo's "用脚画一幅画 / 圈一块花田"
/// task (home spec lineage: 运动能量). Persisted per day so completed doodles land
/// on the 历史数据页's 足迹涂鸦 card, and so future builds can compare 完成度 /
/// 比拼面积 across days. Only the GPS points are stored; the stroke is re-rendered
/// from them by `WalkDoodleShape`.
@Model
final class WalkDoodleRecord {
    @Attribute(.unique) var id: UUID
    /// `startOfDay(createdAt)` — the day-bucket query key (matches `FoodPhoto.day`).
    var day: Date
    var createdAt: Date
    /// The traced path, in capture order.
    var coordinates: [DoodleCoordinate]
    /// Total walked length of the stroke (m).
    var distanceMeters: Double
    /// Area enclosed by the stroke as if its ends were joined (m²) — the basis for
    /// the future 比拼面积 feature.
    var areaSquareMeters: Double
    var durationSeconds: Double
    /// Challenge title — `nil` = freeform. Future: target-doodle prompt name.
    var title: String?
    var updatedAt: Date

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         coordinates: [DoodleCoordinate],
         distanceMeters: Double,
         areaSquareMeters: Double,
         durationSeconds: Double,
         title: String? = nil,
         updatedAt: Date = .now) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: createdAt)
        self.createdAt = createdAt
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.areaSquareMeters = areaSquareMeters
        self.durationSeconds = durationSeconds
        self.title = title
        self.updatedAt = updatedAt
    }
}

extension WalkDoodleRecord {
    /// Has a renderable stroke.
    var hasData: Bool { coordinates.count >= 2 }

    /// `00:33` capture-time label (history-card variant — matches `FoodPhoto`).
    var timeLabel: String {
        let f = WalkDoodleRecord.timeFormatter
        return f.string(from: createdAt)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "hh:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f
    }()
}
