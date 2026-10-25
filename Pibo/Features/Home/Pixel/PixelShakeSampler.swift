import CoreMotion
import Foundation

/// Samples the accelerometer while the pixel stage is on screen (decision 062's shake).
///
/// HarmonyOS subscribes to `SensorId.ACCELEROMETER` at 100 ms inside `PixelStage` and hands
/// each peak to `HomeGrowthController.onShake`, which asks Core whether it counted. iOS has
/// no stage-managed sensor, so the view owns this sampler for as long as it is visible and
/// forwards the same peaks; the decision stays in Core.
///
/// The simulator has no accelerometer, so `start` is a no-op there.
final class PixelShakeSampler {
    /// One sample every 100 ms, like `SHAKE_SAMPLE_NS` in `pixel/PixelStage.ets`.
    private static let interval: TimeInterval = 0.1

    private let manager = CMMotionManager()
    private var running = false

    func start(_ onPeak: @escaping @MainActor (Double) -> Void) {
        guard !running, manager.isAccelerometerAvailable else { return }
        running = true
        manager.accelerometerUpdateInterval = Self.interval
        manager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let data else { return }
            let a = data.acceleration
            let peak = Self.peakMetersPerSecondSquared(x: a.x, y: a.y, z: a.z)
            Task { @MainActor in onPeak(peak) }
        }
    }

    /// Core/Harmony use m/s²; CoreMotion reports multiples of standard gravity.
    nonisolated static func peakMetersPerSecondSquared(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot() * 9.80665
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopAccelerometerUpdates()
    }

    deinit {
        if running { manager.stopAccelerometerUpdates() }
    }
}
