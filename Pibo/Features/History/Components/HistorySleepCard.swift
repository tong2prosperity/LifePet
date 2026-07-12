import SwiftUI

/// 睡眠 card — total duration over a clouds illustration + a sleep-stage timeline,
/// on a dark grey-850 surface (Figma `activity card` 1193:2161). One cloud per
/// stage segment of the night: x = when it happened, y = its stage band
/// (眼动 top / 浅睡 middle / 深睡 bottom), size = its duration (designer note:
/// 云朵大小映射每段时长 · 水平高度区分).
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

    @State private var selectedSegmentStart: Date?
    @State private var isVisible = false
    @State private var isRevealed = false
    @State private var revealGeneration = 0

    var body: some View {
        HistoryCard(title: "睡眠", dark: true, background: { LP.Neutral.grey850 }) {
            VStack(spacing: LP.Spacing.xs) {
                if totalSeconds > 0 {
                    durationLine
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed ? 0 : 4)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isRevealed)
                    SleepClouds(
                        segments: displaySegments,
                        nightStart: effectiveStart,
                        nightEnd: effectiveEnd,
                        selectedSegmentStart: $selectedSegmentStart,
                        isRevealed: isRevealed)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                    timeline
                        .opacity(isRevealed ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.24).delay(0.58),
                            value: isRevealed)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.s)
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
        HStack(spacing: LP.Spacing.s) {
            valueUnit("\(hours)", "h")
            valueUnit("\(minutes)", "min")
        }
    }

    private func valueUnit(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
            Text(value)
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.invertPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.24), value: value)
            Text(unit).lpText(LP.Typography.b3Medium).foregroundStyle(LP.Content.invertPrimary)
                .padding(.bottom, 2)
        }
    }

    private var timeline: some View {
        ZStack {
            HStack {
                Text(timeString(effectiveStart) ?? "—")
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.invertSecondary)
                Spacer(minLength: 0)
                Text(timeString(effectiveEnd) ?? "—")
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.invertSecondary)
            }

            Text(selectionDetail)
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.invertQuarternary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 44)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: selectedSegmentStart)
        }
        .frame(height: 18)
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

/// The night rendered as clouds across a faint time ruler. Each segment becomes
/// one cloud at its time position; vertical position + color encode stage (眼动
/// top / 浅睡 middle / 深睡 bottom), and s / m / l size encodes duration.
private struct SleepClouds: View {
    let segments: [SleepSegmentValue]
    let nightStart: Date?
    let nightEnd: Date?
    @Binding var selectedSegmentStart: Date?
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// y fraction inside the cloud area (the final 12pt are reserved for ticks).
    private static let bandY: [SleepStage: CGFloat] = [.rem: 0.25, .core: 0.5, .deep: 0.75]
    /// Don't draw clouds for slivers shorter than this — they'd be unreadable.
    private static let minVisible: TimeInterval = 8 * 60
    /// At most this many clouds; restless nights can produce dozens of slivers.
    private static let maxClouds = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cloudAreaHeight = max(1, h - 12)
            let renderedSegments = visibleSegments
            let selectedSegment = selection(in: renderedSegments)
            ZStack(alignment: .bottom) {
                ruler(width: w)
                    .frame(height: 8)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: isRevealed ? w : 0)
                    }
                    .animation(
                        reduceMotion
                            ? nil
                            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.62).delay(0.04),
                        value: isRevealed)
                    .position(x: w / 2, y: h - 4)

                ForEach(Array(renderedSegments.enumerated()), id: \.element.start) { _, segment in
                    let progress = progress(for: segment)
                    let isSelected = selectedSegment?.start == segment.start
                    let tint = color(of: segment.stage)
                    cloud(color: tint, scale: scale(for: segment.duration))
                        .scaleEffect(isRevealed ? (isSelected ? 1.05 : 1) : 0.64)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed ? (isSelected ? -2 : 0) : 7)
                        .shadow(
                            color: isSelected ? tint.opacity(0.34) : .clear,
                            radius: isSelected ? 7 : 0,
                            y: 2)
                        .position(
                            x: x(for: segment, width: w),
                            y: cloudAreaHeight * (Self.bandY[segment.stage] ?? 0.5))
                        .zIndex(Double(segment.stage.rawValue))
                        .animation(
                            reduceMotion
                                ? nil
                                : .spring(duration: 0.44, bounce: 0.2)
                                    .delay(0.08 + progress * 0.38),
                            value: isRevealed)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: selectedSegmentStart)
                }

                if let selected = selectedSegment {
                    Rectangle()
                        .fill(LP.Content.invertSecondary)
                        .frame(width: 1, height: cloudAreaHeight)
                        .scaleEffect(y: isRevealed ? 1 : 0.04, anchor: .bottom)
                        .opacity(isRevealed ? 0.72 : 0)
                        .position(
                            x: x(for: selected, width: w),
                            y: cloudAreaHeight / 2)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.54),
                            value: isRevealed)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: selectedSegmentStart)
                        .allowsHitTesting(false)
                        .zIndex(0.5)
                }
            }
            .contentShape(Rectangle())
            // A tap inspects the nearest segment without stealing vertical
            // scrolling, unlike a zero-distance drag gesture inside ScrollView.
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectNearest(to: value.location.x, width: w)
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

    private var visibleSegments: [SleepSegmentValue] {
        var visible = segments.filter { $0.duration >= Self.minVisible }
        if visible.isEmpty { visible = segments }   // all-sliver night: show something
        guard visible.count > Self.maxClouds else { return visible }
        // Sample the whole night at even time intervals. Selecting the longest N
        // over-represents 浅睡 and turns the middle band into one blob.
        let chronological = visible.sorted { $0.start < $1.start }
        var keep = Set<Date>()
        let denominator = Double(max(Self.maxClouds - 1, 1))
        for slot in 0..<Self.maxClouds {
            let target = Double(slot) / denominator
            if let nearest = chronological.min(by: {
                abs(progress(for: $0) - target) < abs(progress(for: $1) - target)
            }) {
                keep.insert(nearest.start)
            }
        }

        // Unusual nights can still miss a short stage (usually REM). Replace a
        // nearby duplicate-stage sample so every recorded stage stays visible.
        for stage in [SleepStage.rem, .core, .deep]
            where chronological.contains(where: { $0.stage == stage })
                && !chronological.contains(where: { keep.contains($0.start) && $0.stage == stage }) {
            guard let representative = chronological
                .filter({ $0.stage == stage })
                .max(by: { $0.duration < $1.duration }) else { continue }
            if keep.count >= Self.maxClouds {
                let selected = chronological.filter { keep.contains($0.start) }
                let counts = Dictionary(grouping: selected, by: { $0.stage.rawValue })
                if let removable = selected
                    .filter({ (counts[$0.stage.rawValue]?.count ?? 0) > 1 })
                    .min(by: {
                        abs($0.start.timeIntervalSince(representative.start))
                            < abs($1.start.timeIntervalSince(representative.start))
                    }) {
                    keep.remove(removable.start)
                }
            }
            keep.insert(representative.start)
        }

        for segment in chronological {
            if keep.count >= Self.maxClouds { break }
            keep.insert(segment.start)
        }
        return chronological.filter { keep.contains($0.start) }
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

    private func progress(for segment: SleepSegmentValue) -> Double {
        guard let nightStart, let nightEnd,
              nightEnd.timeIntervalSince(nightStart) > 0 else { return 0.5 }
        let midpoint = segment.start.addingTimeInterval(segment.duration / 2)
        return max(0, min(1, midpoint.timeIntervalSince(nightStart)
            / nightEnd.timeIntervalSince(nightStart)))
    }

    /// Figma defines s / m / l cloud variants. Keeping the three discrete sizes
    /// makes duration differences legible instead of producing many near-equal
    /// continuous scales.
    private func scale(for duration: TimeInterval) -> CGFloat {
        switch duration {
        case ..<(20 * 60): 0.72
        case ..<(36 * 60): 0.93
        default: 1.16
        }
    }

    private func color(of stage: SleepStage) -> Color {
        switch stage {
        case .rem:   return LP.Neutral.grey300
        case .core:  return LP.Colorful.blue400
        case .deep:  return LP.Colorful.purple700
        case .awake: return .white.opacity(0.3)
        }
    }

    private var resolvedSelectedSegment: SleepSegmentValue? {
        selection(in: visibleSegments)
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

    private func selectNearest(to locationX: CGFloat, width: CGFloat) {
        let candidates = visibleSegments
        guard !candidates.isEmpty else { return }
        let selected = candidates.min {
            abs(x(for: $0, width: width) - locationX)
                < abs(x(for: $1, width: width) - locationX)
        }
        guard let selected, selected.start != resolvedSelectedSegment?.start else { return }
        LPHaptics.tap()
        selectedSegmentStart = selected.start
    }

    private func selectAdjacent(offset: Int) {
        let candidates = visibleSegments
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

    // MARK: Chrome

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
        .compositingGroup()
        .accessibilityHidden(true)
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
