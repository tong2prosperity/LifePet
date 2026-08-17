import SwiftUI

/// One badge animation can acknowledge both the user-confirmed feed and a
/// ledger milestone. Keeping both IDs lets the badge coalesce them into one
/// particle pass, then consume the durable milestone only after it finishes.
struct BoCounterFeedbackRequest: Equatable, Identifiable, Sendable {
    let feedID: UUID?
    let milestoneID: UUID?

    var id: UUID {
        if let milestoneID { return milestoneID }
        guard let feedID else {
            preconditionFailure("A bo feedback request must contain a source ID")
        }
        return feedID
    }

    var sourceIDs: Set<UUID> {
        Set([feedID, milestoneID].compactMap { $0 })
    }

    init?(feedID: UUID?, milestoneID: UUID?) {
        guard feedID != nil || milestoneID != nil else { return nil }
        self.feedID = feedID
        self.milestoneID = milestoneID
    }
}

/// 首页左上角的 `bo` 存量与成熟收取入口。
///
/// 成熟判断和余额变更仍由 `BoLedgerStore` 负责；这里仅表达 Figma 的两种视觉状态，
/// 并编排收取时的能量流、计数增长与确认反馈。
struct BoCounterView: View {
    let balance: Int
    let growthProgress: Double
    let hasRipeBo: Bool
    let feedbackRequest: BoCounterFeedbackRequest?
    let feedbackEnabled: Bool
    let feedbackCompleted: (BoCounterFeedbackRequest) -> Void
    let collectAction: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripePulse = false
    @State private var displayedGrowthProgress: Double
    @State private var pendingGrowthProgress: Double?
    @State private var feedbackGatherVisible = false
    @State private var gatherProgress: CGFloat = 0
    @State private var glyphHighlight: CGFloat = 0
    @State private var activeFeedbackID: UUID?
    @State private var activeFeedbackSourceIDs: Set<UUID> = []
    @State private var activeFeedID: UUID?
    @State private var activeMilestoneID: UUID?
    @State private var queuedFeedbackRequest: BoCounterFeedbackRequest?
    @State private var handledFeedbackIDs: Set<UUID> = []
    @State private var feedbackTask: Task<Void, Never>?
    @State private var collecting = false
    @State private var streamProgress: CGFloat = 0
    @State private var glyphRotation: Double = 0

    /* ─────────────────────────────────────────────────────────
     * BO BADGE FEEDBACK STORYBOARD
     *
     * Read top-to-bottom. Each value is ms after Home becomes visible.
     *
     *    0ms   particles gather into the head-grass; old glow is retained
     *  520ms   particles land; progress glow + brightness rise
     *  720ms   highlight settles toward the persistent progress level
     * 1000ms   durable milestone is consumed
     * ───────────────────────────────────────────────────────── */
    private enum FeedbackMotion {
        static let gatherDuration = 0.52
        static let highlightRiseDuration = 0.20
        static let highlightSettleDuration = 0.28
    }

    init(
        balance: Int,
        growthProgress: Double,
        hasRipeBo: Bool,
        feedbackRequest: BoCounterFeedbackRequest? = nil,
        feedbackEnabled: Bool = true,
        feedbackCompleted: @escaping (BoCounterFeedbackRequest) -> Void = { _ in },
        collectAction: @escaping () -> Bool
    ) {
        self.balance = balance
        self.growthProgress = growthProgress
        self.hasRipeBo = hasRipeBo
        self.feedbackRequest = feedbackRequest
        self.feedbackEnabled = feedbackEnabled
        self.feedbackCompleted = feedbackCompleted
        self.collectAction = collectAction
        _displayedGrowthProgress = State(initialValue: Self.clamped(growthProgress))
    }

    private var accessibilityText: String {
        hasRipeBo
            ? AppLocalization.format("已有 %d 枚 bo，有一枚可以收取", balance)
            : AppLocalization.format("已有 %d 枚 bo", balance)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: handlePrimaryTap) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 116, height: 48)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(AppLocalization.text(hasRipeBo ? "收取成熟的 bo" : "显示当前 bo 库存"))

            Text("\(balance) bo")
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: balance)
                .offset(x: 48, y: 12)
                .allowsHitTesting(false)

            ZStack {
                glyphImage("bo_glyph_unripe")

                // The ripe asset is the same Figma glyph with its approved
                // yellow highlight. Its opacity gives a deliberately rough,
                // glanceable indication instead of introducing a progress bar.
                glyphImage("bo_glyph_ripe")
                    .opacity(progressOverlayOpacity)
            }
                .frame(width: 48, height: 68)
                .scaleEffect(ripePulse ? 1.06 : 1)
                .rotationEffect(.degrees(glyphRotation), anchor: .bottom)
                .brightness(progressBrightness)
                .shadow(
                    color: Color(hex: 0xFFFDAA).opacity(progressGlowOpacity),
                    radius: progressGlowRadius
                )
                .offset(y: -20)
                .allowsHitTesting(false)

            if collecting && !reduceMotion {
                BoCollectionStream(progress: streamProgress)
                    .frame(width: 72, height: 48)
                    .offset(x: 17, y: -4)
                    .allowsHitTesting(false)
            }

            if feedbackGatherVisible && !reduceMotion {
                BoGrowthGather(progress: gatherProgress)
                    .frame(width: 148, height: 108)
                    .offset(y: -20)
                    .allowsHitTesting(false)
            }
        }
        // Figma keeps the capsule at 148×48 while the 68pt glyph overflows
        // upward. Top-leading alignment prevents that decorative overflow (or
        // the feedback canvas) from inflating and vertically centering the pill.
        .frame(width: 116, height: 48, alignment: .topLeading)
        .background(LP.Neutral.grey850, in: Capsule())
        .onAppear {
            syncPulse()
            startFeedbackIfPossible(feedbackRequest)
        }
        .onDisappear { cancelFeedback() }
        .onChange(of: hasRipeBo) { _, _ in syncPulse() }
        .onChange(of: growthProgress) { _, newValue in
            stageGrowthProgress(newValue)
        }
        .onChange(of: feedbackRequest) { _, request in
            if request == nil, activeFeedbackID != nil {
                cancelFeedback()
            }
            startFeedbackIfPossible(request)
            revealStagedProgressIfPossible()
            syncPulse()
        }
        .onChange(of: feedbackEnabled) { _, enabled in
            if enabled {
                startFeedbackIfPossible(feedbackRequest)
                revealStagedProgressIfPossible()
            } else {
                cancelFeedback()
            }
            syncPulse()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced, activeFeedbackID != nil {
                completeFeedbackImmediately()
            }
            syncPulse()
        }
    }

    private var visualGrowthProgress: Double {
        if collecting || (hasRipeBo && !hasUnplayedFeedback) { return 1 }
        return Self.clamped(displayedGrowthProgress)
    }

    private var progressOverlayOpacity: Double {
        if collecting || (hasRipeBo && !hasUnplayedFeedback) { return 1 }
        let persistent = sqrt(visualGrowthProgress) * 0.76
        return min(1, persistent + Double(glyphHighlight) * 0.30)
    }

    private var progressBrightness: Double {
        visualGrowthProgress * 0.045 + Double(glyphHighlight) * 0.16
    }

    private var progressGlowOpacity: Double {
        min(0.92, sqrt(visualGrowthProgress) * 0.56 + Double(glyphHighlight) * 0.72)
    }

    private var progressGlowRadius: CGFloat {
        2 + CGFloat(visualGrowthProgress) * 6 + glyphHighlight * 4
    }

    private var hasUnplayedFeedback: Bool {
        if activeFeedbackID != nil { return true }
        guard let feedbackRequest else { return false }
        return !feedbackRequest.sourceIDs.isSubset(of: handledFeedbackIDs)
    }

    private func glyphImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private func handlePrimaryTap() {
        guard hasRipeBo else {
            LPHaptics.tap()
            return
        }
        collectRipeBo()
    }

    private func collectRipeBo() {
        guard !collecting else { return }
        collecting = true

        if reduceMotion {
            let collected = collectAction()
            if collected { LPHaptics.success() }
            collecting = false
            return
        }

        streamProgress = 0
        withAnimation(.easeIn(duration: 0.42)) { streamProgress = 1 }
        withAnimation(.linear(duration: 0.09).repeatCount(4, autoreverses: true)) {
            glyphRotation = 4
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            let collected = collectAction()
            if collected { LPHaptics.success() }
            withAnimation(.easeOut(duration: 0.18)) {
                collecting = false
                glyphRotation = 0
            }
        }
    }

    private func stageGrowthProgress(_ progress: Double) {
        let target = Self.clamped(progress)
        if !feedbackEnabled || hasUnplayedFeedback {
            pendingGrowthProgress = target
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            displayedGrowthProgress = target
        }
    }

    private func startFeedbackIfPossible(_ request: BoCounterFeedbackRequest?) {
        guard feedbackEnabled, let request,
              !request.sourceIDs.isSubset(of: handledFeedbackIDs)
        else { return }

        if activeFeedbackID != nil {
            if !activeFeedbackSourceIDs.isDisjoint(with: request.sourceIDs) {
                activeFeedbackSourceIDs.formUnion(request.sourceIDs)
                activeFeedID = request.feedID ?? activeFeedID
                activeMilestoneID = request.milestoneID ?? activeMilestoneID
            } else {
                queuedFeedbackRequest = request
            }
            return
        }

        activeFeedbackID = request.id
        activeFeedbackSourceIDs = request.sourceIDs
        activeFeedID = request.feedID
        activeMilestoneID = request.milestoneID

        if reduceMotion {
            completeFeedbackImmediately()
            return
        }

        feedbackGatherVisible = true
        gatherProgress = 0
        glyphHighlight = 0

        feedbackTask = Task { @MainActor in
            // Give Canvas one committed frame at progress 0 before retargeting
            // it; otherwise insertion and the animated value can collapse into
            // the same transaction and show no particle travel at all.
            await Task.yield()
            guard !Task.isCancelled, activeFeedbackID == request.id else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1,
                                       duration: FeedbackMotion.gatherDuration)) {
                gatherProgress = 1
            }

            try? await Task.sleep(for: .seconds(FeedbackMotion.gatherDuration))
            guard !Task.isCancelled, activeFeedbackID == request.id else { return }

            feedbackGatherVisible = false
            let target = pendingGrowthProgress ?? Self.clamped(growthProgress)
            pendingGrowthProgress = nil
            withAnimation(.easeOut(duration: FeedbackMotion.highlightRiseDuration)) {
                displayedGrowthProgress = target
                glyphHighlight = 1
            }

            try? await Task.sleep(for: .seconds(FeedbackMotion.highlightRiseDuration))
            guard !Task.isCancelled, activeFeedbackID == request.id else { return }
            withAnimation(.easeOut(duration: FeedbackMotion.highlightSettleDuration)) {
                glyphHighlight = 0
            }

            try? await Task.sleep(for: .seconds(FeedbackMotion.highlightSettleDuration))
            guard !Task.isCancelled, activeFeedbackID == request.id else { return }
            finishFeedback()
        }
    }

    private func completeFeedbackImmediately() {
        feedbackTask?.cancel()
        feedbackTask = nil
        feedbackGatherVisible = false
        gatherProgress = 1
        glyphHighlight = 0
        displayedGrowthProgress = pendingGrowthProgress ?? Self.clamped(growthProgress)
        pendingGrowthProgress = nil
        finishFeedback()
    }

    private func finishFeedback() {
        guard activeFeedbackID != nil else { return }
        let completedIDs = activeFeedbackSourceIDs
        let completedRequest = BoCounterFeedbackRequest(
            feedID: activeFeedID,
            milestoneID: activeMilestoneID
        )
        let queued = queuedFeedbackRequest

        handledFeedbackIDs.formUnion(completedIDs)
        activeFeedbackID = nil
        activeFeedbackSourceIDs = []
        activeFeedID = nil
        activeMilestoneID = nil
        queuedFeedbackRequest = nil
        feedbackTask = nil
        feedbackGatherVisible = false
        syncPulse()
        if let completedRequest {
            feedbackCompleted(completedRequest)
        }

        if let queued {
            startFeedbackIfPossible(queued)
        }
    }

    private func cancelFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        activeFeedbackID = nil
        activeFeedbackSourceIDs = []
        activeFeedID = nil
        activeMilestoneID = nil
        queuedFeedbackRequest = nil
        feedbackGatherVisible = false
        gatherProgress = 0
        glyphHighlight = 0
    }

    private func revealStagedProgressIfPossible() {
        guard feedbackEnabled, !hasUnplayedFeedback,
              let pendingGrowthProgress else { return }
        self.pendingGrowthProgress = nil
        withAnimation(.easeOut(duration: 0.2)) {
            displayedGrowthProgress = pendingGrowthProgress
        }
    }

    private static func clamped(_ progress: Double) -> Double {
        min(1, max(0, progress))
    }

    /// 只有成熟未收时才持续呼吸；Reduce Motion 下保留静态发光状态。
    private func syncPulse() {
        guard hasRipeBo, !hasUnplayedFeedback, feedbackEnabled, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { ripePulse = false }
            return
        }
        ripePulse = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            ripePulse = true
        }
    }

}

private struct BoGrowthGather: View, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private enum ParticleConfig {
        static let count = 10
        static let stagger: CGFloat = 0.045
        static let target = CGPoint(x: 24, y: 34)
    }

    var body: some View {
        Canvas { context, size in
            for index in 0..<ParticleConfig.count {
                let delay = CGFloat(index) * ParticleConfig.stagger
                let t = min(1, max(0, (progress - delay) / (1 - delay)))
                guard t > 0, t < 1 else { continue }
                let column = CGFloat(index % 4)
                let row = CGFloat(index / 4)
                let start = CGPoint(
                    x: size.width - 10 - column * 22,
                    y: size.height - 10 - row * 16
                )
                let control = CGPoint(
                    x: size.width * (0.48 + CGFloat(index % 2) * 0.08),
                    y: size.height * (0.14 + CGFloat(index % 3) * 0.10)
                )
                let end = CGPoint(
                    x: ParticleConfig.target.x + (CGFloat(index % 3) - 1) * 1.4,
                    y: ParticleConfig.target.y + (CGFloat(index % 2) - 0.5) * 1.6
                )
                let inverse = 1 - t
                let point = CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
                let radius: CGFloat = index.isMultiple(of: 3) ? 2.2 : 1.5
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(Color(hex: 0xFFFDAA).opacity(0.9 - t * 0.25))
                )
            }
        }
    }
}

private struct BoCollectionStream: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<7 {
                let delay = CGFloat(index) * 0.07
                let t = min(1, max(0, (progress - delay) / (1 - delay)))
                guard t > 0, t < 1 else { continue }
                let start = CGPoint(x: 4 + CGFloat(index % 3) * 3, y: 4 + CGFloat(index) * 2)
                let control = CGPoint(x: size.width * 0.46, y: size.height * (0.10 + CGFloat(index % 2) * 0.18))
                let end = CGPoint(x: size.width - 3, y: size.height * 0.58)
                let point = quadraticPoint(from: start, control: control, to: end, t: t)
                let radius: CGFloat = index.isMultiple(of: 2) ? 2.4 : 1.6
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0xFFFDAA).opacity(1 - t * 0.35)))
            }
        }
    }

    private func quadraticPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        BoCounterView(balance: 0, growthProgress: 0.12, hasRipeBo: false, collectAction: { false })
        BoCounterView(balance: 3, growthProgress: 0.62, hasRipeBo: false, collectAction: { false })
        BoCounterView(balance: 7, growthProgress: 1, hasRipeBo: true, collectAction: { true })
    }
    .padding(40)
    .background(Color(hex: 0x9FBFA8))
}
