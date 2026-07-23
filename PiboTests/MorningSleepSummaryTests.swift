import Foundation
import Testing
@testable import Pibo

@Test func sleepTimelineUsesOneUncompressedTimeScale() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(8 * 3_600)
    let segment = SleepSegmentValue(
        start: start.addingTimeInterval(2 * 3_600),
        end: start.addingTimeInterval(4 * 3_600),
        stage: .deep)

    let x = SleepTimelineGeometry.midpointX(
        segment: segment,
        nightStart: start,
        nightEnd: end,
        width: 320)
    let width = SleepTimelineGeometry.cloudWidth(
        duration: segment.duration,
        nightStart: start,
        nightEnd: end,
        width: 320)

    #expect(abs(x - 120) < 0.001)
    #expect(abs(width - 80) < 0.001)
}

@Test func sleepTimelineKeepsBriefIntervalsVisibleWithoutMovingTheirMidpoint() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(8 * 3_600)
    let segment = SleepSegmentValue(
        start: start.addingTimeInterval(4 * 3_600),
        end: start.addingTimeInterval(4 * 3_600 + 2 * 60),
        stage: .awake)

    let x = SleepTimelineGeometry.midpointX(
        segment: segment,
        nightStart: start,
        nightEnd: end,
        width: 320)
    let expectedX = CGFloat(320) * CGFloat(4 * 3_600 + 60) / CGFloat(8 * 3_600)
    let width = SleepTimelineGeometry.cloudWidth(
        duration: segment.duration,
        nightStart: start,
        nightEnd: end,
        width: 320)

    #expect(abs(x - expectedX) < 0.001)
    #expect(width == SleepTimelineGeometry.minimumCloudWidth)
}

@Test func morningSleepBuilderCalculatesContinuityAndAwakenings() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3_600) }
    let source = "watch"
    let samples: [MorningSleepSampleValue] = [
        .init(start: at(-0.25), end: at(8.2), stage: nil, sourceID: source,
              sourceHasDetailedStages: true, isInBed: true),
        .init(start: at(0), end: at(2), stage: .core, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(2), end: at(3), stage: .deep, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(3), end: at(3 + 10.0 / 60), stage: .awake, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(3 + 10.0 / 60), end: at(6), stage: .core, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(6), end: at(8), stage: .rem, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(8), end: at(8.2), stage: .awake, sourceID: source,
              sourceHasDetailedStages: true, isInBed: false),
    ]

    let session = MorningSleepSessionBuilder.latestSession(from: samples)
    #expect(session != nil)
    #expect(session?.awakeningCount == 1)
    #expect(session?.hasInBedSignal == true)
    #expect(session?.hasTerminalAwakeSignal == true)
    #expect(abs((session?.awake ?? 0) - 10 * 60) < 1)
    #expect(abs((session?.continuity ?? 0) - (470.0 / 480.0)) < 0.0001)
}

@Test func morningSleepBuilderPrefersCompleteDetailedSource() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3_600) }
    let samples: [MorningSleepSampleValue] = [
        .init(start: at(0), end: at(8), stage: .core, sourceID: "legacy",
              sourceHasDetailedStages: false, isInBed: false),
        .init(start: at(0.5), end: at(3), stage: .core, sourceID: "watch",
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(3), end: at(4.5), stage: .deep, sourceID: "watch",
              sourceHasDetailedStages: true, isInBed: false),
        .init(start: at(4.5), end: at(7.5), stage: .rem, sourceID: "watch",
              sourceHasDetailedStages: true, isInBed: false),
    ]

    let session = MorningSleepSessionBuilder.latestSession(from: samples)
    #expect(session?.hasDetailedStages == true)
    #expect(abs((session?.total ?? 0) - 7 * 3_600) < 1)
    #expect(abs((session?.deep ?? 0) - 1.5 * 3_600) < 1)
}

@Test func morningSleepBuilderRejectsTinyDetailedFragmentInFavorOfFullLegacyNight() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3_600) }
    let samples: [MorningSleepSampleValue] = [
        .init(start: at(0), end: at(8), stage: .core, sourceID: "legacy",
              sourceHasDetailedStages: false, isInBed: false),
        .init(start: at(7), end: at(7.5), stage: .rem, sourceID: "watch",
              sourceHasDetailedStages: true, isInBed: false),
    ]

    let session = MorningSleepSessionBuilder.latestSession(from: samples)
    #expect(session?.hasDetailedStages == false)
    #expect(abs((session?.total ?? 0) - 8 * 3_600) < 1)
}
