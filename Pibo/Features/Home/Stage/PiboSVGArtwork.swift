import Foundation
import SpriteKit
import UIKit

/// Runtime representation of the canonical Pibo SVG artwork.
///
/// The same parsed paths render the SpriteKit texture and answer hit tests, so
/// the visible silhouette and the interactive silhouette cannot drift apart.
/// The lightweight parser intentionally supports the path commands emitted by
/// Figma for the fixed Pibo body/head assets (M/L/H/V/C/S/Q/T/Z).
final class PiboSVGArtwork {
    let image: UIImage

    private let viewBox: CGRect
    private let hitShapes: [HitShape]

    private struct HitShape {
        let path: CGPath
        let fillRule: CGPathFillRule
    }

    private init(viewBox: CGRect, elements: [PiboSVGElement]) {
        self.viewBox = viewBox
        hitShapes = elements.flatMap { element in
            var shapes: [HitShape] = []
            if element.fillColor != nil {
                shapes.append(HitShape(path: element.path, fillRule: element.fillRule))
            }
            if element.strokeColor != nil, element.strokeWidth > 0 {
                let outline = element.path.copy(
                    strokingWithWidth: element.strokeWidth,
                    lineCap: element.lineCap,
                    lineJoin: element.lineJoin,
                    miterLimit: 10
                )
                shapes.append(HitShape(path: outline, fillRule: .winding))
            }
            return shapes
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        image = UIGraphicsImageRenderer(size: viewBox.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: -viewBox.minX, y: -viewBox.minY)
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)

            for element in elements {
                if let fillColor = element.fillColor {
                    cg.addPath(element.path)
                    cg.setFillColor(fillColor.cgColor)
                    cg.drawPath(using: element.fillRule == .evenOdd ? .eoFill : .fill)
                }
                if let strokeColor = element.strokeColor, element.strokeWidth > 0 {
                    cg.addPath(element.path)
                    cg.setStrokeColor(strokeColor.cgColor)
                    cg.setLineWidth(element.strokeWidth)
                    cg.setLineCap(element.lineCap)
                    cg.setLineJoin(element.lineJoin)
                    cg.strokePath()
                }
            }
        }
    }

    static func load(named name: String, bundle: Bundle = .main) -> PiboSVGArtwork? {
        let directCandidates = [
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Forest"),
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Forest"),
            bundle.url(forResource: name, withExtension: "svg"),
        ]
        let discovered = bundle.urls(forResourcesWithExtension: "svg", subdirectory: nil)?.first {
            $0.deletingPathExtension().lastPathComponent == name
        }
        guard let url = directCandidates.compactMap({ $0 }).first ?? discovered,
              let data = try? Data(contentsOf: url) else { return nil }

        let parser = PiboSVGDocumentParser(data: data)
        guard parser.parse(), parser.viewBox.width > 0, parser.viewBox.height > 0,
              !parser.elements.isEmpty else { return nil }
        return PiboSVGArtwork(viewBox: parser.viewBox, elements: parser.elements)
    }

    func makeTexture() -> SKTexture {
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Tests a point expressed in the local coordinates of a displayed sprite.
    /// SpriteKit local Y points upward; SVG Y points downward, so mapping also
    /// performs the vertical flip into the SVG viewBox.
    func contains(
        spriteLocalPoint point: CGPoint,
        displayedSize: CGSize,
        anchorPoint: CGPoint
    ) -> Bool {
        guard displayedSize.width > 0, displayedSize.height > 0 else { return false }
        let normalizedX = point.x / displayedSize.width + anchorPoint.x
        let normalizedY = anchorPoint.y - point.y / displayedSize.height
        guard (0 ... 1).contains(normalizedX), (0 ... 1).contains(normalizedY) else { return false }

        let svgPoint = CGPoint(
            x: viewBox.minX + normalizedX * viewBox.width,
            y: viewBox.minY + normalizedY * viewBox.height
        )
        return hitShapes.contains { $0.path.contains(svgPoint, using: $0.fillRule) }
    }
}

/// Fixed production assets imported from Figma node `3904:1804`.
enum PiboSVGAssets {
    static let forestBody = PiboSVGArtwork.load(named: "forest_pibo_body")
    static let forestHead = PiboSVGArtwork.load(named: "forest_pibo_head")

    static func artwork(named name: String) -> PiboSVGArtwork? {
        switch name {
        case "forest_pibo_body": return forestBody
        case "forest_pibo_head": return forestHead
        default: return nil
        }
    }
}

private struct PiboSVGElement {
    let path: CGPath
    let fillColor: UIColor?
    let strokeColor: UIColor?
    let strokeWidth: CGFloat
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin
    let fillRule: CGPathFillRule
}

private final class PiboSVGDocumentParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var insideDefinitions = false

    private(set) var viewBox: CGRect = .zero
    private(set) var elements: [PiboSVGElement] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool {
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "svg":
            if let values = attributeDict["viewBox"]?.svgNumbers, values.count == 4 {
                viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            } else if let width = attributeDict["width"]?.svgNumber,
                      let height = attributeDict["height"]?.svgNumber {
                viewBox = CGRect(x: 0, y: 0, width: width, height: height)
            }
        case "defs":
            insideDefinitions = true
        case "path" where !insideDefinitions:
            guard let data = attributeDict["d"] else { return }
            var pathParser = PiboSVGPathParser(data: data)
            guard let path = pathParser.parse() else { return }
            elements.append(makeElement(path: path, attributes: attributeDict))
        case "circle" where !insideDefinitions:
            guard let cx = attributeDict["cx"]?.svgNumber,
                  let cy = attributeDict["cy"]?.svgNumber,
                  let radius = attributeDict["r"]?.svgNumber else { return }
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            elements.append(makeElement(path: CGPath(ellipseIn: rect, transform: nil), attributes: attributeDict))
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "defs" { insideDefinitions = false }
    }

    private func makeElement(path: CGPath, attributes: [String: String]) -> PiboSVGElement {
        let opacity = attributes["opacity"]?.svgNumber ?? 1
        let fillOpacity = opacity * (attributes["fill-opacity"]?.svgNumber ?? 1)
        let strokeOpacity = opacity * (attributes["stroke-opacity"]?.svgNumber ?? 1)
        return PiboSVGElement(
            path: path,
            fillColor: UIColor(svgColor: attributes["fill"], opacity: fillOpacity),
            strokeColor: UIColor(svgColor: attributes["stroke"], opacity: strokeOpacity),
            strokeWidth: attributes["stroke-width"]?.svgNumber ?? 0,
            lineCap: Self.lineCap(attributes["stroke-linecap"]),
            lineJoin: Self.lineJoin(attributes["stroke-linejoin"]),
            fillRule: attributes["fill-rule"] == "evenodd" ? .evenOdd : .winding
        )
    }

    private static func lineCap(_ value: String?) -> CGLineCap {
        switch value {
        case "round": return .round
        case "square": return .square
        default: return .butt
        }
    }

    private static func lineJoin(_ value: String?) -> CGLineJoin {
        switch value {
        case "round": return .round
        case "bevel": return .bevel
        default: return .miter
        }
    }
}

/// Minimal SVG path scanner covering the commands Figma emits for Pibo's fixed
/// assets (M/L/H/V/C/S/Q/T/Z). Shared with the character runtime so the
/// silhouette on screen, the hit-test geometry, and the morph geometry all come
/// from one parser.
struct PiboSVGPathParser {
    private let tokens: [String]
    private var index = 0

    init(data: String) {
        let pattern = #"[A-Za-z]|[-+]?(?:(?:\d*\.\d+)|(?:\d+\.?\d*))(?:[eE][-+]?\d+)?"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(data.startIndex..., in: data)
        tokens = regex?.matches(in: data, range: range).compactMap {
            Range($0.range, in: data).map { String(data[$0]) }
        } ?? []
    }

    mutating func parse() -> CGPath? {
        guard !tokens.isEmpty else { return nil }
        let path = CGMutablePath()
        var command: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadraticControl: CGPoint?

        while index < tokens.count {
            if isCommand(tokens[index]) {
                command = tokens[index].first
                index += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastCubicControl = nil
                    lastQuadraticControl = nil
                    command = nil
                    continue
                }
            }
            guard let activeCommand = command else { return nil }
            let relative = activeCommand.isLowercase
            let before = index

            switch activeCommand.uppercased() {
            case "M":
                guard let values = readNumbers(2) else { return nil }
                current = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                path.move(to: current)
                subpathStart = current
                command = relative ? "l" : "L"
                lastCubicControl = nil
                lastQuadraticControl = nil
            case "L":
                guard let values = readNumbers(2) else { return nil }
                current = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadraticControl = nil
            case "H":
                guard let value = readNumber() else { return nil }
                current.x = relative ? current.x + value : value
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadraticControl = nil
            case "V":
                guard let value = readNumber() else { return nil }
                current.y = relative ? current.y + value : value
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadraticControl = nil
            case "C":
                guard let values = readNumbers(6) else { return nil }
                let control1 = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                let control2 = resolvedPoint(x: values[2], y: values[3], relativeTo: current, relative: relative)
                let end = resolvedPoint(x: values[4], y: values[5], relativeTo: current, relative: relative)
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
                lastCubicControl = control2
                lastQuadraticControl = nil
            case "S":
                guard let values = readNumbers(4) else { return nil }
                let control1 = lastCubicControl.map {
                    CGPoint(x: current.x * 2 - $0.x, y: current.y * 2 - $0.y)
                } ?? current
                let control2 = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                let end = resolvedPoint(x: values[2], y: values[3], relativeTo: current, relative: relative)
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
                lastCubicControl = control2
                lastQuadraticControl = nil
            case "Q":
                guard let values = readNumbers(4) else { return nil }
                let control = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                let end = resolvedPoint(x: values[2], y: values[3], relativeTo: current, relative: relative)
                path.addQuadCurve(to: end, control: control)
                current = end
                lastQuadraticControl = control
                lastCubicControl = nil
            case "T":
                guard let values = readNumbers(2) else { return nil }
                let control = lastQuadraticControl.map {
                    CGPoint(x: current.x * 2 - $0.x, y: current.y * 2 - $0.y)
                } ?? current
                let end = resolvedPoint(x: values[0], y: values[1], relativeTo: current, relative: relative)
                path.addQuadCurve(to: end, control: control)
                current = end
                lastQuadraticControl = control
                lastCubicControl = nil
            default:
                return nil
            }

            if index == before { return nil }
        }
        return path.copy()
    }

    private mutating func readNumbers(_ count: Int) -> [CGFloat]? {
        var values: [CGFloat] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let value = readNumber() else { return nil }
            values.append(value)
        }
        return values
    }

    private mutating func readNumber() -> CGFloat? {
        guard index < tokens.count, !isCommand(tokens[index]),
              let value = Double(tokens[index]) else { return nil }
        index += 1
        return CGFloat(value)
    }

    private func resolvedPoint(x: CGFloat, y: CGFloat, relativeTo current: CGPoint, relative: Bool) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    private func isCommand(_ token: String) -> Bool {
        token.count == 1 && token.unicodeScalars.first.map(CharacterSet.letters.contains) == true
    }
}

private extension String {
    var svgNumber: CGFloat? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "px", with: "")
        return Double(trimmed).map { CGFloat($0) }
    }

    var svgNumbers: [CGFloat] {
        split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { String($0).svgNumber }
    }
}

extension UIColor {
    /// Parses the colour forms Figma emits (`#RGB`, `#RRGGBB`, `white`, `black`).
    /// Returns nil for `none` and `url(...)` paint servers, which callers treat
    /// as "this element has no fill / no stroke".
    convenience init?(svgColor value: String?, opacity: CGFloat) {
        guard let value, value != "none", !value.hasPrefix("url(") else { return nil }
        let normalized: String
        switch value.lowercased() {
        case "white": normalized = "FFFFFF"
        case "black": normalized = "000000"
        default: normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        }

        let expanded: String
        if normalized.count == 3 {
            expanded = normalized.map { "\($0)\($0)" }.joined()
        } else {
            expanded = normalized
        }
        guard expanded.count == 6, let rgb = UInt64(expanded, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: min(max(opacity, 0), 1)
        )
    }
}
