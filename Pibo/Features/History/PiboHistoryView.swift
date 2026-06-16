import SwiftUI
import SwiftData

/// 历史数据页 (history data page) — the health-history surface and the content of
/// the home's 上滑数据二楼 (pulled up from the grab bar; `HomeView`'s
/// `FloorContainer` drawer hosts it and overlays the ⌄ close handle on top).
///
/// Faithful to Figma `🍃 history/data` (59:342 → page 179:8678): a scrollable
/// stack of 打招呼 header → 日期选择 + 品种(bohair) → 活动 / 今日脚步 / 睡眠 /
/// 运动记录 / 体征 / 今日记录 cards. Today's numbers come live from
/// `PetStateStore`; past days read the SwiftData `HealthHistoryStore` (records +
/// per-workout detail + cut-out food photos).
struct PiboHistoryView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private let cal = Calendar.current

    var body: some View {
        // Observe history writes (backfill / reconcile / new food photo) so the
        // selected day refreshes once data lands.
        let _ = history.revision
        let day = makeDay(selectedDate)

        ScrollView(showsIndicators: false) {
            VStack(spacing: LP.Spacing.s) {
                header
                dateSection
                cardsStack(day)
                Color.clear.frame(height: LP.Spacing.xxl)
            }
            .padding(.top, 64)   // clear the ⌄ close handle + dome crown
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("历史"))
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.format("陪你走过的 %d 天", totalDays))
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LP.Spacing.xl)
    }

    // MARK: Date + 品种

    private var dateSection: some View {
        VStack(spacing: 0) {
            HistoryDateBar(
                dateText: Self.dateFormatter.string(from: selectedDate),
                weekdayText: Self.weekdayFormatter.string(from: selectedDate),
                dayLabel: dayLabel,
                canGoForward: selectedDate < cal.startOfDay(for: .now),
                onPrev: { shift(-1) },
                onNext: { shift(1) }
            )
            .padding(.horizontal, LP.Spacing.xl)

            HistoryBohairList()
                .padding(.vertical, LP.Spacing.l)
        }
    }

    // MARK: Cards

    private func cardsStack(_ day: HistoryDay) -> some View {
        VStack(spacing: LP.Spacing.m) {
            HistoryActivityCard(
                kcal: Int(day.activeEnergy.rounded()),
                exerciseMinutes: day.exerciseMinutes,
                standHours: day.standHours)
            HistoryStepsCard(
                steps: day.steps,
                hourlySteps: day.hourlySteps,
                isToday: day.isToday,
                caption: AppLocalization.text(stepsCaption(day.steps)))
            HistorySleepCard(
                totalSeconds: day.sleepTotal, deepSeconds: day.sleepDeep,
                remSeconds: day.sleepREM, start: day.sleepStart, end: day.sleepEnd,
                segments: day.sleepSegments)
            // 没有运动就整卡不渲染；体征同理（全部缺数据才隐藏）。
            if !day.workouts.isEmpty {
                HistoryWorkoutsCard(workouts: day.workouts)
            }
            if day.heartRate > 0 || day.restingHR > 0 || day.hrv > 0 || day.oxygen > 0 {
                HistoryVitalsCard(
                    heartRate: day.heartRate, restingHR: day.restingHR,
                    hrv: day.hrv, oxygen: day.oxygen)
            }
            HistoryFoodCard(foods: day.foods)
        }
        .padding(.horizontal, LP.Spacing.xl)
    }

    // MARK: - Data assembly

    /// One day's displayed subset — live from the store for today, from the
    /// SwiftData record (+ workout / food queries) for past days.
    private struct HistoryDay {
        var date: Date
        var isToday: Bool
        var activeEnergy: Double
        var exerciseMinutes: Int
        var standHours: Int
        var steps: Int
        var hourlySteps: [Int]
        var sleepTotal: TimeInterval
        var sleepDeep: TimeInterval
        var sleepREM: TimeInterval
        var sleepStart: Date?
        var sleepEnd: Date?
        var sleepSegments: [SleepSegmentValue]
        var heartRate: Double
        var restingHR: Double
        var hrv: Double
        var oxygen: Double          // fraction 0–1
        var workouts: [WorkoutRecord]
        var foods: [FoodPhoto]
    }

    private func makeDay(_ date: Date) -> HistoryDay {
        let workouts = history.workouts(on: date)
        let foods = history.foodPhotos(on: date)
        if cal.isDateInToday(date) {
            let sleepH = store.rawSleepHours
            let start = store.rawSleepStart
            // Hourly steps + sleep segments aren't in the live RawMetrics —
            // read them off today's backfilled record.
            let r = history.record(on: date)
            return HistoryDay(
                date: date, isToday: true,
                activeEnergy: store.rawActiveEnergy,
                exerciseMinutes: store.rawExerciseMinutes,
                standHours: Int((Double(store.rawStandMinutes) / 60).rounded()),
                steps: store.rawSteps,
                hourlySteps: r?.hourlySteps ?? [],
                sleepTotal: sleepH * 3600,
                sleepDeep: store.rawSleepDeepHours * 3600,
                sleepREM: store.rawSleepREMHours * 3600,
                sleepStart: start,
                sleepEnd: start.map { $0.addingTimeInterval(sleepH * 3600) },
                sleepSegments: r?.sleepSegments ?? [],
                heartRate: store.rawHeartRate,
                restingHR: store.rawRestingHR,
                hrv: store.rawHRV,
                oxygen: store.rawOxygen,
                workouts: workouts, foods: foods)
        }
        let r = history.record(on: date)
        return HistoryDay(
            date: date, isToday: false,
            activeEnergy: r?.activeEnergy ?? 0,
            exerciseMinutes: r?.exerciseMinutes ?? 0,
            standHours: Int((Double(r?.standMinutes ?? 0) / 60).rounded()),
            steps: r?.steps ?? 0,
            hourlySteps: r?.hourlySteps ?? [],
            sleepTotal: r?.sleepTotal ?? 0,
            sleepDeep: r?.sleepDeep ?? 0,
            sleepREM: r?.sleepREM ?? 0,
            sleepStart: r?.sleepStart,
            sleepEnd: r?.sleepEnd,
            sleepSegments: r?.sleepSegments ?? [],
            heartRate: r?.heartRateAvg ?? 0,
            restingHR: r?.restingHR ?? 0,
            hrv: r?.hrv ?? 0,
            oxygen: r?.oxygenSaturation ?? 0,
            workouts: workouts, foods: foods)
    }

    /// 相识总天数 (header "陪你走过的 N 天").
    private var totalDays: Int { max(1, store.dayCount) }

    /// 第 N/总 天 — N is the selected day's ordinal within the relationship.
    private var dayLabel: String {
        let back = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: selectedDate),
                                      to: cal.startOfDay(for: .now)).day ?? 0
        let n = min(totalDays, max(1, totalDays - back))
        return AppLocalization.format("第 %d/%d 天", n, totalDays)
    }

    private func shift(_ days: Int) {
        guard let next = cal.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let start = cal.startOfDay(for: next)
        guard start <= cal.startOfDay(for: .now) else { return }
        selectedDate = start
    }

    private func stepsCaption(_ steps: Int) -> String {
        switch steps {
        case 10_000...: return "今天走了很远，花也跟着精神"
        case 6_000...:  return "稳稳的一天，继续保持"
        case 3_000...:  return "人生不过三万天，今天也走了几步"
        default:        return "人生不过三万天，今天先迈出第一步"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"; return f
    }()
}

// MARK: - Domed crown

/// The 二楼 panel's domed top — a wide, shallow convex arc (≈ Figma Ellipse 24, a
/// 749-pt circle). The apex bleeds `rise` pt **above** the frame, so at rest
/// (panel offset 0) the dome sits off-screen and the top fills flat; during the
/// pull-up the panel rides down and the crown sweeps into view.
///
/// Lives here (not `HomeView`) because the 二楼 surface is the history page's
/// crown — `HomeView.secondFloorPanel` fills + clips this shape.
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
    PiboHistoryView()
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

/// Preview-only SwiftData host. The container + store live in `static let`s so
/// they survive the whole preview process: a container scoped *inside* the
/// `#Preview` closure deallocates once the closure returns its view, which
/// invalidates the fetched `@Model` rows (`WorkoutRecord` / `FoodPhoto`) — the
/// next body render then traps inside SwiftData when a `ForEach` reads them
/// (`EXC_BREAKPOINT` in `DynamicViewList.updateValue`). The real app is immune
/// because its `ModelContainer` is a long-lived `PiboApp` stored property.
///
/// Disk-backed (a fresh per-process temp store), not `isStoredInMemoryOnly`,
/// since `FoodPhoto.pngData` is `@Attribute(.externalStorage)`.
private enum HistoryPreviewData {
    static let container: ModelContainer = {
        let url = URL.temporaryDirectory.appending(path: "pibo_history_preview_\(UUID().uuidString).store")
        return try! ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self,
            configurations: ModelConfiguration(url: url))
    }()

    static let store: HealthHistoryStore = {
        let s = HealthHistoryStore(context: container.mainContext)
        #if DEBUG
        s.seedSampleAllIfEmpty()
        #endif
        return s
    }()
}
