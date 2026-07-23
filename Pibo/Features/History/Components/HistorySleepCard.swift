import SwiftUI

/// 睡眠 card — a nocturnal cloudscape rather than a chart (Figma `activity card`
/// 1193:2161 + the cloud mock): the total duration floats centered in the sky,
/// below it one opaque puffy cloud per stage segment of the night — x = when it
/// happened, loose vertical band = its stage (清醒 high / 眼动 / 浅睡 / 深睡 low),
/// size = its duration. No gridlines or lane labels; the only chart language is
/// the tick ruler at the bottom (same grammar as 今日脚步) and a thin white
/// hairline marking the inspected segment.
struct HistorySleepCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let totalSeconds: TimeInterval
    let deepSeconds: TimeInterval
    let remSeconds: TimeInterval
    let start: Date?
    let end: Date?
    /// The night's stage segments. Empty (legacy rows) → clouds are derived
    /// from the stage totals instead.
    let segments: [SleepSegmentValue]
    /// The morning modal shows the duration in its own hero, so it hides the
    /// card's built-in duration line to avoid printing the same number twice.
    var showsDuration: Bool = true

    @State private var selectedSegmentStart: Date?
    @State private var isVisible = false
    @State private var isRevealed = false
    @State private var revealGeneration = 0

    /// Sky reserved for the centered duration hero; clouds band below it.
    private var skyInset: CGFloat { showsDuration ? 64 : 10 }
    private var cloudFieldHeight: CGFloat { showsDuration ? 196 : 172 }

    var body: some View {
        HistoryCard(title: "睡眠", dark: true, background: { LP.Neutral.grey800 }) {
            VStack(spacing: 0) {
                if totalSeconds > 0 {
                    ZStack(alignment: .top) {
                        SleepClouds(
                            segments: displaySegments,
                            nightStart: effectiveStart,
                            nightEnd: effectiveEnd,
                            topInset: skyInset,
                            selectedSegmentStart: $selectedSegmentStart,
                            isRevealed: isRevealed)
                            .frame(height: cloudFieldHeight)
                            .frame(maxWidth: .infinity)
                        if showsDuration {
                            durationLine
                                .frame(maxWidth: .infinity)
                                .padding(.top, LP.Spacing.xs)
                                .opacity(isRevealed ? 1 : 0)
                                .offset(y: isRevealed ? 0 : 4)
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 0.28),
                                    value: isRevealed)
                                .allowsHitTesting(false)
                        }
                    }
                    ruler
                        .padding(.top, 6)
                    timeline
                        .padding(.top, LP.Spacing.xs)
                        .opacity(isRevealed ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.20).delay(0.12),
                            value: isRevealed)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.m)
        }
        // `VStack` eagerly builds every card in the ScrollView. Visibility-gated
        // reveal keeps this animation from finishing before the user reaches it.
        .onScrollVisibilityChange(threshold: 0.32) { visible in
            isVisible = visible
            guard visible, !isRevealed else { return }
            startReveal()
        }
        .onChange(of: displaySegments, initial: true) { _, _ in
            selectedSegmentStart = nil
            resetReveal()
        }
    }

    /// Keep every real HealthKit interval, including brief awake periods. The
    /// timeline must not sample or discard intervals merely to look tidier.
    private var displaySegments: [SleepSegmentValue] {
        let recorded = segments
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        if !recorded.isEmpty { return recorded }
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

    /// Prefer the real segment bounds over aggregate start/end. Aggregate totals
    /// exclude awake gaps, so `start + total` can otherwise compress the timeline.
    private var effectiveStart: Date? {
        displaySegments.map(\.start).min() ?? start
    }

    private var effectiveEnd: Date? {
        displaySegments.map(\.end).max() ?? end
    }

    private var selectedSegment: SleepSegmentValue? {
        if let selectedSegmentStart,
           let selected = displaySegments.first(where: { $0.start == selectedSegmentStart }) {
            return selected
        }
        return displaySegments
            .filter { $0.stage == .deep }
            .max { $0.duration < $1.duration }
            ?? displaySegments.first
    }

    private var durationLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
            valueUnit("\(hours)", "h")
            valueUnit("\(minutes)", "min")
        }
    }

    private func valueUnit(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .lpText(LP.Typography.uiH3)
                .foregroundStyle(LP.Content.invertPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.24), value: value)
            Text(unit)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.invertSecondary)
        }
    }

    private var ruler: some View {
        SleepTickRuler()
            .stroke(Color.white.opacity(0.30), lineWidth: 1)
            .frame(height: 9)
            .opacity(isRevealed ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isRevealed)
            .accessibilityHidden(true)
    }

    private var timeline: some View {
        ZStack {
            HStack {
                Text(timeString(effectiveStart) ?? "—")
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.invertPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(timeString(effectiveEnd) ?? "—")
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.invertPrimary)
                    .monospacedDigit()
            }

            Text(selectionDetail)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.invertSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 56)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: selectedSegmentStart)
        }
        .frame(height: 20)
    }

    private var selectionDetail: String {
        guard let segment = selectedSegment else {
            return deepMinutes > 0
                ? AppLocalization.format("深睡 %d 分钟", deepMinutes)
                : ""
        }
        let minutes = max(1, Int((segment.duration / 60).rounded()))
        return AppLocalization.format(
            "%@–%@ · %@ %d 分钟",
            timeString(segment.start) ?? "—",
            timeString(segment.end) ?? "—",
            segment.stage.displayName,
            minutes)
    }

    private var emptyState: some View {
        VStack(spacing: LP.Spacing.s) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LP.Content.invertQuarternary)
            Text(AppLocalization.text("暂无睡眠数据"))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.invertQuarternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    private func resetReveal() {
        revealGeneration += 1
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isRevealed = false
        }
        if isVisible {
            startReveal()
        }
    }

    private func startReveal() {
        revealGeneration += 1
        let generation = revealGeneration
        guard !reduceMotion else {
            isRevealed = true
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard isVisible, revealGeneration == generation else { return }
            isRevealed = true
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

/// One merged nocturnal cloud bank on a single common time scale. Clouds hang
/// from a per-stage baseline (their BOTTOM) and grow upward, so long stages
/// become broad banks rising toward the title while deeper stages hang lowest
/// and in front — the layers stack into one cloudscape instead of four rows.
private struct SleepClouds: View {
    let segments: [SleepSegmentValue]
    let nightStart: Date?
    let nightEnd: Date?
    /// Sky reserved above the clouds (the duration hero floats there).
    let topInset: CGFloat
    @Binding var selectedSegmentStart: Date?
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let renderedSegments = timelineSegments
            let selectedSegment = selection(in: renderedSegments)
            ZStack(alignment: .topLeading) {
                if let selected = selectedSegment {
                    let lineTop = max(2, topInset - 2)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.55),
                                ],
                                startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5, height: max(0, h - lineTop))
                        .position(x: x(for: selected, plotWidth: w), y: lineTop + (h - lineTop) / 2)
                        .opacity(isRevealed ? 1 : 0)
                        .zIndex(0.2)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.20).delay(0.12),
                            value: isRevealed)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: selectedSegmentStart)
                        .allowsHitTesting(false)
                }

                ForEach(Array(renderedSegments.enumerated()), id: \.element.start) { _, segment in
                    let progress = progress(for: segment)
                    let isSelected = selectedSegment?.start == segment.start
                    // Render wider than the data width so neighbors bleed into one
                    // cloud bank — the midpoint x stays data-true, only the puff
                    // overflows its slot. Height follows width; clouds hang from a
                    // baseline (bottom-anchored) and grow upward, filling the sky.
                    let width = cloudWidth(for: segment, timelineWidth: w) * 1.75
                    let height = cloudHeight(width: width)
                    TimelineCloud(
                        tint: color(of: segment.stage),
                        seed: UInt64(bitPattern: Int64(segment.start.timeIntervalSince1970)))
                        .frame(width: width, height: height)
                        .scaleEffect(isRevealed ? (isSelected ? 1.02 : 1) : 0.9, anchor: .bottom)
                        .opacity(isRevealed ? haze(of: segment.stage) : 0)
                        .position(
                            x: x(for: segment, plotWidth: w),
                            y: cloudBottomY(for: segment, plotHeight: h) - height / 2)
                        .zIndex(Double(bandIndex(of: segment.stage)))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeOut(duration: 0.30).delay(0.04 + progress * 0.18),
                            value: isRevealed)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: selectedSegmentStart)
                }
            }
            .contentShape(Rectangle())
            // A tap inspects the nearest segment without stealing vertical
            // scrolling, unlike a zero-distance drag gesture inside ScrollView.
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectNearest(to: value.location.x, plotWidth: w)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.text("睡眠阶段图"))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(AppLocalization.text("轻点不同位置，或上下滑动切换睡眠片段"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selectAdjacent(offset: 1)
                case .decrement: selectAdjacent(offset: -1)
                @unknown default: break
                }
            }
        }
    }

    // MARK: Segment layout

    private var timelineSegments: [SleepSegmentValue] {
        segments
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    /// Direct common-scale mapping across the full plot width.
    private func x(for seg: SleepSegmentValue, plotWidth: CGFloat) -> CGFloat {
        SleepTimelineGeometry.midpointX(
            segment: seg,
            nightStart: nightStart,
            nightEnd: nightEnd,
            width: plotWidth)
    }

    private func progress(for segment: SleepSegmentValue) -> Double {
        guard let nightStart, let nightEnd,
              nightEnd.timeIntervalSince(nightStart) > 0 else { return 0.5 }
        let midpoint = segment.start.addingTimeInterval(segment.duration / 2)
        return max(0, min(1, midpoint.timeIntervalSince(nightStart)
            / nightEnd.timeIntervalSince(nightStart)))
    }

    private func cloudWidth(for segment: SleepSegmentValue, timelineWidth: CGFloat) -> CGFloat {
        SleepTimelineGeometry.cloudWidth(
            duration: segment.duration,
            nightStart: nightStart,
            nightEnd: nightEnd,
            width: timelineWidth)
    }

    /// Height follows length so long stages read as banks, brief ones as puffs —
    /// bottom-anchored, so a tall bank grows up toward the title without clipping.
    private func cloudHeight(width: CGFloat) -> CGFloat {
        min(88, max(34, 22 + width * 0.40))
    }

    private func color(of stage: SleepStage) -> Color {
        switch stage {
        case .rem:   return LP.Colorful.purple300
        case .core:  return Self.coreTint
        case .deep:  return LP.Colorful.purple700
        case .awake: return LP.Neutral.grey200
        }
    }

    /// A softer, more periwinkle blue than `blue400` so 浅睡 (the dominant mass)
    /// sits inside the same dusk family as the lavender/indigo instead of reading
    /// as a separate, greener crayon.
    private static let coreTint = Color(hex: 0x83A2E4)

    /// Atmospheric recession: the upper, farther clouds (清醒 / 眼动) carry a
    /// little haze so they sit behind the solid, nearer lower bank.
    private func haze(of stage: SleepStage) -> Double {
        switch stage {
        case .awake: 0.84
        case .rem:   0.94
        default:     1.0
        }
    }

    /// Clouds hang from a per-stage baseline (their BOTTOM) and grow upward, so
    /// long banks rise toward the title and nothing clips on the ruler. Deeper
    /// stages hang lowest; a seeded jitter undulates the lower edge so the bank
    /// never reads as a ruled row of equal humps.
    private func cloudBottomY(for seg: SleepSegmentValue, plotHeight: CGFloat) -> CGFloat {
        let field = max(1, plotHeight - topInset)
        let base: CGFloat = switch seg.stage {
        case .awake: 0.46
        case .rem:   0.68
        case .core:  0.85
        case .deep:  0.95
        }
        let jitter = (unitJitter(seg) - 0.5) * 0.09
        let fraction = min(0.99, max(0.22, base + jitter))
        return topInset + field * fraction
    }

    /// Deterministic [0,1) offset per segment — same SplitMix64 idea as the cloud
    /// silhouette, so a night keeps its skyline across renders (no per-frame RNG).
    private func unitJitter(_ seg: SleepSegmentValue) -> CGFloat {
        var x = UInt64(bitPattern: Int64(seg.start.timeIntervalSince1970))
            &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31
        return CGFloat(x % 997) / 997
    }

    /// Lower bands render in front, like nearer clouds in a landscape.
    private func bandIndex(of stage: SleepStage) -> Int {
        switch stage {
        case .awake: 1
        case .rem:   2
        case .core:  3
        case .deep:  4
        }
    }

    private var resolvedSelectedSegment: SleepSegmentValue? {
        selection(in: timelineSegments)
    }

    private func selection(in candidates: [SleepSegmentValue]) -> SleepSegmentValue? {
        if let selectedSegmentStart,
           let selected = candidates.first(where: { $0.start == selectedSegmentStart }) {
            return selected
        }
        return candidates
            .filter { $0.stage == .deep }
            .max { $0.duration < $1.duration }
            ?? candidates.first
    }

    private func selectNearest(to locationX: CGFloat, plotWidth: CGFloat) {
        let candidates = timelineSegments
        guard !candidates.isEmpty else { return }
        let selected = candidates.min {
            abs(x(for: $0, plotWidth: plotWidth) - locationX)
                < abs(x(for: $1, plotWidth: plotWidth) - locationX)
        }
        guard let selected, selected.start != resolvedSelectedSegment?.start else { return }
        LPHaptics.tap()
        selectedSegmentStart = selected.start
    }

    private func selectAdjacent(offset: Int) {
        let candidates = timelineSegments
        guard !candidates.isEmpty else { return }
        let currentStart = selection(in: candidates)?.start
        let currentIndex = candidates.firstIndex(where: { $0.start == currentStart }) ?? 0
        let nextIndex = max(0, min(candidates.count - 1, currentIndex + offset))
        let next = candidates[nextIndex]
        guard next.start != currentStart else { return }
        LPHaptics.tap()
        selectedSegmentStart = next.start
    }

    private var accessibilityValue: String {
        guard let segment = resolvedSelectedSegment else {
            return AppLocalization.text("暂无睡眠阶段")
        }
        let minutes = max(1, Int((segment.duration / 60).rounded()))
        return AppLocalization.format("%@，%d 分钟", segment.stage.displayName, minutes)
    }
}

/// Pure common-scale geometry so timeline accuracy can be unit tested without
/// relying on screenshot measurements.
enum SleepTimelineGeometry {
    static let minimumCloudWidth: CGFloat = 34

    static func midpointX(
        segment: SleepSegmentValue,
        nightStart: Date?,
        nightEnd: Date?,
        width: CGFloat
    ) -> CGFloat {
        guard let nightStart, let nightEnd else { return width / 2 }
        let span = nightEnd.timeIntervalSince(nightStart)
        guard span > 0 else { return width / 2 }
        let midpoint = segment.start.addingTimeInterval(segment.duration / 2)
        let fraction = max(0, min(1, midpoint.timeIntervalSince(nightStart) / span))
        return width * fraction
    }

    static func cloudWidth(
        duration: TimeInterval,
        nightStart: Date?,
        nightEnd: Date?,
        width: CGFloat
    ) -> CGFloat {
        guard let nightStart, let nightEnd else { return minimumCloudWidth }
        let span = nightEnd.timeIntervalSince(nightStart)
        guard span > 0 else { return minimumCloudWidth }
        return max(minimumCloudWidth, width * max(0, duration) / span)
    }
}

/// One opaque puffy cloud: a flat capsule base with dome lobes rising off it.
/// Lobe count follows the aspect ratio and each cloud's lobes jitter from a
/// per-segment seed, so the skyline reads as weather rather than stamps.
private struct TimelineCloud: View {
    let tint: Color
    let seed: UInt64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lobes = max(2, min(7, Int((w / (h * 0.62)).rounded())))
            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .frame(width: w, height: h * 0.54)
                ForEach(0..<lobes, id: \.self) { i in
                    let t = (CGFloat(i) + 0.5) / CGFloat(lobes)
                    let spread = max(0, w - h * 0.82)
                    let jitter = (unit(UInt64(i) &* 7 &+ 1) - 0.5) * (spread / CGFloat(max(lobes, 1))) * 0.4
                    let dia = h * (0.68 + 0.30 * unit(UInt64(i) &* 13 &+ 5))
                    Circle()
                        .frame(width: min(dia, max(w, 1)))
                        .offset(
                            x: (t - 0.5) * spread + jitter,
                            y: -h * (0.04 + 0.10 * unit(UInt64(i) &* 29 &+ 11)))
                }
            }
            .frame(width: w, height: h, alignment: .bottom)
            .foregroundStyle(tint)
            .compositingGroup()
        }
        .accessibilityHidden(true)
    }

    /// Deterministic [0,1) hash — SplitMix64 finalizer — so a segment keeps the
    /// same silhouette across renders (no `Date.now`/random per frame).
    private func unit(_ salt: UInt64) -> CGFloat {
        var x = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return CGFloat(x % 1024) / 1024
    }
}

/// Time ruler under the cloudscape — same tick grammar as 今日脚步's ruler
/// (Figma `mark` 1496:2341): a tall tick every 4th at 8pt spacing, short ticks
/// (¼…¾ height) between.
private struct SleepTickRuler: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height
        var i = 0
        var x: CGFloat = 0.5
        while x <= r.width {
            let tall = i % 4 == 0
            p.move(to: CGPoint(x: x, y: tall ? 0 : h * 0.25))
            p.addLine(to: CGPoint(x: x, y: tall ? h : h * 0.75))
            x += 8
            i += 1
        }
        return p
    }
}

private extension SleepStage {
    var displayName: String {
        switch self {
        case .awake: AppLocalization.text("清醒")
        case .rem: AppLocalization.text("眼动")
        case .core: AppLocalization.text("浅睡")
        case .deep: AppLocalization.text("深睡")
        }
    }
}
