import Foundation

/// One completed sleep session attributed to the local calendar day on which
/// the user woke. This is the transport shared by HealthKit ingestion, the
/// background notification path, and the one-shot morning sheet.
struct MorningSleepSummary: Codable, Equatable, Identifiable, Sendable {
    var id: Date { wakeDay }

    let wakeDay: Date
    let generatedAt: Date
    let start: Date
    let end: Date

    let total: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval
    let segments: [SleepSegmentValue]

    let hasDetailedStages: Bool
    let hasInBedSignal: Bool
    let hasTerminalAwakeSignal: Bool
    let awakeningCount: Int?
    let continuity: Double?

    var baselineDelta: TimeInterval?
    /// Number of prior settled nights available to the personal baseline.
    /// Optional/defaulted so pre-v3 persisted summaries remain decodable and
    /// existing construction sites can adopt the metadata incrementally.
    var baselineSampleCount: Int? = nil
    let overnightHRV: Double?
    let sleepingWristTemperature: Double?
    let sleepingWristTemperatureDelta: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?
    // Added 2026-07-17. Optional so an older persisted JSON (which lacks these
    // keys) still decodes — a non-optional field would fail the whole decode and
    // silently drop the morning card on cold launch.
    let sleepHeartRateAverage: Double?
    let sleepHeartRateMin: Double?
    /// Estimated time from getting into bed to falling asleep. Best-effort: only
    /// present when an in-bed envelope exists and the value is in a sane range;
    /// otherwise nil (shown as a placeholder). See the builder's guardrails.
    let sleepLatency: TimeInterval?
    /// Added 2026-09-16 (all optional, so older archives still decode).
    /// `true` only when the body fields above were queried inside this
    /// session's sleep window. A cached summary without the flag shows its
    /// night body records as 未记录 instead of risking daytime values.
    var nightSignalsScoped: Bool? = nil
    /// Longest in-bed envelope overlapping the session, physically bounded.
    var sleepInBed: TimeInterval? = nil
    /// Wake count reported by the provider. HealthKit exposes none, so this
    /// stays nil on iOS; `awakeningCount` above is a local inference.
    var providerAwakeningCount: Int? = nil

    /// Avoid turning a short incidental sample into the once-a-day morning
    /// experience, and never treat a still-growing session as a finished night.
    /// Duration decides eligibility; quiet time (or a demonstrably awake user)
    /// decides finality. All thresholds live in `pibo-core`.
    func readiness(
        now: Date = .now,
        userIsInteracting: Bool
    ) -> PiboCoreSleepAdapter.Readiness {
        PiboCoreSleepAdapter.morningReadiness(
            totalSeconds: total,
            hasInBedSignal: hasInBedSignal,
            hasTerminalAwakeSignal: hasTerminalAwakeSignal,
            secondsSinceSessionEnd: now.timeIntervalSince(end),
            userIsInteracting: userIsInteracting
        )
    }

    /// The earliest moment this session could be considered finished. Used to
    /// time a background notification and a foreground re-check.
    var settledAt: Date {
        end.addingTimeInterval(
            PiboCoreSleepAdapter.morningSettleSeconds(
                hasTerminalAwakeSignal: hasTerminalAwakeSignal
            )
        )
    }

    /// Whether this summary is still worth surfacing. Replaces a strict
    /// "must be today" rule so a notification tapped after midnight resolves.
    func isWithinCatchupWindow(now: Date = .now) -> Bool {
        PiboCoreSleepAdapter.morningWithinCatchupWindow(
            secondsSinceWakeDayStart: now.timeIntervalSince(wakeDay)
        )
    }

    /// True once the wake-day is no longer the current calendar day — the card
    /// then reads as a dated retrospective rather than "last night".
    func isCatchUp(now: Date = .now) -> Bool {
        !Calendar.current.isDate(wakeDay, inSameDayAs: now)
    }

    var wakeDayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: wakeDay)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    var notificationIdentifier: String { "pibo.sleep.\(wakeDayKey)" }
}

/// Copy owned by the future narrative pass. Keeping every Pibo-authored line
/// here lets product replace the placeholders without touching delivery,
/// routing, persistence, or card layout.
///
/// Product note: the sleep surface intentionally uses a **calm, neutral** voice
/// — NOT Pibo's tsundere/garbled register. Swap these strings freely; keep the
/// tone plain.
enum MorningSleepCopy {
    /// Deliberately free of any time reference: the same notification serves a
    /// morning riser, a night-shift worker waking mid-afternoon, and a summary
    /// deferred out of the quiet band.
    static let notificationTitle = "睡眠记录整理好了"
    static let notificationBody = "点开看看这一觉睡了多久，深睡、眼动和清醒的分布。"
    static let cardPiboLine = "昨晚的睡眠记录在这里。"
    /// Shown instead of `cardPiboLine` when the card is opened on a later day.
    static let cardPiboCatchUpLine = "这是那天的睡眠记录。"
}

#if DEBUG
extension MorningSleepSummary {
    static func debugFixture(now: Date = .now) -> MorningSleepSummary {
        let calendar = Calendar.current
        var end = calendar.date(bySettingHour: 9, minute: 32, second: 0, of: now) ?? now
        if end > now { end = calendar.date(byAdding: .day, value: -1, to: end) ?? now }
        let start = end.addingTimeInterval(-398 * 60)
        var cursor = start
        let plan: [(SleepStage, Int)] = [
            (.core, 36), (.deep, 22), (.core, 42), (.rem, 18),
            (.core, 31), (.deep, 19), (.core, 50), (.awake, 3),
            (.rem, 31), (.core, 38), (.rem, 34), (.core, 28),
            (.awake, 5), (.rem, 41),
        ]
        let segments = plan.map { stage, minutes in
            let segmentEnd = cursor.addingTimeInterval(TimeInterval(minutes * 60))
            defer { cursor = segmentEnd }
            return SleepSegmentValue(start: cursor, end: segmentEnd, stage: stage)
        }
        return MorningSleepSummary(
            wakeDay: calendar.startOfDay(for: end),
            generatedAt: now,
            start: start,
            end: end,
            total: 390 * 60,
            core: 225 * 60,
            deep: 41 * 60,
            rem: 124 * 60,
            awake: 8 * 60,
            segments: segments,
            hasDetailedStages: true,
            hasInBedSignal: true,
            hasTerminalAwakeSignal: true,
            awakeningCount: 2,
            continuity: 0.93,
            baselineDelta: 24 * 60,
            baselineSampleCount: 8,
            overnightHRV: 46,
            sleepingWristTemperature: 33.2,
            sleepingWristTemperatureDelta: 0.2,
            respiratoryRate: 14.2,
            oxygenSaturation: nil,
            sleepHeartRateAverage: 57,
            sleepHeartRateMin: 49,
            sleepLatency: 12 * 60,
            nightSignalsScoped: true,
            sleepInBed: 412 * 60
        )
    }
}
#endif

/// Pure input used by the session builder. HealthKit samples are mapped into
/// this value first so session selection and calculations remain testable
/// without a device or HealthKit store.
struct MorningSleepSampleValue: Sendable {
    let start: Date
    let end: Date
    let stage: SleepStage?
    let sourceID: String
    let sourceHasDetailedStages: Bool
    let isInBed: Bool
}

struct MorningSleepSessionValue: Sendable {
    let start: Date
    let end: Date
    let total: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval
    let segments: [SleepSegmentValue]
    let hasDetailedStages: Bool
    let hasInBedSignal: Bool
    let hasTerminalAwakeSignal: Bool
    let awakeningCount: Int?
    let continuity: Double?
    /// Earliest in-bed envelope start covering this session's onset, when one
    /// exists. Kept so the caller can estimate sleep latency (onset − in-bed).
    let inBedStart: Date?
    /// Longest physically plausible in-bed envelope overlapping the session.
    var inBedDuration: TimeInterval? = nil
}

enum MorningSleepSessionBuilder {
    /// Select the best session on the most recent wake-day. Detailed stages win
    /// when they cover most of the longest candidate; otherwise a complete
    /// legacy block wins over a tiny detailed fragment from another source.
    static func latestSession(
        from samples: [MorningSleepSampleValue],
        calendar: Calendar = .current
    ) -> MorningSleepSessionValue? {
        let bySource = Dictionary(grouping: samples, by: \.sourceID)
        let candidates = bySource.values.flatMap { sessions(from: Array($0)) }
        guard let latestWakeDay = candidates.map({ calendar.startOfDay(for: $0.end) }).max()
        else { return nil }

        let latestCandidates = candidates.filter {
            calendar.startOfDay(for: $0.end) == latestWakeDay
        }
        guard let longest = latestCandidates.max(by: { $0.total < $1.total }) else { return nil }

        let sufficientlyCompleteDetailed = latestCandidates.filter {
            $0.hasDetailedStages && $0.total >= longest.total * 0.6
        }
        return sufficientlyCompleteDetailed.max(by: { $0.total < $1.total }) ?? longest
    }

    private struct SessionBounds {
        var start: Date
        var end: Date
    }

    private static func sessions(
        from sourceSamples: [MorningSleepSampleValue]
    ) -> [MorningSleepSessionValue] {
        let asleep = sourceSamples
            .filter { sample in
                guard let stage = sample.stage else { return false }
                return stage != .awake && sample.end > sample.start
            }
            .sorted { $0.start < $1.start }
        guard !asleep.isEmpty else { return [] }

        var bounds: [SessionBounds] = []
        for sample in asleep {
            if var last = bounds.last,
               PiboCoreSleepAdapter.samplesShareSession(
                   gapSeconds: sample.start.timeIntervalSince(last.end)
               ) {
                last.start = min(last.start, sample.start)
                last.end = max(last.end, sample.end)
                bounds[bounds.count - 1] = last
            } else {
                bounds.append(SessionBounds(start: sample.start, end: sample.end))
            }
        }

        return bounds.compactMap { bound in
            makeSession(bound: bound, sourceSamples: sourceSamples)
        }
    }

    private static func makeSession(
        bound: SessionBounds,
        sourceSamples: [MorningSleepSampleValue]
    ) -> MorningSleepSessionValue? {
        let overlapping = sourceSamples.filter {
            $0.stage != nil && $0.end > bound.start && $0.start < bound.end
        }
        let rawSegments = overlapping.compactMap { sample -> SleepSegmentValue? in
            guard let stage = sample.stage else { return nil }
            let start = max(sample.start, bound.start)
            let end = min(sample.end, bound.end)
            guard end > start else { return nil }
            return SleepSegmentValue(start: start, end: end, stage: stage)
        }
        let segments = normalize(rawSegments)
        let asleepSegments = segments.filter { $0.stage != .awake }
        guard let start = asleepSegments.map(\.start).min(),
              let end = asleepSegments.map(\.end).max()
        else { return nil }

        func duration(_ stage: SleepStage) -> TimeInterval {
            segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
        }

        let core = duration(.core)
        let deep = duration(.deep)
        let rem = duration(.rem)
        let awake = duration(.awake)
        let total = core + deep + rem
        guard total > 0 else { return nil }

        let detailed = sourceSamples.contains { $0.sourceHasDetailedStages }
        let internalAwake = segments.filter {
            $0.stage == .awake
                && $0.duration >= 2 * 60
                && $0.start > start.addingTimeInterval(5 * 60)
                && $0.end < end.addingTimeInterval(-5 * 60)
        }
        let hasInBed = sourceSamples.contains { sample in
            guard sample.isInBed else { return false }
            let overlapStart = max(sample.start, start)
            let overlapEnd = min(sample.end, end)
            return overlapEnd.timeIntervalSince(overlapStart) >= total * 0.5
        }
        // Earliest in-bed envelope that actually contains sleep onset. Used only
        // to estimate latency; contributes no stage duration.
        let inBedStart = sourceSamples
            .filter { $0.isInBed && $0.start <= start && $0.end > start }
            .map(\.start)
            .min()
        let terminalAwake = sourceSamples.contains { sample in
            guard sample.stage == .awake else { return false }
            return sample.start <= end.addingTimeInterval(10 * 60) && sample.end >= end
        }

        return MorningSleepSessionValue(
            start: start,
            end: end,
            total: total,
            core: core,
            deep: deep,
            rem: rem,
            awake: awake,
            segments: segments,
            hasDetailedStages: detailed,
            hasInBedSignal: hasInBed,
            hasTerminalAwakeSignal: terminalAwake,
            awakeningCount: detailed ? internalAwake.count : nil,
            continuity: detailed && total + awake > 0 ? total / (total + awake) : nil,
            inBedStart: inBedStart,
            inBedDuration: sourceSamples
                .filter { $0.isInBed && $0.end > start && $0.start < end }
                .map { $0.end.timeIntervalSince($0.start) }
                .filter { $0.isFinite && $0 > 0 && $0 <= 24 * 60 * 60 }
                .max()
        )
    }

    /// Resolve duplicate/overlapping intervals from one source without counting
    /// the same wall-clock time twice, then merge adjacent same-stage samples.
    private static func normalize(_ input: [SleepSegmentValue]) -> [SleepSegmentValue] {
        let sorted = input.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        var result: [SleepSegmentValue] = []

        for original in sorted {
            var segment = original
            if let last = result.last {
                if segment.start < last.end {
                    if segment.stage == last.stage {
                        result[result.count - 1].end = max(last.end, segment.end)
                        continue
                    }
                    guard segment.end > last.end else { continue }
                    segment.start = last.end
                }

                if PiboCoreSleepAdapter.segmentsShouldMerge(
                    sameStage: segment.stage == result[result.count - 1].stage,
                    gapSeconds: segment.start.timeIntervalSince(result[result.count - 1].end)
                ) {
                    result[result.count - 1].end = max(result[result.count - 1].end, segment.end)
                    continue
                }
            }
            result.append(segment)
        }
        return result
    }
}
