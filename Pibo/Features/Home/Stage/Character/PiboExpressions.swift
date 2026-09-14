import Foundation
import CoreGraphics
import PiboCore

/// Approved vector artwork and display-clock tracks. Health and behavior
/// selection stay in Core; this file only interpolates the shared media.
struct PiboExpressionLibrary: Decodable {
    struct Part: Decodable {
        let id: String
        let closed: Bool
        let fill: String?
        let stroke: String?
        let strokeWidth: Double
        let poses: [[Double]]

        func path(weights: [Double]) -> CGPath {
            let values = poses[0].indices.map { k in
                weights.indices.reduce(0.0) { $0 + weights[$1] * poses[$1][k] }
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: values[0], y: values[1]))
            for i in stride(from: 2, to: values.count, by: 6) {
                path.addCurve(to: CGPoint(x: values[i + 4], y: values[i + 5]),
                              control1: CGPoint(x: values[i], y: values[i + 1]),
                              control2: CGPoint(x: values[i + 2], y: values[i + 3]))
            }
            if closed { path.closeSubpath() }
            return path
        }
    }
    struct Eye: Decodable { let closed: String; let open: String }
    struct Clip: Decodable {
        let duration: Double
        let fps: Double
        let loop: Bool
        let target: String
        let fatigue: [Double]
        let weights: [[Double]]
        let eyes: [[Double]]
        let transforms: [[[Double]]]
        let sprout: [[Double]]
        let rest: PiboExpressionFrame

        func sample(_ seconds: Double) -> PiboExpressionFrame {
            let frame = max(0, min(duration, seconds)) * fps
            return PiboExpressionFrame(
                fatigue: Self.track(fatigue, frame: floor(frame)),
                weights: weights.map { Self.track($0, frame: frame) },
                eyes: eyes.map { Self.track($0, frame: frame) },
                transforms: transforms.map { $0.map { Self.track($0, frame: frame) } },
                sprout: sprout.map { Self.track($0, frame: frame) }
            )
        }

        static func track(_ keys: [Double], frame: Double) -> Double {
            guard keys.count > 2, frame > keys[0] else { return keys[1] }
            var low = 0, high = keys.count / 2 - 1
            if frame >= keys[high * 2] { return keys[high * 2 + 1] }
            while high - low > 1 {
                let mid = (low + high) / 2
                if keys[mid * 2] <= frame { low = mid } else { high = mid }
            }
            let u = (frame - keys[low * 2]) / (keys[high * 2] - keys[low * 2])
            return keys[low * 2 + 1] + (keys[high * 2 + 1] - keys[low * 2 + 1]) * u
        }
    }

    let schemaVersion: Int
    let artVersion: String
    let bindings: [String: String]
    let parts: [Part]
    let fatigueEye: Eye
    let clips: [String: Clip]

    static let shared: Self? = try? load()
    static func load(bundle: Bundle = .main) throws -> Self {
        let url = bundle.url(forResource: "PiboExpressions", withExtension: "json", subdirectory: "Character")
            ?? bundle.url(forResource: "PiboExpressions", withExtension: "json")
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard library.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        return library
    }
}

struct PiboExpressionFrame: Decodable {
    var fatigue: Double
    var weights: [Double]
    var eyes: [Double]
    var transforms: [[Double]]
    var sprout: [Double]

    static func matrix(_ m: [Double]) -> CGAffineTransform {
        CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    func blended(to b: Self, amount: Double, parts: [PiboExpressionLibrary.Part]) -> Self {
        func mix(_ a: [Double], _ b: [Double]) -> [Double] {
            zip(a, b).map { $0 + ($1 - $0) * amount }
        }
        return Self(fatigue: b.fatigue, weights: mix(weights, b.weights), eyes: mix(eyes, b.eyes),
                    transforms: transforms.indices.map { i in
                        // Fatigue eyes use a local silhouette, regular eyes use
                        // artboard coordinates: never interpolate those origins.
                        if fatigue != b.fatigue && parts[i].id.hasSuffix("eye") { return b.transforms[i] }
                        return mix(transforms[i], b.transforms[i])
                    }, sprout: mix(sprout, b.sprout))
    }
}

struct PiboExpressionEyePaths {
    private struct Element { let type: CGPathElementType; let points: [CGPoint] }
    private let closed: [Element]
    private let open: [Element]

    init(_ eye: PiboExpressionLibrary.Eye) {
        func elements(_ source: String) -> [Element] {
            var result: [Element] = []
            PiboCharacterGeometry.path(svgPathData: source, transform: .identity)?.applyWithBlock { pointer in
                let e = pointer.pointee
                let count: Int = switch e.type {
                case .moveToPoint, .addLineToPoint: 1
                case .addQuadCurveToPoint: 2
                case .addCurveToPoint: 3
                default: 0
                }
                result.append(Element(type: e.type, points: (0..<count).map { e.points[$0] }))
            }
            return result
        }
        closed = elements(eye.closed)
        open = elements(eye.open)
    }

    func path(openness: Double) -> CGPath {
        let path = CGMutablePath()
        for (i, e) in closed.enumerated() {
            let p = e.points.indices.map { j in
                CGPoint(x: e.points[j].x + (open[i].points[j].x - e.points[j].x) * openness,
                        y: e.points[j].y + (open[i].points[j].y - e.points[j].y) * openness)
            }
            switch e.type {
            case .moveToPoint: path.move(to: p[0])
            case .addLineToPoint: path.addLine(to: p[0])
            case .addQuadCurveToPoint: path.addQuadCurve(to: p[1], control: p[0])
            case .addCurveToPoint: path.addCurve(to: p[2], control1: p[0], control2: p[1])
            case .closeSubpath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

@MainActor
final class PiboExpressionPlayer {
    private(set) var profile = ""
    private var start = 0.0
    private var transition = ""
    private var food = ""
    private var foodStart = 0.0
    private var patStart: Double?
    private var patPending = false
    private var patFrom: PiboExpressionFrame?
    private var previous: PiboExpressionFrame?
    private var incoming: PiboExpressionFrame?

    func select(_ profile: String, time: Double) {
        guard self.profile != profile else { return }
        incoming = previous
        let from = PiboCoreExpression.allCases.first { $0.contentID == self.profile }
        let to = PiboCoreExpression.allCases.first { $0.contentID == profile }
        transition = if let from, let to {
            PiboCoreExpressionTransition.resolve(from: from, to: to).contentID ?? ""
        } else { "" }
        self.profile = profile
        if profile.isEmpty { incoming = nil; previous = nil }
        start = time
        food = ""
        if profile != "stable" && profile != "stableThinking" { cancelPat() }
    }
    func observe(onRight: Bool, time: Double) {
        food = "\(profile).food.\(onRight ? "right" : "left")"
        foodStart = time
    }
    func cancelObservation() { food = "" }
    func restartPat() { patPending = true; patFrom = previous }
    func cancelPat() { patStart = nil; patPending = false; patFrom = nil }

    func sample(_ library: PiboExpressionLibrary, time: Double, reduced: Bool) -> PiboExpressionFrame? {
        guard let idle = library.clips[profile] else { return nil }
        if reduced { previous = idle.rest; return idle.rest }
        let elapsed = max(0, time - start), transition = library.clips[transition]
        var p: PiboExpressionFrame
        if let transition, elapsed < transition.duration { p = transition.sample(elapsed) }
        else { p = idle.sample((elapsed - (transition?.duration ?? 0)).truncatingRemainder(dividingBy: idle.duration)) }
        if patPending { patStart = time; patPending = false }
        if let patStart, let pat = library.clips["stable.pat"], time - patStart < pat.duration {
            let t = time - patStart
            let u = min(1, t / 0.12, (pat.duration - t) / 0.18)
            p = (t < 0.12 ? patFrom ?? p : p).blended(to: pat.sample(t), amount: u * u * (3 - 2 * u), parts: library.parts)
        }
        if let food = library.clips[food], time - foodStart < food.duration {
            let observation = food.sample(max(0, time - foodStart))
            var deltas: [CGAffineTransform] = []
            for i in p.transforms.indices {
                let delta = PiboExpressionFrame.matrix(food.rest.transforms[i]).inverted()
                    .concatenating(PiboExpressionFrame.matrix(observation.transforms[i]))
                deltas.append(delta)
                let m = PiboExpressionFrame.matrix(p.transforms[i]).concatenating(delta)
                p.transforms[i] = [m.a, m.b, m.c, m.d, m.tx, m.ty, p.transforms[i][6]]
            }
            p.eyes = p.eyes.indices.map { p.eyes[$0] * observation.eyes[$0] / max(0.001, food.rest.eyes[$0]) }
            if let bo = library.parts.firstIndex(where: { $0.id == "bo" }) {
                let root = CGPoint(x: p.sprout[0], y: p.sprout[1]).applying(deltas[bo])
                let tip = CGPoint(x: p.sprout[2], y: p.sprout[3]).applying(deltas[bo])
                p.sprout = [root.x, root.y, tip.x, tip.y]
            }
        }
        if let incoming, elapsed < 0.12 {
            let u = elapsed / 0.12
            p = incoming.blended(to: p, amount: u * u * (3 - 2 * u), parts: library.parts)
        } else { incoming = nil }
        previous = p
        return p
    }
}
