import Foundation
import SwiftUI

/// 今日脚步 card — big step count over a plant landscape with a time ruler
/// (Figma `activity card` 1374:529 / `walk data-v` 186:1023). The waking window
/// **06:00–22:00** maps to 16 hourly columns; each grows a plant whose stage
/// maps that hour's volume (石头 → 嫩芽 → 松树 → 高株) over the mint hills, with
/// fireflies, a tick ruler and a peak-hour callout.
struct HistoryStepsCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let steps: Int
    /// Per-hour step counts (index = hour 0–23). Empty → fall back to a
    /// day-total pattern (legacy rows without hourly data).
    let hourlySteps: [Int]
    let isToday: Bool
    let caption: String

    /// Window shown by the landscape + ruler.
    static let startHour = 6
    static let endHour = 22

    @State private var isVisible = false
    @State private var isRevealed = false
    @State private var revealGeneration = 0

    var body: some View {
        let cols = columns()
        HistoryCard(title: "今日脚步", background: { background }) {
            HStack(alignment: .bottom, spacing: LP.Spacing.s) {
                Text("\(steps)")
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                    .monospacedDigit()
                Text("步")
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, LP.Spacing.s)

            VStack(spacing: 4) {
                GrassField(columns: cols, isToday: isToday, isRevealed: isRevealed)
                    .frame(height: 114)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    TickRuler()
                        .stroke(LP.Content.quarternary, lineWidth: 1)
                        .frame(height: 8)
                    axisLabels(peak: peakCallout(cols))
                }
                .padding(.horizontal, 16)   // Figma 321-in-353 inset
            }
        }
        // `VStack` eagerly builds every history card. Start only when this card
        // actually enters the viewport, otherwise the grow-in finishes offscreen.
        .onScrollVisibilityChange(threshold: 0.72) { visible in
            isVisible = visible
            guard visible, !isRevealed else { return }
            startReveal()
        }
        .onChange(of: cols, initial: true) { _, _ in
            resetReveal()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.text("今日脚步"))
        .accessibilityValue(AppLocalization.text("\(steps)步，\(caption)"))
    }

    // MARK: Axis labels (06:00 · 峰值 · 22:00)

    private func axisLabels(peak: (range: String, steps: Int)?) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%02d:00", Self.startHour))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            if let peak {
                HStack(spacing: 4) {
                    Text(peak.range)
                    Text("\(peak.steps)步")
                }
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.quarternary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            Text(String(format: "%02d:00", Self.endHour))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    // MARK: Data

    /// Per-hour steps for the window [startHour, endHour) → 16 columns.
    private func columns() -> [Int] {
        guard hourlySteps.isEmpty else {
            return (Self.startHour..<Self.endHour).map {
                $0 < hourlySteps.count ? hourlySteps[$0] : 0
            }
        }
        guard steps > 0 else {
            return Array(repeating: 0, count: Self.endHour - Self.startHour)
        }
        // Legacy (no hourly data): spread the day total over a plausible curve.
        let vigor = min(1.0, Double(steps) / 10_000)
        return Self.legacyPattern.map { Int(Double($0) * vigor * 1500) }  // 1500 = full hour
    }

    /// The busiest hour in the window → the `8:00-9:00 200步` callout. Only for
    /// real per-hour data (a synthesised legacy curve has no meaningful peak).
    private func peakCallout(_ cols: [Int]) -> (range: String, steps: Int)? {
        guard !hourlySteps.isEmpty, let maxV = cols.max(), maxV > 0,
              let idx = cols.firstIndex(of: maxV) else { return nil }
        let h = Self.startHour + idx
        return ("\(h):00-\(h + 1):00", maxV)
    }

    /// Relative volume per hour 06:00–21:00 for legacy rows (morning / lunch /
    /// evening emphasis).
    private static let legacyPattern: [CGFloat] = [
        0.3, 0.7, 1.0, 0.8, 0.5, 0.6, 0.9, 0.7, 0.4, 0.5, 0.6, 0.7, 1.0, 0.9, 0.5, 0.3,
    ]

    private var background: some View {
        LP.Fill.bgContainer
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
}

// MARK: - Landscape

/// Plant landscape — one growth-stage plant per hourly column over the mint
/// hills and fireflies. The stage→height scale is
/// **fixed across days** so the field reads as data (a 高株 ≈ a near-max hour).
/// On today, columns still ahead render dimmed.
///
/// 入场生长动画：the field **grows in left→right** — the mint hills sweep in under a moving
/// reveal mask, each hour's plant 冒头 (bottom-anchored spring pop) staggered to
/// fire as the sweep reaches its column, then the 萤火虫 fade in last. Driven by
/// the card's scroll visibility so it cannot finish before the user reaches it.
private struct GrassField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-hour steps for hours `HistoryStepsCard.startHour …` (one per column).
    let columns: [Int]
    let isToday: Bool
    let isRevealed: Bool

    /// Wall-clock of the full left→right sweep; plant pops stagger across ~80% of it.
    private static let sweepDuration: Double = 1.05

    /// Firefly positions in the full 353 × 114 landscape. These retain the
    /// Figma `walk decoration` frame's central spread instead of spanning edge
    /// to edge. Values are x/y fractions of the landscape.
    private static let fireflySpots: [(CGFloat, CGFloat)] = [
        (0.348, 0.456), (0.156, 0.553), (0.405, 0.553), (0.663, 0.474),
        (0.688, 0.553), (0.771, 0.272), (0.822, 0.237),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                // 山丘从左往右铺开。Figma 中山丘约 355 × 100，植物数据区
                // 内收 8pt 且位于其下方；额外石头会重复最低档位，因此不叠加。
                Image("walk_hills")
                    .resizable()
                    .frame(width: w + 2, height: min(100, h), alignment: .top)
                    .frame(width: w, height: h, alignment: .top)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: isRevealed ? w + 4 : 0)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: Self.sweepDuration),
                                value: isRevealed)
                    }

                // 植物：每列随扫掠到达而「冒头」，底部锚点弹簧上弹。
                plantRow(h: min(91, h))
                    .padding(.horizontal, 8)

                // 萤火虫：最后淡入。
                fireflies(w: w, h: h)
                    .opacity(isRevealed ? 1 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeIn(duration: 0.5).delay(Self.sweepDuration * 0.7),
                        value: isRevealed)
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
    }

    private func plantRow(h: CGFloat) -> some View {
        let currentHour = Calendar.current.component(.hour, from: .now)
        let count = max(columns.count - 1, 1)
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(columns.indices, id: \.self) { i in
                let hour = HistoryStepsCard.startHour + i
                let stage = PlantStage.forHourSteps(columns[i])
                // Pop right as the sweep edge reaches this column (delay = x-fraction).
                let delay = Double(i) / Double(count) * Self.sweepDuration * 0.8
                PlantView(stage: stage, fieldHeight: h, dimmed: isToday && hour > currentHour)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isRevealed ? 1 : 0.15, anchor: .bottom)
                    .opacity(isRevealed ? 1 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.5, dampingFraction: 0.6).delay(delay),
                        value: isRevealed)
            }
        }
    }

    private func fireflies(w: CGFloat, h: CGFloat) -> some View {
        ForEach(Self.fireflySpots.indices, id: \.self) { i in
            Circle()
                .fill(Color(hex: 0xFFDF51))
                .frame(width: 4, height: 4)
                .shadow(color: Color(hex: 0xFFDF51, alpha: 0.9), radius: 2.5)
                .position(x: w * Self.fireflySpots[i].0, y: h * Self.fireflySpots[i].1)
        }
    }
}

// MARK: - Growth stages

/// Discrete growth stages for the landscape — each maps an hour's step volume
/// to one of the Figma `walk number` variants (1496:1416). Each renders the
/// **real exported variant artwork** (vector PDF in `Assets.xcassets/plants`,
/// "Preserve Vector Data"), so it stays crisp at any size — no hand-drawn
/// approximation.
private enum PlantStage {
    case rock, sprout, pine, tall

    /// One-hour step count → stage. Figma defines four visual variants but no
    /// numeric thresholds: zero is the rock state, while the three growth bands
    /// cover a practical hour of light → sustained walking.
    static func forHourSteps(_ s: Int) -> PlantStage {
        switch s {
        case ...0:        return .rock
        case 1..<150:     return .sprout
        case 150..<500:   return .pine
        default:          return .tall
        }
    }

    /// Vector asset in `Assets.xcassets/plants` (exported from the Figma variant).
    var asset: String {
        switch self {
        case .rock:   return "walk_rock"
        case .sprout: return "walk_sprout"
        case .pine:   return "walk_pine"
        case .tall:   return "walk_tall"
        }
    }

    /// Height of the Figma variant frame (all 48 wide) — drives the fixed
    /// cross-day scale: 石头 20 / 嫩芽 36 / 松树 64 / 高株 96, so a 高株 fills
    /// the field and the rest keep their real proportions.
    var frameHeight: CGFloat {
        switch self {
        case .rock:   return 20
        case .sprout: return 36
        case .pine:   return 64
        case .tall:   return 96
        }
    }

    /// All variant frames share this width / tallest height (Figma 1496:1416).
    static let frameWidth: CGFloat = 48
    static let tallestFrame: CGFloat = 96
}

/// One plant — the real Figma variant artwork, sized to its fixed stage height
/// (高株 fills the field) keeping the exported aspect, bottom-aligned in its
/// column. `dimmed` for today's not-yet-reached hours.
private struct PlantView: View {
    let stage: PlantStage
    let fieldHeight: CGFloat
    var dimmed: Bool = false

    var body: some View {
        let scale = fieldHeight / PlantStage.tallestFrame
        Image(stage.asset)
            .resizable()
            .frame(width: PlantStage.frameWidth * scale,
                   height: stage.frameHeight * scale)
            .opacity(dimmed ? 0.4 : 1)
    }
}

// MARK: - Tick ruler

/// The time ruler under the landscape (Figma `mark` 1496:2341): a tall tick
/// every 32pt with three short ticks (¼…¾ height) between, repeated across the
/// width. Stroke in `LP.Content.quarternary`.
private struct TickRuler: Shape {
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

// MARK: - Preview

#if DEBUG
/// Plausible 24-hour step distributions for previewing the landscape — mirrors
/// the seed weight curve (night ≈ 0, morning / lunch / evening peaks) so each
/// daily total spreads into realistic hourly columns and exercises every stage.
private enum StepsPreviewData {
    static func day(_ total: Int) -> [Int] {
        let weights: [Double] = (0..<24).map { h in
            switch h {
            case 0..<7:   return 0.05
            case 7..<10:  return 1.8
            case 12..<14: return 1.2
            case 18..<21: return 2.0
            default:      return 0.7
            }
        }
        let sum = weights.reduce(0, +)
        return weights.map { Int(Double(total) * $0 / sum) }
    }
}

#Preview("今日脚步 · 各档位") {
    ScrollView {
        VStack(spacing: LP.Spacing.l) {
            HistoryStepsCard(steps: 8234, hourlySteps: StepsPreviewData.day(8234),
                             isToday: false, caption: "走得不错，花也精神")
            HistoryStepsCard(steps: 16_500, hourlySteps: StepsPreviewData.day(16_500),
                             isToday: false, caption: "今天像在森林里穿行")
            HistoryStepsCard(steps: 1_820, hourlySteps: StepsPreviewData.day(1_820),
                             isToday: false, caption: "...今天...有点懒啵")
            HistoryStepsCard(steps: 4_300, hourlySteps: StepsPreviewData.day(9_000),
                             isToday: true, caption: "今天才刚开始（未到的时段会变暗）")
            HistoryStepsCard(steps: 7_000, hourlySteps: [],
                             isToday: false, caption: "老数据 · 无小时分布（兜底）")
        }
        .padding(LP.Spacing.xl)
    }
    .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
}
#endif
