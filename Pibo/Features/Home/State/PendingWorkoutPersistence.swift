import Foundation
import os

/// Persists the single workout awaiting Home presentation. Invalid payloads
/// are removed immediately so a corrupt value cannot reopen the same sheet on
/// every launch.
@MainActor
enum PendingWorkoutPersistence {
    static func save(
        _ workout: PendingWorkout?,
        defaults: UserDefaults = .standard,
        key: String = PiboPersistenceKeys.Defaults.pendingWorkout
    ) {
        guard let workout else {
            defaults.removeObject(forKey: key)
            return
        }

        do {
            let data = try JSONEncoder().encode(workout)
            defaults.set(data, forKey: key)
        } catch {
            LPLog.petState.error(
                "persistPendingWorkout encode failed: \(error.localizedDescription, privacy: .public) — clearing key"
            )
            defaults.removeObject(forKey: key)
        }
    }

    static func load(
        defaults: UserDefaults = .standard,
        key: String = PiboPersistenceKeys.Defaults.pendingWorkout
    ) -> PendingWorkout? {
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            return try JSONDecoder().decode(PendingWorkout.self, from: data)
        } catch {
            LPLog.petState.error(
                "loadPendingWorkout decode failed: \(error.localizedDescription, privacy: .public) — discarding"
            )
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    static func clear(
        defaults: UserDefaults = .standard,
        key: String = PiboPersistenceKeys.Defaults.pendingWorkout
    ) {
        defaults.removeObject(forKey: key)
    }
}
