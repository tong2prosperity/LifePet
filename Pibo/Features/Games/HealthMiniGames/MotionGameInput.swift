import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import Vision

// MARK: - Motion Input

@Observable
final class MotionGameInput {
    var stepPulse = 0
    var bellDownPulse = 0
    var bellUpPulse = 0
    var statusText = "动作感应"
    var requiresManualStepInput = false
    var requiresManualBellInput = false
    var isBellCalibrating = false
    var isBellCalibrated = false

    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private var baselineSteps: Int?
    private var reportedPedometerSteps = 0
    private var baselineGravity = SIMD3<Double>(0, -1, 0)
    private var calibrationGravitySum = SIMD3<Double>(repeating: 0)
    private var calibrationSampleCount = 0
    private var filteredTiltDegrees = 0.0
    private var stableBellSamples = 0
    private var lastBellTransitionAt = 0.0
    private var bellDetectionPhase = BellDetectionPhase.waitingForDown
    private var isPedometerActive = false
    private var isBellMotionActive = false

    private enum BellDetectionPhase {
        case waitingForDown
        case waitingForUp
    }

    func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else {
            requiresManualStepInput = true
            statusText = "自动不可用"
            return
        }
        baselineSteps = nil
        reportedPedometerSteps = 0
        isPedometerActive = true
        requiresManualStepInput = false
        statusText = "正在计步"
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            guard error == nil, let data else {
                Task { @MainActor in
                    guard self.isPedometerActive else { return }
                    self.requiresManualStepInput = true
                    self.stopPedometer()
                    self.statusText = "自动不可用"
                }
                return
            }
            let total = data.numberOfSteps.intValue
            Task { @MainActor in
                guard self.isPedometerActive else { return }
                if self.baselineSteps == nil {
                    self.baselineSteps = total
                }
                let baseline = self.baselineSteps ?? total
                let delta = max(0, total - baseline)
                if delta > self.reportedPedometerSteps {
                    self.stepPulse += delta - self.reportedPedometerSteps
                    self.reportedPedometerSteps = delta
                }
            }
        }
    }

    func useManualSteps() {
        stopPedometer()
        requiresManualStepInput = false
        statusText = "手动左右脚"
    }

    func stopPedometer() {
        isPedometerActive = false
        pedometer.stopUpdates()
        baselineSteps = nil
        reportedPedometerSteps = 0
        if !requiresManualStepInput { statusText = "动作感应" }
    }

    func prepareBellMotionMode() {
        requiresManualBellInput = false
        statusText = isBellCalibrated ? "已校准 · 可以开始" : "请站直并校准"
    }

    func useManualBell() {
        stopMotion()
        requiresManualBellInput = false
        statusText = "手动下 / 起"
    }

    func beginBellCalibration() {
        stopMotion()
        guard motionManager.isDeviceMotionAvailable else {
            requiresManualBellInput = true
            statusText = "动作感应不可用"
            return
        }

        requiresManualBellInput = false
        isBellCalibrated = false
        isBellCalibrating = true
        calibrationGravitySum = SIMD3<Double>(repeating: 0)
        calibrationSampleCount = 0
        statusText = "站直保持不动…"
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard self.isBellCalibrating else { return }
            guard error == nil, let motion else {
                self.requiresManualBellInput = true
                self.isBellCalibrating = false
                self.statusText = "动作感应不可用"
                self.motionManager.stopDeviceMotionUpdates()
                return
            }

            let gravity = SIMD3(
                motion.gravity.x,
                motion.gravity.y,
                motion.gravity.z
            )
            self.calibrationGravitySum += gravity
            self.calibrationSampleCount += 1
            guard self.calibrationSampleCount >= 30 else { return }

            self.baselineGravity = self.normalized(self.calibrationGravitySum)
            self.isBellCalibrating = false
            self.isBellCalibrated = true
            self.statusText = "校准完成 · 可以开始"
            self.motionManager.stopDeviceMotionUpdates()
            LPHaptics.success()
        }
    }

    func startBellMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            requiresManualBellInput = true
            statusText = "动作感应不可用"
            return
        }
        guard isBellCalibrated else {
            statusText = "请先站直校准"
            return
        }

        motionManager.stopDeviceMotionUpdates()
        bellDetectionPhase = .waitingForDown
        isBellMotionActive = true
        stableBellSamples = 0
        filteredTiltDegrees = 0
        lastBellTransitionAt = ProcessInfo.processInfo.systemUptime
        statusText = "请缓慢下蹲"
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard self.isBellMotionActive else { return }
            guard error == nil, let motion else {
                self.motionManager.stopDeviceMotionUpdates()
                self.isBellMotionActive = false
                self.requiresManualBellInput = true
                self.statusText = "动作感应中断 · 已切到手动"
                return
            }
            self.handleBellMotion(gravity: SIMD3(
                motion.gravity.x,
                motion.gravity.y,
                motion.gravity.z
            ))
        }
    }

    func stopMotion() {
        isBellMotionActive = false
        motionManager.stopDeviceMotionUpdates()
        isBellCalibrating = false
        statusText = isBellCalibrated ? "已校准" : "动作感应"
    }

    private func handleBellMotion(gravity: SIMD3<Double>) {
        let currentGravity = normalized(gravity)
        let dot = (
            currentGravity.x * baselineGravity.x
                + currentGravity.y * baselineGravity.y
                + currentGravity.z * baselineGravity.z
        ).clamped(to: -1...1)
        let tiltDegrees = acos(dot) * 180 / .pi
        filteredTiltDegrees = filteredTiltDegrees * 0.72 + tiltDegrees * 0.28
        let now = ProcessInfo.processInfo.systemUptime

        switch bellDetectionPhase {
        case .waitingForDown:
            stableBellSamples = filteredTiltDegrees >= 11 ? stableBellSamples + 1 : 0
            guard stableBellSamples >= 4, now - lastBellTransitionAt >= 0.55 else { return }
            bellDetectionPhase = .waitingForUp
            stableBellSamples = 0
            lastBellTransitionAt = now
            bellDownPulse += 1
            statusText = "已下蹲 · 请起身"
        case .waitingForUp:
            stableBellSamples = filteredTiltDegrees <= 5 ? stableBellSamples + 1 : 0
            guard stableBellSamples >= 4, now - lastBellTransitionAt >= 0.65 else { return }
            bellDetectionPhase = .waitingForDown
            stableBellSamples = 0
            lastBellTransitionAt = now
            bellUpPulse += 1
            statusText = "已起身 · 请下蹲"
        }
    }

    private func normalized(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0.0001 else { return SIMD3<Double>(0, -1, 0) }
        return vector / length
    }
}
