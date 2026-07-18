import SwiftUI

/// Redesigned 足迹 surface. The original `PiboHistoryView` remains available in
/// `HistoryFloorView` as 原版 while this screen is evaluated.
struct PiboFootprintsView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    @Environment(PiboSpeechService.self) private var piboSpeech

    private enum Scope: Hashable {
        case journal
        case trends
    }

    @State private var scope: Scope = Self.debugInitialScope
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var selectedHour: Int?
    @State private var trendRange: FootprintsTrendRange = .sevenDays
    @State private var trendMetric: FootprintsMetric = .sleep
    @State private var trendSelectedDate: Date?
    @State private var sheet: FootprintsDetailDestination? = Self.debugInitialSheet
    @State private var insightSpeech: PiboSpeech?

    private let calendar = Calendar.current

    private static var debugInitialScope: Scope {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PiboHistoryScope=trends") {
            return .trends
        }
        #endif
        return .journal
    }

    private static var debugInitialSheet: FootprintsDetailDestination? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("-PiboHistorySheet=")
        }) else { return nil }
        switch String(raw.dropFirst("-PiboHistorySheet=".count)) {
        case "sleep": return .metric(.sleep)
        case "steps": return .metric(.steps)
        case "vitals": return .vitals
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private static var debugScrollTarget: String? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("-PiboHistoryScroll=")
        }) else { return nil }
        return String(raw.dropFirst("-PiboHistoryScroll=".count))
        #else
        return nil
        #endif
    }

    var body: some View {
        let _ = history.revision
        let day = FootprintsDaySnapshot.make(
            date: selectedDate,
            store: store,
            history: history
        )
        let insight = FootprintsInsight.make(day: day, history: history)
        let trendPoints = FootprintsTrendPoint.make(
            range: trendRange,
            store: store,
            history: history
        )

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: LP.Spacing.xxl) {
                    header
                    scopeControl

                    if scope == .journal {
                        journalContent(day: day, insight: insight)
                    } else {
                        FootprintsTrendView(
                            points: trendPoints,
                            appearance: store.appearance,
                            range: $trendRange,
                            metric: $trendMetric,
                            selectedDate: $trendSelectedDate,
                            onOpenMetric: { sheet = .metric($0) }
                        )
                    }

                    // Liquid Glass floats over scroll content on iOS 26. Keep
                    // the final photo/doodle fully scrollable above the bar.
                    Color.clear.frame(height: 128)
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.top, 76)
            }
            .task {
                guard let target = Self.debugScrollTarget else { return }
                await Task.yield()
                proxy.scrollTo(target, anchor: .top)
            }
        }
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .onChange(of: selectedDate) { _, _ in selectedHour = nil }
        .task(id: InsightSpeechRequest(
            date: selectedDate,
            cue: insight.speechCue,
            isVisible: scope == .journal
        )) {
            guard scope == .journal else {
                insightSpeech = nil
                return
            }
            insightSpeech = piboSpeech.resolve(
                cues: [insight.speechCue],
                context: .dashboard()
            )
        }
        .sheet(item: $sheet) { destination in
            FootprintsDetailSheetHost(
                destination: destination,
                day: detailDay,
                trendPoints: detailTrendPoints,
                stress: store.derivedStress,
                rmssd: store.rmssd,
                stressBaseline: store.stressBaseline
            )
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.text("足迹"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text(AppLocalization.text("与 Pibo 相识第 \(relationshipDay) 天"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
            }
            Spacer(minLength: 48)
            Text(scope == .journal ? Self.fullDate.string(from: selectedDate) : "近况")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
        }
    }

    private var scopeControl: some View {
        FootprintsScopeControl(
            choices: [(.journal, "日记"), (.trends, "趋势")],
            selection: $scope
        )
    }

    private func journalContent(
        day: FootprintsDaySnapshot,
        insight: FootprintsInsight
    ) -> some View {
        VStack(spacing: LP.Spacing.xxl) {
            FootprintsDateStrip(
                selectedDate: $selectedDate,
                minimumDate: store.identity.birthDate
            )

            FootprintsInsightHero(
                insight: insight,
                piboLine: insightSpeech?.text,
                appearance: store.appearance,
                onOpen: { sheet = .metric(insight.metric) }
            )

            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                FootprintsSectionHeader(
                    "这一天的身体",
                    caption: "轻点指标查看个人常态与数据来源"
                )
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: LP.Spacing.s),
                        GridItem(.flexible()),
                    ],
                    spacing: LP.Spacing.s
                ) {
                    ForEach(FootprintsMetric.allCases) { metric in
                        FootprintsMetricTile(
                            metric: metric,
                            value: metric.value(in: day),
                            comparison: comparison(for: metric, day: day),
                            onOpen: { sheet = .metric(metric) }
                        )
                    }
                }
            }

            FootprintsDayRhythmCard(day: day, selectedHour: $selectedHour)
                .id("rhythm")
            FootprintsBodySignalsCard(day: day) { sheet = .vitals }

            if day.isToday, let stress = store.derivedStress {
                FootprintsStressCompactCard(
                    stress: stress,
                    baseline: store.stressBaseline,
                    onOpen: { sheet = .stress }
                )
            }

            FootprintsMomentsSection(
                day: day,
                onWorkout: { sheet = .workout($0) },
                onFood: { sheet = .food($0) },
                onDoodle: { sheet = .doodle($0) }
            )
            .id("moments")
        }
    }

    private var relationshipDay: Int {
        let birth = calendar.startOfDay(for: store.identity.birthDate)
        let selected = calendar.startOfDay(for: selectedDate)
        let offset = calendar.dateComponents([.day], from: birth, to: selected).day ?? 0
        return max(1, offset + 1)
    }

    private var detailDay: FootprintsDaySnapshot {
        let date = scope == .journal ? selectedDate : Date()
        return FootprintsDaySnapshot.make(date: date, store: store, history: history)
    }

    private var detailTrendPoints: [FootprintsTrendPoint] {
        FootprintsTrendPoint.make(
            range: .thirtyDays,
            store: store,
            history: history
        )
    }

    private func comparison(
        for metric: FootprintsMetric,
        day: FootprintsDaySnapshot
    ) -> String {
        let value = metric.value(in: day)
        guard metric.hasValue(value) else { return "暂无可用数据" }
        guard let end = calendar.date(byAdding: .day, value: -1, to: day.date),
              let start = calendar.date(byAdding: .day, value: -28, to: day.date) else {
            return "正在积累个人常态"
        }
        let values = history.records(from: start, to: end)
            .map(metric.value)
            .filter(metric.hasValue)
        guard values.count >= 5, let baseline = footprintsMedian(values) else {
            return "正在积累个人常态"
        }
        let delta = value - baseline
        if abs(delta) <= max(0.1, baseline * 0.04) { return "接近你的近期常态" }
        switch metric {
        case .sleep:
            let minutes = Int((abs(delta) * 60).rounded())
            return "比常态\(delta > 0 ? "多" : "少") \(minutes) 分钟"
        case .steps:
            return "比常态\(delta > 0 ? "多" : "少") \(Int(abs(delta).rounded())) 步"
        case .activeEnergy:
            return "比常态\(delta > 0 ? "高" : "低") \(Int(abs(delta).rounded())) kcal"
        case .hrv:
            return "比常态\(delta > 0 ? "高" : "低") \(Int(abs(delta).rounded())) ms"
        }
    }

    private static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private struct InsightSpeechRequest: Hashable {
        let date: Date
        let cue: PiboSpeechCue
        let isVisible: Bool
    }
}

#Preview("足迹新版") {
    PiboFootprintsView()
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(HistoryPreviewData.store)
}
