import Foundation
import SwiftUI

/// The presentation-only projection used by the in-world 状态观测仪.
/// Deterministic scoring stays in PiboCore; this type only formats persisted
/// results for the forest UI and keeps a measured zero distinct from no result.
struct WellnessInstrumentData: Equatable {
    struct Score: Equatable {
        let value: Double
        let confidenceLevel: Int32
        let baselineDays: Int
    }

    let generatedAt: Date?
    let algorithmVersion: UInt32?
    let sleep: Score?
    let recovery: Score?
    let activity: Score?
    let sleepDebtMinutes: Double?
    let acuteTrainingLoad: Double?
    let chronicTrainingLoad: Double?
    let trainingBalanceStatus: Int32?
    let recoveryIndexScore: Double?
    let resilience: Score?
    let resilienceObservedDays: Int

    init(record: HealthDayRecord?) {
        let snapshot = record?.wellnessSnapshot
        let hasObservedTraining = (snapshot?.acuteTrainingObservedDays ?? 0) > 0
            || (snapshot?.chronicTrainingObservedDays ?? 0) > 0
        generatedAt = snapshot?.generatedAt
        algorithmVersion = snapshot?.algorithmVersion
        sleep = snapshot?.sleepScore.map(Self.score)
        recovery = snapshot?.recoveryScore.map(Self.score)
        activity = snapshot?.activityScore.map(Self.score)
        sleepDebtMinutes = snapshot?.sleepDebtMinutes
        acuteTrainingLoad = snapshot.flatMap {
            ($0.acuteTrainingObservedDays ?? 0) > 0 ? $0.acuteTrainingLoad : nil
        }
        chronicTrainingLoad = snapshot.flatMap {
            ($0.chronicTrainingObservedDays ?? 0) > 0 ? $0.chronicWeeklyTrainingLoad : nil
        }
        trainingBalanceStatus = hasObservedTraining ? snapshot?.trainingBalanceStatus : nil
        recoveryIndexScore = record?.recoveryIndexScore
        resilience = snapshot?.resilienceScore.map(Self.score)
        resilienceObservedDays = snapshot?.resilienceObservedDays ?? 0
    }

    private static func score(_ snapshot: DailyWellnessScoreSnapshot) -> Score {
        Score(
            value: snapshot.value,
            confidenceLevel: snapshot.confidenceLevel,
            baselineDays: snapshot.baselineDays
        )
    }

    #if DEBUG
    static let preview = WellnessInstrumentData(
        generatedAt: .now,
        algorithmVersion: 1,
        sleep: Score(value: 78, confidenceLevel: 3, baselineDays: 18),
        recovery: Score(value: 71, confidenceLevel: 2, baselineDays: 12),
        activity: Score(value: 64, confidenceLevel: 3, baselineDays: 21),
        sleepDebtMinutes: 82,
        acuteTrainingLoad: 236,
        chronicTrainingLoad: 198,
        trainingBalanceStatus: 5,
        recoveryIndexScore: 76,
        resilience: Score(value: 68, confidenceLevel: 2, baselineDays: 11),
        resilienceObservedDays: 11
    )
    #endif

    private init(
        generatedAt: Date?,
        algorithmVersion: UInt32?,
        sleep: Score?,
        recovery: Score?,
        activity: Score?,
        sleepDebtMinutes: Double?,
        acuteTrainingLoad: Double?,
        chronicTrainingLoad: Double?,
        trainingBalanceStatus: Int32?,
        recoveryIndexScore: Double?,
        resilience: Score?,
        resilienceObservedDays: Int
    ) {
        self.generatedAt = generatedAt
        self.algorithmVersion = algorithmVersion
        self.sleep = sleep
        self.recovery = recovery
        self.activity = activity
        self.sleepDebtMinutes = sleepDebtMinutes
        self.acuteTrainingLoad = acuteTrainingLoad
        self.chronicTrainingLoad = chronicTrainingLoad
        self.trainingBalanceStatus = trainingBalanceStatus
        self.recoveryIndexScore = recoveryIndexScore
        self.resilience = resilience
        self.resilienceObservedDays = resilienceObservedDays
    }
}

/// A custom in-world overlay rather than a system sheet: the instrument grows
/// from its lower-left forest position while a narrow rim of the world remains.
struct WellnessInstrumentView: View {
    let data: WellnessInstrumentData
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var showsCalculationBasis = false
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LP.Fill.maskModal
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                    .accessibilityHidden(true)

                instrumentPanel
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.top, max(LP.Spacing.m, proxy.safeAreaInsets.top + LP.Spacing.s))
                    .padding(.bottom, max(LP.Spacing.m, proxy.safeAreaInsets.bottom + LP.Spacing.s))
                    .offset(y: dragOffset)
                    .opacity(dragOffset > 0 ? max(0.72, 1 - dragOffset / 500) : 1)
            }
            .ignoresSafeArea()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
        .lpDynamicTypeScaling()
        .task {
            await Task.yield()
            headingFocused = true
        }
    }

    private var instrumentPanel: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollView {
                VStack(spacing: LP.Spacing.l) {
                    recoveryHero
                    observationStrip
                    trainingSection
                    resilienceSection
                    calculationBasis
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.bottom, LP.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .background(LP.Fill.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: LP.Radius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LP.Radius.xxl, style: .continuous)
                .stroke(LP.Border.secondary, lineWidth: LP.BorderWidth.hair)
        }
        .lpShadow(LP.Shadow.elevation4)
    }

    private var panelHeader: some View {
        VStack(spacing: LP.Spacing.xs) {
            Capsule()
                .fill(LP.Content.quarternary)
                .frame(width: 42, height: 4)
                .frame(height: 20)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: LP.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("状态观测仪")
                        .lpText(LP.Typography.uiH5)
                        .foregroundStyle(LP.Content.primary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    Text(generatedLabel)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                Spacer(minLength: LP.Spacing.s)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LP.Content.secondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LP.Fill.bgContainer))
                        .overlay(Circle().stroke(LP.Border.tertiary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭状态观测仪")
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.s)
        }
        .contentShape(Rectangle())
        .gesture(dismissGesture)
    }

    private var recoveryHero: some View {
        VStack(spacing: LP.Spacing.s) {
            ZStack {
                TreeRingField()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Text("恢复分")
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.secondary)
                    Text(scoreText(data.recovery))
                        .lpText(LP.Typography.uiH1)
                        .monospacedDigit()
                        .foregroundStyle(LP.Content.primary)
                        .contentTransition(.numericText())
                    Text(confidenceText(data.recovery))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.accent)
                        .padding(.horizontal, LP.Spacing.s)
                        .padding(.vertical, LP.Spacing.xs)
                        .background(Capsule().fill(LP.Colorful.green100))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("恢复分，\(scoreAccessibilityText(data.recovery))，\(confidenceText(data.recovery))")
            }
            .frame(height: 190)

            HStack(spacing: LP.Spacing.s) {
                ScoreMarker(label: "睡眠分", score: data.sleep)
                ScoreMarker(label: "活动分", score: data.activity)
            }

            Text(data.recovery == nil ? "数据还不够。先继续观察。" : "今天的恢复记录已生成")
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, LP.Spacing.s)
    }

    private var observationStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LP.Spacing.s) {
                compactMetric(
                    title: "睡眠债",
                    value: minutesText(data.sleepDebtMinutes),
                    note: "近期需要与实际睡眠"
                )
                compactMetric(
                    title: "恢复指数",
                    value: numberText(data.recoveryIndexScore),
                    note: "入睡后心率下降形态"
                )
            }
            VStack(spacing: LP.Spacing.s) {
                compactMetric(
                    title: "睡眠债",
                    value: minutesText(data.sleepDebtMinutes),
                    note: "近期需要与实际睡眠"
                )
                compactMetric(
                    title: "恢复指数",
                    value: numberText(data.recoveryIndexScore),
                    note: "入睡后心率下降形态"
                )
            }
        }
    }

    private func compactMetric(title: String, value: String, note: String) -> some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LP.Colorful.teal500)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LP.Colorful.teal100))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.secondary)
                Text(value)
                    .lpText(LP.Typography.b1Medium)
                    .monospacedDigit()
                    .foregroundStyle(LP.Content.primary)
                Text(note)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(LP.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .stroke(LP.Border.tertiary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)，\(note)")
    }

    private var trainingSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("训练负荷")
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Spacer()
                    Text(trainingStatusText)
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.accent)
                }

                TrainingRootRow(
                    label: "近 7 天",
                    value: data.acuteTrainingLoad,
                    maximum: trainingMaximum,
                    tint: LP.Fill.foundationAccent
                )
                TrainingRootRow(
                    label: "28 天周均",
                    value: data.chronicTrainingLoad,
                    maximum: trainingMaximum,
                    tint: LP.Colorful.teal500
                )
                Text("两条根系使用同一比例尺，只比较近期负荷与个人记录。")
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
    }

    private var resilienceSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("韧性")
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Spacer()
                    Text(scoreText(data.resilience))
                        .lpText(LP.Typography.uiH4)
                        .monospacedDigit()
                        .foregroundStyle(LP.Content.primary)
                }
                ResilienceNotches(observedDays: data.resilienceObservedDays)
                    .accessibilityHidden(true)
                HStack {
                    Text("14 天观察窗")
                    Spacer()
                    Text("已观测 \(min(14, max(0, data.resilienceObservedDays))) / 14 天")
                }
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                Text(confidenceText(data.resilience))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "韧性，\(scoreAccessibilityText(data.resilience))，已观测 \(min(14, max(0, data.resilienceObservedDays))) 天，\(confidenceText(data.resilience))"
        )
    }

    private var calculationBasis: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        showsCalculationBasis.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("查看计算依据")
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(LP.Content.primary)
                            Text(algorithmLabel)
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LP.Content.tertiary)
                            .rotationEffect(.degrees(showsCalculationBasis ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsCalculationBasis ? "已展开" : "已折叠")

                if showsCalculationBasis {
                    Divider().overlay(LP.Separator.secondary)
                        .padding(.vertical, LP.Spacing.m)
                    VStack(alignment: .leading, spacing: LP.Spacing.m) {
                        basisRow("睡眠分", "睡眠时长、规律、连续性与可用睡眠阶段")
                        basisRow("活动分", "步数、活跃分钟与活跃小时")
                        basisRow("恢复分", "睡眠、HRV、心率、腕温与训练记录中的可用项")
                        basisRow("韧性", "14 天恢复、压力与恢复性活动记录")
                        Text("仅使用已授权且实际到达设备的记录；缺失数据不会按 0 分处理。")
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func basisRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            Circle()
                .fill(LP.Fill.foundationAccent)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
                .accessibilityHidden(true)
            Text(title)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.primary)
                .frame(width: 48, alignment: .leading)
            Text(detail)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                    .stroke(LP.Border.tertiary, lineWidth: 1)
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isDismissing else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 88 || value.predictedEndTranslation.height > 150 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        if !reduceMotion {
            // Keep the panel below its resting position until the parent
            // removal transition completes; resetting here causes a visible
            // one-frame rebound after a successful pull-down.
            dragOffset = max(dragOffset, 22)
        }
        onDismiss()
    }

    private var generatedLabel: String {
        guard let generatedAt = data.generatedAt else { return "等待今天的数据" }
        return generatedAt.formatted(.dateTime.month().day().hour().minute()) + " 更新"
    }

    private var algorithmLabel: String {
        guard let algorithmVersion = data.algorithmVersion else { return "Core 算法 · 数据不足" }
        return "Core 算法 v\(algorithmVersion)"
    }

    private var trainingMaximum: Double {
        max(1, max(data.acuteTrainingLoad ?? 0, data.chronicTrainingLoad ?? 0))
    }

    private var trainingStatusText: String {
        switch data.trainingBalanceStatus {
        case 1: "基线建立中"
        case 2: "近期无负荷"
        case 3: "低于近期"
        case 4: "与近期相当"
        case 5: "高于近期"
        case 6: "明显高于近期"
        default: "数据不足"
        }
    }

    private func scoreText(_ score: WellnessInstrumentData.Score?) -> String {
        guard let score else { return "—" }
        return Int(score.value.rounded()).formatted()
    }

    private func scoreAccessibilityText(_ score: WellnessInstrumentData.Score?) -> String {
        guard let score else { return "数据不足" }
        return "\(Int(score.value.rounded())) 分"
    }

    private func confidenceText(_ score: WellnessInstrumentData.Score?) -> String {
        guard let score else { return "数据不足" }
        return switch score.confidenceLevel {
        case 1: "基线建立中"
        case 2: "参考值"
        case 3: "基线稳定"
        default: "数据不足"
        }
    }

    private func minutesText(_ value: Double?) -> String {
        guard let value else { return "数据不足" }
        let minutes = max(0, Int(value.rounded()))
        if minutes >= 60 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(remainder) 分"
        }
        return "\(minutes) 分钟"
    }

    private func numberText(_ value: Double?) -> String {
        guard let value else { return "数据不足" }
        return Int(value.rounded()).formatted()
    }
}

private struct TreeRingField: View {
    var body: some View {
        ZStack {
            ring(size: 250, color: LP.Colorful.green200, width: 1)
            ring(size: 214, color: LP.Colorful.teal200, width: 1.5)
            ring(size: 176, color: LP.Colorful.green300, width: 2)
            ring(size: 138, color: LP.Colorful.teal100, width: 8)
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 3) ? LP.Colorful.teal500 : LP.Colorful.green300)
                    .frame(width: 2, height: index.isMultiple(of: 3) ? 10 : 6)
                    .offset(y: -104)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipped()
    }

    private func ring(size: CGFloat, color: Color, width: CGFloat) -> some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: width == 1 ? [3, 5] : []))
            .frame(width: size, height: size)
            .offset(y: 34)
    }
}

private struct ScoreMarker: View {
    let label: String
    let score: WellnessInstrumentData.Score?

    var body: some View {
        HStack(spacing: LP.Spacing.s) {
            Circle()
                .fill(score == nil ? LP.Content.quarternary : LP.Fill.foundationAccent)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 2)
            Text(score.map { Int($0.value.rounded()).formatted() } ?? "—")
                .lpText(LP.Typography.b2Medium)
                .monospacedDigit()
                .foregroundStyle(LP.Content.primary)
        }
        .padding(.horizontal, LP.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Capsule().fill(LP.Fill.bgContainer))
        .overlay(Capsule().stroke(LP.Border.tertiary, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(score.map { "\(Int($0.value.rounded())) 分" } ?? "数据不足")")
    }
}

private struct TrainingRootRow: View {
    let label: String
    let value: Double?
    let maximum: Double
    let tint: Color

    var body: some View {
        HStack(spacing: LP.Spacing.m) {
            Text(label)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 68, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LP.Fill.bgSurfaceSecondary)
                    if let value {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(5, proxy.size.width * min(1, max(0, value / maximum))))
                    }
                }
            }
            .frame(height: 7)
            Text(value.map(Self.formatLoad) ?? "—")
                .lpText(LP.Typography.c1Medium)
                .monospacedDigit()
                .foregroundStyle(LP.Content.primary)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value.map(Self.formatLoad) ?? "数据不足")")
    }

    nonisolated private static func formatLoad(_ value: Double) -> String {
        value < 10 ? value.formatted(.number.precision(.fractionLength(1))) : Int(value.rounded()).formatted()
    }
}

private struct ResilienceNotches: View {
    let observedDays: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<14, id: \.self) { index in
                Capsule()
                    .fill(index < observedCount ? LP.Colorful.teal500 : LP.Fill.bgSurfaceSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: index.isMultiple(of: 7) ? 22 : 14)
            }
        }
        .frame(height: 22, alignment: .bottom)
    }

    private var observedCount: Int { min(14, max(0, observedDays)) }
}

#if DEBUG
#Preview("状态观测仪") {
    WellnessInstrumentView(data: .preview, onDismiss: {})
        .background(LP.Colorful.green200)
        .preferredColorScheme(.light)
}

#Preview("状态观测仪 · 数据不足") {
    WellnessInstrumentView(data: WellnessInstrumentData(record: nil), onDismiss: {})
        .background(LP.Colorful.green200)
        .preferredColorScheme(.light)
}
#endif
