import Foundation
import PiboCore

/// Persisted presentation-neutral projection of one Core wellness report.
/// Raw HealthKit facts remain on `HealthDayRecord`; this payload can be safely
/// regenerated whenever the Core algorithm version changes.
struct DailyWellnessScoreSnapshot: Codable, Equatable, Sendable {
    let value: Double
    let confidence: Double
    let confidenceLevel: Int32
    let baselineDays: Int
    let availableInputs: UInt32
    let missingInputs: UInt32

    nonisolated init(_ score: PiboCoreWellnessScore) {
        value = score.value
        confidence = score.confidence
        confidenceLevel = score.confidenceLevel.rawValue
        baselineDays = score.baselineDays
        availableInputs = score.availableInputs.rawValue
        missingInputs = score.missingInputs.rawValue
    }
}

struct DailyWellnessSnapshot: Codable, Equatable, Sendable {
    let algorithmVersion: UInt32
    let generatedAt: Date

    let sleepScore: DailyWellnessScoreSnapshot?
    let sleepSufficiency: Double?
    let sleepRegularity: Double?
    let sleepContinuity: Double?
    let sleepNeedMinutes: Double?
    let sleepDebtMinutes: Double?
    let bedtimeWindowStartMinute: Int?
    let bedtimeWindowEndMinute: Int?
    let deepSleepShare: Double?
    let remSleepShare: Double?

    let activityScore: DailyWellnessScoreSnapshot?
    let stepsScore: Double?
    let activeMinutesScore: Double?
    let activeHoursScore: Double?

    let acuteTrainingLoad: Double
    let chronicWeeklyTrainingLoad: Double
    let trainingBalanceRatio: Double?
    let trainingBalanceStatus: Int32
    /// Optional for backward-compatible decoding of snapshots written before
    /// Core's observation counts were persisted. A load is displayable only
    /// when its matching count is greater than zero.
    let acuteTrainingObservedDays: Int?
    let chronicTrainingObservedDays: Int?

    let recoveryScore: DailyWellnessScoreSnapshot?
    let recoverySleepContributor: Double?
    let recoveryHRVContributor: Double?
    let recoveryHeartRateContributor: Double?
    let recoveryTemperatureContributor: Double?
    let recoveryTrainingContributor: Double?

    let readinessScore: DailyWellnessScoreSnapshot?
    let readinessBand: Int32?
    let readinessSleepSufficiency: Double?
    let readinessLoadStatus: Int32?
    let readinessPrimaryReason: Int32?
    let readinessSecondaryReason: Int32?
    let readinessCalibrationDays: Int?
    let readinessRequiredCalibrationDays: Int?

    var restorativeMinutes: Double?
    var restorativeConfidence: Double?

    var resilienceScore: DailyWellnessScoreSnapshot?
    var resilienceRecoveryContributor: Double?
    var resilienceStressContributor: Double?
    var resilienceRestorativeContributor: Double?
    var resilienceObservedDays: Int

    nonisolated init(
        report: PiboCoreWellnessReport,
        readiness: PiboCoreWellnessReadinessResult? = nil,
        generatedAt: Date
    ) {
        algorithmVersion = report.algorithmVersion
        self.generatedAt = generatedAt
        sleepScore = report.sleep.score.map(DailyWellnessScoreSnapshot.init)
        sleepSufficiency = report.sleep.sufficiencyScore
        sleepRegularity = report.sleep.regularityScore
        sleepContinuity = report.sleep.continuityScore
        sleepNeedMinutes = report.sleep.sleepNeedMinutes
        sleepDebtMinutes = report.sleep.sleepDebtMinutes
        bedtimeWindowStartMinute = report.sleep.bedtimeWindow?.startMinute
        bedtimeWindowEndMinute = report.sleep.bedtimeWindow?.endMinute
        deepSleepShare = report.sleep.deepSleepShare
        remSleepShare = report.sleep.remSleepShare
        activityScore = report.activity.score.map(DailyWellnessScoreSnapshot.init)
        stepsScore = report.activity.stepsScore
        activeMinutesScore = report.activity.activeMinutesScore
        activeHoursScore = report.activity.activeHoursScore
        acuteTrainingLoad = report.training.acuteLoad
        chronicWeeklyTrainingLoad = report.training.chronicWeeklyLoad
        trainingBalanceRatio = report.training.ratio
        trainingBalanceStatus = report.training.status.rawValue
        acuteTrainingObservedDays = report.training.acuteObservedDays
        chronicTrainingObservedDays = report.training.chronicObservedDays
        recoveryScore = report.recovery.score.map(DailyWellnessScoreSnapshot.init)
        recoverySleepContributor = report.recovery.sleepScore
        recoveryHRVContributor = report.recovery.hrvScore
        recoveryHeartRateContributor = report.recovery.heartRateScore
        recoveryTemperatureContributor = report.recovery.temperatureScore
        recoveryTrainingContributor = report.recovery.trainingScore
        readinessScore = readiness?.score.map(DailyWellnessScoreSnapshot.init)
        readinessBand = readiness?.band.rawValue
        readinessSleepSufficiency = readiness?.sleepSufficiencyScore
        readinessLoadStatus = readiness?.loadStatus.rawValue
        readinessPrimaryReason = readiness?.primaryReason.rawValue
        readinessSecondaryReason = readiness?.secondaryReason.rawValue
        readinessCalibrationDays = readiness?.calibrationDays
        readinessRequiredCalibrationDays = readiness?.requiredCalibrationDays
        restorativeMinutes = nil
        restorativeConfidence = nil
        resilienceScore = nil
        resilienceRecoveryContributor = nil
        resilienceStressContributor = nil
        resilienceRestorativeContributor = nil
        resilienceObservedDays = 0
    }

    nonisolated mutating func apply(_ restorative: PiboCoreWellnessRestorativeTimeResult?) {
        restorativeMinutes = restorative?.restorativeMinutes
        restorativeConfidence = restorative?.confidence
    }

    nonisolated mutating func apply(_ resilience: PiboCoreWellnessResilienceResult?) {
        resilienceScore = resilience.map { DailyWellnessScoreSnapshot($0.score) }
        resilienceRecoveryContributor = resilience?.recoveryComponent
        resilienceStressContributor = resilience?.stressComponent
        resilienceRestorativeContributor = resilience?.restorativeComponent
        resilienceObservedDays = resilience?.observedDays ?? 0
    }
}
