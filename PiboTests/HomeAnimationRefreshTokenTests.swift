import Foundation
import SwiftData
import Testing
@testable import Pibo

@MainActor
struct HomeAnimationRefreshTokenTests {
    @Test func storeSnapshotPreservesEveryObservedValue() throws {
        let suite = "HomeAnimationRefreshTokenTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(
            for: HealthDayRecord.self,
            WorkoutRecord.self,
            FoodPhoto.self,
            WalkDoodleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        let store = PetStateStore(demoMode: true)

        let token = HomeAnimationRefreshToken(store: store, history: history)

        #expect(token == HomeAnimationRefreshToken(
            steps: store.rawSteps,
            sleepHours: store.rawSleepHours,
            hasWorkout: store.hasWorkoutToday,
            rmssd: store.rmssd,
            historyRevision: history.revision,
            pendingAchievementID: store.animationExperience.pendingAchievement?.id,
            notificationPresentationRequestID: store.animationExperience
                .notificationPresentationRequestID
        ))
    }
}
