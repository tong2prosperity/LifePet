import PiboCore
import SwiftUI

// Decision 062: the readout of the badge Pibo wears, as the observation report Pibo writes
// about you (and copies into its letters home). Every value is Core's: the score, the band,
// sleep sufficiency, load and the reasons; this only lays them out on paper. It never reads
// raw health numbers.
//
// Ported from HarmonyPibo `pixel/ui/ReadoutReport.ets`.

/// One column of the week: the day, its score and band, and whether it is today.
struct ReadoutReportDay: Identifiable, Equatable {
    var date: Date
    var score: Double?
    var band: Int32?
    var today: Bool
    var id: Date { date }
}

/// Lit squares per bar and segments of the gauge.
private let reportBarBlocks = 10
private let reportBlockHeight: CGFloat = 5

private func reportBandColor(_ band: Int32?) -> Color {
    guard let band, let value = PiboCoreWellnessReadinessBand(rawValue: band) else {
        return PixelUIColor.sleep
    }
    switch value {
    case .significantlyBelow: return PixelUIColor.warn
    case .belowPersonalNormal: return PixelUIColor.gold
    case .personalNormal: return PixelUIColor.leafLight
    case .ample: return PixelUIColor.leaf
    case .unavailable: return PixelUIColor.sleep
    }
}

/// The torn edge of the paper strip, top or bottom: 24 teeth, every other one shorter.
private struct TornEdge: View {
    /// Teeth hang down from the strip's top edge (the bottom edge of the paper).
    var down: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { index in
                Rectangle()
                    .fill(PixelUIColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: index % 2 == 0 ? 6 : 3)
                    .frame(maxHeight: .infinity, alignment: down ? .top : .bottom)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The dotted rule between sections.
private struct ReportRule: View {
    var body: some View {
        HStack {
            ForEach(0..<20, id: \.self) { _ in
                Rectangle()
                    .fill(PixelUIColor.inkSoft.opacity(0.5))
                    .frame(width: 6, height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct ReadoutReport: View {
    var record: HealthDayRecord?
    var historyRecords: [HealthDayRecord] = []
    var availability: HealthDataService.DataAvailability = .available(lastCheckedAt: .now)
    var usesMock = false
    /// 相处天数 (`PetStateStore.dayCount`): the report's "地球第 N 天".
    var dayCount = 1
    /// The Core state Pibo shows (`PiboPixelActivity`), the colour of the lens.
    var badgeState = 0
    var badgeCracked = false
    var maxBodyHeight: CGFloat = 420
    /// The footprints' copy of a past day (决定 063): midnight of that day, nil for today.
    var anchorDay: Date?
    var onClose: () -> Void = {}
    var onCheckHealth: () -> Void = {}

    private var snapshot: DailyWellnessSnapshot? { WellnessReadout.snapshot(of: record) }
    private var score: Double? { WellnessReadout.readyScore(snapshot, availability: availability) }

    private var today: Date {
        Calendar.current.startOfDay(for: anchorDay ?? Date())
    }

    /// Seven columns, oldest first, missing days left empty.
    private var days: [ReadoutReportDay] {
        let calendar = Calendar.current
        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let record = historyRecords.first { calendar.isDate($0.date, inSameDayAs: date) }
            let snapshot = WellnessReadout.snapshot(of: record)
            return ReadoutReportDay(date: date,
                                    score: snapshot?.readinessScore?.value,
                                    band: snapshot?.readinessBand,
                                    today: offset == 0)
        }
    }

    private var stampText: String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: today)).\(calendar.component(.day, from: today))"
    }

    private var daysAccessibilityText: String {
        let calendar = Calendar.current
        return days.map { day in
            let month = calendar.component(.month, from: day.date)
            let date = calendar.component(.day, from: day.date)
            return "\(month)月\(date)日\(day.score.map { "\(Int($0.rounded()))分" } ?? "无数据")"
        }
        .joined(separator: "，")
    }

    var body: some View {
        VStack(spacing: 0) {
            TornEdge(down: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    head
                    if score != nil { available } else { unavailable }
                    ReportRule()
                    week
                    fieldNote
                    Text(AppLocalization.text(anchorDay != nil
                        ? "— 这是 Pibo 抄回家的那一份 —"
                        : "— Pibo 会抄一份寄回家 —"))
                        .font(PixelFont.font(12))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: maxBodyHeight)
            .background(PixelUIColor.paper)
            .overlay {
                Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2)
            }
            TornEdge(down: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Head

    private var head: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                bigBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.text("读数徽章"))
                        .font(PixelFont.font(18))
                        .foregroundStyle(PixelUIColor.ink)
                        .accessibilityIdentifier("status-observer-heading")
                    Text(AppLocalization.format("观测报告 · 地球第 %@ 天", "\(max(1, dayCount))"))
                        .font(PixelFont.font(12))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The postmark: today's date, stamped a little crooked.
                Text(stampText)
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.warn)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay {
                        Rectangle().strokeBorder(
                            PixelUIColor.warn,
                            style: StrokeStyle(lineWidth: 2, dash: [3, 2])
                        )
                    }
                    .rotationEffect(.degrees(-8))
                    .accessibilityHidden(true)

                Text("×")
                    .font(PixelFont.font(20))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(width: 44, height: 44)
                    .background(PixelUIColor.paperDim)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel(AppLocalization.text("关闭读数徽章"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("status-observer-close")
            }
            .frame(maxWidth: .infinity)

            if usesMock {
                Text(AppLocalization.text("示例数据 · 不代表你的健康状态"))
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                    .background(PixelUIColor.gold)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            }
        }
    }

    private var bigBadge: some View {
        ZStack {
            PixelCanvas(logicalWidth: 7, logicalHeight: 7,
                        revision: badgeState * 4 + (badgeCracked ? 2 : 0) + (score == nil ? 1 : 0)) { frame in
                drawPiboPixelBadgeAt(frame, 1, 1,
                                     score == nil ? .dataUnknown : piboPixelBadgeFor(badgeState),
                                     badgeCracked, true)
            }
            .frame(width: 42, height: 42)
            if score == nil {
                Text("?")
                    .font(PixelFont.font(14))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    // MARK: Readings

    private var available: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.text(WellnessReadout.conclusion(snapshot, availability: availability)))
                .font(PixelFont.font(18))
                .foregroundStyle(PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text("\(Int((score ?? 0).rounded()))")
                        .font(PixelFont.font(36))
                        .foregroundStyle(PixelUIColor.ink)
                    Text("/100")
                        .font(PixelFont.font(12))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .padding(.bottom, 6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.text(WellnessReadout.bandLabel(snapshot?.readinessBand)))
                        .font(PixelFont.font(12))
                        .foregroundStyle(PixelUIColor.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(reportBandColor(snapshot?.readinessBand))
                        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    PixelBar(fraction: (score ?? 0) / 100, segments: reportBarBlocks,
                             color: reportBandColor(snapshot?.readinessBand), barHeight: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format(
                "今日准备度，%@ 分，%@",
                "\(Int((score ?? 0).rounded()))",
                AppLocalization.text(WellnessReadout.bandLabel(snapshot?.readinessBand))
            ))

            ReportRule()

            reading(icon: PixelIcons.moon, label: "睡眠充足度",
                    value: WellnessReadout.sleepSufficiencyLabel(snapshot),
                    fraction: (snapshot?.readinessSleepSufficiency ?? 0) / 100,
                    color: PixelUIColor.sleep,
                    showBar: snapshot?.readinessSleepSufficiency != nil)
            reading(icon: PixelIcons.flame, label: "近期身体负荷",
                    value: WellnessReadout.loadLabel(snapshot),
                    fraction: 0, color: PixelUIColor.activity, showBar: false)
        }
    }

    private func reading(icon: [String], label: String, value: String, fraction: Double,
                         color: Color, showBar: Bool) -> some View {
        HStack(spacing: 8) {
            PixelIcon(rows: icon, iconSize: 16)
            Text(AppLocalization.text(label))
                .font(PixelFont.font(12))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(width: 92, alignment: .leading)
            if showBar {
                PixelBar(fraction: fraction, segments: 10, color: color, barHeight: 10)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            Text(AppLocalization.text(value))
                .font(PixelFont.font(12))
                .foregroundStyle(PixelUIColor.ink)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AppLocalization.text(label)) \(AppLocalization.text(value))")
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.text(
                WellnessReadout.unavailableTitle(snapshot, availability: availability)))
                .font(PixelFont.font(18))
                .foregroundStyle(PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppLocalization.text(
                WellnessReadout.unavailableDetail(snapshot, availability: availability)))
                .font(.system(size: 13))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)

            if availability.hasReliableData, (snapshot?.readinessRequiredCalibrationDays ?? 0) > 0 {
                let required = snapshot?.readinessRequiredCalibrationDays ?? 7
                PixelBar(fraction: Double(snapshot?.readinessCalibrationDays ?? 0) / Double(required),
                         segments: Int(required), color: PixelUIColor.sleep, barHeight: 12)
                    .accessibilityHidden(true)
            }
            if !availability.hasReliableData {
                PixelButton(label: AppLocalization.text("查看"),
                            buttonID: "status-observer-check-health",
                            onTap: onCheckHealth)
            }
        }
    }

    // MARK: Week

    private var week: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.text("最近 7 天"))
                .font(PixelFont.font(12))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    VStack(spacing: 1) {
                        if day.today {
                            PixelCanvas(logicalWidth: 32, logicalHeight: 40,
                                        revision: badgeState + (badgeCracked ? 16 : 0)) { frame in
                                let pose = PiboPixelPose()
                                pose.bodyStage = 0
                                pose.leafGrowth = 0.6
                                pose.badge = piboPixelBadgeFor(badgeState)
                                pose.badgeCracked = badgeCracked
                                pose.badgeLit = true
                                drawPiboPixel(frame, 16, 39, pose)
                            }
                            .frame(width: 32, height: 40)
                        }
                        if let score = day.score {
                            // Ten blocks, lit from the bottom by the day's band.
                            VStack(spacing: 1) {
                                ForEach(Array((0..<reportBarBlocks).reversed()), id: \.self) { block in
                                    Rectangle()
                                        .fill(block < max(1, Int((score / 10).rounded()))
                                              ? reportBandColor(day.band)
                                              : Color.clear)
                                        .frame(height: reportBlockHeight)
                                }
                            }
                        } else {
                            Rectangle()
                                .strokeBorder(PixelUIColor.inkSoft,
                                              style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(height: reportBlockHeight * 2)
                        }
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .font(PixelFont.font(12))
                            .foregroundStyle(day.today ? PixelUIColor.ink : PixelUIColor.inkSoft)
                            .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: CGFloat(reportBarBlocks) * (reportBlockHeight + 1) + 64,
                   alignment: .bottom)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format(
            "最近七日准备度，%@。缺失日期保持空缺。", daysAccessibilityText))
    }

    // MARK: Field note

    private var fieldNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(PixelUIColor.warn)
                    .frame(width: 8, height: 8)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                Text(AppLocalization.text("主要依据"))
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let primary = WellnessReadout.reasonLabel(snapshot?.readinessPrimaryReason)
            if !primary.isEmpty {
                Text("· \(AppLocalization.text(primary))")
                    .font(.system(size: 13))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let secondary = WellnessReadout.reasonLabel(snapshot?.readinessSecondaryReason)
            if snapshot?.readinessSecondaryReason != snapshot?.readinessPrimaryReason,
               !secondary.isEmpty {
                Text("· \(AppLocalization.text(secondary))")
                    .font(.system(size: 13))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("\(AppLocalization.text(WellnessReadout.updatedLabel(snapshot))) · \(AppLocalization.text("只比较你的个人记录"))")
                .font(.system(size: 11))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(pixelHex: 0xFFF3C4))
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .rotationEffect(.degrees(0.8))
    }
}

// MARK: - Host

/// The strip prints out of the badge: a receipt printer moves in steps, not a glide.
/// Reduce Motion skips the print and shows it at once.
struct StatusObserverReportHost: View {
    var record: HealthDayRecord?
    var historyRecords: [HealthDayRecord] = []
    var availability: HealthDataService.DataAvailability = .available(lastCheckedAt: .now)
    var usesMock = false
    var dayCount = 1
    var badgeState = 0
    var badgeCracked = false
    var panelTop: CGFloat = 72
    var stageWidth: CGFloat = 393
    var stageHeight: CGFloat = 760
    var bottomInset: CGFloat = 0
    var onClose: () -> Void = {}
    var onCheckHealth: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 hidden above the badge, 1 fully printed. Advances in eight equal jumps.
    @State private var progress: CGFloat = 0

    private var width: CGFloat { min(420, stageWidth - 32) }

    private var bodyMaxHeight: CGFloat {
        max(200, min(stageHeight * 0.72, stageHeight - panelTop - bottomInset - 28))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            ReadoutReport(record: record,
                          historyRecords: historyRecords,
                          availability: availability,
                          usesMock: usesMock,
                          dayCount: dayCount,
                          badgeState: badgeState,
                          badgeCracked: badgeCracked,
                          maxBodyHeight: bodyMaxHeight,
                          onClose: onClose,
                          onCheckHealth: onCheckHealth)
                .frame(width: width)
                .clipShape(Rectangle())
                .background(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(Color(pixelHex: 0x2E3B45).opacity(0.35))
                        .offset(x: 3, y: 3)
                }
                .offset(y: panelTop - (1 - progress) * stageHeight)
        }
        .onAppear(perform: printOut)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("status-observer-report")
    }

    /// A receipt printer moves in steps, not a glide.
    private func printOut() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        Task { @MainActor in
            for step in 1...8 {
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(.linear(duration: 0.05)) {
                    progress = CGFloat(step) / 8
                }
            }
        }
    }
}
