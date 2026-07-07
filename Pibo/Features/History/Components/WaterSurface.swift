import SwiftUI

/// 玻璃水面 —— 活动卡底部的水池（取代旧的静态 `RippleField` 线稿）。
///
/// 三列水池分别压在 卡路里 / 运动 / 站立 三个数字下方，每列的「雨量」由
/// `intensities[i] ∈ [0,1]`（该项对目标的达成度）驱动：达成越高 → 滴得越密、
/// 水珠越大、涟漪越强；为 0 → 静止水面。底面（青色渐变 + 反光条 + 静态环纹）经
/// `waterGlass` Metal 着色器做**折射 + 镜面高光**，叠加「水珠坠落 → 触水皇冠 →
/// 回弹水柱」三拍的轻量 Canvas。
///
/// 每列雨量不同 → 每列周期不同，所以**相位 `local` 与强度 `amp` 都在 Swift 端用
/// Double 算好再传给 shader**（shader 不碰时间，彻底避开 float32 精度问题）。
///
/// 效率：`floorIsOpen` 环境值门控 —— 二楼合上时 `TimelineView(paused:)` 停转、
/// 着色器不再每帧刷新，零开销（与 stage 的 `SpriteView(isPaused:)` 同源阈值）。
struct WaterSurface: View {
    /// 三列雨量强度 [卡路里, 运动, 站立]，各 ∈ [0,1]。默认全开（预览/缺省照常下雨）。
    var intensities: [Double] = [1, 1, 1]
    var tint: Color = LP.Colorful.cyan500

    @Environment(\.floorIsOpen) private var isActive

    private let dropXFrac: [CGFloat] = [0.22, 0.50, 0.78]
    private let phases: [Double] = [0.0, 0.34, 0.67]
    private let impactFrac: Double = 0.36         // 须与 WaterGlass.metal 的 kImpactFrac 一致
    private let periodSlow: Double = 4.2          // 雨量低 → 稀疏
    private let periodFast: Double = 1.6          // 雨量高 → 密集

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centers = dropXFrac.map { CGPoint(x: size.width * $0, y: size.height * 0.6) }
            // amp/period 只随数据变（与 t 无关）→ 放在 TimelineView 之外。
            let amps = (0..<3).map { i in i < intensities.count ? min(1, max(0, intensities[i])) : 0 }
            let periods = amps.map { periodSlow + (periodFast - periodSlow) * $0 }
            let base = waterBase(centers: centers, amps: amps)
            // 全干（三列达成度/雨量都为 0，如无活动的历史日）时没有可动的水滴，
            // 逐帧跑 `waterGlass` 着色器 + Canvas 纯属浪费 → 直接暂停，只留静态 base。
            // 历史页现在是常驻的 fullScreenCover（`floorIsOpen` 恒为 true），不再有
            // 二楼开合来自然停下，这条干旱判定是主要的省电闸。
            let dry = amps.allSatisfy { $0 < 0.02 }

            TimelineView(.animation(paused: !isActive || dry)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // 每列相位 local∈[0,1)：Swift 端 Double 取模，精度无忧。
                let locals = (0..<3).map { i in
                    Float((t / periods[i] + phases[i]).truncatingRemainder(dividingBy: 1))
                }

                ZStack {
                    base.layerEffect(
                        ShaderLibrary.waterGlass(
                            .float2(size),
                            .float2(centers[0]), .float(locals[0]), .float(Float(amps[0])),
                            .float2(centers[1]), .float(locals[1]), .float(Float(amps[1])),
                            .float2(centers[2]), .float(locals[2]), .float(Float(amps[2]))),
                        maxSampleOffset: CGSize(width: 12, height: 12))

                    dropOverlay(t: t, centers: centers, amps: amps, periods: periods)
                }
            }
        }
    }

    /// 底面：折射/高光要「掰弯」的纹理。上方透明 → 下方淡青池，叠横向反光条 + 静态环纹
    /// （环纹透明度随该列雨量淡入淡出，静止列更安静）。
    private func waterBase(centers: [CGPoint], amps: [Double]) -> some View {
        Canvas { ctx, sz in
            ctx.fill(
                Path(CGRect(origin: .zero, size: sz)),
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0), tint.opacity(0), tint.opacity(0.5)]),
                    startPoint: CGPoint(x: sz.width / 2, y: 0),
                    endPoint: CGPoint(x: sz.width / 2, y: sz.height)))

            for f in [CGFloat(0.66), 0.80, 0.92] {
                let y = sz.height * f
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(line, with: .color(.white.opacity(0.16)), lineWidth: 1.4)
            }

            for (i, c) in centers.enumerated() {
                let alpha = 0.08 + 0.14 * (i < amps.count ? amps[i] : 0)
                for r in stride(from: CGFloat(12), through: 44, by: 11) {
                    let rect = CGRect(x: c.x - r, y: c.y - r * 0.45, width: r * 2, height: r * 0.9)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(alpha)), lineWidth: 1.2)
                }
            }
        }
    }

    /// 落点的「水珠坠落 → 触水皇冠 → 回弹水柱」三拍（与着色器同一相位、同一节奏）。
    /// shader 负责扩散涟漪，这层负责"这是一颗水滴"的识别度；尺寸随该列雨量缩放。
    private func dropOverlay(t: Double, centers: [CGPoint], amps: [Double], periods: [Double]) -> some View {
        Canvas { ctx, sz in
            for (i, c) in centers.enumerated() {
                let amp = amps[i]
                if amp < 0.02 { continue }                       // 静止列：不滴
                let local = (t / periods[i] + phases[i]).truncatingRemainder(dividingBy: 1)
                if local < impactFrac {
                    fallingDrop(into: &ctx, cx: c.x, surfaceY: c.y,
                                topY: sz.height * 0.02, p: local / impactFrac, amp: amp)
                } else {
                    impact(into: &ctx, cx: c.x, surfaceY: c.y,
                           rp: (local - impactFrac) / (1 - impactFrac), amp: amp)
                }
            }
        }
    }

    /// 泪滴形水珠：圆肚朝下（先落）、尖头朝上（拖尾），加速时纵向拉长（运动模糊感，
    /// 但不是直线段）。两段三次贝塞尔让底部切线水平 → 真圆肚；白色高光 + 青色描边 → 玻璃质感。
    private func fallingDrop(into ctx: inout GraphicsContext,
                            cx: CGFloat, surfaceY: CGFloat, topY: CGFloat, p: Double, amp: Double) {
        let y = topY + (surfaceY - topY) * CGFloat(p * p)   // easeIn 加速坠落
        let bead = CGFloat(3.6 + 1.4 * amp)                  // 雨量越大水珠越大
        let len = (11 + 9 * CGFloat(p)) * CGFloat(0.8 + 0.2 * amp)
        let apex = CGPoint(x: cx, y: y - len)

        var drop = Path()
        drop.move(to: apex)
        drop.addCurve(to: CGPoint(x: cx, y: y),
                      control1: CGPoint(x: cx + bead, y: y - len * 0.6),
                      control2: CGPoint(x: cx + bead, y: y))      // 底部切线水平 → 圆肚
        drop.addCurve(to: apex,
                      control1: CGPoint(x: cx - bead, y: y),
                      control2: CGPoint(x: cx - bead, y: y - len * 0.6))
        drop.closeSubpath()

        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.5), tint]),
            startPoint: apex, endPoint: CGPoint(x: cx, y: y)))
        ctx.stroke(drop, with: .color(LP.Colorful.cyan700.opacity(0.45)), lineWidth: 0.8)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - bead * 0.55, y: y - bead * 1.15,
                                        width: bead * 0.7, height: bead * 0.95)),
                 with: .color(.white.opacity(0.85)))
    }

    /// 触水：皇冠水花（快速外扩淡出的扁环）+ 回弹水柱顶着一颗水珠（Rayleigh jet，
    /// 升起再落下）—— 水滴入水的标志性回跳。整体尺寸随该列雨量缩放。
    private func impact(into ctx: inout GraphicsContext,
                       cx: CGFloat, surfaceY: CGFloat, rp: Double, amp: Double) {
        let k = CGFloat(0.6 + 0.4 * amp)
        if rp < 0.22 {
            let a = 1 - rp / 0.22
            let r = CGFloat(5 + 24 * rp) * k
            let rect = CGRect(x: cx - r, y: surfaceY - r * 0.3, width: r * 2, height: r * 0.6)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 * a)), lineWidth: 1.4)
        }
        if rp < 0.42 {
            let env = sin(rp / 0.42 * .pi)               // 0 → 1 → 0：升起再落回
            let jetH = CGFloat(env) * 17 * k
            let beadR = CGFloat(env) * 3.0 * k
            let topY = surfaceY - jetH
            var col = Path()
            col.move(to: CGPoint(x: cx, y: surfaceY))
            col.addLine(to: CGPoint(x: cx, y: topY + beadR))
            ctx.stroke(col, with: .color(tint.opacity(0.85 * env)),
                       style: StrokeStyle(lineWidth: CGFloat(env) * 2.0 + 0.6, lineCap: .round))
            if beadR > 0.6 {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - beadR, y: topY - beadR,
                                                width: beadR * 2, height: beadR * 2)),
                         with: .color(tint))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - beadR * 0.4, y: topY - beadR * 0.7,
                                                width: beadR * 0.7, height: beadR * 0.85)),
                         with: .color(.white.opacity(0.7)))
            }
        }
    }
}
