import Foundation

/// The presentation-only projection used by the in-world 状态观测仪.
/// Deterministic scoring stays in PiboCore; this type only formats persisted
/// results for the forest UI and keeps a measured zero distinct from no result.
struct WellnessInstrumentData: Equatable {
    struct Score: Equatable {
        let value: Double
        let confidenceLevel: Int32
        let baselineDays: Int
    }

    let generatedAt: Date?
    let algorithmVersion: UInt32?
    let sleep: Score?
    let recovery: Score?
    let activity: Score?
    let sleepDebtMinutes: Double?
    let acuteTrainingLoad: Double?
    let chronicTrainingLoad: Double?
    let trainingBalanceStatus: Int32?
    let recoveryIndexScore: Double?
    let resilience: Score?
    let resilienceObservedDays: Int

    init(record: HealthDayRecord?) {
        let snapshot = record?.wellnessSnapshot
        let hasObservedTraining = (snapshot?.acuteTrainingObservedDays ?? 0) > 0
            || (snapshot?.chronicTrainingObservedDays ?? 0) > 0
        generatedAt = snapshot?.generatedAt
        algorithmVersion = snapshot?.algorithmVersion
        sleep = snapshot?.sleepScore.map(Self.score)
        recovery = snapshot?.recoveryScore.map(Self.score)
        activity = snapshot?.activityScore.map(Self.score)
        sleepDebtMinutes = snapshot?.sleepDebtMinutes
        acuteTrainingLoad = snapshot.flatMap {
            ($0.acuteTrainingObservedDays ?? 0) > 0 ? $0.acuteTrainingLoad : nil
        }
        chronicTrainingLoad = snapshot.flatMap {
            ($0.chronicTrainingObservedDays ?? 0) > 0 ? $0.chronicWeeklyTrainingLoad : nil
        }
        trainingBalanceStatus = hasObservedTraining ? snapshot?.trainingBalanceStatus : nil
        recoveryIndexScore = record?.recoveryIndexScore
        resilience = snapshot?.resilienceScore.map(Self.score)
        resilienceObservedDays = snapshot?.resilienceObservedDays ?? 0
    }

    private static func score(_ snapshot: DailyWellnessScoreSnapshot) -> Score {
        Score(
            value: snapshot.value,
            confidenceLevel: snapshot.confidenceLevel,
            baselineDays: snapshot.baselineDays
        )
    }

    #if DEBUG
    static let preview = WellnessInstrumentData(
        generatedAt: .now,
        algorithmVersion: 1,
        sleep: Score(value: 78, confidenceLevel: 3, baselineDays: 18),
        recovery: Score(value: 71, confidenceLevel: 2, baselineDays: 12),
        activity: Score(value: 64, confidenceLevel: 3, baselineDays: 21),
        sleepDebtMinutes: 82,
        acuteTrainingLoad: 236,
        chronicTrainingLoad: 198,
        trainingBalanceStatus: 5,
        recoveryIndexScore: 76,
        resilience: Score(value: 68, confidenceLevel: 2, baselineDays: 11),
        resilienceObservedDays: 11
    )
    #endif

    private init(
        generatedAt: Date?,
        algorithmVersion: UInt32?,
        sleep: Score?,
        recovery: Score?,
        activity: Score?,
        sleepDebtMinutes: Double?,
        acuteTrainingLoad: Double?,
        chronicTrainingLoad: Double?,
        trainingBalanceStatus: Int32?,
        recoveryIndexScore: Double?,
        resilience: Score?,
        resilienceObservedDays: Int
    ) {
        self.generatedAt = generatedAt
        self.algorithmVersion = algorithmVersion
        self.sleep = sleep
        self.recovery = recovery
        self.activity = activity
        self.sleepDebtMinutes = sleepDebtMinutes
        self.acuteTrainingLoad = acuteTrainingLoad
        self.chronicTrainingLoad = chronicTrainingLoad
        self.trainingBalanceStatus = trainingBalanceStatus
        self.recoveryIndexScore = recoveryIndexScore
        self.resilience = resilience
        self.resilienceObservedDays = resilienceObservedDays
    }
}
