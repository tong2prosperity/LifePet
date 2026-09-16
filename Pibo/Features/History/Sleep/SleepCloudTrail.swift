import SwiftUI

// MARK: - Palette

/// Stage colors of the continuous cloud trail. Shared by the history card, the
/// detail sheet (trail, mini trail, stage list) and the morning card so a stage
/// always reads as the same hue.
enum SleepTrailPalette {
    static let light = Color(hex: 0x8DABF4)   // 浅睡
    static let deep = Color(hex: 0x5552A5)    // 深睡
    static let rem = Color(hex: 0xC3A8EF)     // 眼动
    static let awake = Color(hex: 0xF8EAD8)   // 清醒 — warm-white seam

    static func color(_ stage: SleepStage) -> Color {
        switch stage {
        case .core: light
        case .deep: deep
        case .rem: rem
        case .awake: awake
        }
    }

    /// Legend / stage-list order.
    static let stageOrder: [SleepStage] = [.awake, .rem, .core, .deep]
}

extension SleepStage {
    var trailDisplayName: String {
        switch self {
        case .awake: AppLocalization.text("清醒")
        case .rem: AppLocalization.text("眼动")
        case .core: AppLocalization.text("浅睡")
        case .deep: AppLocalization.text("深睡")
        }
    }
}

// MARK: - Geometry

/// The visible time axis of one night.
struct SleepTrailTimeline: Equatable {
    let start: Date
    let end: Date

    var span: TimeInterval { end.timeIntervalSince(start) }

    func x(of date: Date, width: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat(date.timeIntervalSince(start) / span) * width
    }
}

struct SleepTrailPoint: Equatable {
    var x: CGFloat
    var top: CGFloat
    var bottom: CGFloat
}

/// One exact-time color slice inside a contour.
struct SleepTrailSlice: Equatable {
    let x: CGFloat
    let width: CGFloat
    let stage: SleepStage
}

/// One contour: a contiguous run of recorded intervals.
struct SleepTrailRun: Equatable {
    var left: CGFloat
    var right: CGFloat
    var points: [SleepTrailPoint]
    var slices: [SleepTrailSlice]
}

/// Pure platform geometry for the continuous cloud trail.
///
/// Color boundaries always use recorded timestamps; the soft outline (bezier
/// contour + small undulation) is decoration only, never a continuous estimate
/// of sleep depth. Nothing here fabricates stages: unrecorded time breaks the
/// contour, overlapping inputs become separate contours, and a short interval
/// keeps its true proportional width (no minimum width).
enum SleepTrailGeometry {
    /// Two recorded intervals continue one contour only when they touch.
    static let continuityTolerance: TimeInterval = 0.001

    /// Finite, positive, known-stage intervals sorted by time.
    static func validSegments(_ source: [SleepSegmentValue]) -> [SleepSegmentValue] {
        source
            .filter { segment in
                segment.start.timeIntervalSinceReferenceDate.isFinite
                    && segment.end.timeIntervalSinceReferenceDate.isFinite
                    && segment.end > segment.start
                    && SleepStage(rawValue: segment.stageRaw) != nil
            }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
            }
    }

    /// Axis spanning every recorded interval, widened by the supplied
    /// fall-asleep / wake times when they lie outside. `nil` without stages —
    /// a total alone never gets a timeline.
    static func timeline(
        segments: [SleepSegmentValue],
        fallbackStart: Date? = nil,
        fallbackEnd: Date? = nil
    ) -> SleepTrailTimeline? {
        let values = validSegments(segments)
        guard let first = values.first else { return nil }
        var start = first.start
        var end = first.end
        for segment in values {
            start = min(start, segment.start)
            end = max(end, segment.end)
        }
        if let fallbackStart, fallbackStart.timeIntervalSinceReferenceDate.isFinite {
            start = min(start, fallbackStart)
        }
        if let fallbackEnd, fallbackEnd.timeIntervalSinceReferenceDate.isFinite {
            end = max(end, fallbackEnd)
        }
        guard end > start else { return nil }
        return SleepTrailTimeline(start: start, end: end)
    }

    /// Contours for `segments` on `width` points.
    static func runs(
        segments source: [SleepSegmentValue],
        timeline: SleepTrailTimeline,
        width: CGFloat,
        heightScale: CGFloat = 1
    ) -> [SleepTrailRun] {
        let values = validSegments(source)
        guard width > 0, timeline.span > 0, !values.isEmpty else { return [] }
        var runs: [SleepTrailRun] = []
        var previousEnd: Date?
        for segment in values {
            let left = timeline.x(of: segment.start, width: width)
            let right = timeline.x(of: segment.end, width: width)
            let continues = previousEnd.map {
                abs(segment.start.timeIntervalSince($0)) <= continuityTolerance
            } ?? false
            // Never bridge a missing observation; overlapping inputs start a
            // separate silhouette instead of inventing an order or blend.
            if !continues || runs.isEmpty {
                runs.append(SleepTrailRun(left: left, right: right, points: [], slices: []))
            }
            let index = runs.count - 1
            runs[index].right = right
            runs[index].slices.append(
                SleepTrailSlice(x: left, width: right - left, stage: segment.stage)
            )
            // Waking is a precise seam; it must not raise a decorative spike.
            if segment.stage != .awake {
                let top: CGFloat = switch segment.stage {
                case .rem: -25
                case .deep: -9
                default: -16
                }
                let bottom: CGFloat = segment.stage == .deep ? 29 : 14
                runs[index].points.append(SleepTrailPoint(
                    x: (left + right) / 2,
                    top: top * heightScale,
                    bottom: bottom * heightScale
                ))
            }
            previousEnd = segment.end
        }
        return runs.map { run in
            var run = run
            if run.points.isEmpty {
                run.points = [SleepTrailPoint(
                    x: (run.left + run.right) / 2,
                    top: -16 * heightScale,
                    bottom: 14 * heightScale
                )]
            }
            var contour: [SleepTrailPoint] = []
            for (index, point) in run.points.enumerated() {
                if index > 0 {
                    let previous = run.points[index - 1]
                    let softness = min(3, (point.x - previous.x) * 0.12) * heightScale
                    contour.append(SleepTrailPoint(
                        x: (previous.x + point.x) / 2,
                        top: (previous.top + point.top) / 2 + softness,
                        bottom: (previous.bottom + point.bottom) / 2 - softness * 0.5
                    ))
                }
                contour.append(point)
            }
            run.points = contour
            return run
        }
    }

    /// Closed contour with bounded bezier edges and rounded caps.
    static func path(for run: SleepTrailRun, center: CGFloat) -> Path {
        var path = Path()
        guard let first = run.points.first, let last = run.points.last,
              run.right > run.left else { return path }
        let cap = min(12, (run.right - run.left) / 2)
        let left = run.left + cap
        let right = run.right - cap
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: center + y) }

        path.move(to: point(run.left, (first.top + first.bottom) / 2))
        path.addCurve(to: point(left, first.top),
                      control1: point(run.left, first.top),
                      control2: point(left, first.top))
        var x = left
        var y = first.top
        for p in run.points where p.x > left && p.x < right {
            let middle = (x + p.x) / 2
            path.addCurve(to: point(p.x, p.top),
                          control1: point(middle, y),
                          control2: point(middle, p.top))
            x = p.x
            y = p.top
        }
        path.addCurve(to: point(right, last.top),
                      control1: point((x + right) / 2, y),
                      control2: point((x + right) / 2, last.top))
        path.addCurve(to: point(run.right, (last.top + last.bottom) / 2),
                      control1: point(run.right, last.top),
                      control2: point(run.right, last.top))
        path.addCurve(to: point(right, last.bottom),
                      control1: point(run.right, last.bottom),
                      control2: point(run.right, last.bottom))
        x = right
        y = last.bottom
        for p in run.points.reversed() where p.x > left && p.x < right {
            let middle = (x + p.x) / 2
            path.addCurve(to: point(p.x, p.bottom),
                          control1: point(middle, y),
                          control2: point(middle, p.bottom))
            x = p.x
            y = p.bottom
        }
        path.addCurve(to: point(left, first.bottom),
                      control1: point((x + left) / 2, y),
                      control2: point((x + left) / 2, first.bottom))
        path.addCurve(to: point(run.left, (first.top + first.bottom) / 2),
                      control1: point(run.left, first.bottom),
                      control2: point(run.left, first.bottom))
        path.closeSubpath()
        return path
    }

    /// The interval containing the tapped time; inside an unrecorded gap the
    /// segment whose boundary is nearest in time.
    static func segment(
        atX x: CGFloat,
        width: CGFloat,
        segments source: [SleepSegmentValue],
        timeline: SleepTrailTimeline
    ) -> SleepSegmentValue? {
        let values = validSegments(source)
        guard !values.isEmpty, width > 0 else { return nil }
        let fraction = Double(max(0, min(1, x / width)))
        let time = timeline.start.addingTimeInterval(fraction * timeline.span)
        if let containing = values.first(where: { time >= $0.start && time < $0.end }) {
            return containing
        }
        return values.min { lhs, rhs in
            boundaryDistance(lhs, time) < boundaryDistance(rhs, time)
        }
    }

    private static func boundaryDistance(_ segment: SleepSegmentValue, _ time: Date) -> TimeInterval {
        min(abs(segment.start.timeIntervalSince(time)), abs(segment.end.timeIntervalSince(time)))
    }

    /// Sequential stepping for VoiceOver. With no current selection the first
    /// step lands on the first (or last) interval.
    static func adjacent(
        to current: SleepSegmentValue?,
        offset: Int,
        segments source: [SleepSegmentValue]
    ) -> SleepSegmentValue? {
        let values = validSegments(source)
        guard !values.isEmpty else { return nil }
        guard let current,
              let index = values.firstIndex(of: current) else {
            return offset >= 0 ? values.first : values.last
        }
        return values[max(0, min(values.count - 1, index + offset))]
    }

    /// Interior local whole-hour ticks, thinned to about four and kept clear of
    /// the start/end labels.
    static func hourTicks(
        timeline: SleepTrailTimeline,
        width: CGFloat,
        edgeClearance: CGFloat = 60,
        calendar: Calendar = .current
    ) -> [Date] {
        guard width > 0, timeline.span > 0 else { return [] }
        let stepHours = max(1, Int((timeline.span / 3600 / 4).rounded(.up)))
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: timeline.start)
        components.minute = 0
        components.second = 0
        guard let floorHour = calendar.date(from: components) else { return [] }
        var ticks: [Date] = []
        var tick = calendar.date(byAdding: .hour, value: stepHours, to: floorHour)
        while let current = tick, current < timeline.end {
            let position = timeline.x(of: current, width: width)
            if position >= edgeClearance, width - position >= edgeClearance {
                ticks.append(current)
            }
            tick = calendar.date(byAdding: .hour, value: stepHours, to: current)
        }
        return ticks
    }
}

// MARK: - Formatting

enum SleepTrailFormat {
    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return clockFormatter.string(from: date)
    }

    static func minutes(_ segment: SleepSegmentValue) -> Int {
        max(1, Int((segment.duration / 60).rounded()))
    }

    static func selectionDetail(_ segment: SleepSegmentValue) -> String {
        AppLocalization.format(
            "%@–%@ · %@ %d 分钟",
            clock(segment.start),
            clock(segment.end),
            segment.stage.trailDisplayName,
            minutes(segment)
        )
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Canvas

/// Draws the trail. Canvas re-runs its closure whenever any input or the size
/// changes, so every data / size change is a full redraw with no stale geometry.
struct SleepCloudTrailCanvas: View {
    let segments: [SleepSegmentValue]
    let timeline: SleepTrailTimeline
    /// Vertical center of the contour inside the canvas.
    let center: CGFloat
    var heightScale: CGFloat = 1
    var selected: SleepSegmentValue?

    var body: some View {
        Canvas { context, size in
            let runs = SleepTrailGeometry.runs(
                segments: segments,
                timeline: timeline,
                width: size.width,
                heightScale: heightScale
            )
            let unaliased = FillStyle(antialiased: false)
            for run in runs {
                let contour = SleepTrailGeometry.path(for: run, center: center)
                context.drawLayer { layer in
                    layer.clip(to: contour)
                    // One fill per exact-time slice; pixel-snapped so adjacent
                    // slices never leave a hairline seam between them.
                    for slice in run.slices {
                        layer.fill(
                            Path(CGRect(x: slice.x, y: 0, width: slice.width, height: size.height)),
                            with: .color(SleepTrailPalette.color(slice.stage)),
                            style: unaliased
                        )
                    }
                    // One shared, subtle light treatment across the silhouette.
                    layer.fill(
                        Path(CGRect(x: run.left, y: 0, width: run.right - run.left, height: size.height)),
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0x22 / 255), location: 0),
                                .init(color: .white.opacity(0), location: 0.48),
                                .init(color: Color(hex: 0x0A103D, alpha: 0x14 / 255), location: 1),
                            ]),
                            startPoint: CGPoint(x: 0, y: center - 28 * heightScale),
                            endPoint: CGPoint(x: 0, y: center + 32 * heightScale)
                        )
                    )
                }
            }
            if let selected {
                let x = timeline.x(
                    of: selected.start.addingTimeInterval(selected.duration / 2),
                    width: size.width
                )
                var line = Path()
                line.move(to: CGPoint(x: x, y: center - 37 * heightScale))
                line.addLine(to: CGPoint(x: x, y: center + 35 * heightScale))
                context.stroke(line, with: .color(.white.opacity(0xC7 / 255)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Start / interior-hour / end labels under the trail.
struct SleepTrailRuler: View {
    let timeline: SleepTrailTimeline

    var body: some View {
        Canvas { context, size in
            let lineColor = Color(hex: 0x748399, alpha: 0x66 / 255)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0.5, y: 1))
            baseline.addLine(to: CGPoint(x: size.width - 0.5, y: 1))
            context.stroke(baseline, with: .color(lineColor), lineWidth: 0.7)

            let ticks = [timeline.start]
                + SleepTrailGeometry.hourTicks(timeline: timeline, width: size.width)
                + [timeline.end]
            for (index, time) in ticks.enumerated() {
                let x = max(0.5, min(size.width - 0.5, timeline.x(of: time, width: size.width)))
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 1))
                tick.addLine(to: CGPoint(x: x, y: 8))
                context.stroke(tick, with: .color(lineColor), lineWidth: 0.7)
                let label = context.resolve(
                    Text(SleepTrailFormat.clock(time))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color(hex: 0xAAB2C7))
                )
                let anchor: UnitPoint = index == 0
                    ? .topLeading
                    : (index == ticks.count - 1 ? .topTrailing : .top)
                context.draw(label, at: CGPoint(x: x, y: 14), anchor: anchor)
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}
