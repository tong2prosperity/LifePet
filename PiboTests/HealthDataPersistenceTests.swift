import Foundation
import HealthKit
import Testing
@testable import Pibo

@MainActor
struct HealthDataPersistenceTests {
    @Test func authorizationFlagRoundTripsBothValues() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }

        #expect(!HealthDataPersistence.authorizationWasGranted(defaults: fixture.defaults))

        HealthDataPersistence.setAuthorizationGranted(true, defaults: fixture.defaults)
        #expect(HealthDataPersistence.authorizationWasGranted(defaults: fixture.defaults))

        HealthDataPersistence.setAuthorizationGranted(false, defaults: fixture.defaults)
        #expect(!HealthDataPersistence.authorizationWasGranted(defaults: fixture.defaults))
    }

    @Test func workoutAnchorRoundTripsAndNilRemovesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }

        #expect(HealthDataPersistence.loadWorkoutAnchor(defaults: fixture.defaults) == nil)

        HealthDataPersistence.persistWorkoutAnchor(
            HKQueryAnchor(fromValue: 42),
            defaults: fixture.defaults
        )
        #expect(HealthDataPersistence.loadWorkoutAnchor(defaults: fixture.defaults) != nil)

        HealthDataPersistence.persistWorkoutAnchor(nil, defaults: fixture.defaults)
        #expect(HealthDataPersistence.loadWorkoutAnchor(defaults: fixture.defaults) == nil)
    }

    private func makeFixture() throws -> (suite: String, defaults: UserDefaults) {
        let suite = "health-data-persistence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (suite, defaults)
    }
}
