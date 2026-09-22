import SwiftUI
import SwiftData

/// 健康记录 — the full-screen health-history page (Figma `🍃 history/data`,
/// Harmony-first 2026-09-09 「历史健康记录真实性与浏览修复」).
///
/// A fixed header + date bar over a scrollable card stack. **Every day, today
/// included, reads the persisted `HealthDayRecord`**: the summary cards and
/// the sleep detail share that same record, so the page never mixes a live
/// value of unknown date into a day, and never computes wake time from net
/// sleep. Missing → "—", a recorded 0 stays 0.
struct PiboHistoryView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    @Environment(HealthDataService.self) private var health
    @Environment(BoLedgerStore.self) private var boLedger

    /// Card to scroll to on open (notification deep link). `nil` = top of page.
    var focus: HistoryFocus?

    @State private var selectedDate: Date = Self.initialDate()
    @State private var preparingShare = false
    @State private var shareSnapshot: TodayPiboShareSnapshot?
    @State private var showHealthStatus = false
    @State private var sleepDetailOpen = Self.debugOpensSleepDetail()

    private let cal = Calendar.current
    private static let topAnchor = "history-top"

    /// 截图验证用：`-PiboHistoryDayOffset=1` 直接落在昨天。
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

    /// 截图验证用：`-PiboHistorySleepDetail` 打开所选日期的睡眠详情（模拟器无法合成点击）。
    private static func debugOpensSleepDetail() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PiboHistorySleepDetail")
        #else
        return false
        #endif
    }

    var body: some View {
        // Observe history writes (backfill / reconcile / new food photo) so the
        // selected day refreshes once data lands.
        let _ = history.revision
        let record = history.record(on: selectedDate)
        let day = HistoryDayDisplay.make(date: selectedDate, record: record)

        VStack(spacing: LP.Spacing.s) {
            header
            HistoryDateBar(selectedDate: selectedDate, onSelect: select)
                .padding(.horizontal, LP.Spacing.xl)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: LP.Spacing.s) {
                        Color.clear.frame(height: 0).id(Self.topAnchor)
                        cardsStack(day)
                            // A new day is a new card tree: selections, reveals
                            // and cached geometry never carry across dates.
                            .id(day.date)
                        statusFooter
                    }
                    .padding(.top, LP.Spacing.s)
                    .padding(.bottom, LP.Spacing.xxl)
                }
                .task { await scrollToFocus(using: proxy) }
                .onChange(of: selectedDate) { _, _ in
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
        .padding(.top, LP.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { shareSnapshot != nil },
            set: { if !$0 { shareSnapshot = nil } }
        )) {
            if let shareSnapshot {
                TodayPiboShareSheet(
                    snapshot: shareSnapshot,
                    boFillProgress: boLedger.growthProgress
                )
            }
        }
        .sheet(isPresented: $showHealthStatus) {
            HealthDataStatusSheet()
        }
        .sheet(isPresented: $sleepDetailOpen) {
            // Same record as the summary card above.
            SleepDetailContent(
                detail: day.sleep,
                history: history,
                onClose: { sleepDetailOpen = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x232B3B))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: LP.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("健康记录"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(AppLocalization.format("陪你走过的 %d 天", totalDays))
                    .lpText(LP.Typography.c1Regular)
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
            } else {
                Button {
                    LPHaptics.tap()
                    select(cal.startOfDay(for: .now))
                } label: {
                    Text(AppLocalization.text("今天"))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.accent)
                        .padding(.horizontal, LP.Spacing.l)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(LP.Fill.bgContainer))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("回到今天"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, LP.Spacing.xl)
        // Leave room for `HistoryScreen`'s close button (36pt + margins).
        .padding(.trailing, 64)
    }

    // MARK: Cards

    private func cardsStack(_ day: HistoryDayDisplay) -> some View {
        let workouts = history.workouts(on: day.date)
        let rmssd = HistoryDayDisplay.rmssd(
            day: day.date,
            dailyMedian: StressBaselineStore.dailyMedian(for: day.date),
            latest: store.rmssd,
            latestMeasuredAt: store.rmssdMeasuredAt
        )
        let hasVitals = day.heartRate != nil || day.restingHeartRate != nil
            || rmssd != nil || day.oxygenSaturation != nil
        return VStack(spacing: LP.Spacing.m) {
            HistoryActivityCard(
                kcal: day.activeEnergy.map { Int($0.rounded()) },
                exerciseMinutes: day.exerciseMinutes,
                standHours: day.standHours,
                moveGoal: day.moveGoal,
                exerciseGoal: day.exerciseGoal,
                standGoal: day.standGoal)
            HistoryStepsCard(
                steps: day.steps,
                hourlySteps: day.hourlySteps,
                isToday: day.isToday,
                dayID: day.date)
            HistorySleepCard(
                totalSeconds: day.sleep.total,
                start: day.sleep.start,
                end: day.sleep.end,
                segments: day.sleep.segments,
                onExpand: { sleepDetailOpen = true })
            if !workouts.isEmpty {
                HistoryWorkoutsCard(workouts: workouts)
            }
            if hasVitals {
                HistoryVitalsCard(
                    heartRate: day.heartRate,
                    restingHR: day.restingHeartRate,
                    rmssd: rmssd,
                    rmssdQualifier: rmssdQualifier(rmssd, isToday: day.isToday),
                    oxygen: day.oxygenSaturation)
            } else {
                Text(AppLocalization.text("身体指标 · 当天暂无记录"))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LP.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LP.Fill.bgContainer)
                    )
            }
            // 压力 — today only. 派生分随每分钟心率刷新（HRV 锚点 + 心率调制）。
            if day.isToday, let stress = store.derivedStress {
                HistoryStressCard(stress: stress, rmssd: store.rmssd, baseline: store.stressBaseline)
                    .id(HistoryFocus.stress)
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(HistoryDataStatusText.text(
                authState: health.authState,
                availability: health.dataAvailability
            ))
            Text(AppLocalization.text("“—”表示未收到记录；可在设置中检查健康授权与同步。"))
        }
        .lpText(LP.Typography.c1Regular)
        .foregroundStyle(LP.Content.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.s)
    }

    /// Past days show the day median as-is. Today's reading is judged against
    /// the personal baseline through `StressScore` (the `pibo-core` kernel);
    /// while the baseline is cold-starting the tile says so plainly.
    private func rmssdQualifier(_ rmssd: Double?, isToday: Bool) -> String {
        guard let rmssd else { return "暂无" }
        guard isToday else { return "当日中位数" }
        guard let baseline = store.stressBaseline,
              baseline.dayCount >= StressScore.coldStartDays,
              let score = StressScore.anchor(rmssd: rmssd, baseline: baseline)
        else { return "建立个人参考中" }
        return StressScore.tier(for: score).displayName
    }

    // MARK: - Navigation

    private func select(_ date: Date) {
        let day = HistoryDateNavigation.clamped(date)
        guard day != selectedDate else { return }
        selectedDate = day
    }

    /// Scroll the routed card into view once the page has laid out. The delay
    /// lets the SwiftData-backed cards exist before scrolling to them.
    private func scrollToFocus(using proxy: ScrollViewProxy) async {
        guard let focus else { return }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(focus, anchor: .center)
        }
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
}

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
