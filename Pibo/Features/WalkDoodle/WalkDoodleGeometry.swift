import SwiftUI
import CoreLocation
import MapKit

// MARK: - Geometry

/// Pure path math for walk doodles — length, enclosed area, a fitting map region,
/// and the formatted display strings. Stateless so both the live `WalkDoodleSession`
/// and the persisted `WalkDoodleRecord` derive the same numbers.
enum DoodleGeometry {

    /// Walked length of the stroke in metres (sum of consecutive segment lengths).
    static func pathLength(_ coords: [CLLocationCoordinate2D]) -> Double {
        PiboCoreDoodleAdapter.pathLength(coords)
    }

    /// Area (m²) enclosed by the stroke as if its ends were joined — the shoelace
    /// formula on a local equirectangular projection (metres relative to the first
    /// point). This "圈住的地" is what the future 比拼面积 feature ranks.
    static func enclosedArea(_ coords: [CLLocationCoordinate2D]) -> Double {
        PiboCoreDoodleAdapter.enclosedArea(coords)
    }

    /// A camera region that frames the whole stroke with a little breathing room.
    /// `nil` for an empty / single-point path (caller falls back to user location).
    static func boundingRegion(_ coords: [CLLocationCoordinate2D], paddingFactor: Double = 1.4) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // Floor the span so a tiny doodle doesn't zoom to street-crack level.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, 0.002),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, 0.002))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: Display strings

    /// `820 m` / `2.41 km`.
    static func distanceText(_ metres: Double) -> String {
        metres < 1000
            ? "\(Int(metres.rounded())) m"
            : String(format: "%.2f km", metres / 1000)
    }

    /// `640 m²` / `1.83 公顷` (1 公顷 = 10 000 m²).
    static func areaText(_ squareMetres: Double) -> String {
        squareMetres < 10_000
            ? "\(Int(squareMetres.rounded())) m²"
            : String(format: "%.2f 公顷", squareMetres / 10_000)
    }

    /// `mm:ss`.
    static func durationText(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Stroke shape

/// Renders a doodle's GPS path as a thick rounded stroke fitted into a rect —
/// the offline mini-render used on the 历史数据页 card and the save preview (the
/// live recording view draws the real-geo `MapPolyline` instead). Projects
/// lon→x / lat→y(flip), then scales uniformly so the doodle keeps its real aspect.
struct WalkDoodleShape: Shape {
    var coordinates: [DoodleCoordinate]
    /// Inset (pt) so the round line cap isn't clipped by the rect edge.
    var inset: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let origin = coordinates.first else { return path }

        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(origin.latitude * .pi / 180)
        // Project to local metres (y up).
        let pts = coordinates.map { c in
            CGPoint(x: (c.longitude - origin.longitude) * mPerDegLon,
                    y: (c.latitude - origin.latitude) * mPerDegLat)
        }
        var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let spanX = max(maxX - minX, 0.0001)
        let spanY = max(maxY - minY, 0.0001)
        let box = rect.insetBy(dx: inset, dy: inset)
        let scale = min(box.width / spanX, box.height / spanY)
        // Centre the scaled drawing in the box.
        let drawnW = spanX * scale, drawnH = spanY * scale
        let offX = box.minX + (box.width - drawnW) / 2
        let offY = box.minY + (box.height - drawnH) / 2

        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: offX + (p.x - minX) * scale,
                    y: offY + (maxY - p.y) * scale)   // flip y so north is up
        }

        path.move(to: map(pts[0]))
        for p in pts.dropFirst() { path.addLine(to: map(p)) }
        return path
    }
}

// MARK: - Challenge (scaffold for 布置涂鸦)

/// A doodle task Pibo hands the user. MVP ships `.freeform` only; named target
/// shapes (圆 / 心 / 字) slot in later so `WalkDoodleView` can score 完成度 and
/// the history can 比拼面积. Carried into `WalkDoodleResult.title` on save.
struct WalkDoodleChallenge: Equatable {
    var title: String?          // nil = freeform
    var promptKey: String       // Pibo-voice assignment line (localization key)

    static let freeform = WalkDoodleChallenge(
        title: nil,
        promptKey: "...用脚...画一个圈...给花占块地...啵")
}

// MARK: - Pibo voice (feature-local copy pools, like PiboCameraView.genericComments)

/// 魔丸态 garbled-but-readable fragments for the walk-doodle task — tsundere,
/// flower/land framing, never a plain "去运动吧". Pools stay local to the feature
/// (mirrors `PiboCameraView.genericComments`); only the §2 greeting copy is locked
/// app-wide.
enum WalkDoodleCopy {
    /// Task card subtitle + the idle-screen assignment line.
    static let taskPrompts = [
        "...用脚...画一个圈...给花占块地...啵",
        "...走出去...描一笔...大的...",
        "...这片地...走一圈...圈住...种花...",
        "...别用手...用脚画...啵",
    ]

    /// Murmured while recording (shown faintly over the map).
    static let recordingHints = [
        "...走...慢慢描...",
        "...这一笔...歪了...啵",
        "...再走...还没圈上...",
        "...嗯...这块地...不错...",
    ]

    /// Spoken on save (also bubbles on the home stage).
    static let savedLines = [
        "...嗯...这块地...归花了...",
        "...画...完了...？还行...啵",
        "...歪歪扭扭...花...喜欢...",
        "...占住了...这块...种花...",
    ]

    /// When the user stops before drawing anything worth keeping.
    static let tooShortLines = [
        "...就这么点...？再走...",
        "...没画完...啵...回去走...",
        "...这...不算...重画...",
    ]
}
