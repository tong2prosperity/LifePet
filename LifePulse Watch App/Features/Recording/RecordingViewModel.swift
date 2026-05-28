import Foundation
import Observation

@MainActor
@Observable
final class RecordingViewModel {
    var session: VitalSession?
    var latestSnapshot: VitalSnapshot?
    var errorMessage: String?

    private let workout = WorkoutSessionManager()
    private let sender = WatchConnectivitySender.shared
    private var hrv = HRVCalculator()
    private var pending: [VitalSample] = []
    private var flushTask: Task<Void, Never>?

    private static let flushInterval: Duration = .seconds(2)

    var latestHeartRate: Double? { latestSnapshot?.first(of: .heartRate)?.value }
    var latestSpO2: Double? { latestSnapshot?.first(of: .spo2)?.value }
    var latestHRV: Double? { latestSnapshot?.first(of: .hrv)?.value }

    init() {}

    func start() async {
        do {
            workout.stream.onSamples = { [weak self] samples in
                Task { @MainActor [weak self] in
                    self?.ingest(samples)
                }
            }
            let session = try await workout.start()
            self.session = session
            sender.send(.sessionStarted(session))

            flushTask?.cancel()
            flushTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.flushInterval)
                    self?.flush()
                }
            }
        } catch {
            errorMessage = String(describing: error)
            print("[Pibo watch] start failed: \(error)")
        }
    }

    func stop() async {
        flushTask?.cancel()
        flushTask = nil
        flush()

        do {
            if let finished = try await workout.stop(), let endedAt = finished.endedAt {
                sender.send(.sessionEnded(sessionID: finished.id, endedAt: endedAt))
                session = finished
            }
        } catch {
            errorMessage = String(describing: error)
            print("[Pibo watch] stop failed: \(error)")
        }
    }

    private func ingest(_ samples: [VitalSample]) {
        for sample in samples {
            pending.append(sample)
            if sample.kind == .heartRate, sample.value > 0 {
                // Pseudo RR interval derived from HR — rough HRV proxy until we wire HKHeartbeatSeriesQuery.
                hrv.append(60_000 / sample.value)
                if let rmssd = hrv.rmssd {
                    pending.append(VitalSample(
                        kind: .hrv,
                        value: rmssd,
                        unit: "ms",
                        timestamp: sample.timestamp
                    ))
                }
            }
        }
    }

    private func flush() {
        guard let session, !pending.isEmpty else { return }
        let snapshot = VitalSnapshot(sessionID: session.id, samples: pending)
        pending.removeAll(keepingCapacity: true)
        latestSnapshot = snapshot
        sender.send(.snapshot(snapshot))
    }
}
