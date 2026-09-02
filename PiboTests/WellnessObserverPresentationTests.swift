import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
struct WellnessObserverPresentationTests {
    @Test func healthAvailabilityAlwaysOverridesPersistedScore() throws {
        let record = try recordWithReadiness()
        let cases: [(HealthDataService.DataAvailability,
                     WellnessObserverPresentation.UnavailableKind)] = [
            (.unavailable, .healthKitUnavailable),
            (.needsAuthorization, .needsAuthorization),
            (.checking, .checking),
            (.noReadableData, .noReadableData),
            (.temporarilyInterrupted(lastReadableAt: .now), .temporarilyInterrupted),
        ]

        for (availability, expected) in cases {
            let presentation = WellnessObserverPresentation.make(
                record: record,
                availability: availability
            )
            #expect(presentation.content == .unavailable(expected))
        }
    }

    @Test func availableProjectionMapsBandLoadAndCoreReasons() throws {
        let bands: [(PiboCoreWellnessReadinessBand, WellnessObserverPresentation.Band)] = [
            (.significantlyBelow, .significantlyBelow),
            (.belowPersonalNormal, .belowPersonalNormal),
            (.personalNormal, .personalNormal),
            (.ample, .ample),
        ]
        let loads: [(PiboCoreWellnessLoadStatus, WellnessObserverPresentation.Load)] = [
            (.buildingBaseline, .buildingBaseline),
            (.belowUsual, .belowUsual),
            (.usual, .usual),
            (.aboveUsual, .aboveUsual),
            (.unavailable, .unavailable),
        ]

        for (band, expectedBand) in bands {
            for (load, expectedLoad) in loads {
                let record = try recordWithReadiness(band: band, load: load)
                let presentation = WellnessObserverPresentation.make(
                    record: record,
                    availability: .available(lastCheckedAt: .now)
                )
                guard case .available(let value) = presentation.content else {
                    Issue.record("Expected an available readiness projection")
                    continue
                }
                #expect(value.band == expectedBand)
                #expect(value.load == expectedLoad)
                #expect(value.score == 78)
                #expect(value.sleepSufficiency == 86)
                #expect(value.primaryReason == .sleepSufficient)
                #expect(value.secondaryReason == .hrvUsual)
                #expect(value.calibrationDays == 18)
            }
        }
    }

    @Test func everyCoreReasonMapsWithoutInferringFromScore() throws {
        let reasons: [(PiboCoreWellnessReadinessReason,
                       WellnessObserverPresentation.Reason)] = [
            (.missingCurrentSleep, .missingCurrentSleep),
            (.buildingPersonalBaseline, .buildingPersonalBaseline),
            (.sleepInsufficient, .sleepInsufficient),
            (.sleepSufficient, .sleepSufficient),
            (.hrvBelowUsual, .hrvBelowUsual),
            (.hrvUsual, .hrvUsual),
            (.hrvAboveUsual, .hrvAboveUsual),
            (.heartRateElevated, .heartRateElevated),
            (.heartRateUsual, .heartRateUsual),
            (.heartRateLowerThanUsual, .heartRateLowerThanUsual),
            (.temperatureDeviation, .temperatureDeviation),
            (.recentLoadAboveUsual, .recentLoadAboveUsual),
            (.recentLoadUsual, .recentLoadUsual),
        ]

        for (reason, expected) in reasons {
            let record = try recordWithReadiness(primaryReason: reason)
            let presentation = WellnessObserverPresentation.make(
                record: record,
                availability: .available(lastCheckedAt: .now)
            )
            guard case .available(let value) = presentation.content else {
                Issue.record("Expected an available readiness projection")
                continue
            }
            #expect(value.primaryReason == expected)
        }
    }

    @Test func calibrationAndMissingSleepNeverProduceAZeroScore() throws {
        let calibration = try recordWithReadiness(
            score: nil,
            primaryReason: .buildingPersonalBaseline,
            calibrationDays: 5,
            requiredCalibrationDays: 7
        )
        #expect(WellnessObserverPresentation.make(
            record: calibration,
            availability: .available(lastCheckedAt: .now)
        ).content == .unavailable(.buildingPersonalBaseline(observed: 5, required: 7)))

        let missingSleep = try recordWithReadiness(
            score: nil,
            primaryReason: .missingCurrentSleep
        )
        #expect(WellnessObserverPresentation.make(
            record: missingSleep,
            availability: .available(lastCheckedAt: .now)
        ).content == .unavailable(.missingCurrentSleep))

        #expect(WellnessObserverPresentation.make(
            record: nil,
            availability: .available(lastCheckedAt: .now)
        ).content == .unavailable(.missingCurrentSleep))
    }

    @Test func versionMismatchAndUnknownBandRefuseStaleScore() throws {
        let stale = try recordWithReadiness(
            algorithmVersion: PiboCoreWellness.algorithmVersion + 1
        )
        #expect(WellnessObserverPresentation.make(
            record: stale,
            availability: .available(lastCheckedAt: .now)
        ).content == .unavailable(.updating))

        let unknownBand = try recordWithReadiness(rawBand: 99)
        #expect(WellnessObserverPresentation.make(
            record: unknownBand,
            availability: .available(lastCheckedAt: .now)
        ).content == .unavailable(.updating))
    }

    @Test func duplicateOrUnavailableSecondaryReasonIsOmitted() throws {
        let duplicate = try recordWithReadiness(
            primaryReason: .sleepSufficient,
            secondaryReason: .sleepSufficient
        )
        let presentation = WellnessObserverPresentation.make(
            record: duplicate,
            availability: .available(lastCheckedAt: .now)
        )
        guard case .available(let value) = presentation.content else {
            Issue.record("Expected an available readiness projection")
            return
        }
        #expect(value.primaryReason == .sleepSufficient)
        #expect(value.secondaryReason == nil)
    }

    private func recordWithReadiness(
        algorithmVersion: UInt32 = PiboCoreWellness.algorithmVersion,
        score: Double? = 78,
        band: PiboCoreWellnessReadinessBand = .personalNormal,
        rawBand: Int32? = nil,
        load: PiboCoreWellnessLoadStatus = .usual,
        primaryReason: PiboCoreWellnessReadinessReason = .sleepSufficient,
        secondaryReason: PiboCoreWellnessReadinessReason = .hrvUsual,
        calibrationDays: Int = 18,
        requiredCalibrationDays: Int = 7
    ) throws -> HealthDayRecord {
        let day = Calendar.current.startOfDay(for: .now)
        let generatedAt = day.addingTimeInterval(9 * 3_600)
        let record = HealthDayRecord(date: day)
        let report = PiboCoreWellnessAdapter.report(current: record, history: [])
        let base = DailyWellnessSnapshot(report: report, generatedAt: generatedAt)
        let encoded = try JSONEncoder().encode(base)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["algorithmVersion"] = Int(algorithmVersion)
        object["readinessBand"] = Int(rawBand ?? band.rawValue)
        object["readinessSleepSufficiency"] = 86.0
        object["readinessLoadStatus"] = Int(load.rawValue)
        object["readinessPrimaryReason"] = Int(primaryReason.rawValue)
        object["readinessSecondaryReason"] = Int(secondaryReason.rawValue)
        object["readinessCalibrationDays"] = calibrationDays
        object["readinessRequiredCalibrationDays"] = requiredCalibrationDays
        if let score {
            object["readinessScore"] = [
                "value": score,
                "confidence": 0.82,
                "confidenceLevel": 3,
                "baselineDays": calibrationDays,
                "availableInputs": 0,
                "missingInputs": 0,
            ]
        } else {
            object.removeValue(forKey: "readinessScore")
        }
        record.wellnessPayload = try JSONSerialization.data(withJSONObject: object)
        return record
    }
}
