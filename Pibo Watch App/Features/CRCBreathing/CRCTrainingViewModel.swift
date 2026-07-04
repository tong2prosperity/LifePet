import Combine
import Foundation

@MainActor
final class CRCTrainingViewModel: ObservableObject {
    @Published var step: CRCFlowStep = .intro
    @Published var baselineProgress: Double = 0
    @Published var baselineRemaining: Int = Int(CRCConstants.baselineDuration)
    @Published var elapsedSeconds: Int = 0
    @Published var latestHeartRate: CRCHeartReading?
    @Published var latestBreathReading: CRCBreathReading?
    /// Live HRV (ms), read off the breath-driven HR swing (RSA). Refreshes with
    /// every heart-rate sample — the real-time 心率变异 the training screen shows.
    /// Honest proxy, not clinical RMSSD (see `CRCHRVEstimator`).
    @Published var liveHRV: Double?
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
    @Published var transient: CRCTransientState = .none

    private let workout = WorkoutSessionManager()
    private let motionDetector = CRCMotionBreathingDetector()
    private let haptic = CRCHapticGuide()
    private var coupling = CRCCouplingEngine()
    /// Live RSA/HRV estimator, fed every heart-rate sample.
    private var hrvEstimator = CRCHRVEstimator()
    /// Per-tick samples of the live HRV, averaged into the report (fallback when
    /// no authoritative heartbeat series was captured).
    private var liveHRVReadings: [Double] = []
    private var baselineHeartRates: [Double] = []
    private var snapshots: [CRCSnapshot] = []
    private var sessionStartedAt = Date()
    private var accumulatedPausedTime: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var baselineTask: Task<Void, Never>?
    private var couplingTask: Task<Void, Never>?
    private var hasReceivedMotionUpdate = false
    private var hasReceivedHeartRate = false
    /// Bumped each time a report is produced, so a late background RMSSD refine
    /// from a previous session can't patch the current report.
    private var reportGeneration = 0
    private var unstableTickCount = 0
    private var unstableCooldownUntil: Date?

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

    /// Seconds remaining in the recommended training duration (floored at 0).
    var remainingSeconds: Int {
        max(0, Int(CRCConstants.recommendedTrainingDuration) - elapsedSeconds)
    }

    func startDetection() async {
        guard step == .intro || step == .error else { return }
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
        guard step != .intro, step != .report else { return }
        isStopping = true
        transient = .none
        baselineTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        _ = try? await workout.stop()

        // Best-effort: log the active minutes to Apple Health as a mindful session.
        let end = Date()
        let start = end.addingTimeInterval(-Double(elapsedSeconds))
        await workout.saveMindfulSession(start: start, end: end)
        recordTrainingDay()

        // Show the report immediately with the live-HRV average. The authoritative
        // RMSSD from the recorded heartbeat series is refined in the background —
        // those series persist asynchronously after the workout, so querying now
        // would usually block on nothing.
        report = makeReport(sessionRMSSD: nil)
        step = .report
        isStopping = false
        reportGeneration += 1
        refineSessionRMSSD(start: sessionStartedAt, end: end)
    }

    /// Poll for the session's real heartbeat-series RMSSD a little after the
    /// workout ends (the system writes the series asynchronously), and patch it
    /// into the visible report once it lands — upgrading the 心率变异 row from the
    /// `≈` live estimate to the authoritative value. Silent no-op if none appears.
    private func refineSessionRMSSD(start: Date, end: Date) {
        let token = reportGeneration
        Task { @MainActor [weak self] in
            for delay in [3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.step == .report, self.reportGeneration == token else { return }
                if let rmssd = await self.workout.sessionRMSSD(start: start, end: end) {
                    guard self.step == .report, self.reportGeneration == token else { return }
                    self.report?.sessionRMSSD = rmssd
                    return
                }
            }
        }
    }

    /// Open the single exit menu (merges the old pause + end-confirm): freeze the clock and
    /// stop ticks + haptics while the sheet is up. Sensors keep running.
    func openMenu() {
        guard step == .coreTraining, pauseStartedAt == nil else { return }
        pauseStartedAt = Date()
        couplingTask?.cancel()
        haptic.stop()
        transient = .menu
    }

    /// Resume after a pause / dismissed overlay: roll the paused gap into the offset and restart ticks.
    func resumeTraining() {
        guard step == .coreTraining else { return }
        if let pauseStartedAt {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStartedAt)
            self.pauseStartedAt = nil
        }
        transient = .none
        haptic.start()
        startCouplingLoop()
    }

    /// Resume from the 检测不稳定 overlay and suppress re-triggering for a short cooldown.
    func dismissUnstable() {
        unstableCooldownUntil = Date().addingTimeInterval(15)
        unstableTickCount = 0
        resumeTraining()
    }

    /// Discard the session without saving a report and return to the intro.
    func discardTraining() async {
        transient = .none
        baselineTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        await workout.cancel()
        step = .intro
        resetRuntime()
    }

    func reset() {
        baselineTask?.cancel()
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        step = .intro
        resetRuntime()
    }

    private func resetRuntime() {
        baselineProgress = 0
        baselineRemaining = Int(CRCConstants.baselineDuration)
        elapsedSeconds = 0
        latestHeartRate = nil
        latestBreathReading = nil
        liveHRV = nil
        hrvEstimator.reset()
        liveHRVReadings.removeAll(keepingCapacity: true)
        snapshot = nil
        report = nil
        errorMessage = nil
        transient = .none
        accumulatedPausedTime = 0
        pauseStartedAt = nil
        unstableTickCount = 0
        unstableCooldownUntil = nil
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
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        await workout.cancel()
        errorMessage = message
        step = .error
    }

    private func beginCoupledTraining() {
        sessionStartedAt = Date()
        accumulatedPausedTime = 0
        pauseStartedAt = nil
        elapsedSeconds = 0
        unstableTickCount = 0
        unstableCooldownUntil = nil
        coupling.reset(startDate: sessionStartedAt)
        haptic.start()
        step = .coreTraining
        startCouplingLoop()
    }

    private func startCouplingLoop() {
        couplingTask?.cancel()
        couplingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                elapsedSeconds = max(
                    0,
                    Int(Date().timeIntervalSince(sessionStartedAt) - accumulatedPausedTime)
                )
                let currentSnapshot = coupling.snapshot(
                    heartRate: latestHeartRate,
                    baselineHeartRate: baselineHeartRate,
                    breathReading: latestBreathReading,
                    pose: poseAssessment,
                    elapsed: TimeInterval(elapsedSeconds)
                )
                snapshot = currentSnapshot
                snapshots.append(currentSnapshot)
                if let hrv = hrvEstimator.rmssdMs { liveHRVReadings.append(hrv) }
                haptic.update(
                    phase: currentSnapshot.phase,
                    syncScore: currentSnapshot.syncScore
                )

                evaluateStability(for: currentSnapshot)
                if transient == .unstable {
                    return
                }

                if elapsedSeconds >= Int(CRCConstants.recommendedTrainingDuration) {
                    await stopTraining()
                    return
                }

                try? await Task.sleep(for: .seconds(Int(CRCConstants.couplingTickInterval)))
            }
        }
    }

    /// Raise the 检测不稳定 overlay after sustained low-confidence detection (with cooldown).
    private func evaluateStability(for snapshot: CRCSnapshot) {
        let isUnstable = snapshot.pose.poseConfidence < 0.35 || snapshot.breathSignalQuality < 0.2
        guard isUnstable else {
            unstableTickCount = 0
            return
        }

        if let cooldown = unstableCooldownUntil, Date() < cooldown {
            return
        }

        unstableTickCount += 1
        if unstableTickCount >= 5 {
            unstableTickCount = 0
            pauseStartedAt = Date()
            haptic.stop()
            transient = .unstable
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

            // Feed the live RSA/HRV estimator off every HR sample. Smooth with a
            // light EWMA so the readout doesn't jump every sample (the raw value
            // is noisy off averaged BPM); only advance when a fresh value exists.
            hrvEstimator.append(bpm: sample.value, at: sample.timestamp)
            if let raw = hrvEstimator.rmssdMs {
                liveHRV = liveHRV.map { $0 + 0.35 * (raw - $0) } ?? raw
            }

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

    private func makeReport(sessionRMSSD: Double? = nil) -> CRCTrainingReport {
        let usedSnapshots = snapshots
        // Active training time (pauses already excluded from elapsedSeconds).
        let duration = TimeInterval(elapsedSeconds)
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

        // Pibo-voice close-out — warm, tsundere, never blaming (product tone: 不问责).
        let piboLine: String
        if avgBreath > 0 && avgBreath <= 7.0 && avgSync >= 0.60 {
            piboLine = "…花…喝饱了…啵。"
        } else if avgSync >= 0.45 {
            piboLine = "…还行吧…没让你白坐着…"
        } else {
            piboLine = "…下次…再陪我久一点…"
        }

        let liveHRVAverage = liveHRVReadings.isEmpty ? nil : average(liveHRVReadings)

        return CRCTrainingReport(
            couplingIndex: Int(avgCoupling.rounded()),
            averageHeartRate: Int(avgHeart.rounded()),
            averageBreathingRate: avgBreath,
            syncStability: avgSync,
            duration: duration,
            recommendation: recommendation,
            piboLine: piboLine,
            sessionRMSSD: sessionRMSSD,
            liveHRVAverage: liveHRVAverage
        )
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Companion-day tracking (mirrors the phone's 与Pibo相识第N天)

    private static let firstDayKey = "pibo.crc.firstDay"

    /// 1-based day count since the first ever completed session (0 before the first).
    var companionDay: Int {
        guard let first = UserDefaults.standard.object(forKey: Self.firstDayKey) as? Date else {
            return 0
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return max(1, days + 1)
    }

    private func recordTrainingDay() {
        if UserDefaults.standard.object(forKey: Self.firstDayKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstDayKey)
        }
    }
}
