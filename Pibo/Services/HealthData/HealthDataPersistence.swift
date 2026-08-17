import Foundation
import HealthKit
import os

/// Owns the durable launch state used by `HealthDataService`.
///
/// HealthKit does not expose trustworthy read-authorization state, so the
/// authorization flag records only that the system prompt completed once.
/// Workout queries persist their secure-coding anchor separately so later
/// launches resume from the last delivered sample.
@MainActor
enum HealthDataPersistence {
    private static let workoutAnchorKey = PiboPersistenceKeys.Defaults.workoutAnchor
    private static let authorizedKey = PiboPersistenceKeys.Defaults.healthKitAuthorized
    private static let lastReadableDataKey = "pibo.health.last-readable-data.v1"

    static func loadWorkoutAnchor(
        defaults: UserDefaults = .standard
    ) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: workoutAnchorKey) else {
            LPLog.workout.debug("No persisted anchor — first launch path")
            return nil
        }
        do {
            let anchor = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self,
                from: data
            )
            LPLog.workout.debug("Anchor loaded from UserDefaults")
            return anchor
        } catch {
            LPLog.workout.error(
                "Anchor unarchive failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func persistWorkoutAnchor(
        _ anchor: HKQueryAnchor?,
        defaults: UserDefaults = .standard
    ) {
        guard let anchor else {
            defaults.removeObject(forKey: workoutAnchorKey)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: anchor,
                requiringSecureCoding: true
            )
            defaults.set(data, forKey: workoutAnchorKey)
        } catch {
            LPLog.workout.error(
                "Anchor archive failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func authorizationWasGranted(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: authorizedKey)
    }

    static func setAuthorizationGranted(
        _ granted: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(granted, forKey: authorizedKey)
    }

    static func lastReadableDataDate(
        defaults: UserDefaults = .standard
    ) -> Date? {
        guard defaults.object(forKey: lastReadableDataKey) != nil else { return nil }
        let value = defaults.double(forKey: lastReadableDataKey)
        guard value.isFinite, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    static func setLastReadableDataDate(
        _ date: Date,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(date.timeIntervalSince1970, forKey: lastReadableDataKey)
    }
}
