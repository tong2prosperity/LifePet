import CoreGraphics
import SwiftUI
import UIKit

/// 头顶那株「毛」的静态矢量图标。
///
/// 直接取角色数据 `default` 态的 `bo` / `boline` 两条路径，和舞台上那株**同源** ——
/// 不另出一套图标资产。角色造型将来若有修订，这里跟着一起变，不会出现「首页的毛和
/// Pibo 头上的毛不是同一株」这种低级但很显眼的不一致。
struct PiboBoGlyph: View {
    /// 灰掉：用于「位置在这儿，但还不是你的」。
    var isDimmed = false

    var body: some View {
        Canvas { context, size in
            guard let glyph = PiboBoGlyphGeometry.shared else { return }
            var fitted = glyph.transform(into: size)
            let dim = isDimmed ? 0.28 : 1.0

            if let fill = glyph.fill.copy(using: &fitted) {
                context.fill(Path(fill), with: .color(glyph.fillColor.opacity(dim)))
            }
            if let line = glyph.line.copy(using: &fitted) {
                // 设计里这条高光只有 0.84（在 300pt 的画板上）。按比例缩到图标尺寸会
                // 细到看不见，所以给一个下限 —— 宁可略粗，也别让它凭空消失。
                let width = max(glyph.lineWidth * glyph.scale(into: size), 0.5)
                context.stroke(
                    Path(line),
                    with: .color(glyph.lineColor.opacity(dim)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// 解析一次、全程复用的图标几何。
enum PiboBoGlyphGeometry {

    struct Resolved {
        let fill: CGPath
        let line: CGPath
        let bounds: CGRect
        let lineWidth: CGFloat
        let fillColor: Color
        let lineColor: Color

        /// 等比缩放系数：把设计尺寸的毛塞进给定的图标尺寸。
        func scale(into size: CGSize) -> CGFloat {
            guard bounds.width > 0, bounds.height > 0 else { return 1 }
            return min(size.width / bounds.width, size.height / bounds.height)
        }

        /// 等比缩放 + 居中。SwiftUI 与 SVG 的 Y 轴同向，所以不需要翻转 ——
        /// SpriteKit 那边的 `designTransform` 才要翻。
        func transform(into size: CGSize) -> CGAffineTransform {
            let s = scale(into: size)
            return CGAffineTransform(
                translationX: (size.width - bounds.width * s) / 2 - bounds.minX * s,
                y: (size.height - bounds.height * s) / 2 - bounds.minY * s
            )
            .scaledBy(x: s, y: s)
        }
    }

    static let shared: Resolved? = resolve()

    private static func resolve() -> Resolved? {
        guard let data = PiboCharacterData.shared,
              let state = data.states[PiboAnimationStateMap.fallback]
        else { return nil }

        func element(_ id: String) -> PiboCharacterData.Element? {
            state.elements.first { $0.id == id }
        }
        guard let boElement = element("bo"),
              let lineElement = element("boline"),
              let fill = PiboCharacterGeometry.path(svgPathData: boElement.d, transform: .identity),
              let line = PiboCharacterGeometry.path(svgPathData: lineElement.d, transform: .identity)
        else { return nil }

        // 只按填充形状定框。高光线本来就在毛的内部，把它算进来不会改变外框，
        // 但描边宽度会让 `boundingBoxOfPath` 略微外扩，反而把图标缩小一点。
        let bounds = fill.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // 颜色走角色渲染用的同一个解析器，免得两处对 `#20937A` 的理解跑偏。
        let fillColor = UIColor(svgColor: boElement.fill, opacity: 1).map(Color.init)
        let lineColor = UIColor(svgColor: lineElement.stroke, opacity: 1).map(Color.init)

        return Resolved(
            fill: fill,
            line: line,
            bounds: bounds,
            lineWidth: lineElement.strokeWidth ?? 0.84,
            fillColor: fillColor ?? Color(hex: 0x20937A),
            lineColor: lineColor ?? .white
        )
    }
}

#Preview {
    HStack(spacing: 24) {
        PiboBoGlyph().frame(width: 20, height: 28)
        PiboBoGlyph().frame(width: 44, height: 60)
        PiboBoGlyph(isDimmed: true).frame(width: 44, height: 60)
    }
    .padding(40)
    .background(LP.Fill.bgContainer)
}
