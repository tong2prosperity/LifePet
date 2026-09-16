import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Pibo

/// Pins the continuous cloud trail to recorded time: exact color splits, no
/// minimum width, gaps and overlaps never bridged, hit-testing by interval.
struct SleepCloudTrailGeometryTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func at(minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func segment(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepSegmentValue {
        SleepSegmentValue(start: at(minutes: from), end: at(minutes: to), stage: stage)
    }

    @Test func colorSlicesSplitExactlyAtRecordedTimes() throws {
        let segments = [
            segment(0, 120, .core),
            segment(120, 240, .deep),
            segment(240, 360, .rem),
            segment(360, 480, .core),
        ]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let runs = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 320)

        #expect(runs.count == 1)
        let slices = try #require(runs.first?.slices)
        #expect(slices.map(\.stage) == [.core, .deep, .rem, .core])
        #expect(slices.map(\.x) == [0, 80, 160, 240])
        #expect(slices.allSatisfy { abs($0.width - 80) < 0.0001 })
        #expect(runs[0].left == 0)
        #expect(abs(runs[0].right - 320) < 0.0001)
    }

    @Test func threeMinuteAwakeningKeepsItsProportionalWidth() throws {
        let segments = [
            segment(0, 240, .core),
            segment(240, 243, .awake),
            segment(243, 480, .core),
        ]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let runs = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 320)
        let awake = try #require(runs.first?.slices.first { $0.stage == .awake })

        // 3 of 480 minutes on 320pt → 2pt. No 34pt floor, no enlargement.
        #expect(abs(awake.width - 2) < 0.0001)
        #expect(abs(awake.x - 160) < 0.0001)
        // An awake seam contributes no contour spike point of its own.
        #expect(runs[0].points.count == 3)
    }

    @Test func unrecordedGapBreaksTheContour() throws {
        let segments = [
            segment(0, 120, .core),
            segment(180, 300, .deep),
        ]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let runs = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 300)

        #expect(runs.count == 2)
        #expect(abs(runs[0].right - 120) < 0.0001)
        #expect(abs(runs[1].left - 180) < 0.0001)
        // Nothing is drawn across the gap.
        let covered = runs.flatMap(\.slices).reduce(CGFloat(0)) { $0 + $1.width }
        #expect(abs(covered - 240) < 0.0001)
    }

    @Test func overlappingInputsBecomeSeparateContours() throws {
        let segments = [
            segment(0, 120, .core),
            segment(60, 180, .rem),
        ]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let runs = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 180)

        #expect(runs.count == 2)
        #expect(runs[0].slices.map(\.stage) == [.core])
        #expect(runs[1].slices.map(\.stage) == [.rem])
    }

    @Test func invalidIntervalsAreDroppedAndNoStagesMeansNoTimeline() {
        let invalid = [
            SleepSegmentValue(start: at(minutes: 10), end: at(minutes: 10), stage: .core),
            SleepSegmentValue(start: at(minutes: 20), end: at(minutes: 5), stage: .deep),
        ]
        var unknown = SleepSegmentValue(start: at(minutes: 0), end: at(minutes: 30), stage: .core)
        unknown.stageRaw = 9
        #expect(SleepTrailGeometry.validSegments(invalid + [unknown]).isEmpty)
        #expect(SleepTrailGeometry.timeline(
            segments: [],
            fallbackStart: at(minutes: 0),
            fallbackEnd: at(minutes: 480)
        ) == nil)
    }

    @Test func timelineWidensToFallAsleepAndWakeTimesButNeverShrinks() throws {
        let segments = [segment(30, 450, .core)]
        let widened = try #require(SleepTrailGeometry.timeline(
            segments: segments,
            fallbackStart: at(minutes: 0),
            fallbackEnd: at(minutes: 480)
        ))
        #expect(widened.start == at(minutes: 0))
        #expect(widened.end == at(minutes: 480))

        let unaffected = try #require(SleepTrailGeometry.timeline(
            segments: segments,
            fallbackStart: at(minutes: 60),
            fallbackEnd: at(minutes: 400)
        ))
        #expect(unaffected.start == at(minutes: 30))
        #expect(unaffected.end == at(minutes: 450))
    }

    @Test func tapSelectsTheContainingIntervalAndGapsPickNearestBoundary() throws {
        let segments = [
            segment(0, 100, .core),
            segment(100, 103, .awake),
            segment(103, 200, .deep),
            segment(300, 400, .rem),
        ]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let width: CGFloat = 400

        // x == minute on this 400-minute, 400pt axis.
        #expect(SleepTrailGeometry.segment(atX: 101.5, width: width, segments: segments, timeline: timeline)?.stage == .awake)
        #expect(SleepTrailGeometry.segment(atX: 150, width: width, segments: segments, timeline: timeline)?.stage == .deep)
        // Inside the 200–300 gap: nearer the deep end at 200…
        #expect(SleepTrailGeometry.segment(atX: 220, width: width, segments: segments, timeline: timeline)?.stage == .deep)
        // …and nearer the REM start at 300.
        #expect(SleepTrailGeometry.segment(atX: 290, width: width, segments: segments, timeline: timeline)?.stage == .rem)
        // A nearby-midpoint rule would have picked the long deep block here.
        #expect(SleepTrailGeometry.segment(atX: 102.9, width: width, segments: segments, timeline: timeline)?.stage == .awake)
    }

    @Test func voiceOverStepsThroughEveryInterval() {
        let segments = [segment(0, 60, .core), segment(60, 62, .awake), segment(62, 120, .rem)]
        let first = SleepTrailGeometry.adjacent(to: nil, offset: 1, segments: segments)
        #expect(first?.stage == .core)
        let second = SleepTrailGeometry.adjacent(to: first, offset: 1, segments: segments)
        #expect(second?.stage == .awake)
        let third = SleepTrailGeometry.adjacent(to: second, offset: 1, segments: segments)
        #expect(third?.stage == .rem)
        #expect(SleepTrailGeometry.adjacent(to: third, offset: 1, segments: segments) == third)
    }

    @Test func hourTicksAreLocalWholeHoursClearOfTheEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 15, hour: 23, minute: 10
        )))
        let end = start.addingTimeInterval(8 * 3_600)
        let ticks = SleepTrailGeometry.hourTicks(
            timeline: SleepTrailTimeline(start: start, end: end),
            width: 320,
            calendar: calendar
        )
        #expect(!ticks.isEmpty)
        for tick in ticks {
            let parts = calendar.dateComponents([.minute, .second], from: tick)
            #expect(parts.minute == 0 && parts.second == 0)
            let x = SleepTrailTimeline(start: start, end: end).x(of: tick, width: 320)
            #expect(x >= 60 && 320 - x >= 60)
        }
    }

    @Test func contourStaysInsideItsRunAndMiniTrailScalesHeight() throws {
        let segments = [segment(0, 200, .core), segment(200, 260, .deep), segment(260, 400, .rem)]
        let timeline = try #require(SleepTrailGeometry.timeline(segments: segments))
        let full = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 300)
        let mini = SleepTrailGeometry.runs(segments: segments, timeline: timeline, width: 300, heightScale: 0.3)
        let fullPath = SleepTrailGeometry.path(for: full[0], center: 100)
        let bounds = fullPath.boundingRect
        #expect(bounds.minX >= full[0].left - 0.001)
        #expect(bounds.maxX <= full[0].right + 0.001)
        let miniBounds = SleepTrailGeometry.path(for: mini[0], center: 13).boundingRect
        #expect(miniBounds.height < bounds.height * 0.5)
        // Mini scaling never changes horizontal slices.
        #expect(mini[0].slices == full[0].slices)
    }
}
