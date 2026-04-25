import SwiftUI

/// 三状态生命轨迹图. 横轴随宠物实际寿命变化（PRD v0.7：no fixed 21 days），
/// 纵轴 0–100. 三条折线对应 体力 / 精力 / 心情，外加 30/85 阈值参考线。
///
/// Rendered with `Canvas` — folds neatly into the SwiftUI tree, no SwiftCharts
/// dependency, and gives us pixel control over dashed strokes + the "今天" /
/// "✦升天" end marker.
struct CatalogTrajectoryChart: View {
    let pet: CatalogPet
    /// 340×140 mirrors the prototype viewBox; we let SwiftUI resize this
    /// proportionally so the chart fills its parent column.
    private let viewBox = CGSize(width: 340, height: 140)
    private let pad = (left: 22.0, right: 18.0, top: 15.0, bottom: 28.0)

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let scale = min(size.width / viewBox.width, size.height / viewBox.height)
            let originX = (size.width - viewBox.width * scale) / 2
            let originY = (size.height - viewBox.height * scale) / 2
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: originX / scale, y: originY / scale)

            drawGrid(ctx)
            drawAxisLabels(ctx)
            drawSeries(ctx, values: pet.series.energy,   color: LP.Colors.muted, width: 1.2)
            drawSeries(ctx, values: pet.series.vitality, color: LP.Colors.ink,   width: 1.2)
            drawSeries(ctx, values: pet.series.mood,     color: LP.Colors.coral, width: 1.8)
            drawEndMarker(ctx)
            drawLastDots(ctx)
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    // MARK: - Coordinate helpers

    /// y for a 0–100 stat value.
    private func vy(_ v: Int) -> CGFloat {
        let top = pad.top
        let bottom = viewBox.height - pad.bottom
        return top + (1 - CGFloat(v) / 100) * (bottom - top)
    }

    /// x for a 1-indexed day.
    private func dx(_ d: Int) -> CGFloat {
        let n = pet.totalDays
        let left = pad.left
        let right = viewBox.width - pad.right
        guard n > 1 else { return (left + right) / 2 }
        return left + CGFloat(d - 1) * (right - left) / CGFloat(n - 1)
    }

    // MARK: - Drawing

    private func drawGrid(_ ctx: GraphicsContext) {
        let left = pad.left, right = viewBox.width - pad.right
        let topLine = vy(100), midLine = vy(50), bottomLine = vy(0)

        // Top + middle dashed gridlines.
        for y in [topLine, midLine] {
            var p = Path()
            p.move(to: CGPoint(x: left, y: y))
            p.addLine(to: CGPoint(x: right, y: y))
            ctx.stroke(p, with: .color(LP.Colors.hairline),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        }
        // Bottom solid baseline.
        var base = Path()
        base.move(to: CGPoint(x: left, y: bottomLine))
        base.addLine(to: CGPoint(x: right, y: bottomLine))
        ctx.stroke(base, with: .color(LP.Colors.hairline), lineWidth: 1)

        // PRD reference lines: 30 (low) and 85 (high) in coral, very faint.
        for v in [30, 85] {
            var p = Path()
            p.move(to: CGPoint(x: left,  y: vy(v)))
            p.addLine(to: CGPoint(x: right, y: vy(v)))
            ctx.stroke(p, with: .color(LP.Colors.coral.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 0.4, dash: [1, 3]))
        }
    }

    private func drawAxisLabels(_ ctx: GraphicsContext) {
        let labelFont = Font.system(size: 7, design: .monospaced)
        let muted = LP.Colors.muted

        // Y axis 100 / 50 / 0
        let yTicks: [(Int, CGFloat)] = [(100, vy(100)), (50, vy(50)), (0, vy(0))]
        for (val, y) in yTicks {
            let text = Text("\(val)").font(labelFont).foregroundStyle(muted)
            ctx.draw(text, at: CGPoint(x: 12, y: y), anchor: .center)
        }

        // Adaptive day labels — same buckets as the prototype.
        let n = pet.totalDays
        let labels: [Int]
        switch n {
        case ...3:  labels = [1, n]
        case 4...7: labels = [1, Int(ceil(Double(n) / 2)), n]
        case 8...14: labels = [1, 5, 10, n]
        default:    labels = [1, 5, 10, 15, n]
        }
        let baselineY = viewBox.height - pad.bottom + 12
        for d in Set(labels).sorted() where d <= n {
            let text = Text("D\(d)").font(labelFont).foregroundStyle(muted)
            ctx.draw(text, at: CGPoint(x: dx(d), y: baselineY), anchor: .center)
        }
    }

    private func drawSeries(_ ctx: GraphicsContext, values: [Int], color: Color, width: CGFloat) {
        guard !values.isEmpty else { return }
        var p = Path()
        for (i, v) in values.enumerated() {
            let x = dx(i + 1)
            let y = vy(v)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else      { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(p, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drawEndMarker(_ ctx: GraphicsContext) {
        let n = pet.totalDays
        let xEnd = dx(n)
        if pet.isAlive {
            // "今天" — empty coral circle on the latest mood point.
            let last = pet.series.mood.last ?? 0
            let center = CGPoint(x: xEnd, y: vy(last))
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                       with: .color(LP.Colors.coral), lineWidth: 1)
            let label = Text("· 今天 ·").font(.system(size: 7, design: .monospaced))
                .foregroundStyle(LP.Colors.coral)
            ctx.draw(label, at: CGPoint(x: xEnd - 4, y: pad.top - 5), anchor: .trailing)
        } else {
            // "升天" — ink dashed vertical at end + small text.
            var p = Path()
            p.move(to: CGPoint(x: xEnd, y: pad.top))
            p.addLine(to: CGPoint(x: xEnd, y: viewBox.height - pad.bottom))
            ctx.stroke(p, with: .color(LP.Colors.muted),
                       style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
            let label = Text("✦ 升天").font(.system(size: 7, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            ctx.draw(label, at: CGPoint(x: xEnd - 4, y: pad.top - 5), anchor: .trailing)
        }
    }

    private func drawLastDots(_ ctx: GraphicsContext) {
        let i = pet.days - 1
        guard i >= 0 else { return }
        let x = dx(pet.days)
        let dot: (Int, Color, CGFloat) -> Void = { v, c, r in
            let rect = CGRect(x: x - r, y: vy(v) - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(c))
        }
        if i < pet.series.vitality.count { dot(pet.series.vitality[i], LP.Colors.ink, 2) }
        if i < pet.series.energy.count   { dot(pet.series.energy[i],   LP.Colors.muted, 2) }
        if i < pet.series.mood.count     { dot(pet.series.mood[i],     LP.Colors.coral, 2.5) }
    }
}

// MARK: - Legend

/// "心情 · 精力 · 体力" legend rendered above the chart. Single line, mono.
struct CatalogTrajectoryLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            chip(color: LP.Colors.coral, label: "心情", thick: true)
            chip(color: LP.Colors.muted, label: "精力", thick: false)
            chip(color: LP.Colors.ink,   label: "体力", thick: false)
        }
        .lpText(LP.Typography.monoTiny)
        .foregroundStyle(LP.Colors.muted)
    }

    private func chip(color: Color, label: String, thick: Bool) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: thick ? 2.5 : 2)
            Text(label)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        CatalogTrajectoryLegend()
        CatalogTrajectoryChart(pet: .bean)
            .lpStampedCard()
        CatalogTrajectoryChart(pet: .blob)
            .lpStampedCard()
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}
