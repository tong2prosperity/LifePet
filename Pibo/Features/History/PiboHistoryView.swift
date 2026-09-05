import SwiftUI
import SwiftData

/// 历史数据页 (history data page) — the health-history surface and the content of
/// the home's 上滑数据二楼 (pulled up from the grab bar; `HomeView`'s
/// `FloorContainer` drawer hosts it and overlays the ⌄ close handle on top).
///
/// Faithful to Figma `🍃 history/data` (59:342 → page 179:8678): a scrollable
/// stack of 打招呼 header → 日期选择 → 活动 / 今日脚步 / 睡眠 / 运动记录 / 体征 /
/// 压力 cards. Today's numbers come live from `PetStateStore`; past days read
/// the SwiftData `HealthHistoryStore` (records + per-workout detail).
///
/// The 0801 走查 cut four blocks from this page: 品种(bohair) 选择器 + 「第 N/总 天」,
/// 睡眠周报, 今日记录 (餐照), 足迹涂鸦. Their components are still on disk.
struct PiboHistoryView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    @Environment(HealthDataService.self) private var health

    /// Card to scroll to on open (notification deep link). `nil` = top of page.
    var focus: HistoryFocus?

    @State private var selectedDate: Date = Self.initialDate()
    @State private var preparingShare = false
    @State private var shareSnapshot: TodayPiboShareSnapshot?
    @State private var showHealthStatus = false

    private let cal = Calendar.current

    /// 截图验证用：`-PiboHistoryDayOffset=1` 直接落在昨天（今天读的是实时 store，
    /// 模拟器上全是 0，看不出卡片对数据的映射）。
    private static func initialDate() -> Date {
        let today = Calendar.current.startOfDay(for: .now)
        #if DEBUG
        let prefix = "-PiboHistoryDayOffset="
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let offset = Int(raw.dropFirst(prefix.count)),
           let shifted = Calendar.current.date(byAdding: .day, value: -offset, to: today) {
            return shifted
        }
        #endif
        return today
    }

    var body: some View {
        // Observe history writes (backfill / reconcile / new food photo) so the
        // selected day refreshes once data lands.
        let _ = history.revision
        let day = makeDay(selectedDate)

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: LP.Spacing.s) {
                    header
                    dateSection
                    cardsStack(day)
                    Color.clear.frame(height: LP.Spacing.xxl)
                }
                .padding(.top, 88)   // clear the #E8EEF1 dome ceiling crown (drawn on top)
            }
            .task { await scrollToFocus(using: proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { shareSnapshot != nil },
            set: { if !$0 { shareSnapshot = nil } }
        )) {
            if let shareSnapshot { TodayPiboShareSheet(snapshot: shareSnapshot) }
        }
        .sheet(isPresented: $showHealthStatus) {
            HealthDataStatusSheet()
        }
        // Transparent — the opaque rising surface is `FloorContainer`'s single drawer
        // (one #E8EEF1 `FloorDome` surface: convex-up domed top, fills down), which
        // this content rides on top of. Giving this ScrollView its own opaque bg would
        // make it a *second* surface fading in mid-pull → a dome-region jump. Cards
        // carry their own fills.
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: LP.Spacing.m) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text(AppLocalization.text("历史"))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.secondary)
                Text(AppLocalization.format("陪你走过的 %d 天", totalDays))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
            }
            Spacer(minLength: 0)
            if cal.isDateInToday(selectedDate) {
                Button {
                    prepareTodayShare()
                } label: {
                    Group {
                        if preparingShare { ProgressView() }
                        else { Image(systemName: "square.and.arrow.up") }
                    }
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LP.Fill.bgContainer))
                }
                .buttonStyle(.plain)
                .disabled(preparingShare)
                .accessibilityLabel(preparingShare ? "正在准备今日分享" : "分享今天的 Pibo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LP.Spacing.xl)
    }

    // MARK: Date

    /// 品种(bohair) 选择器 + 「第 N/总 天」 were removed in the 0801 走查 — both were
    /// display-only (no 品种 model behind them). `HistoryBohairList` is kept on
    /// disk so restoring it is a one-line change once a real 品种 model lands.
    private var dateSection: some View {
        HistoryDateBar(
            dateText: Self.dateFormatter.string(from: selectedDate),
            weekdayText: Self.weekdayFormatter.string(from: selectedDate),
            canGoForward: selectedDate < cal.startOfDay(for: .now),
            onPrev: { shift(-1) },
            onNext: { shift(1) }
        )
        .padding(.horizontal, LP.Spacing.xl)
    }

    // MARK: Cards

    private func cardsStack(_ day: HistoryDay) -> some View {
        VStack(spacing: LP.Spacing.m) {
            HistoryActivityCard(
                kcal: Int(day.activeEnergy.rounded()),
                exerciseMinutes: day.exerciseMinutes,
                standHours: day.standHours,
                moveGoal: day.moveGoal,
                exerciseGoal: day.exerciseGoal,
                standGoal: day.standGoal)
            HistoryStepsCard(
                steps: day.steps,
                hourlySteps: day.hourlySteps,
                isToday: day.isToday,
                caption: AppLocalization.text(stepsCaption(day.steps)),
                dayID: day.date)
            HistorySleepCard(
                totalSeconds: day.sleepTotal, deepSeconds: day.sleepDeep,
                remSeconds: day.sleepREM, start: day.sleepStart, end: day.sleepEnd,
                segments: day.sleepSegments)
            // 没有运动就整卡不渲染；体征同理（全部缺数据才隐藏）。
            if !day.workouts.isEmpty {
                HistoryWorkoutsCard(workouts: day.workouts)
            }
            if day.heartRate > 0 || day.restingHR > 0 || day.rmssd > 0 || day.oxygen > 0 {
                HistoryVitalsCard(
                    heartRate: day.heartRate, restingHR: day.restingHR,
                    rmssd: day.rmssd, stressLevel: stressTier(day.rmssd),
                    oxygen: day.oxygen)
            }
            // 压力 — today only. 派生分随每分钟心率刷新（HRV 锚点 + 心率调制）。
            if day.isToday, let stress = store.derivedStress {
                HistoryStressCard(stress: stress, rmssd: store.rmssd, baseline: store.stressBaseline)
                    .id(HistoryFocus.stress)
            }
            // 睡眠周报 / 今日记录 / 足迹涂鸦 三个板块在 0801 走查里被删掉；
            // 组件文件保留（`HistorySleepWeeklyCard` / `HistoryFoodCard` /
            // `HistoryDoodleCard`），要恢复只需在这里加回一行。
            // 注意 `SleepWeeklyReport` 本身不是死代码 —— 首页的晨间睡眠卡还在用。
        }
        .padding(.horizontal, LP.Spacing.xl)
    }

    /// Tier for a day's RMSSD against the personal baseline. Routed through
    /// `StressScore` so the 体征 tile, the 压力卡 and the notification all judge by
    /// the same `pibo-core` kernel — this view must not carry its own cut-offs.
    /// `nil` while the baseline is still cold-starting, which the tile says out
    /// loud rather than dressing a population guess as a personal read.
    private func stressTier(_ rmssd: Double) -> StressLevel? {
        guard rmssd > 0, let baseline = store.stressBaseline,
              baseline.dayCount >= StressScore.coldStartDays else { return nil }
        return StressScore.anchor(rmssd: rmssd, baseline: baseline).map(StressScore.tier(for:))
    }

    // MARK: - Deep link

    /// Scroll the routed card into view once the page has laid out.
    ///
    /// The frame delay is load-bearing: `cardsStack` is built from `makeDay`,
    /// whose SwiftData reads land after the first layout pass, so scrolling
    /// immediately targets an id that doesn't exist yet. A no-op is also the
    /// correct outcome when the card genuinely isn't there — the 压力卡 renders
    /// only for today and only with a derived score — so this never needs to
    /// verify the target, just to ask after the page has settled.
    private func scrollToFocus(using proxy: ScrollViewProxy) async {
        guard let focus else { return }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(focus, anchor: .center)
        }
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
        var moveGoal: Double
        var exerciseGoal: Int
        var standGoal: Int
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
        var hrv: Double             // Apple SDNN — legacy, no longer displayed
        /// Our own RMSSD for this day. Today = the live reading; past days = that
        /// day's finalized median resting reading. A different metric from `hrv`.
        var rmssd: Double
        var oxygen: Double          // fraction 0–1
        var workouts: [WorkoutRecord]
    }

    private func makeDay(_ date: Date) -> HistoryDay {
        let workouts = history.workouts(on: date)
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
                moveGoal: r?.moveGoal ?? 0,
                exerciseGoal: r?.exerciseGoal ?? 0,
                standGoal: r?.standGoal ?? 0,
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
                rmssd: store.rmssd ?? 0,
                oxygen: store.rawOxygen,
                workouts: workouts)
        }
        let r = history.record(on: date)
        return HistoryDay(
            date: date, isToday: false,
            activeEnergy: r?.activeEnergy ?? 0,
            exerciseMinutes: r?.exerciseMinutes ?? 0,
            standHours: Int((Double(r?.standMinutes ?? 0) / 60).rounded()),
            moveGoal: r?.moveGoal ?? 0,
            exerciseGoal: r?.exerciseGoal ?? 0,
            standGoal: r?.standGoal ?? 0,
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
            rmssd: StressBaselineStore.dailyMedian(for: date) ?? 0,
            oxygen: r?.oxygenSaturation ?? 0,
            workouts: workouts)
    }

    /// 相识总天数 (header "陪你走过的 N 天").
    private var totalDays: Int { max(1, store.dayCount) }

    private func prepareTodayShare() {
        guard !preparingShare else { return }
        preparingShare = true
        Task {
            await health.reconcile()
            let snapshot = TodayPiboShareSnapshot.make(
                store: store,
                record: history.record(on: .now)
            )
            if health.dataAvailability.hasReliableData, snapshot.hasHealthFacts {
                shareSnapshot = snapshot
            } else {
                showHealthStatus = true
            }
            preparingShare = false
        }
    }


    private func shift(_ days: Int) {
        guard let next = cal.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let start = cal.startOfDay(for: next)
        guard start <= cal.startOfDay(for: .now) else { return }
        selectedDate = start
    }

    private func stepsCaption(_ steps: Int) -> String {
        steps > 0 ? "history.steps.recorded" : "history.steps.empty"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"; return f
    }()
}

// `FloorDome` (the #E8EEF1 drawer surface shape) moved to
// `Features/Home/Floor/FloorDome.swift` — it's the pull-up's surface, not history
// content. This page is just the (transparent) content that rides on top of it.

#Preview {
    PiboHistoryView()
        .background(Color(hex: 0xEAEEEF).ignoresSafeArea())
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

/// Preview-only SwiftData host, **shared by the `PiboHistoryView` and `HomeView`
/// previews** (HomeView embeds PiboHistoryView, so its preview hits the same SwiftData
/// paths). The container + store live in `static let`s so they survive the whole
/// preview process: a container scoped *inside* a `#Preview` closure deallocates once
/// the closure returns its view, which invalidates the fetched `@Model` rows
/// (`WorkoutRecord` / `FoodPhoto`) — the next body render then traps inside SwiftData
/// (`EXC_BREAKPOINT`, e.g. a `ForEach` reading rows, or a re-layout re-fetching). The
/// real app is immune because its `ModelContainer` is a long-lived `PiboApp` property.
///
/// Disk-backed (a fresh per-process temp store), not `isStoredInMemoryOnly`,
/// since `FoodPhoto.pngData` is `@Attribute(.externalStorage)`.
enum HistoryPreviewData {
    static let container: ModelContainer = {
        let url = URL.temporaryDirectory.appending(path: "pibo_history_preview_\(UUID().uuidString).store")
        return try! ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self,
            configurations: ModelConfiguration(url: url))
    }()

    static let store: HealthHistoryStore = {
        let s = HealthHistoryStore(context: container.mainContext)
        #if DEBUG
        Task { await s.seedSampleAllIfEmpty() }
        #endif
        return s
    }()
}
