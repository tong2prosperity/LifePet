import Foundation
import HealthKit

enum WorkoutSessionError: Error {
    case healthDataUnavailable
}

@MainActor
final class WorkoutSessionManager: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    let stream: VitalsStream
    private(set) var current: VitalSession?

    init(stream: VitalsStream = VitalsStream()) {
        self.stream = stream
        super.init()
    }

    private static let readTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.oxygenSaturation),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutSessionError.healthDataUnavailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func start() async throws -> VitalSession {
        try await requestAuthorization()

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        builder.delegate = stream
        session.delegate = self

        self.session = session
        self.builder = builder

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        let vs = VitalSession(startedAt: startDate)
        current = vs
        return vs
    }

    func stop() async throws -> VitalSession? {
        guard let session, let builder, var vs = current else { return nil }
        session.end()
        try await builder.endCollection(at: Date())
        _ = try await builder.finishWorkout()

        vs.endedAt = Date()
        current = vs
        self.session = nil
        self.builder = nil
        return vs
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("[LifePulse watch] workout state: \(fromState.rawValue) -> \(toState.rawValue)")
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[LifePulse watch] workout error: \(error)")
    }
}
