import SwiftUI
import SwiftData

/// 上滑数据二楼 (历史数据二楼) — the "second floor" pulled up from the home grab
/// bar. Pibo's feet hang from a domed crown (the panel edge during the pull-up),
/// over a scrollable day strip + 今日能量 + 睡眠 / 运动 cards (per selected day),
/// and a 本月活动 heat-map. Today's numbers come live from `PetStateStore`; past
/// days + the heat-map read the SwiftData `HealthHistoryStore`.
///
/// Faithful to Figma nodes 74:6250 (day) / 74:6288 (month): cool grey-blue panel
/// (#EAEEEF), 4%-black date-strip rail wrapping a white pill, #1FA843 accents,
/// rounded-square day selection. Only the displayed subset of each
/// `HealthDayRecord` is rendered — the store keeps the full set.
struct PiboDashboardView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history

    enum Mode { case day, month }
    @State private var mode: Mode = .day
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private let cal = Calendar.current
    /// How many days back the strip / heat-map cover.
    private static let historyDays = 30

    // Date-strip / energy / heat-map accent — the brand green (#1FA843 = green 500).
    // The panel surface (#EAEEEF dome) is drawn by `FloorContainer`; this view is
    // content-only. (Future/inactive greys now read from `LP.Content`.)
    private let accent = LP.Fill.foundationAccent

    // DateFormatter init is expensive — share one instance.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"; return f
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月"; return f
    }()

    var body: some View {
        // Observe history writes (backfill / reconcile) so selecting a day or the
        // heat-map refreshes once data lands.
        let _ = history.revision

        // Content only — the domed #EAEEEF surface + the hanging-feet handle are
        // drawn by `FloorContainer` so they can rise/fade/emerge independently.
        // The top inset clears the feet that hang from the status bar.
        VStack(spacing: LP.Spacing.l) {
            dateStrip
            Group {
                if mode == .day { dayContent } else { monthContent }
            }
            // Content sits 8pt inside the date strip (Figma: rail margin 20 / content 28).
            .padding(.horizontal, LP.Spacing.s)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LP.Spacing.xl)   // 20 — date-strip margin
        .padding(.top, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Scrollable date strip + calendar toggle

    /// A 4%-black rail wrapping a white scrolling pill of day cells, with the
    /// grid toggle resting on the rail to the right (Figma 74:6259).
    private var dateStrip: some View {
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0...Self.historyDays)
            .compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .reversed()
        let recordDays = recentRecordDays

        return HStack(spacing: LP.Spacing.m) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayChip(day, hasData: recordDays.contains(day) || cal.isDateInToday(day))
                                .id(day)
                        }
                    }
                    .padding(5)
                }
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous).fill(LP.Fill.bgPop)
                )
                .onAppear { proxy.scrollTo(today, anchor: .trailing) }
            }
            gridToggle
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(Color.black.opacity(0.04))   // 4%-black rail — bespoke subtle wash, no token
        )
    }

    private var gridToggle: some View {
        Button {
            mode = (mode == .month) ? .day : .month
        } label: {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(mode == .month ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(mode == .month ? accent : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("本月活动"))
    }

    private func dayChip(_ day: Date, hasData: Bool) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: selectedDate) && mode == .day
        let isFuture = day > cal.startOfDay(for: .now)
        let fg: Color = isSel ? LP.Fill.foundationOnAccent
            : isFuture ? LP.Content.quarternary
            : (hasData ? accent : LP.Content.tertiary)
        return Text("\(cal.component(.day, from: day))")
            .lpText(LP.Typography.b2Medium)
            .foregroundStyle(fg)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSel ? accent : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { if !isFuture { mode = .day; selectedDate = day } }
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

    /// Big energy score with the "/5 今日能量 · …" caption and the 5-dot meter
    /// stacked to its right (Figma 74:6250) — the dots align under the caption,
    /// not under the number.
    private func energyLine(_ d: DayData) -> some View {
        HStack(alignment: .center, spacing: LP.Spacing.m) {
            Text("\(d.energyScore)")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(LP.Content.primary)
            VStack(alignment: .leading, spacing: 7) {
                Text(AppLocalization.format("/ 5  %@ · %@",
                                            AppLocalization.text(d.isToday ? "今日能量" : "当日能量"),
                                            d.energyWord))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i < d.energyScore ? accent : Color.black.opacity(0.12))
                            .frame(width: 7, height: 7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func sleepCard(_ d: DayData) -> some View {
        dataCard(icon: "moon.stars.fill", title: "睡眠",
                 tint: LP.Colorful.yellow500, tag: d.sleepTag) {
            cardRow("时长", d.sleepDurationText)
            cardRow("深睡", d.sleepDeepText)
            Divider().overlay(LP.Separator.primary)
            cardRow("基线", "7h · 持平", muted: true)
        }
    }

    private func exerciseCard(_ d: DayData) -> some View {
        dataCard(icon: "figure.run", title: "运动", tint: accent,
                 tag: d.isToday ? "进行中" : (d.steps > 0 ? "已完成" : nil)) {
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

            VStack(spacing: LP.Spacing.l) {
                HStack(spacing: LP.Spacing.s) {
                    Image(systemName: "chevron.left").foregroundStyle(LP.Content.tertiary)
                    Text(Self.monthFormatter.string(from: selectedDate))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(LP.Content.tertiary)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .medium))

                monthGrid
            }
            .padding(LP.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgPop)
            )
        }
    }

    private var monthGrid: some View {
        let levels = monthActivityLevels        // [day-of-month : 0–4]
        let cols = Array(repeating: GridItem(.flexible(), spacing: LP.Spacing.s), count: 7)
        let count = cal.range(of: .day, in: .month, for: selectedDate)?.count ?? 30
        return LazyVGrid(columns: cols, spacing: LP.Spacing.s) {
            ForEach(1...count, id: \.self) { day in
                let level = levels[day] ?? 0
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(heatColor(level))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if level >= 3 {
                            Image(systemName: "hurricane")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accent)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint.opacity(0.15)))
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
                .fill(LP.Fill.bgPop)
                .lpShadow(LP.Shadow.elevation2)
        )
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
        case 0: return Color.black.opacity(0.05)
        case 1: return accent.opacity(0.18)
        case 2: return accent.opacity(0.34)
        case 3: return accent.opacity(0.50)
        default: return accent.opacity(0.68)
        }
    }
}

// MARK: - Domed crown

/// The 二楼 panel's domed top — a wide, shallow convex arc (≈ Figma Ellipse 24, a
/// 749-pt circle). The apex bleeds `rise` pt **above** the frame, so at rest
/// (panel offset 0) the dome sits off-screen and the top fills flat; during the
/// pull-up the panel rides down and the crown sweeps into view.
struct FloorDome: Shape {
    var rise: CGFloat = 54
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let shoulderY = rect.minY
        let apexY = rect.minY - rise
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        // Quadratic whose apex lands at `apexY`: control = 2·apex − shoulder.
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: shoulderY),
                       control: CGPoint(x: rect.midX, y: 2 * apexY - shoulderY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
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
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(hist)
}
