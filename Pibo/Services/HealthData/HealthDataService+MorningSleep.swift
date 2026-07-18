import Foundation
import HealthKit
import os

enum MorningSleepHealthTypes {
    /// These values enrich a sleep session but never trigger the morning flow
    /// by themselves. `sleepAnalysis` remains the sole wake-up signal.
    static var enrichmentReadTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
        ]
    }
}

extension HealthDataService {
    /// Foreground-only permission expansion for existing installs. New installs
    /// receive these types in the initial HealthKit request; existing users are
    /// asked only after a real recent sleep sample exists, so a device with no
    /// sleep data remains completely silent.
    func requestMorningSleepEnrichmentAuthorizationIfNeeded() async {
        guard authState == .granted, await hasRecentSleepData() else { return }
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: [],
                read: MorningSleepHealthTypes.enrichmentReadTypes
            )
            guard status == .shouldRequest else { return }
            try await store.requestAuthorization(
                toShare: [],
                read: MorningSleepHealthTypes.enrichmentReadTypes
            )
            LPLog.healthKit.notice("Requested morning-sleep enrichment read scopes")
        } catch {
            LPLog.healthKit.error(
                "Morning-sleep enrichment auth failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// The complete latest session used by both background notification work
    /// and the first foreground open. Sleep stages determine the time window;
    /// all optional quantities are then queried concurrently inside that window.
    func fetchLatestMorningSleepSummary(now: Date = .now) async -> MorningSleepSummary? {
        let samples = await fetchRecentSleepSamples(now: now)
        guard !samples.isEmpty else { return nil }

        let inBedSamples = samples.filter {
            HKCategoryValueSleepAnalysis(rawValue: $0.value) == .inBed
        }
        let stageSamples = samples.filter {
            HKCategoryValueSleepAnalysis(rawValue: $0.value) != .inBed
        }
        let grouped = Dictionary(grouping: stageSamples) { sample in
            let revision = sample.sourceRevision
            return "\(revision.source.bundleIdentifier)|\(revision.productType ?? "-")"
        }

        var values: [MorningSleepSampleValue] = []
        for (sourceID, sourceSamples) in grouped {
            let hasDetailed = sourceSamples.contains { sample in
                PiboCoreSleepAdapter.sampleIsDetailed(
                    HKCategoryValueSleepAnalysis(rawValue: sample.value)
                )
            }
            for sample in sourceSamples {
                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                let resolved = PiboCoreSleepAdapter.resolveSample(
                    value,
                    hasDetailedSamples: hasDetailed
                )
                let stage: SleepStage?
                switch resolved {
                case .awake:                         stage = .awake
                case .deep:                          stage = .deep
                case .rem:                           stage = .rem
                case .core, .legacyAsleep, .unspecified: stage = .core
                case .ignored:                       stage = nil
                }
                guard stage != nil else { continue }
                values.append(MorningSleepSampleValue(
                    start: sample.startDate,
                    end: sample.endDate,
                    stage: stage,
                    sourceID: sourceID,
                    sourceHasDetailedStages: hasDetailed,
                    isInBed: false
                ))
            }

            // `inBed` commonly comes from the phone's sleep schedule while the
            // detailed stages come from the watch. Copy the envelope into each
            // candidate source solely as supporting evidence; it contributes no
            // stage duration and therefore cannot double-count sleep.
            for sample in inBedSamples {
                values.append(MorningSleepSampleValue(
                    start: sample.startDate,
                    end: sample.endDate,
                    stage: nil,
                    sourceID: sourceID,
                    sourceHasDetailedStages: hasDetailed,
                    isInBed: true
                ))
            }
        }

        guard let session = MorningSleepSessionBuilder.latestSession(from: values) else {
            return nil
        }

        async let overnightHRV = medianQuantity(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            start: session.start,
            end: session.end
        )
        async let respiratoryRate = medianQuantity(
            .respiratoryRate,
            unit: .count().unitDivided(by: .minute()),
            start: session.start,
            end: session.end
        )
        async let oxygenSaturation = medianQuantity(
            .oxygenSaturation,
            unit: .percent(),
            start: session.start,
            end: session.end
        )
        async let wristTemperature = sleepingWristTemperature(
            sessionStart: session.start,
            sessionEnd: session.end
        )
        // Heart rate across the sleep window: one query, avg + min computed
        // locally. `heartRate` is already in the core HK auth set, so this needs
        // no enrichment scope.
        async let heartRateValues = quantityValues(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            start: session.start,
            end: session.end
        )

        let temperature = await wristTemperature
        let heartRates = await heartRateValues.map(\.value)
        let sleepHeartRateAverage = heartRates.isEmpty
            ? nil
            : heartRates.reduce(0, +) / Double(heartRates.count)
        let sleepHeartRateMin = heartRates.min()

        // Sleep latency = onset − in-bed start. Guardrails: only when an in-bed
        // envelope exists and the gap is in a plausible range, since the in-bed
        // start can be a *scheduled* bedtime rather than lights-out.
        let sleepLatency: TimeInterval? = {
            guard session.hasInBedSignal, let inBedStart = session.inBedStart else { return nil }
            let value = session.start.timeIntervalSince(inBedStart)
            return (value > 0 && value < 90 * 60) ? value : nil
        }()

        let summary = MorningSleepSummary(
            wakeDay: Calendar.current.startOfDay(for: session.end),
            generatedAt: now,
            start: session.start,
            end: session.end,
            total: session.total,
            core: session.core,
            deep: session.deep,
            rem: session.rem,
            awake: session.awake,
            segments: session.segments,
            hasDetailedStages: session.hasDetailedStages,
            hasInBedSignal: session.hasInBedSignal,
            hasTerminalAwakeSignal: session.hasTerminalAwakeSignal,
            awakeningCount: session.awakeningCount,
            continuity: session.continuity,
            baselineDelta: nil,
            overnightHRV: await overnightHRV,
            sleepingWristTemperature: temperature.value,
            sleepingWristTemperatureDelta: temperature.delta,
            respiratoryRate: await respiratoryRate,
            oxygenSaturation: await oxygenSaturation,
            sleepHeartRateAverage: sleepHeartRateAverage,
            sleepHeartRateMin: sleepHeartRateMin,
            sleepLatency: sleepLatency
        )
        LPLog.sleep.info(
            "Morning summary wakeDay=\(summary.wakeDayKey, privacy: .public) total=\(Int(summary.total / 60), privacy: .public)min detailed=\(summary.hasDetailedStages, privacy: .public)"
        )
        return summary
    }

    private func hasRecentSleepData(now: Date = .now) async -> Bool {
        let samples = await fetchRecentSleepSamples(now: now)
        let hasDetailed = samples.contains { sample in
            PiboCoreSleepAdapter.sampleIsDetailed(
                HKCategoryValueSleepAnalysis(rawValue: sample.value)
            )
        }
        return samples.contains { sample in
            switch PiboCoreSleepAdapter.resolveSample(
                HKCategoryValueSleepAnalysis(rawValue: sample.value),
                hasDetailedSamples: hasDetailed
            ) {
            case .legacyAsleep, .core, .deep, .rem, .unspecified: true
            case .ignored, .awake: false
            }
        }
    }

    private func fetchRecentSleepSamples(now: Date) async -> [HKCategorySample] {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .categorySample(
                    type: HKCategoryType(.sleepAnalysis),
                    predicate: predicate
                ),
            ],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store)
        } catch {
            LPLog.sleep.error(
                "Recent sleep query failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func medianQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        let values = await quantityValues(identifier, unit: unit, start: start, end: end)
            .map(\.value)
        return Self.median(values)
    }

    private struct DatedQuantityValue: Sendable {
        let date: Date
        let value: Double
    }

    private func quantityValues(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [DatedQuantityValue] {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map {
                DatedQuantityValue(
                    date: $0.startDate,
                    value: $0.quantity.doubleValue(for: unit)
                )
            }
        } catch {
            // Missing authorization and unsupported hardware both intentionally
            // become nil in the UI; HealthKit does not let read-side clients
            // distinguish them reliably.
            LPLog.sleep.debug(
                "Sleep quantity \(identifier.rawValue, privacy: .public) unavailable: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private struct WristTemperatureResult: Sendable {
        let value: Double?
        let delta: Double?
    }

    private func sleepingWristTemperature(
        sessionStart: Date,
        sessionEnd: Date
    ) async -> WristTemperatureResult {
        let historyStart = Calendar.current.date(
            byAdding: .day,
            value: -21,
            to: sessionStart
        ) ?? sessionStart
        let queryEnd = sessionEnd.addingTimeInterval(2 * 60 * 60)
        let values = await quantityValues(
            .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            start: historyStart,
            end: queryEnd
        )
        let currentStart = sessionStart.addingTimeInterval(-2 * 60 * 60)
        let current = values.filter { $0.date >= currentStart && $0.date <= queryEnd }
            .map(\.value)
        let baseline = values.filter { $0.date < currentStart }.map(\.value)
        let currentMedian = Self.median(current)
        let baselineMedian = baseline.count >= 5 ? Self.median(baseline) : nil
        return WristTemperatureResult(
            value: currentMedian,
            delta: currentMedian.flatMap { current in
                baselineMedian.map { current - $0 }
            }
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
