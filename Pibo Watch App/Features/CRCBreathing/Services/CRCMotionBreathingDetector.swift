import CoreMotion
import Foundation

nonisolated private final class CRCBandPassFilter {
    private let lowAlpha: Double
    private let highAlpha: Double
    private var lowState: Double = 0
    private var highState: Double = 0
    private var previousLow: Double = 0
    private var hasValue = false

    init(lowCutoffHz: Double, highCutoffHz: Double, sampleRate: Double) {
        let dt = 1.0 / sampleRate
        let lowRC = 1.0 / (2.0 * .pi * highCutoffHz)
        let highRC = 1.0 / (2.0 * .pi * lowCutoffHz)
        lowAlpha = dt / (lowRC + dt)
        highAlpha = highRC / (highRC + dt)
    }

    func reset() {
        lowState = 0
        highState = 0
        previousLow = 0
        hasValue = false
    }

    func apply(_ input: Double) -> Double {
        if !hasValue {
            lowState = input
            previousLow = input
            hasValue = true
        }

        lowState += lowAlpha * (input - lowState)
        let high = highAlpha * (highState + lowState - previousLow)
        previousLow = lowState
        highState = high
        return high
    }
}

private struct CRCChannelAnalysis {
    var rate: Double
    var phaseProgress: Double
    var amplitude: Double
    var quality: Double
    var score: Double
    var name: String
}

nonisolated private final class CRCMotionChannel {
    let name: String
    let weight: Double
    private let filter = CRCBandPassFilter(
        lowCutoffHz: 0.07,
        highCutoffHz: 0.65,
        sampleRate: CRCConstants.motionSampleRate
    )
    private var values: [Double] = []
    private var times: [TimeInterval] = []
    private let maxSamples = Int(CRCConstants.motionSampleRate * 14)

    init(name: String, weight: Double) {
        self.name = name
        self.weight = weight
    }

    func reset() {
        filter.reset()
        values.removeAll(keepingCapacity: true)
        times.removeAll(keepingCapacity: true)
    }

    func append(rawValue: Double, timestamp: TimeInterval) {
        values.append(filter.apply(rawValue))
        times.append(timestamp)

        if values.count > maxSamples {
            values.removeFirst(values.count - maxSamples)
            times.removeFirst(times.count - maxSamples)
        }
    }

    func analyze() -> CRCChannelAnalysis? {
        guard values.count > Int(CRCConstants.motionSampleRate * 5),
              let lastTime = times.last else { return nil }

        let mean = values.reduce(0, +) / Double(values.count)
        let centered = values.map { $0 - mean }
        let amplitude = robustAmplitude(centered)
        guard amplitude > 0.0008 else { return nil }

        let crossings = risingZeroCrossings(centered: centered)
        guard crossings.count >= 2 else { return nil }

        let periods = zip(crossings, crossings.dropFirst()).map { previous, next in
            times[next] - times[previous]
        }.filter { period in
            let rate = 60.0 / period
            return rate >= CRCConstants.minimumMeasuredBreathingRate
                && rate <= CRCConstants.maximumMeasuredBreathingRate
        }
        guard !periods.isEmpty else { return nil }

        let averagePeriod = periods.reduce(0, +) / Double(periods.count)
        let variance = periods
            .map { pow($0 - averagePeriod, 2) }
            .reduce(0, +) / Double(periods.count)
        let coefficientOfVariation = averagePeriod > 0 ? sqrt(variance) / averagePeriod : 1
        let stability = (1.0 - coefficientOfVariation / 0.35).crcClampedUnit
        let amplitudeScore = min(1.0, amplitude / 0.018)
        let quality = (0.65 * stability + 0.35 * amplitudeScore).crcClampedUnit
        let rate = 60.0 / averagePeriod

        let lastCrossingIndex = crossings.last ?? 0
        let elapsed = max(0, lastTime - times[lastCrossingIndex])
        let phaseProgress = min(1, elapsed / averagePeriod)

        return CRCChannelAnalysis(
            rate: rate,
            phaseProgress: phaseProgress,
            amplitude: amplitude,
            quality: quality,
            score: quality * amplitude * weight,
            name: name
        )
    }

    private func robustAmplitude(_ centered: [Double]) -> Double {
        let sorted = centered.sorted()
        guard sorted.count > 10 else { return 0 }
        let lowIndex = max(0, Int(Double(sorted.count - 1) * 0.1))
        let highIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.9))
        return (sorted[highIndex] - sorted[lowIndex]) / 2
    }

    private func risingZeroCrossings(centered: [Double]) -> [Int] {
        var crossings: [Int] = []
        for index in 1..<centered.count {
            if centered[index - 1] <= 0, centered[index] > 0 {
                crossings.append(index)
            }
        }
        return crossings
    }
}

nonisolated final class CRCMotionBreathingDetector {
    typealias UpdateHandler = @Sendable (CRCBreathReading?, CRCPoseAssessment) -> Void

    nonisolated(unsafe) var onUpdate: UpdateHandler?

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "fun.tiebao.pibo.crc.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let channels: [CRCMotionChannel] = [
        CRCMotionChannel(name: "倾斜 X", weight: 1.25),
        CRCMotionChannel(name: "倾斜 Y", weight: 1.25),
        CRCMotionChannel(name: "线性 Z", weight: 1.0),
        CRCMotionChannel(name: "转动 X", weight: 0.95),
        CRCMotionChannel(name: "转动 Y", weight: 0.95),
    ]

    private var baselineAmplitude: Double?
    private var latestAssessment = CRCPoseAssessment(
        poseConfidence: 0,
        orientationConfidence: 0,
        stillnessConfidence: 0,
        breathingSignalQuality: 0,
        isLikelyPlaced: false,
        guidance: "将手腕自然贴近胸腹部"
    )
    private var lastPublishTimestamp: TimeInterval = 0

    var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    @discardableResult
    func start() -> Bool {
        guard motionManager.isDeviceMotionAvailable else {
            publish(reading: nil, assessment: latestAssessment)
            return false
        }

        channels.forEach { $0.reset() }
        baselineAmplitude = nil
        lastPublishTimestamp = 0
        motionManager.deviceMotionUpdateInterval = 1.0 / CRCConstants.motionSampleRate
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: motionQueue
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }

        return true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func process(_ motion: CMDeviceMotion) {
        let timestamp = motion.timestamp
        let rawValues = [
            motion.gravity.x,
            motion.gravity.y,
            motion.userAcceleration.z,
            motion.rotationRate.x * 0.06,
            motion.rotationRate.y * 0.06,
        ]

        for (channel, rawValue) in zip(channels, rawValues) {
            channel.append(rawValue: rawValue, timestamp: timestamp)
        }

        guard timestamp - lastPublishTimestamp >= 0.5 else { return }
        lastPublishTimestamp = timestamp

        let analyses = channels.compactMap { $0.analyze() }
        let best = analyses.max { $0.score < $1.score }
        let signalQuality = best?.quality ?? 0
        let assessment = assessPose(motion: motion, signalQuality: signalQuality)
        latestAssessment = assessment

        guard let best else {
            publish(reading: nil, assessment: assessment)
            return
        }

        if baselineAmplitude == nil, assessment.poseConfidence > 0.62, best.quality > 0.35 {
            baselineAmplitude = max(best.amplitude, 0.001)
        } else if let baseline = baselineAmplitude, best.quality > 0.45 {
            baselineAmplitude = baseline * 0.96 + max(best.amplitude, 0.001) * 0.04
        }

        let amplitudeReference = max(baselineAmplitude ?? best.amplitude, 0.001)
        let amplitudeScore = min(1.4, best.amplitude / amplitudeReference)
        let reading = CRCBreathReading(
            breathsPerMinute: best.rate,
            phaseProgress: best.phaseProgress,
            amplitude: best.amplitude,
            amplitudeScore: amplitudeScore,
            signalQuality: best.quality,
            selectedChannel: best.name,
            timestamp: Date()
        )

        publish(reading: reading, assessment: assessment)
    }

    private func assessPose(
        motion: CMDeviceMotion,
        signalQuality: Double
    ) -> CRCPoseAssessment {
        let gravity = motion.gravity
        let acceleration = motion.userAcceleration
        let rotation = motion.rotationRate

        let faceUp = ((-gravity.z - 0.45) / 0.45).crcClampedUnit
        let tiltPenalty = min(1, hypot(gravity.x, gravity.y) / 0.85)
        let orientation = (faceUp * (1 - tiltPenalty * 0.25)).crcClampedUnit

        let accelerationMagnitude = sqrt(
            acceleration.x * acceleration.x
            + acceleration.y * acceleration.y
            + acceleration.z * acceleration.z
        )
        let rotationMagnitude = sqrt(
            rotation.x * rotation.x
            + rotation.y * rotation.y
            + rotation.z * rotation.z
        )
        let accelerationStillness = (1.0 - accelerationMagnitude / 0.20).crcClampedUnit
        let rotationStillness = (1.0 - rotationMagnitude / 0.75).crcClampedUnit
        let stillness = (0.55 * accelerationStillness + 0.45 * rotationStillness).crcClampedUnit

        let poseConfidence = (
            0.42 * orientation
            + 0.28 * stillness
            + 0.30 * signalQuality
        ).crcClampedUnit

        let guidance: String
        if orientation < 0.45 {
            guidance = "表盘朝上，手腕贴近胸腹部"
        } else if stillness < 0.45 {
            guidance = "手腕保持稳定，放松肩膀"
        } else if signalQuality < 0.30 {
            guidance = "呼吸信号较弱，轻贴腹部"
        } else {
            guidance = "姿势稳定，继续自然呼吸"
        }

        return CRCPoseAssessment(
            poseConfidence: poseConfidence,
            orientationConfidence: orientation,
            stillnessConfidence: stillness,
            breathingSignalQuality: signalQuality,
            isLikelyPlaced: poseConfidence > 0.60 && signalQuality > 0.28,
            guidance: guidance
        )
    }

    private func publish(reading: CRCBreathReading?, assessment: CRCPoseAssessment) {
        onUpdate?(reading, assessment)
    }
}
