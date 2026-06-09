import SwiftUI
import SwiftData

/// 上滑数据二楼 (历史数据二楼) — the "second floor" pulled up from the home grab
/// bar. A scrollable day strip + 今日能量 + 睡眠 / 运动 cards (per selected day),
/// and a 本月活动 heat-map. Today's numbers come live from `PetStateStore`; past
/// days + the heat-map read the SwiftData `HealthHistoryStore`.
///
/// Faithful to Figma nodes 74:6250 (day) / 74:6288 (month). Only the displayed
/// subset of each `HealthDayRecord` is rendered — the store keeps the full set.
struct PiboDashboardView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    /// Drag the 尾巴 / chevron down → back to the home floor.
    var onClose: () -> Void = {}

    enum Mode { case day, month }
    @State private var mode: Mode = .day
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private let cal = Calendar.current
    /// How many days back the strip / heat-map cover.
    private static let historyDays = 30

    // DateFormatter init is expensive — share one instance.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"; return f
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年M月"; return f
    }()

    var body: some View {
        // Observe history writes (backfill / reconcile) so selecting a day or the
        // heat-map refreshes once data lands.
        let _ = history.revision

        ZStack(alignment: .top) {
            LP.Fill.bgSurface.ignoresSafeArea()

            VStack(spacing: LP.Spacing.l) {
                tailHandle
                dateStrip
                Group {
                    if mode == .day { dayContent } else { monthContent }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LP.Spacing.l)
        }
    }

    // MARK: Pibo 尾巴 handle (drag down to go back)

    private var tailHandle: some View {
        VStack(spacing: 2) {
            Color.clear
                .frame(height: 58)
                .overlay(alignment: .top) {
                    Image("pibo_body")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                        .offset(y: -104)
                }
                .clipped()
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LP.Content.quarternary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.top, LP.Spacing.s)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { v in if v.translation.height > 30 { onClose() } }
        )
    }

    // MARK: Scrollable date strip + calendar toggle

    private var dateStrip: some View {
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0...Self.historyDays)
            .compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .reversed()
        let recordDays = recentRecordDays

        return HStack(spacing: LP.Spacing.s) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(days, id: \.self) { day in
                            dayChip(day, hasData: recordDays.contains(day) || cal.isDateInToday(day))
                                .id(day)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onAppear { proxy.scrollTo(today, anchor: .trailing) }
            }
            Button {
                mode = (mode == .month) ? .day : .month
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(mode == .month ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                            .fill(mode == .month ? LP.Fill.foundationAccent : LP.Fill.bgContainer)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(LP.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Separator.primary, lineWidth: 1)
        )
    }

    private func dayChip(_ day: Date, hasData: Bool) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: selectedDate) && mode == .day
        let fg: Color = isSel ? LP.Fill.foundationOnAccent
            : (hasData ? LP.Content.primary : LP.Content.quarternary)
        return Text("\(cal.component(.day, from: day))")
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(fg)
            .frame(width: 32, height: 32)
            .background(Circle().fill(isSel ? LP.Fill.foundationAccent : .clear))
            .contentShape(Circle())
            .onTapGesture { mode = .day; selectedDate = day }
    }

    // MARK: Day view

    private var dayContent: some View {
        let d = selectedDayData
        return VStack(alignment: .leading, spacing: LP.Spacing.l) {
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.text(d.isToday ? "今日数据" : "历史数据"))
                    .lpText(LP.Typography.uiH3)
                    .foregroundStyle(LP.Content.primary)
                Text(Self.dayFormatter.string(from: d.date))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                energyLine(d)
            }
            sleepCard(d)
            exerciseCard(d)
        }
    }

    private func energyLine(_ d: DayData) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Text("\(d.energyScore)")
                .lpText(LP.Typography.uiH2)
                .foregroundStyle(LP.Content.primary)
            Text(AppLocalization.format("/ 5  %@ · %@",
                                        AppLocalization.text(d.isToday ? "今日能量" : "当日能量"),
                                        d.energyWord))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < d.energyScore ? LP.Fill.foundationAccent : LP.Content.quarternary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.top, LP.Spacing.xs)
    }

    private func sleepCard(_ d: DayData) -> some View {
        dataCard(icon: "moon.zzz.fill", title: "睡眠", tint: Color(hex: 0x6C8BD0), tag: d.sleepTag) {
            cardRow("时长", d.sleepDurationText)
            cardRow("深睡", d.sleepDeepText)
            Divider().overlay(LP.Separator.primary)
            cardRow("基线", "7h · 持平", muted: true)
        }
    }

    private func exerciseCard(_ d: DayData) -> some View {
        dataCard(icon: "figure.run", title: "运动", tint: Color(hex: 0xE08A4B),
                 tag: d.isToday && d.exerciseMinutes > 0 ? "进行中" : nil) {
            cardRow("步数", d.steps > 0 ? "\(d.steps)" : "—")
            cardRow("卡路里", d.activeEnergy > 0 ? "\(Int(d.activeEnergy)) kcal" : "—")
            cardRow("户外步行", d.exerciseMinutes > 0 ? "\(d.exerciseMinutes) 分钟" : "—")
            Divider().overlay(LP.Separator.primary)
            cardRow("基线", "基于过去7天均值，每日自动更新", muted: true)
        }
    }

    // MARK: Month view

    private var monthContent: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            Text(AppLocalization.text("本月活动数据"))
                .lpText(LP.Typography.uiH3)
                .foregroundStyle(LP.Content.primary)

            VStack(spacing: LP.Spacing.m) {
                HStack {
                    Image(systemName: "chevron.left").foregroundStyle(LP.Content.tertiary)
                    Text(Self.monthFormatter.string(from: selectedDate))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(LP.Content.tertiary)
                }
                .font(.system(size: 13, weight: .medium))

                monthGrid
            }
            .padding(LP.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Separator.primary, lineWidth: 1)
            )
        }
    }

    private var monthGrid: some View {
        let levels = monthActivityLevels        // [day-of-month : 0–4]
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let count = cal.range(of: .day, in: .month, for: selectedDate)?.count ?? 30
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(1...count, id: \.self) { day in
                let level = levels[day] ?? 0
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(heatColor(level))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if level >= 3 {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(LP.Fill.foundationAccent)
                        }
                    }
                    .onTapGesture { selectDay(ofMonth: day) }
            }
        }
    }

    // MARK: - Card building blocks

    private func dataCard<Content: View>(
        icon: String, title: String, tint: Color, tag: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Content.primary)
                Spacer(minLength: 0)
                if let tag {
                    Text(AppLocalization.text(tag))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
            content()
        }
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Separator.primary, lineWidth: 1)
        )
        .lpShadow(LP.Shadow.elevation1)
    }

    private func cardRow(_ label: String, _ value: String, muted: Bool = false) -> some View {
        HStack {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
            Spacer(minLength: LP.Spacing.m)
            Text(AppLocalization.text(value))
                .lpText(muted ? LP.Typography.c1Regular : LP.Typography.b2Medium)
                .foregroundStyle(muted ? LP.Content.quarternary : LP.Content.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Data plumbing

    /// The displayed subset for one day — live from the store for today, from the
    /// SwiftData record for past days.
    private struct DayData {
        var date: Date
        var isToday: Bool
        var sleepHours: Double
        var sleepDeepPercent: Int
        var steps: Int
        var activeEnergy: Double
        var exerciseMinutes: Int
        var energyScore: Int

        var sleepDurationText: String {
            guard sleepHours > 0 else { return "—" }
            let h = Int(sleepHours), m = Int((sleepHours - Double(h)) * 60)
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        var sleepDeepText: String { sleepHours > 0 && sleepDeepPercent > 0 ? "\(sleepDeepPercent)%" : "—" }
        var sleepTag: String? {
            guard sleepHours > 0 else { return nil }
            return sleepHours >= 7 ? "良好" : (sleepHours >= 6 ? "一般" : "不足")
        }
        var energyWord: String {
            switch energyScore {
            case 4...: return "充沛"
            case 3:    return "良好"
            case 2:    return "普通"
            default:   return "低迷"
            }
        }
    }

    private var selectedDayData: DayData {
        if cal.isDateInToday(selectedDate) {
            let h = store.rawSleepHours
            return DayData(
                date: selectedDate, isToday: true,
                sleepHours: h,
                sleepDeepPercent: h > 0 ? Int((store.rawSleepDeepHours / h) * 100) : 0,
                steps: store.rawSteps, activeEnergy: store.rawActiveEnergy,
                exerciseMinutes: store.rawExerciseMinutes,
                energyScore: liveEnergyScore)
        }
        if let r = history.record(on: selectedDate) {
            return DayData(
                date: selectedDate, isToday: false,
                sleepHours: r.sleepTotal / 3600, sleepDeepPercent: r.deepSleepPercent,
                steps: r.steps, activeEnergy: r.activeEnergy, exerciseMinutes: r.exerciseMinutes,
                energyScore: r.energyScore)
        }
        return DayData(date: selectedDate, isToday: false, sleepHours: 0, sleepDeepPercent: 0,
                       steps: 0, activeEnergy: 0, exerciseMinutes: 0, energyScore: 0)
    }

    /// Days (startOfDay) in the strip window that actually have a stored record.
    private var recentRecordDays: Set<Date> {
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -Self.historyDays, to: today) ?? today
        return Set(history.records(from: start, to: today).map { cal.startOfDay(for: $0.date) })
    }

    /// day-of-month → activity level 0–4 for the selected month.
    private var monthActivityLevels: [Int: Int] {
        var out: [Int: Int] = [:]
        for r in history.recordsForMonth(containing: selectedDate) {
            out[cal.component(.day, from: r.date)] = r.activityLevel
        }
        return out
    }

    private var liveEnergyScore: Int {
        switch store.activityState {
        case .active: return 4
        case .waking: return 3
        case .idle: return 2
        case .disturbed, .irritated: return 1
        case .deepSleep: return 2
        }
    }

    private func selectDay(ofMonth day: Int) {
        var comps = cal.dateComponents([.year, .month], from: selectedDate)
        comps.day = day
        if let date = cal.date(from: comps), date <= Date() {
            selectedDate = cal.startOfDay(for: date)
            mode = .day
        }
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 0: return LP.Content.quarternary.opacity(0.12)
        case 1: return LP.Fill.foundationAccent.opacity(0.22)
        case 2: return LP.Fill.foundationAccent.opacity(0.40)
        case 3: return LP.Fill.foundationAccent.opacity(0.62)
        default: return LP.Fill.foundationAccent.opacity(0.85)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: HealthDayRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let hist = HealthHistoryStore(context: container.mainContext)
    #if DEBUG
    hist.seedSampleHistoryIfEmpty()
    #endif
    return PiboDashboardView()
        .environment(PetStateStore(demoMode: true))
        .environment(hist)
}
