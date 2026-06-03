import Combine
import Foundation

@MainActor
final class CRCTrainingViewModel: ObservableObject {
    @Published var step: CRCFlowStep = .welcome
    @Published var baselineProgress: Double = 0
    @Published var baselineRemaining: Int = Int(CRCConstants.baselineDuration)
    @Published var elapsedSeconds: Int = 0
    @Published var latestHeartRate: CRCHeartReading?
    @Published var latestBreathReading: CRCBreathReading?
    @Published var poseAssessment = CRCPoseAssessment(
        poseConfidence: 0,
        orientationConfidence: 0,
        stillnessConfidence: 0,
        breathingSignalQuality: 0,
        isLikelyPlaced: false,
        guidance: "将手腕自然贴近胸腹部"
    )
    @Published var snapshot: CRCSnapshot?
    @Published var report: CRCTrainingReport?
    @Published var errorMessage: String?
    @Published var isStopping = false

    private let workout = WorkoutSessionManager()
    private let motionDetector = CRCMotionBreathingDetector()
    private let haptic = CRCHapticGuide()
    private var coupling = CRCCouplingEngine()
    private var baselineHeartRates: [Double] = []
    private var snapshots: [CRCSnapshot] = []
    private var sessionStartedAt = Date()
    private var baselineTask: Task<Void, Never>?
    private var couplingTask: Task<Void, Never>?
    private var flowTask: Task<Void, Never>?
    private var hasReceivedMotionUpdate = false
    private var hasReceivedHeartRate = false

    var baselineHeartRate: Double {
        guard !baselineHeartRates.isEmpty else {
            return latestHeartRate?.bpm ?? 72
        }

        let sorted = baselineHeartRates.sorted()
        let trim = min(sorted.count / 10, max(0, sorted.count - 1))
        let values = sorted.dropFirst(trim).dropLast(trim)
        let usable = values.isEmpty ? sorted[...] : values
        return usable.reduce(0, +) / Double(usable.count)
    }

    var currentStepNumber: Int {
        min(step.rawValue, CRCFlowStep.report.rawValue)
    }

    func showPreparation() {
        report = nil
        errorMessage = nil
        step = .preparation
    }

    func startDetection() async {
        guard step == .preparation || step == .welcome || step == .error else { return }
        resetRuntime()
        guard motionDetector.isAvailable else {
            errorMessage = "当前设备无法检测腕部运动，请在支持运动传感器的 Apple Watch 上训练。"
            step = .error
            return
        }

        motionDetector.onUpdate = { [weak self] reading, assessment in
            Task { @MainActor [weak self] in
                self?.hasReceivedMotionUpdate = true
                self?.latestBreathReading = reading
                self?.poseAssessment = assessment
            }
        }

        guard motionDetector.start() else {
            errorMessage = "当前设备无法启动腕部运动检测，请稍后重试。"
            step = .error
            return
        }

        guard await waitForMotionUpdate(timeout: 2.5) else {
            motionDetector.stop()
            errorMessage = "当前设备没有返回运动传感器数据，请在真机 Apple Watch 上训练。"
            step = .error
            return
        }

        workout.stream.onSamples = { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.ingest(samples: samples)
            }
        }

        do {
            _ = try await workout.start()
            step = .baseline
            sessionStartedAt = Date()
            await collectBaseline()
            guard step == .baseline else { return }
            guard await validateBaselineSignals() else { return }
            beginCoupledTraining()
        } catch {
            print("[Pibo watch] failed to start HealthKit workout: \(error)")
            errorMessage = healthStartErrorMessage(for: error)
            step = .error
            motionDetector.stop()
            await workout.cancel()
        }
    }

    func stopTraining() async {
        guard step != .welcome, step != .report else { return }
        isStopping = true
        baselineTask?.cancel()
        flowTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        _ = try? await workout.stop()
        report = makeReport()
        step = .report
        isStopping = false
    }

    func reset() {
        baselineTask?.cancel()
        flowTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        step = .welcome
        resetRuntime()
    }

    private func resetRuntime() {
        baselineProgress = 0
        baselineRemaining = Int(CRCConstants.baselineDuration)
        elapsedSeconds = 0
        latestHeartRate = nil
        latestBreathReading = nil
        snapshot = nil
        report = nil
        errorMessage = nil
        hasReceivedMotionUpdate = false
        hasReceivedHeartRate = false
        baselineHeartRates.removeAll(keepingCapacity: true)
        snapshots.removeAll(keepingCapacity: true)
        coupling.reset()
    }

    private func waitForMotionUpdate(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if hasReceivedMotionUpdate {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        return hasReceivedMotionUpdate
    }

    private func collectBaseline() async {
        baselineTask?.cancel()
        baselineTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for second in 0..<Int(CRCConstants.baselineDuration) {
                guard !Task.isCancelled else { return }
                baselineProgress = Double(second) / CRCConstants.baselineDuration
                baselineRemaining = Int(CRCConstants.baselineDuration) - second
                try? await Task.sleep(for: .seconds(1))
            }

            baselineProgress = 1
            baselineRemaining = 0
        }

        await baselineTask?.value
    }

    private func validateBaselineSignals() async -> Bool {
        if !hasReceivedHeartRate {
            await failDetection(
                message: "未检测到心率数据，请确认手表佩戴贴合并已授权健康数据。"
            )
            return false
        }

        if latestBreathReading == nil {
            await failDetection(
                message: "未检测到稳定呼吸运动，请调整手腕位置后重新开始。"
            )
            return false
        }

        return true
    }

    private func failDetection(message: String) async {
        baselineTask?.cancel()
        flowTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        await workout.cancel()
        errorMessage = message
        step = .error
    }

    private func beginCoupledTraining() {
        sessionStartedAt = Date()
        elapsedSeconds = 0
        coupling.reset(startDate: sessionStartedAt)
        haptic.start()
        step = .breathingGuide
        startFlowLoop()
        startCouplingLoop()
    }

    private func startFlowLoop() {
        flowTask?.cancel()
        flowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Int(CRCConstants.introductoryGuideDuration)))
            guard !Task.isCancelled else { return }
            step = .realtimeMonitor

            try? await Task.sleep(for: .seconds(Int(CRCConstants.realtimeMonitorDuration)))
            guard !Task.isCancelled else { return }
            step = .adaptiveTuning

            try? await Task.sleep(for: .seconds(Int(CRCConstants.adaptiveReviewDuration)))
            guard !Task.isCancelled else { return }
            step = .trainingFeedback
        }
    }

    private func startCouplingLoop() {
        couplingTask?.cancel()
        couplingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                elapsedSeconds = Int(Date().timeIntervalSince(sessionStartedAt))
                let currentSnapshot = coupling.snapshot(
                    heartRate: latestHeartRate,
                    baselineHeartRate: baselineHeartRate,
                    breathReading: latestBreathReading,
                    pose: poseAssessment,
                    elapsed: TimeInterval(elapsedSeconds)
                )
                snapshot = currentSnapshot
                snapshots.append(currentSnapshot)
                haptic.update(
                    phase: currentSnapshot.phase,
                    syncScore: currentSnapshot.syncScore
                )

                if elapsedSeconds >= Int(CRCConstants.recommendedTrainingDuration) {
                    await stopTraining()
                    return
                }

                try? await Task.sleep(for: .seconds(Int(CRCConstants.couplingTickInterval)))
            }
        }
    }

    private func ingest(samples: [VitalSample]) {
        for sample in samples where sample.kind == .heartRate {
            let reading = CRCHeartReading(
                bpm: sample.value,
                confidence: sample.value >= 42 && sample.value <= 190 ? 1 : 0.35,
                timestamp: sample.timestamp
            )
            latestHeartRate = reading
            hasReceivedHeartRate = true

            if step == .baseline {
                baselineHeartRates.append(sample.value)
            }
        }
    }

    private func healthStartErrorMessage(for error: Error) -> String {
        if let workoutError = error as? WorkoutSessionError {
            switch workoutError {
            case .healthDataUnavailable:
                return "当前设备无法使用健康数据，请在真机 Apple Watch 上训练。"
            case .workoutSharingDenied:
                return "请在健康权限中允许 Pibo 写入体能训练并读取心率。"
            }
        }

        return "无法开启心率监测，请检查健康权限。"
    }

    private func makeReport() -> CRCTrainingReport {
        let usedSnapshots = snapshots
        let duration = max(0, Date().timeIntervalSince(sessionStartedAt))
        let avgCoupling = average(usedSnapshots.map(\.couplingIndex))
        let avgHeart = average(usedSnapshots.map(\.heartRate))
        let avgBreath = average(usedSnapshots.map(\.measuredBreathingRate))
        let avgSync = average(usedSnapshots.map(\.followQuality))

        let recommendation: String
        if avgCoupling >= 78 && avgSync >= 0.70 {
            recommendation = "建议每日训练 5-10 分钟，继续保持稳定节律。"
        } else if avgCoupling >= 58 {
            recommendation = "建议从 5 分钟开始，优先保持手腕稳定。"
        } else {
            recommendation = "先练习腹式呼吸和姿势摆放，再逐步延长训练。"
        }

        return CRCTrainingReport(
            couplingIndex: Int(avgCoupling.rounded()),
            averageHeartRate: Int(avgHeart.rounded()),
            averageBreathingRate: avgBreath,
            syncStability: avgSync,
            duration: duration,
            recommendation: recommendation
        )
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
