import CoreGraphics
import Foundation
import UIKit

/// Turns the pre-matched geometry into `CGPath`s, and interpolates between two
/// states.
///
/// All the hard correspondence work — resampling two differently-structured
/// outlines onto a shared topology, and deciding which point maps to which —
/// happened in the build-time generator. What is left here is a lerp, which is
/// why no morphing library is needed on device.
enum PiboCharacterGeometry {
    /// Design coordinates are SVG's (Y down, origin top-left of the 300×300
    /// frame); SpriteKit's are Y up. Maps design space into a node-local space
    /// centred on the frame.
    static func designTransform(scale: CGFloat, frame: CGSize) -> CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: -scale)
            .translatedBy(x: -frame.width / 2, y: -frame.height / 2)
    }

    // MARK: - Static paths

    static func path(
        for morph: PiboCharacterData.Morph,
        stateID: String,
        transform: CGAffineTransform
    ) -> CGPath? {
        guard let values = morph.values(for: stateID) else { return nil }
        return makePath(morph: morph, values: values, transform: transform)
    }

    /// Parses an element's raw `d`. Used for decorations, which never morph.
    static func path(svgPathData: String, transform: CGAffineTransform) -> CGPath? {
        var parser = PiboSVGPathParser(data: svgPathData)
        guard let path = parser.parse() else { return nil }
        var matrix = transform
        return path.copy(using: &matrix)
    }

    // MARK: - Interpolation

    /// Interpolates between two states of the same shared path.
    ///
    /// Both strategies lerp the same way — the generator guarantees the two
    /// value arrays are the same length and index-aligned. `structured` keeps
    /// its béziers because its values *are* control points; `resampled` walks a
    /// polygon whose vertex count was fixed at build time.
    static func interpolatedPath(
        for morph: PiboCharacterData.Morph,
        from fromStateID: String,
        to toStateID: String,
        progress: CGFloat,
        transform: CGAffineTransform
    ) -> CGPath? {
        guard let from = morph.values(for: fromStateID),
              let to = morph.values(for: toStateID) else { return nil }

        return interpolatedPath(
            for: morph,
            fromValues: from,
            toValues: to,
            progress: progress,
            transform: transform
        )
    }

    /// Interpolates from a captured in-flight shape. State-to-state retargeting
    /// uses this overload so an interrupted morph continues from the exact
    /// geometry currently on screen instead of jumping back to a named state.
    static func interpolatedPath(
        for morph: PiboCharacterData.Morph,
        fromValues from: [CGFloat],
        toValues to: [CGFloat],
        progress: CGFloat,
        transform: CGAffineTransform
    ) -> CGPath? {
        guard from.count == to.count else { return nil }

        if progress <= 0 { return makePath(morph: morph, values: from, transform: transform) }
        if progress >= 1 { return makePath(morph: morph, values: to, transform: transform) }

        var blended = [CGFloat](repeating: 0, count: from.count)
        for index in blended.indices {
            blended[index] = from[index] + (to[index] - from[index]) * progress
        }
        return makePath(morph: morph, values: blended, transform: transform)
    }

    static func interpolatedValues(
        for morph: PiboCharacterData.Morph,
        from fromStateID: String,
        to toStateID: String,
        progress: CGFloat
    ) -> [CGFloat]? {
        guard let from = morph.values(for: fromStateID),
              let to = morph.values(for: toStateID),
              from.count == to.count else { return nil }
        let clamped = min(max(progress, 0), 1)
        return zip(from, to).map { first, second in
            first + (second - first) * clamped
        }
    }

    // MARK: - Stroke → fill

    /// Converts a stroked centreline into its filled outline.
    ///
    /// `boline` — the highlight line on the sprout — is a sub-point-wide stroke,
    /// which is the shape most likely to alias badly once SpriteKit tessellates
    /// it. Interpolating the centreline (exact, 12 béziers) and *then* outlining
    /// keeps the structural correspondence while handing the renderer a filled
    /// sliver instead of a hairline.
    static func outlined(
        _ path: CGPath,
        width: CGFloat,
        lineCap: CGLineCap,
        lineJoin: CGLineJoin
    ) -> CGPath {
        path.copy(strokingWithWidth: max(width, 0.01), lineCap: lineCap, lineJoin: lineJoin, miterLimit: 10)
    }

    static func lineCap(_ value: String?) -> CGLineCap {
        switch value {
        case "round": .round
        case "square": .square
        default: .butt
        }
    }

    static func lineJoin(_ value: String?) -> CGLineJoin {
        switch value {
        case "round": .round
        case "bevel": .bevel
        default: .miter
        }
    }

    // MARK: - Path-level deformation

    /// Radial swell with Gaussian falloff around `centre`.
    ///
    /// Every point — including control points — moves through the same field, so
    /// curvature is preserved and the outline stays smooth. Points far from the
    /// centre are untouched, which is the whole point: the bum swells while the
    /// face does not shift a pixel.
    static func bulged(
        _ path: CGPath,
        centre: CGPoint,
        radius: CGFloat,
        magnitude: CGFloat,
        bias: CGVector
    ) -> CGPath {
        let falloff = 1 / (radius * radius)
        return mapped(path) { point in
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            let weight = exp(-(dx * dx + dy * dy) * falloff * 2)
            guard weight > 0.001 else { return point }
            let swell = 1 + magnitude * weight
            return CGPoint(
                x: centre.x + dx * swell + bias.dx * magnitude * weight,
                y: centre.y + dy * swell + bias.dy * magnitude * weight
            )
        }
    }

    /// Jelly wobble: displaces the outline radially by a travelling sine.
    static func wiggled(
        _ path: CGPath,
        amplitude: CGFloat,
        waves: CGFloat,
        phase: CGFloat,
        controlsOnly: Bool = false
    ) -> CGPath {
        let box = path.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return path }
        let centre = CGPoint(x: box.midX, y: box.midY)
        let transform: (CGPoint) -> CGPoint = { point in
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            let distance = max(hypot(dx, dy), 0.0001)
            let angle = atan2(dy, dx)
            let offset = sin(angle * waves + phase) * amplitude
            return CGPoint(
                x: point.x + dx / distance * offset,
                y: point.y + dy / distance * offset
            )
        }
        guard controlsOnly else { return mapped(path, transform) }

        let result = CGMutablePath()
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: result.move(to: points[0])
            case .addLineToPoint: result.addLine(to: points[0])
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: points[1], control: transform(points[0]))
            case .addCurveToPoint:
                result.addCurve(
                    to: points[2],
                    control1: transform(points[0]),
                    control2: transform(points[1])
                )
            case .closeSubpath: result.closeSubpath()
            @unknown default: break
            }
        }
        return result.copy() ?? path
    }

    /// Rebuilds a path with every point passed through `transform`.
    private static func mapped(_ path: CGPath, _ transform: (CGPoint) -> CGPoint) -> CGPath {
        let result = CGMutablePath()
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                result.move(to: transform(points[0]))
            case .addLineToPoint:
                result.addLine(to: transform(points[0]))
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: transform(points[1]), control: transform(points[0]))
            case .addCurveToPoint:
                result.addCurve(
                    to: transform(points[2]),
                    control1: transform(points[0]),
                    control2: transform(points[1])
                )
            case .closeSubpath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result.copy() ?? path
    }

    // MARK: - Private

    private static func makePath(
        morph: PiboCharacterData.Morph,
        values: [CGFloat],
        transform: CGAffineTransform
    ) -> CGPath? {
        let path = CGMutablePath()
        switch morph.strategy {
        case .resampled:
            guard values.count >= 4 else { return nil }
            path.move(to: CGPoint(x: values[0], y: values[1]), transform: transform)
            for index in stride(from: 2, to: values.count, by: 2) {
                path.addLine(to: CGPoint(x: values[index], y: values[index + 1]), transform: transform)
            }
            if morph.closed { path.closeSubpath() }

        case .structured:
            guard let commands = morph.commands else { return nil }
            var cursor = 0
            for command in commands {
                switch command {
                case "M":
                    guard cursor + 1 < values.count else { return nil }
                    path.move(to: CGPoint(x: values[cursor], y: values[cursor + 1]), transform: transform)
                    cursor += 2
                case "L":
                    guard cursor + 1 < values.count else { return nil }
                    path.addLine(to: CGPoint(x: values[cursor], y: values[cursor + 1]), transform: transform)
                    cursor += 2
                case "C":
                    guard cursor + 5 < values.count else { return nil }
                    path.addCurve(
                        to: CGPoint(x: values[cursor + 4], y: values[cursor + 5]),
                        control1: CGPoint(x: values[cursor], y: values[cursor + 1]),
                        control2: CGPoint(x: values[cursor + 2], y: values[cursor + 3]),
                        transform: transform
                    )
                    cursor += 6
                case "Z":
                    path.closeSubpath()
                default:
                    return nil
                }
            }
        }
        return path.isEmpty ? nil : path.copy()
    }
}

/// The design package's easing: a pure acceleration curve. Overshoot is banned —
/// an eased `t > 1` combined with polygon-sampled morphing produces spikes, which
/// is why the designer's v2 (easeOutBack) was rejected outright.
struct PiboUnitBezier {
    private let x1, y1, x2, y2: Double

    init(_ values: [Double]) {
        x1 = values.count > 0 ? values[0] : 0
        y1 = values.count > 1 ? values[1] : 0
        x2 = values.count > 2 ? values[2] : 1
        y2 = values.count > 3 ? values[3] : 1
    }

    func callAsFunction(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        // Newton on x(u) = clamped, then evaluate y(u). Six iterations is well
        // past convergence for the monotone curves we ship.
        var u = clamped
        for _ in 0 ..< 6 {
            let x = bezier(u, x1, x2) - clamped
            let dx = derivative(u, x1, x2)
            if abs(dx) < 1e-6 { break }
            u -= x / dx
        }
        return bezier(min(max(u, 0), 1), y1, y2)
    }

    private func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}
