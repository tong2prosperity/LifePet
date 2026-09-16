import Foundation
import Testing
@testable import Pibo

struct SleepDetailValuesTests {
    private let wake = Calendar.current.date(
        bySettingHour: 7, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_758_000_000)
    )!

    private func summary(
        total: TimeInterval = 476 * 60,
        segments: [SleepSegmentValue],
        inBed: TimeInterval? = nil,
        latency: TimeInterval? = nil,
        scoped: Bool? = true,
        baselineDelta: TimeInterval? = nil,
        baselineCount: Int? = nil
    ) -> MorningSleepSummary {
        MorningSleepSummary(
            wakeDay: Calendar.current.startOfDay(for: wake),
            generatedAt: wake,
            start: wake.addingTimeInterval(-480 * 60),
            end: wake,
            total: total,
            core: 282 * 60, deep: 84 * 60, rem: 110 * 60, awake: 4 * 60,
            segments: segments,
            hasDetailedStages: !segments.isEmpty,
            hasInBedSignal: inBed != nil,
            hasTerminalAwakeSignal: false,
            awakeningCount: 3,
            continuity: nil,
            baselineDelta: baselineDelta,
            baselineSampleCount: baselineCount,
            overnightHRV: 42,
            sleepingWristTemperature: 34.1,
            sleepingWristTemperatureDelta: nil,
            respiratoryRate: nil,
            oxygenSaturation: 0.96,
            sleepHeartRateAverage: 55,
            sleepHeartRateMin: 48,
            sleepLatency: latency,
            nightSignalsScoped: scoped,
            sleepInBed: inBed
        )
    }

    private func sampleSegments() -> [SleepSegmentValue] {
        let start = wake.addingTimeInterval(-480 * 60)
        func seg(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepSegmentValue {
            SleepSegmentValue(
                start: start.addingTimeInterval(from * 60),
                end: start.addingTimeInterval(to * 60),
                stage: stage
            )
        }
        // 浅睡 282 · 眼动 110 · 深睡 84 · 清醒 4 = 480 recorded minutes.
        return [
            seg(0, 150, .core), seg(150, 234, .deep), seg(234, 238, .awake),
            seg(238, 370, .core), seg(370, 480, .rem),
        ]
    }

    @Test func stagePercentagesUseRecordedPlottedTimeAsTheDenominator() {
        let detail = SleepNightDetail.from(summary: summary(segments: sampleSegments()))
        #expect(detail.recordedStageSeconds == 480 * 60)
        let byStage = Dictionary(uniqueKeysWithValues: detail.stageStats.map { ($0.stage, $0) })
        #expect(abs((byStage[.core]?.percent ?? 0) - 58.75) < 0.001)
        #expect(abs((byStage[.rem]?.percent ?? 0) - 22.9167) < 0.001)
        #expect(abs((byStage[.deep]?.percent ?? 0) - 17.5) < 0.001)
        #expect(abs((byStage[.awake]?.percent ?? 0) - 0.8333) < 0.001)
        #expect(detail.stageStats.map(\.stage) == [.awake, .rem, .core, .deep])
    }

    @Test func gapsAreNotCountedInTheDenominator() {
        let start = wake.addingTimeInterval(-480 * 60)
        let segments = [
            SleepSegmentValue(start: start, end: start.addingTimeInterval(3_600), stage: .core),
            SleepSegmentValue(
                start: start.addingTimeInterval(3 * 3_600),
                end: start.addingTimeInterval(4 * 3_600),
                stage: .deep
            ),
        ]
        let detail = SleepNightDetail.from(summary: summary(segments: segments))
        #expect(detail.recordedStageSeconds == 2 * 3_600)
        #expect(detail.stageStats.first { $0.stage == .deep }?.percent == 50)
    }

    @Test func noStagesMeansNoStageStatsAndNoFabrication() {
        let detail = SleepNightDetail.from(summary: summary(segments: []))
        #expect(!detail.hasStages)
        #expect(detail.stageStats.isEmpty)
        #expect(detail.recordedAwakeIntervals == nil)
        #expect(detail.total == 476 * 60)
    }

    @Test func explicitZeroIsNotMissing() {
        let zero = SleepNightDetail.from(summary: summary(segments: [], latency: 0))
        #expect(zero.plausibleLatency == 0)
        #expect(SleepDetailFormat.duration(zero.plausibleLatency) == "0 分钟")
        let missing = SleepNightDetail.from(summary: summary(segments: [], latency: nil))
        #expect(missing.plausibleLatency == nil)
        #expect(SleepDetailFormat.duration(missing.plausibleLatency) == "—")
        #expect(SleepDetailFormat.duration(12 * 60) == "12 分钟")
        #expect(SleepDetailFormat.duration(492 * 60) == "8 小时 12 分")
    }

    @Test func inBedShorterThanSleepReadsAsMissing() {
        let tiny = SleepNightDetail.from(summary: summary(segments: [], inBed: 20))
        #expect(tiny.plausibleInBed == nil)
        let plausible = SleepNightDetail.from(summary: summary(segments: [], inBed: 492 * 60))
        #expect(plausible.plausibleInBed.map { abs($0 - 29_520) < 0.001 } == true)
        let zero = SleepNightDetail.from(summary: summary(segments: [], inBed: 0))
        #expect(zero.plausibleInBed == nil)
    }

    @Test func legacyUnscopedSummaryShowsNightBodyAsUnrecorded() {
        let legacy = SleepNightDetail.from(summary: summary(segments: [], scoped: nil))
        #expect(legacy.nightValue(legacy.sleepHeartRateAverage) == nil)
        #expect(legacy.nightValue(legacy.overnightHRVSDNN) == nil)
        let scoped = SleepNightDetail.from(summary: summary(segments: []))
        #expect(scoped.nightValue(scoped.sleepHeartRateAverage) == 55)
        #expect(scoped.nightValue(0) == nil)
    }

    @Test func legacyArchivedJSONWithoutNewKeysStillDecodes() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(summary(segments: []))) as? [String: Any]
        )
        object.removeValue(forKey: "nightSignalsScoped")
        object.removeValue(forKey: "sleepInBed")
        object.removeValue(forKey: "providerAwakeningCount")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MorningSleepSummary.self, from: data)
        #expect(decoded.nightSignalsScoped == nil)
        #expect(SleepNightDetail.from(summary: decoded).nightSignalsScoped == false)
    }

    @Test func historyDayNeverBorrowsABaselineOrComputesWakeTime() {
        let record = HealthDayRecord(date: Calendar.current.startOfDay(for: wake))
        record.sleepTotal = 6 * 3_600
        record.sleepStart = wake.addingTimeInterval(-7 * 3_600)
        record.sleepEnd = nil
        let detail = SleepNightDetail.from(record: record)
        #expect(detail.baselineDelta == nil)
        #expect(detail.baselineSampleCount == nil)
        #expect(detail.end == nil)
        #expect(SleepDetailFormat.baseline(delta: detail.baselineDelta, sampleCount: nil).isEmpty)
        // Provider wake counts do not exist in HealthKit; a local count is not promoted.
        record.sleepAwakeningCount = 4
        #expect(SleepNightDetail.from(record: record).providerAwakeningCount == nil)
    }

    @Test func morningSummaryCarriesItsOwnBaseline() {
        let detail = SleepNightDetail.from(summary: summary(
            segments: [], baselineDelta: 24 * 60, baselineCount: 8
        ))
        #expect(SleepDetailFormat.baseline(delta: detail.baselineDelta, sampleCount: detail.baselineSampleCount)
            == "个人常态 +24分 · 基于 8 晚")
    }

    @Test func trendKeepsMissingDatesAsEmptySlots() {
        let detail = SleepNightDetail.from(summary: summary(segments: []))
        let calendar = Calendar.current
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: detail.wakeDay)!
        let days = detail.trendDays { date in
            date == twoDaysAgo ? 7 * 3_600 : nil
        }
        #expect(days.count == 7)
        #expect(days.last?.date == detail.wakeDay)
        #expect(days.last?.seconds == detail.total)
        #expect(days.filter { $0.seconds != nil }.count == 2)
        #expect(days[4].seconds.map { abs($0 - 25_200) < 0.001 } == true)
        #expect(days[5].seconds == nil)
    }

    @Test func weeklyReportComesFromCoreAndKeepsRealDates() {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: wake)
        let nights = (1...3).map { offset -> SleepWeeklyReport.Night in
            let date = calendar.date(byAdding: .day, value: -offset, to: end)!
            return .init(date: date, total: 7 * 3_600)
        }
        let report = SleepWeeklyReport.report(
            records: nights,
            endDay: end,
            live: .init(total: 6 * 3_600, deep: 0, rem: 0, awake: 0, start: nil, end: nil)
        )
        #expect(report.trend.count == 7)
        #expect(report.trend.map(\.hasData) == [false, false, false, true, true, true, true])
        #expect(report.nightsWithData == 4)
        #expect(!report.suggestions.isEmpty)
    }
}
