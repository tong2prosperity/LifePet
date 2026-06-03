import Foundation

struct CRCCouplingEngine {
    private(set) var guidedBreathingRate = CRCConstants.initialGuidedBreathingRate
    private(set) var previousGuidedBreathingRate = CRCConstants.initialGuidedBreathingRate
    private var sessionStart = Date()

    mutating func reset(startDate: Date = Date()) {
        guidedBreathingRate = CRCConstants.initialGuidedBreathingRate
        previousGuidedBreathingRate = CRCConstants.initialGuidedBreathingRate
        sessionStart = startDate
    }

    mutating func snapshot(
        heartRate: CRCHeartReading?,
        baselineHeartRate: Double,
        breathReading: CRCBreathReading?,
        pose: CRCPoseAssessment,
        elapsed: TimeInterval
    ) -> CRCSnapshot {
        let hr = heartRate?.bpm ?? max(62, baselineHeartRate)
        let measuredRate = measuredBreathingRate(from: breathReading, pose: pose)
        let ratio = hr / measuredRate
        let ratioError = ratio - CRCConstants.targetHeartBreathRatio

        previousGuidedBreathingRate = guidedBreathingRate
        let closedLoopTarget = guidedBreathingRate + 0.06 * ratioError
        let stageTarget = stageTargetBreathingRate(
            elapsed: elapsed,
            heartRate: hr,
            baselineHeartRate: baselineHeartRate
        )
        let blendedTarget = 0.55 * closedLoopTarget + 0.45 * stageTarget
        let clampedTarget = min(
            CRCConstants.maxGuidedBreathingRate,
            max(CRCConstants.minGuidedBreathingRate, blendedTarget)
        )
        guidedBreathingRate += 0.20 * (clampedTarget - guidedBreathingRate)

        let coupling = couplingIndex(heartBreathRatio: ratio)
        let followQuality = followQuality(
            measuredRate: measuredRate,
            guidedRate: guidedBreathingRate,
            signalQuality: breathReading?.signalQuality ?? 0
        )
        let sync = (
            0.46 * coupling / 100
            + 0.28 * followQuality
            + 0.16 * pose.poseConfidence
            + 0.10 * (heartRate?.confidence ?? 0.65)
        ).crcClampedUnit

        let phaseInfo = phase(for: guidedBreathingRate, elapsed: elapsed)
        return CRCSnapshot(
            timestamp: Date(),
            heartRate: hr,
            measuredBreathingRate: measuredRate,
            guidedBreathingRate: guidedBreathingRate,
            previousGuidedBreathingRate: previousGuidedBreathingRate,
            heartBreathRatio: ratio,
            couplingIndex: coupling,
            syncScore: sync * 100,
            phase: phaseInfo.phase,
            phaseProgress: phaseInfo.progress,
            pose: pose,
            breathSignalQuality: breathReading?.signalQuality ?? 0,
            amplitudeScore: breathReading?.amplitudeScore ?? 0,
            followQuality: followQuality
        )
    }

    private func measuredBreathingRate(
        from reading: CRCBreathReading?,
        pose: CRCPoseAssessment
    ) -> Double {
        guard let reading,
              reading.signalQuality > 0.28,
              pose.poseConfidence > 0.45 else {
            return guidedBreathingRate
        }

        return min(
            CRCConstants.maximumMeasuredBreathingRate,
            max(CRCConstants.minimumMeasuredBreathingRate, reading.breathsPerMinute)
        )
    }

    private func stageTargetBreathingRate(
        elapsed: TimeInterval,
        heartRate: Double,
        baselineHeartRate: Double
    ) -> Double {
        let progress = min(1, elapsed / CRCConstants.recommendedTrainingDuration)
        var target = 6.0 - 0.7 * progress

        if baselineHeartRate > 0, heartRate > baselineHeartRate + 5 {
            target -= 0.25
        } else if baselineHeartRate > 0, heartRate < baselineHeartRate - 6 {
            target += 0.20
        }

        return min(
            CRCConstants.maxGuidedBreathingRate,
            max(CRCConstants.minGuidedBreathingRate, target)
        )
    }

    private func couplingIndex(heartBreathRatio: Double) -> Double {
        let normalizedError = abs(heartBreathRatio - CRCConstants.targetHeartBreathRatio)
            / CRCConstants.targetHeartBreathRatio
        let score = 100.0 / (1.0 + exp(6.0 * (normalizedError - 0.28)))
        return min(100, max(0, score))
    }

    private func followQuality(
        measuredRate: Double,
        guidedRate: Double,
        signalQuality: Double
    ) -> Double {
        let rateError = abs(measuredRate - guidedRate)
        let rateScore = (1.0 - rateError / 2.2).crcClampedUnit
        return (0.70 * rateScore + 0.30 * signalQuality).crcClampedUnit
    }

    private func phase(
        for breathingRate: Double,
        elapsed: TimeInterval
    ) -> (phase: CRCBreathingPhase, progress: Double) {
        let cycleDuration = 60.0 / max(0.1, breathingRate)
        let cycleProgress = elapsed
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

        if cycleProgress < CRCConstants.inhaleRatio {
            return (.inhale, cycleProgress / CRCConstants.inhaleRatio)
        }

        return (
            .exhale,
            (cycleProgress - CRCConstants.inhaleRatio) / CRCConstants.exhaleRatio
        )
    }
}
