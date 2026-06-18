import SwiftUI

// MARK: - Pibo portrait (Figma-faithful component composer)
//
// Assembles the separated components (`PiboComponents.swift`) into a full Pibo
// using the EXACT relative geometry of the Figma 主体形象 (node `1855:4343`).
// Layout lives in the Figma "design space" (the Group 70 body frame, origin at
// the body's top-left, +y down) so every part sits where the design put it; the
// whole thing is then scaled to fit the view. Default appearance → pixel-faithful
// to the design; the editor's params nudge each part from there.
//
// Z-order (back→front): contact shadow · 头顶植物 · 手 · 腿 · 身子 · 鼻子 ·
// 眼睛 · 眉毛. Arms/legs/leaf sit behind the body and peek past its silhouette.

struct PiboPortraitView: View {
    var appearance: PiboAppearance
    var showShadow: Bool = true

    // Figma design-space union bounds (body frame + overflowing arms/legs/leaf).
    private static let unionMinX: CGFloat = -7
    private static let unionMaxX: CGFloat = 251.52
    private static let unionMinY: CGFloat = -102.5
    private static let unionMaxY: CGFloat = 235
    private static var unionW: CGFloat { unionMaxX - unionMinX }   // 258.52
    private static var unionH: CGFloat { unionMaxY - unionMinY }   // 337.5
    private static var cx: CGFloat { (unionMinX + unionMaxX) / 2 } // 122.26
    private static var cy: CGFloat { (unionMinY + unionMaxY) / 2 } // 66.25

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.unionW,
                            geo.size.height / Self.unionH) * 0.9
            // Map a design-space point → view point.
            let P: (CGFloat, CGFloat) -> CGPoint = { x, y in
                CGPoint(x: geo.size.width / 2 + (x - Self.cx) * scale,
                        y: geo.size.height / 2 + (y - Self.cy) * scale)
            }
            let a = appearance
            let pal = a.palette

            // Body geometry (scaled about its center for widthScale / aspect).
            let bodyW = 226.195 * a.body.widthScale
            let bodyH = 212.156 * a.body.aspect
            let bodyCenter = CGPoint(x: 113.0975, y: 106.078)   // native body center

            // Face box (fixed position relative to the body), design coords.
            let faceX: CGFloat = 88, faceY: CGFloat = 66, faceW: CGFloat = 72, faceH: CGFloat = 52
            let faceCenterX = faceX + 36

            ZStack {
                if showShadow {
                    Ellipse().fill(.black.opacity(0.10))
                        .frame(width: 150 * scale, height: 26 * scale)
                        .position(P(116, 236))
                }

                // 头顶植物 — behind the body crown.
                let plantSide = 127.067 * scale * a.plant.size
                PiboPlant(kind: a.plant.kind, size: plantSide, color: pal.plant.color)
                    .rotationEffect(.degrees(a.plant.sway))
                    .position(P(112.07, -38.97))

                // 手 — behind the body, hugging its sides. Both arms share the same
                // base path; the 左臂 (Vector 16) is un-flipped, sits low and pokes a
                // small nub down-left; the 右臂 (Vector 17) is flipped-X and tucked up
                // into the body's wide right shoulder so the forearm hangs along — and
                // stays in contact with — the body contour (no floating gap).
                if a.arms.visible {
                    let armDY = (a.arms.drop - 0.18) * 120
                    arm(at: P(18.63, 123.5 + armDY), scale: scale, length: a.arms.length,
                        color: pal.limb.color, mirror: false)
                    arm(at: P(212, 108 + armDY), scale: scale, length: a.arms.length,
                        color: pal.limb.color, mirror: true)
                }

                // 腿 — tall capsules, tops tucked behind the body.
                if a.legs.visible {
                    let legH = 94 * a.legs.length
                    let legW: CGFloat = 32
                    let legBottom: CGFloat = 235
                    let legY = legBottom - legH / 2
                    let legDX = 15 * a.legs.spread
                    PiboLeg(size: CGSize(width: legW * scale, height: legH * scale), color: pal.limb.color)
                        .position(P(116 - legDX, legY))
                    PiboLeg(size: CGSize(width: legW * scale, height: legH * scale), color: pal.limb.color)
                        .position(P(116 + legDX, legY))
                }

                // 身子
                PiboBodyShape().fill(pal.body.color)
                    .overlay(strokeOverlay(pal.outline))
                    .frame(width: bodyW * scale, height: bodyH * scale)
                    .position(P(bodyCenter.x, bodyCenter.y))

                // 鼻子 / 腮
                let noseW = 40.0 * a.nose.size, noseH = 20.8 * a.nose.size
                PiboNose(shape: a.nose.shape,
                         size: CGSize(width: noseW * scale, height: noseH * scale), color: pal.nose.color)
                    .position(P(124.89, faceY + a.nose.drop * faceH))

                // 眼睛 (大椭圆) — exact Figma rx10.5 ry5.5 by default.
                let eyeOffset = a.eyes.spacing * faceW
                let eyeY = faceY + a.eyes.height * faceH
                let eyeW = 2 * 10.5 * a.eyes.size, eyeH = 2 * 5.5 * a.eyes.size
                eye(at: P(faceCenterX - eyeOffset, eyeY), w: eyeW * scale, h: eyeH * scale,
                    a: a, color: pal.eye.color, mirror: false)
                eye(at: P(faceCenterX + eyeOffset, eyeY), w: eyeW * scale, h: eyeH * scale,
                    a: a, color: pal.eye.color, mirror: true)

                // 眉毛 (小圆) — exact Figma r3.38 by default.
                let browOffset = a.brows.spacing * faceW
                let browY = faceY + a.brows.lift * faceH
                let browR = 3.38 * a.brows.size
                brow(at: P(faceCenterX - browOffset, browY), r: browR * scale,
                     a: a, color: pal.brow.color, mirror: false)
                brow(at: P(faceCenterX + browOffset, browY), r: browR * scale,
                     a: a, color: pal.brow.color, mirror: true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Part builders

    @ViewBuilder
    private func strokeOverlay(_ outline: PiboColor) -> some View {
        if outline.a > 0.02 {
            PiboBodyShape().stroke(outline.color, lineWidth: 2)
        }
    }

    private func arm(at p: CGPoint, scale: CGFloat, length: CGFloat, color: Color, mirror: Bool) -> some View {
        let style = StrokeStyle(lineWidth: PiboArmShape.nativeWidth * scale,
                                lineCap: .round, lineJoin: .round)
        return ZStack {
            PiboArmShape().stroke(color, style: style)
            // Whisper of shading only at the very shoulder (where the arm meets the
            // body), fading out fast — Figma's arm MaskGroup, kept subtle so it
            // reads as depth, not a gap.
            PiboArmShape().stroke(
                LinearGradient(colors: [Color(hex: 0xC2CCD3).opacity(0.4), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.32)),
                style: style)
        }
        .frame(width: PiboArmShape.viewBox.width * scale,
               height: PiboArmShape.viewBox.height * scale * length)
        .scaleEffect(x: mirror ? -1 : 1)
        .position(p)
    }

    private func eye(at p: CGPoint, w: CGFloat, h: CGFloat,
                     a: PiboAppearance, color: Color, mirror: Bool) -> some View {
        PiboEye(shape: a.eyes.shape, size: CGSize(width: w, height: h), color: color)
            .rotationEffect(.degrees(a.eyes.tilt))
            .scaleEffect(x: mirror ? -1 : 1)
            .position(p)
    }

    private func brow(at p: CGPoint, r: CGFloat,
                      a: PiboAppearance, color: Color, mirror: Bool) -> some View {
        PiboBrow(shape: a.brows.shape,
                 size: CGSize(width: r * 2.4, height: r * 2), color: color, angle: a.brows.angle)
            .scaleEffect(x: mirror ? -1 : 1)
            .position(p)
    }
}

// MARK: - Preview

#Preview("Pibo portrait") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(PiboAppearance.presets, id: \.name) { preset in
                VStack {
                    PiboPortraitView(appearance: preset.appearance)
                        .frame(width: 200, height: 260)
                        .background(Color(hex: 0xEAEEF0))
                    Text(preset.name).lpText(LP.Typography.b4Medium)
                }
                .padding(8)
            }
        }
    }
    .background(LP.Fill.bgSurface)
}
