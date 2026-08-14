import Foundation
import Testing
@testable import Pibo

@MainActor
struct PendingWorkoutPersistenceTests {
    @Test func savedWorkoutRoundTripsWithoutChangingItsPayload() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let workout = fixture.workout()

        PendingWorkoutPersistence.save(
            workout,
            defaults: fixture.defaults,
            key: fixture.key
        )

        let restored = PendingWorkoutPersistence.load(
            defaults: fixture.defaults,
            key: fixture.key
        )
        #expect(restored == workout)
    }

    @Test func savingNilAndExplicitClearBothRemoveTheStoredWorkout() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data([0x01]), forKey: fixture.key)

        PendingWorkoutPersistence.save(
            nil,
            defaults: fixture.defaults,
            key: fixture.key
        )
        #expect(fixture.defaults.object(forKey: fixture.key) == nil)

        fixture.defaults.set(Data([0x02]), forKey: fixture.key)
        PendingWorkoutPersistence.clear(
            defaults: fixture.defaults,
            key: fixture.key
        )
        #expect(fixture.defaults.object(forKey: fixture.key) == nil)
    }

    @Test func corruptStoredPayloadIsDiscardedAfterFailedRestore() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data("not-json".utf8), forKey: fixture.key)

        let restored = PendingWorkoutPersistence.load(
            defaults: fixture.defaults,
            key: fixture.key
        )

        #expect(restored == nil)
        #expect(fixture.defaults.object(forKey: fixture.key) == nil)
    }

    @Test func encodingFailureClearsAnyPreviouslyStoredPayload() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data([0x03]), forKey: fixture.key)
        let invalid = fixture.workout(kcal: .infinity)

        PendingWorkoutPersistence.save(
            invalid,
            defaults: fixture.defaults,
            key: fixture.key
        )

        #expect(fixture.defaults.object(forKey: fixture.key) == nil)
    }
}

@MainActor
private final class Fixture {
    let suiteName: String
    let defaults: UserDefaults
    let key = "test.pendingWorkout"

    init() throws {
        let suiteName = "PendingWorkoutPersistenceTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func workout(kcal: Double? = 180) -> PendingWorkout {
        PendingWorkout(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .run,
            label: "跑步",
            durationMin: 24,
            kcal: kcal,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000),
            gainVitality: 20
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
