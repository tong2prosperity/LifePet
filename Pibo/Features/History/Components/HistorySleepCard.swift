import SwiftUI

/// 睡眠 card — total duration over a clouds illustration + a sleep-stage timeline,
/// on a dark grey-850 surface (Figma `activity card` 1193:2161). One cloud per
/// stage segment of the night: x = when it happened, y = its stage band
/// (眼动 top / 浅睡 middle / 深睡 bottom), size = its duration (designer note:
/// 云朵大小映射每段时长 · 水平高度区分).
struct HistorySleepCard: View {
    let totalSeconds: TimeInterval
    let deepSeconds: TimeInterval
    let remSeconds: TimeInterval
    let start: Date?
    let end: Date?
    /// The night's stage segments. Empty (legacy rows) → clouds are derived
    /// from the stage totals instead.
    let segments: [SleepSegmentValue]

    var body: some View {
        HistoryCard(title: "睡眠", dark: true, background: { LP.Neutral.grey850 }) {
            VStack(spacing: LP.Spacing.xs) {
                if totalSeconds > 0 {
                    durationLine
                    SleepClouds(
                        segments: displaySegments,
                        nightStart: start, nightEnd: end)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                    timeline
                } else {
                    Text(AppLocalization.text("暂无睡眠数据"))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(LP.Content.invertQuarternary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LP.Spacing.xxl)
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.s)
        }
    }

    /// Sleep-only segments for the illustration; legacy rows without segments
    /// get a plausible 浅睡/深睡/眼动 spread synthesized from the totals.
    private var displaySegments: [SleepSegmentValue] {
        let asleep = segments.filter { $0.stage != .awake }
        if !asleep.isEmpty { return asleep }
        guard let start, totalSeconds > 0 else { return [] }
        let core = max(0, totalSeconds - deepSeconds - remSeconds)
        // Rough night shape: 浅睡 → 深睡 (front-loaded) → 浅睡 → 眼动 (toward morning).
        let plan: [(SleepStage, TimeInterval)] = [
            (.core, core * 0.5), (.deep, deepSeconds), (.core, core * 0.5), (.rem, remSeconds),
        ]
        var t = start
        return plan.compactMap { stage, dur in
            guard dur > 60 else { return nil }
            defer { t = t.addingTimeInterval(dur) }
            return SleepSegmentValue(start: t, end: t.addingTimeInterval(dur), stage: stage)
        }
    }

    private var hours: Int { Int(totalSeconds) / 3600 }
    private var minutes: Int { (Int(totalSeconds) % 3600) / 60 }
    private var deepMinutes: Int { Int(deepSeconds) / 60 }

    private var durationLine: some View {
        HStack(spacing: LP.Spacing.s) {
            valueUnit("\(hours)", "h")
            valueUnit("\(minutes)", "min")
        }
    }

    private func valueUnit(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
            Text(value).lpText(LP.Typography.uiH4).foregroundStyle(LP.Content.invertPrimary)
            Text(unit).lpText(LP.Typography.b3Medium).foregroundStyle(LP.Content.invertPrimary)
                .padding(.bottom, 2)
        }
    }

    private var timeline: some View {
        HStack {
            Text(timeString(start) ?? "—")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.invertSecondary)
            Spacer(minLength: 0)
            if deepMinutes > 0 {
                Text(AppLocalization.format("深睡 %d 分钟", deepMinutes))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.invertQuarternary)
            }
            Spacer(minLength: 0)
            Text(timeString(end) ?? "—")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.invertSecondary)
        }
    }

    private func timeString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.hm.string(from: date)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "H:mm"
        return f
    }()
}

/// The night rendered as clouds over three faint stage lines (mock: 水平高度区分
/// 眼动/浅睡/深睡). Each segment becomes one cloud at its time position; cloud
/// scale follows duration, color follows stage (眼动 near-white, 浅睡 blue,
/// 深睡 dark purple). A faint ruler runs along the bottom.
private struct SleepClouds: View {
    let segments: [SleepSegmentValue]
    let nightStart: Date?
    let nightEnd: Date?

    /// y fraction of each stage band line.
    private static let bandY: [SleepStage: CGFloat] = [.rem: 0.2, .core: 0.5, .deep: 0.8]
    /// Don't draw clouds for slivers shorter than this — they'd be unreadable.
    private static let minVisible: TimeInterval = 8 * 60
    /// At most this many clouds; beyond it keep the longest (restless nights
    /// produce dozens of slivers).
    private static let maxClouds = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                ForEach([SleepStage.rem, .core, .deep], id: \.rawValue) { stage in
                    bandLine(stage: stage, w: w, h: h)
                }
                ruler(width: w).frame(height: 8).position(x: w / 2, y: h - 4)

                ForEach(visibleSegments.indices, id: \.self) { i in
                    let seg = visibleSegments[i]
                    cloud(color: color(of: seg.stage), scale: scale(for: seg.duration))
                        .position(x: x(for: seg, width: w),
                                  y: h * (Self.bandY[seg.stage] ?? 0.5))
                }
            }
        }
    }

    // MARK: Segment layout

    private var visibleSegments: [SleepSegmentValue] {
        var visible = segments.filter { $0.duration >= Self.minVisible }
        if visible.isEmpty { visible = segments }   // all-sliver night: show something
        guard visible.count > Self.maxClouds else { return visible }
        // Cap by duration, but guarantee each present stage keeps its two
        // longest clouds — a pure longest-N cut would drop every 眼动 segment
        // (REM periods run shorter than 浅睡/深睡) and empty the top band.
        var keep = Set<Date>()
        for stage in [SleepStage.rem, .core, .deep] {
            visible.filter { $0.stage == stage }
                .sorted { $0.duration > $1.duration }
                .prefix(2)
                .forEach { keep.insert($0.start) }
        }
        for seg in visible.sorted(by: { $0.duration > $1.duration }) {
            if keep.count >= Self.maxClouds { break }
            keep.insert(seg.start)
        }
        return visible.filter { keep.contains($0.start) }
    }

    /// Segment midpoint mapped across the night span, inset so the largest
    /// cloud stays inside the card.
    private func x(for seg: SleepSegmentValue, width: CGFloat) -> CGFloat {
        let inset: CGFloat = 40
        guard let nightStart, let nightEnd,
              nightEnd.timeIntervalSince(nightStart) > 0 else { return width / 2 }
        let span = nightEnd.timeIntervalSince(nightStart)
        let mid = seg.start.addingTimeInterval(seg.duration / 2)
        let frac = max(0, min(1, mid.timeIntervalSince(nightStart) / span))
        return inset + frac * (width - inset * 2)
    }

    /// 云朵大小映射每段时长: ~15 min reads small, ≥90 min reads full.
    private func scale(for duration: TimeInterval) -> CGFloat {
        0.45 + CGFloat(min(1.0, duration / 5400)) * 0.75
    }

    private func color(of stage: SleepStage) -> Color {
        switch stage {
        case .rem:   return .white.opacity(0.88)
        case .core:  return LP.Colorful.blue400
        case .deep:  return LP.Colorful.purple600
        case .awake: return .white.opacity(0.3)
        }
    }

    // MARK: Chrome

    private func bandLine(stage: SleepStage, w: CGFloat, h: CGFloat) -> some View {
        let y = h * (Self.bandY[stage] ?? 0.5)
        let label: String = switch stage {
        case .rem: "眼动"
        case .core: "浅睡"
        case .deep: "深睡"
        case .awake: ""
        }
        return ZStack(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: w, height: 1)
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.invertQuarternary)
                .padding(.trailing, 2)
                .background(LP.Neutral.grey850)
        }
        .position(x: w / 2, y: y)
    }

    private func cloud(color: Color, scale: CGFloat) -> some View {
        ZStack {
            Circle().frame(width: 24, height: 24).offset(x: -15)
            Circle().frame(width: 34, height: 34)
            Circle().frame(width: 22, height: 22).offset(x: 16, y: 3)
            Capsule().frame(width: 58, height: 16).offset(y: 11)
        }
        .foregroundStyle(color)
        .scaleEffect(scale)
        .frame(width: 64, height: 44)
    }

    private func ruler(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, Int(width / 6)), id: \.self) { _ in
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 6)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}
