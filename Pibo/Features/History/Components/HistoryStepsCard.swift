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
    /// 拖动杆选中的列（0 = startHour）。`nil` = 未选中，中间标签回落到峰值时段。
    @State private var selectedIndex: Int? = Self.debugInitialScrubIndex()

    /// 截图验证用：`-PiboStepsScrubIndex=5` 直接渲染选中态（模拟器上无法合成拖动手势）。
    private static func debugInitialScrubIndex() -> Int? {
        #if DEBUG
        let prefix = "-PiboStepsScrubIndex="
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            return Int(raw.dropFirst(prefix.count))
        }
        #endif
        return nil
    }

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
                GrassField(
                    columns: cols,
                    isToday: isToday,
                    isRevealed: isRevealed,
                    selectedIndex: selectedIndex,
                    onScrub: { index in
                        guard index != selectedIndex else { return }
                        LPHaptics.tap()
                        selectedIndex = index
                    })
                    .frame(height: 114)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    TickRuler()
                        .stroke(LP.Content.quarternary, lineWidth: 1)
                        .frame(height: 8)
                    axisLabels(peak: peakCallout(cols), selected: selectedCallout(cols))
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
        // 换了一天就把拖动杆的选中丢掉 —— 索引在新的一天依然合法，所以不清的话
        // 中间那格会静悄悄显示新数据里同一小时的值，看着像"选中还在"，其实用户
        // 从没在这一天点过。刻意不带 `initial: true`：那会在首帧就把调试参数
        // `-PiboStepsScrubIndex=` 注入的选中态抹掉。
        .onChange(of: cols) { _, _ in
            selectedIndex = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.text("今日脚步"))
        .accessibilityValue(accessibilityValue(cols))
        // 拖动杆是纯手势控件，读屏用户碰不到它 —— 上下轻扫改为逐小时切换，
        // 和睡眠卡切换睡眠片段是同一套动作（`selectAdjacent`）。
        .accessibilityHint(AppLocalization.text("上下滑动逐小时查看"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectAdjacent(offset: 1, in: cols)
            case .decrement: selectAdjacent(offset: -1, in: cols)
            @unknown default: break
            }
        }
    }

    /// 读屏播报：没选中就报当天总数 + 文案，选中了就补上那一小时。
    private func accessibilityValue(_ cols: [Int]) -> String {
        let base = AppLocalization.text("\(steps)步，\(caption)")
        guard let callout = selectedCallout(cols) else { return base }
        return "\(base)，\(callout.range) \(callout.steps)步"
    }

    /// 从当前选中列走一步；还没选过就从峰值那一列起步，落点和视觉一致。
    private func selectAdjacent(offset: Int, in cols: [Int]) {
        guard !cols.isEmpty else { return }
        let start = selectedIndex ?? peakIndex(cols) ?? 0
        selectedIndex = min(max(0, start + offset), cols.count - 1)
    }

    // MARK: Axis labels (06:00 · 峰值/选中 · 22:00)

    /// 中间那格默认是峰值时段；一旦拖动杆选了某一列，就改显示那一小时的真实数据
    /// （与睡眠卡的 `selectionDetail` 同一套行为）。
    private func axisLabels(peak: (range: String, steps: Int)?,
                            selected: (range: String, steps: Int)?) -> some View {
        let callout = selected ?? peak
        return HStack(spacing: 4) {
            Text(String(format: "%02d:00", Self.startHour))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            if let callout {
                HStack(spacing: 4) {
                    Text(callout.range)
                    Text("\(callout.steps)步")
                }
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(selected == nil ? LP.Content.quarternary : LP.Content.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.16), value: selectedIndex)
            }
            Spacer(minLength: 0)
            Text(String(format: "%02d:00", Self.endHour))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    /// 选中列的「HH:00-HH:00 N步」。越界返回 nil，回落到峰值。
    private func selectedCallout(_ cols: [Int]) -> (range: String, steps: Int)? {
        guard let i = selectedIndex, cols.indices.contains(i) else { return nil }
        let h = Self.startHour + i
        return ("\(h):00-\(h + 1):00", cols[i])
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
        guard let idx = peakIndex(cols) else { return nil }
        let h = Self.startHour + idx
        return ("\(h):00-\(h + 1):00", cols[idx])
    }

    /// 峰值那一列。只对真实的逐小时数据有意义 —— 合成的 legacy 曲线没有真峰值。
    private func peakIndex(_ cols: [Int]) -> Int? {
        guard !hourlySteps.isEmpty, let maxV = cols.max(), maxV > 0 else { return nil }
        return cols.firstIndex(of: maxV)
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
    /// 拖动杆选中的列，`nil` = 未选中（不画竖线）。
    var selectedIndex: Int?
    var onScrub: (Int) -> Void = { _ in }


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
                MintHills()
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
                plantRow(h: min(91, h), width: w)

                // 拖动杆的竖线 —— 与睡眠卡同一形状（1.5pt，上端淡出），只是这张卡
                // 是浅底，所以用深色而不是白色，否则看不见。
                if let selectedIndex, columns.indices.contains(selectedIndex) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    LP.Content.primary.opacity(0),
                                    LP.Content.primary.opacity(0.45),
                                    LP.Content.primary.opacity(0.45),
                                ],
                                startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5, height: h)
                        .position(x: geometry.centerX(of: selectedIndex, in: w), y: h / 2)
                        .opacity(isRevealed ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedIndex)
                        .allowsHitTesting(false)
                }

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
            .contentShape(Rectangle())
            // 轻点选中 + 横向拖动连续查看。`minimumDistance: 8` 让竖直方向的
            // 滚动先被 ScrollView 抢走 —— 零距离的 DragGesture 会把整页滚动吃掉，
            // 这也正是睡眠卡当初只用 tap 的原因。
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { onScrub(geometry.index(atX: $0.location.x, in: w)) }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        // 只认横向拖动。竖直方向虽然会被 ScrollView 抢去滚动，但
                        // `simultaneousGesture` 仍会把 `onChanged` 发过来 —— 不挡的话
                        // 滑过这张卡就会顺手改掉选中并震一下。
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        onScrub(geometry.index(atX: value.location.x, in: w))
                    }
            )
        }
    }

    /// 植物按**列心绝对定位**，而不是等宽 `HStack`。
    ///
    /// `PlantView` 用的是固定尺寸（`frameWidth` 48pt × 高度缩放），`.frame(maxWidth:
    /// .infinity)` 压不下去 —— 16 棵合起来约 759pt，塞进 363pt 宽的卡片会让整行溢出
    /// 后被居中，结果是 06–09 点和 20–22 点几列**直接被裁到卡片外看不见**，而刻度尺和
    /// 峰值标签还按整段时间在标，两者对不上。改成每棵按 `StepsColumnGeometry` 的列心
    /// 落位后，相邻植物自然重叠（Figma 参考里本来就是重叠的树林），16 列都在卡内，
    /// 拖动杆的竖线、命中判定、刻度尺这才处在同一个坐标系里。
    private func plantRow(h: CGFloat, width: CGFloat) -> some View {
        let currentHour = Calendar.current.component(.hour, from: .now)
        let count = max(columns.count - 1, 1)
        let g = geometry
        return ZStack(alignment: .bottom) {
            ForEach(columns.indices, id: \.self) { i in
                let hour = HistoryStepsCard.startHour + i
                let stage = PlantStage.forHourSteps(columns[i])
                // Pop right as the sweep edge reaches this column (delay = x-fraction).
                let delay = Double(i) / Double(count) * Self.sweepDuration * 0.8
                PlantView(stage: stage, fieldHeight: h, dimmed: isToday && hour > currentHour)
                    .scaleEffect(isRevealed ? 1 : 0.15, anchor: .bottom)
                    .opacity(isRevealed ? 1 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.5, dampingFraction: 0.6).delay(delay),
                        value: isRevealed)
                    .offset(x: g.centerX(of: i, in: width) - width / 2)
            }
        }
        // 显式给出宽度：`.offset` 不参与布局，不锁宽的话 ZStack 会缩到最宽的那棵植物，
        // 偏移就变成相对那个小框的中心算了。
        .frame(width: width, height: h, alignment: .bottom)
    }

    // MARK: Column geometry

    private var geometry: StepsColumnGeometry {
        StepsColumnGeometry(count: columns.count)
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

// MARK: - Mint hills

/// 薄荷色山丘 — Figma `activity card` (1496:5974) 里 `walk data-v` 的山丘层：
/// 渐变填充 + 山脊描边。
///
/// **这里不用导出的矢量资源，是有原因的，别改回 `Image("walk_hills")`。**
/// 该图形的渐变靠 `stop-opacity: 0.3 → 0` 实现，而仓库的
/// SVG → `rsvg-convert -f pdf` → imageset 管线会把它拆成一个 luminosity
/// soft mask；CoreGraphics 渲染这个 mask 时只覆盖到图形宽度的 **75%**，右侧
/// 填充整块消失（描边不吃 mask，所以只剩一条线）。用一份新导出的 SVG 重跑管线
/// 也一样断，所以那份 `walk_hills.pdf` 资源是坏的、并且不可能靠重新导出修好。
/// 凡是带 `stop-opacity` 渐变的 Figma 图形，都要走这条路，别走 PDF。
///
/// 路径数值逐字来自 Figma 的 SVG 导出（设计尺寸 285 × 86.1717），因此这不是
/// 手工描摹 —— 以后 Figma 改了形状，重新导一份 SVG 直接比对这些数字即可。
///
/// 配色取**卡片实例**而不是素材节点：素材区那个独立的 `Group 117` (1496:4495)
/// 用深青 `#22B394` 描边，但卡片里用的是与填充同色的浅薄荷 `#70D6C1`（4× 导出
/// 采样为 `#80DCCC`，抗锯齿后的结果；旧 PDF 资源里也正是 `#70D6C1`）。
private struct MintHills: View {
    /// 填充渐变的起止色 —— 山脊描边同样用这个色（不透明）。
    private static let mint: UInt32 = 0x70D6C1

    var body: some View {
        ZStack(alignment: .top) {
            HillsShape(closed: true)
                .fill(LinearGradient(
                    colors: [Color(hex: Self.mint, alpha: 0.3),
                             Color(hex: Self.mint, alpha: 0)],
                    startPoint: .top, endPoint: .bottom))
            HillsShape(closed: false)
                .stroke(Color(hex: Self.mint), lineWidth: 1)
        }
    }
}

/// 山脊曲线。`closed` 时向下收成 `Vector 94` 的填充体 —— 填充和描边共用同一条
/// 曲线，两者永远不会错位。按 `preserveAspectRatio="none"` 非等比拉伸到给定
/// 矩形，和原先 `Image.resizable()` 的行为一致。
private struct HillsShape: Shape {
    var closed: Bool

    nonisolated func path(in rect: CGRect) -> Path {
        // 设计画板尺寸；下面的坐标都在这个空间里。
        let design = CGSize(width: 285, height: 86.1717)
        // `Vector 95` 的 C 命令：(控制点1, 控制点2, 终点)。
        let crest: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 17, y: 26.3865), CGPoint(x: 12, y: 20.3111), CGPoint(x: 23, y: 20.3111)),
            (CGPoint(x: 35.5, y: 20.3111), CGPoint(x: 34, y: 26.3865), CGPoint(x: 44, y: 26.3865)),
            (CGPoint(x: 54, y: 26.3865), CGPoint(x: 54.7548, y: 11.6716), CGPoint(x: 66.7548, y: 11.6716)),
            (CGPoint(x: 78.7548, y: 11.6716), CGPoint(x: 77, y: 20.3111), CGPoint(x: 88, y: 20.3111)),
            (CGPoint(x: 99, y: 20.3111), CGPoint(x: 97.5, y: 0.5), CGPoint(x: 110.5, y: 0.5)),
            (CGPoint(x: 125.5, y: 0.5), CGPoint(x: 124, y: 26.3865), CGPoint(x: 139, y: 26.3865)),
            (CGPoint(x: 154, y: 26.3865), CGPoint(x: 157.03, y: 11.6716), CGPoint(x: 171.03, y: 11.6716)),
            (CGPoint(x: 185.03, y: 11.6716), CGPoint(x: 182, y: 20.3111), CGPoint(x: 197, y: 20.3111)),
            (CGPoint(x: 212, y: 20.3111), CGPoint(x: 207, y: 0.5), CGPoint(x: 220, y: 0.5)),
            (CGPoint(x: 236, y: 0.5), CGPoint(x: 227.53, y: 11.6716), CGPoint(x: 240.03, y: 11.6716)),
            (CGPoint(x: 250.53, y: 11.6716), CGPoint(x: 248.385, y: 0.5), CGPoint(x: 260, y: 0.5)),
            (CGPoint(x: 273, y: 0.5), CGPoint(x: 272, y: 26.3865), CGPoint(x: 285, y: 26.3865)),
        ]

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 26.3865))
        for (c1, c2, end) in crest {
            p.addCurve(to: end, control1: c1, control2: c2)
        }
        if closed {
            p.addLine(to: CGPoint(x: design.width, y: design.height))
            p.addLine(to: CGPoint(x: 0, y: design.height))
            p.closeSubpath()
        }
        return p.applying(
            CGAffineTransform(scaleX: rect.width / design.width,
                              y: rect.height / design.height)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
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
