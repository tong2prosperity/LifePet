import SwiftUI

/// 睡眠 card — the approved continuous cloud trail (Harmony-first 2026-09-08
/// 「云雾轨迹」). One continuous contour per contiguous run of recorded
/// intervals, filled strictly by each interval's real start/end.
///
/// Truthfulness rules this view must keep:
/// - no stages → total, times and 缺少阶段记录; never a fabricated timeline;
/// - unrecorded gaps break the contour; short intervals keep their real width;
/// - the initial overview has no cursor; a tap selects the interval that
///   contains the tapped time (a gap picks the nearest boundary interval).
struct HistorySleepCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let totalSeconds: TimeInterval
    /// Fall-asleep time (the card range starts here, like the detail header).
    let start: Date?
    /// Wake time. Never computed from `start + total`.
    let end: Date?
    let segments: [SleepSegmentValue]
    /// Embedded inside the detail sheet: no chrome, title or duration.
    var embedded: Bool = false
    /// History shows 「展开睡眠详情」 when a night exists.
    var onExpand: (() -> Void)?

    @State private var selectedSegment: SleepSegmentValue?
    @State private var isRevealed = false

    private var plotted: [SleepSegmentValue] { SleepTrailGeometry.validSegments(segments) }

    private var timeline: SleepTrailTimeline? {
        SleepTrailGeometry.timeline(segments: plotted, fallbackStart: start, fallbackEnd: end)
    }

    private var graphHeight: CGFloat { embedded ? 116 : 204 }
    private var trailCenter: CGFloat { graphHeight - 43 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                Text(AppLocalization.text("睡眠"))
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xC4CBDC))
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
            }
            if totalSeconds > 0 {
                Group {
                    if let timeline {
                        trailContent(timeline)
                    } else {
                        stagelessContent
                    }
                }
                .padding(.horizontal, embedded ? 0 : 24)
                .padding(.bottom, embedded ? 0 : (onExpand == nil ? 24 : 4))
            } else {
                Text(AppLocalization.text("暂无睡眠数据"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0xA7AEC0))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
            }
            if let onExpand, totalSeconds > 0 {
                Button {
                    LPHaptics.tap()
                    onExpand()
                } label: {
                    Text(AppLocalization.text("展开睡眠详情"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xC4CBDC))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !embedded {
                LinearGradient(
                    colors: [Color(hex: 0x252B3A), Color(hex: 0x1E2430)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: embedded ? 0 : 26, style: .continuous))
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(hex: 0xA7B4D5, alpha: 0x22 / 255), lineWidth: 1)
            }
        }
        .onAppear { reveal() }
        .onChange(of: segments) { _, _ in resetForNewData() }
        .onChange(of: start) { _, _ in resetForNewData() }
        .onChange(of: end) { _, _ in resetForNewData() }
    }

    // MARK: Trail

    @ViewBuilder
    private func trailContent(_ timeline: SleepTrailTimeline) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    SleepCloudTrailCanvas(
                        segments: plotted,
                        timeline: timeline,
                        center: trailCenter,
                        selected: selectedSegment
                    )
                    if !embedded {
                        durationHeader(timeline)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        select(atX: value.location.x, width: geometry.size.width, timeline: timeline)
                    }
                )
            }
            .frame(height: graphHeight)
            .opacity(isRevealed ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.text("睡眠阶段图"))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(AppLocalization.text("轻点不同位置选择睡眠片段；上下轻扫逐段切换"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }

            SleepTrailRuler(timeline: timeline)
                .opacity(isRevealed ? 1 : 0)

            if let selectedSegment {
                Text(SleepTrailFormat.selectionDetail(selectedSegment))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xC4CBDC))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }

            legend
                .padding(.top, 24)
        }
    }

    private func durationHeader(_ timeline: SleepTrailTimeline) -> some View {
        let minutes = Int((totalSeconds / 60).rounded(.down))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(minutes / 60)")
                    .font(.system(size: 50, weight: .light))
                Text(AppLocalization.text("小时"))
                    .font(.system(size: 23))
                Text("\(minutes % 60)")
                    .font(.system(size: 50, weight: .light))
                Text(AppLocalization.text("分"))
                    .font(.system(size: 23))
            }
            .foregroundStyle(Color(hex: 0xF7F1EA))
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format("睡眠 %d 小时 %d 分", minutes / 60, minutes % 60))
            // Same semantics as the detail header: fall-asleep → wake. The
            // trail and axis still start at the earliest recorded interval, so
            // a pre-sleep awake stretch stays visible.
            Text("\(SleepTrailFormat.clock(start ?? timeline.start)) — \(SleepTrailFormat.clock(end ?? timeline.end))")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xACB3C8))
                .monospacedDigit()
        }
    }

    private var legend: some View {
        HStack {
            ForEach(SleepTrailPalette.stageOrder, id: \.rawValue) { stage in
                HStack(spacing: 4) {
                    if embedded {
                        Circle()
                            .fill(SleepTrailPalette.color(stage))
                            .frame(width: 12, height: 12)
                    } else {
                        Capsule()
                            .fill(SleepTrailPalette.color(stage))
                            .frame(width: 16, height: 10)
                    }
                    Text(stage.trailDisplayName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xC4CBDC))
                }
                if stage != SleepTrailPalette.stageOrder.last { Spacer(minLength: 0) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Stageless

    private var stagelessContent: some View {
        let minutes = Int((totalSeconds / 60).rounded(.down))
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0x7F899C))
                .accessibilityHidden(true)
            Text(AppLocalization.format("%d 小时 %d 分", minutes / 60, minutes % 60))
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(hex: 0xF7F1EA))
                .monospacedDigit()
            Text("\(SleepTrailFormat.clock(start)) — \(SleepTrailFormat.clock(end))")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xACB3C8))
                .monospacedDigit()
            Text(AppLocalization.text("缺少阶段记录"))
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xC4CBDC))
            Text(AppLocalization.text("仅有睡眠总量，无法展示阶段时间线"))
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x8D97AC))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, embedded ? 8 : 0)
        .accessibilityElement(children: .combine)
    }

    // MARK: Interaction

    private var accessibilityValue: String {
        if let selectedSegment {
            return AppLocalization.format(
                "%@，%@ 到 %@，%d 分钟",
                selectedSegment.stage.trailDisplayName,
                SleepTrailFormat.clock(selectedSegment.start),
                SleepTrailFormat.clock(selectedSegment.end),
                SleepTrailFormat.minutes(selectedSegment)
            )
        }
        return AppLocalization.format("共 %d 段记录，未选择片段", plotted.count)
    }

    private func select(atX x: CGFloat, width: CGFloat, timeline: SleepTrailTimeline) {
        guard let segment = SleepTrailGeometry.segment(
            atX: x, width: width, segments: plotted, timeline: timeline
        ), segment != selectedSegment else { return }
        LPHaptics.tap()
        selectedSegment = segment
    }

    private func step(_ offset: Int) {
        guard let next = SleepTrailGeometry.adjacent(
            to: selectedSegment, offset: offset, segments: plotted
        ), next != selectedSegment else { return }
        selectedSegment = next
    }

    private func resetForNewData() {
        selectedSegment = nil
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { isRevealed = false }
        reveal()
    }

    /// Fade only — the reveal never animates geometry, so a short interval
    /// is never drawn wider than its real duration, even mid-animation.
    private func reveal() {
        guard !isRevealed else { return }
        if reduceMotion {
            isRevealed = true
        } else {
            withAnimation(.easeOut(duration: 0.24)) { isRevealed = true }
        }
    }
}
