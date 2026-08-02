import Combine
import Foundation
import os

@MainActor
final class CRCTrainingViewModel: ObservableObject {
    @Published var step: CRCFlowStep = .intro
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
    @Published var selectedDurationSeconds: Int = 3 * 60

    private let workout = WorkoutSessionManager()
    private let motionDetector = CRCMotionBreathingDetector()
    private let haptic = CRCHapticGuide()
    private var coupling = CRCCouplingEngine()
    /// Live RSA/HRV estimator, fed every heart-rate sample.
    private var hrvEstimator = CRCHRVEstimator()
    /// Per-tick samples of the live HRV, averaged into the report (fallback when
    /// no authoritative heartbeat series was captured).
    private var liveHRVReadings: [Double] = []
    private var sessionReferenceHeartRate: Double?
    private var snapshots: [CRCSnapshot] = []
    private var sessionStartedAt = Date()
    private var accumulatedPausedTime: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var couplingTask: Task<Void, Never>?
    /// Bumped each time a report is produced, so a late background RMSSD refine
    /// from a previous session can't patch the current report.
    private var reportGeneration = 0
    private var unstableTickCount = 0
    private var unstableCooldownUntil: Date?
#if DEBUG
    private var visualValidationTask: Task<Void, Never>?
#endif

    private var referenceHeartRate: Double {
        sessionReferenceHeartRate ?? latestHeartRate?.bpm ?? 72
    }

    /// Seconds remaining in the recommended training duration (floored at 0).
    var remainingSeconds: Int {
        max(0, selectedDurationSeconds - elapsedSeconds)
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
                self?.latestBreathReading = reading
                self?.poseAssessment = assessment
            }
        }

        guard motionDetector.start() else {
            errorMessage = "当前设备无法启动腕部运动检测，请稍后重试。"
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
            beginCoupledTraining()
        } catch {
            LPLog.watchBreathing.error(
                "start HealthKit workout failed: \(String(describing: error), privacy: .public)"
            )
            errorMessage = healthStartErrorMessage(for: error)
            step = .error
            motionDetector.stop()
            await workout.cancel()
        }
    }

    func stopTraining() async {
        // Only the active training can be stopped-and-reported (menu-save or the
        // auto-complete tick). Guarding on the exact step avoids ever building a
        // zero-duration report from an error state if an entry point is added.
        guard step == .coreTraining else { return }
        isStopping = true
        transient = .none
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
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        await workout.cancel()
        step = .intro
        resetRuntime()
    }

    func reset() {
        couplingTask?.cancel()
        motionDetector.stop()
        haptic.stop()
        step = .intro
        resetRuntime()
    }

    private func resetRuntime() {
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
        sessionReferenceHeartRate = nil
        snapshots.removeAll(keepingCapacity: true)
        coupling.reset()
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
                    baselineHeartRate: referenceHeartRate,
                    breathReading: latestBreathReading,
                    pose: poseAssessment,
                    elapsed: TimeInterval(elapsedSeconds)
                )
                snapshot = currentSnapshot
                snapshots.append(currentSnapshot)
                if let hrv = hrvEstimator.rmssdMs { liveHRVReadings.append(hrv) }
                // Drop a frozen estimate if the HR stream stalled (signal loss) —
                // don't keep displaying the last value as if it were live.
                if let last = hrvEstimator.lastSampleTime, Date().timeIntervalSince(last) > 15 {
                    liveHRV = nil
                }
                haptic.update(
                    phase: currentSnapshot.phase,
                    syncScore: currentSnapshot.syncScore
                )

                evaluateStability(for: currentSnapshot)
                if transient == .unstable {
                    return
                }

                if elapsedSeconds >= selectedDurationSeconds {
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
            if sessionReferenceHeartRate == nil {
                sessionReferenceHeartRate = sample.value
            }

            // Feed the live RSA/HRV estimator off every HR sample. Smooth with a
            // light EWMA so the readout doesn't jump every sample (the raw value
            // is noisy off averaged BPM); only advance when a fresh value exists.
            hrvEstimator.append(bpm: sample.value, at: sample.timestamp)
            if let raw = hrvEstimator.rmssdMs {
                liveHRV = liveHRV.map { $0 + 0.35 * (raw - $0) } ?? raw
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

#if DEBUG
    func startVisualValidationIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-PiboWatchVisualTraining") else { return }
        visualValidationTask?.cancel()
        step = .coreTraining
        selectedDurationSeconds = 3 * 60
        elapsedSeconds = 42
        latestHeartRate = CRCHeartReading(bpm: 68, confidence: 1, timestamp: Date())
        liveHRV = 42
        snapshot = visualValidationSnapshot(phase: .inhale, progress: 0)
        visualValidationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                snapshot = visualValidationSnapshot(phase: .inhale, progress: 0)
                try? await Task.sleep(for: .seconds(4.5))
                guard !Task.isCancelled else { return }
                snapshot = visualValidationSnapshot(phase: .exhale, progress: 0)
                try? await Task.sleep(for: .seconds(5.5))
                elapsedSeconds = min(elapsedSeconds + 10, selectedDurationSeconds - 1)
            }
        }
    }

    private func visualValidationSnapshot(phase: CRCBreathingPhase, progress: Double) -> CRCSnapshot {
        CRCSnapshot(
            timestamp: Date(),
            heartRate: 68,
            measuredBreathingRate: 6.1,
            guidedBreathingRate: 6,
            previousGuidedBreathingRate: 6,
            heartBreathRatio: 11.3,
            couplingIndex: 76,
            syncScore: 0.8,
            phase: phase,
            phaseProgress: progress,
            pose: poseAssessment,
            breathSignalQuality: 0.9,
            amplitudeScore: 0.8,
            followQuality: 0.8
        )
    }
#endif
}
