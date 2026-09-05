import Foundation
import os
import PiboCore
import WatchConnectivity

@MainActor
final class PiboCompanionSyncService: NSObject, WCSessionDelegate {
    private var latest: PiboCompanionSnapshot?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publish(
        store: PetStateStore,
        record: HealthDayRecord?,
        shadowView: ShadowStateDTO?,
        now: Date = .now
    ) {
        var moveProgress: Double?
        var exerciseProgress: Double?
        var standProgress: Double?
        if let record, record.moveGoal > 0, record.exerciseGoal > 0, record.standGoal > 0 {
            let value = PiboCoreActivityWater.intensities(
                activeCalories: record.activeEnergy,
                exerciseMinutes: Double(record.exerciseMinutes),
                standHours: Double(record.standMinutes) / 60,
                moveGoal: record.moveGoal,
                exerciseGoal: Double(record.exerciseGoal),
                standGoal: Double(record.standGoal)
            )
            moveProgress = value.move
            exerciseProgress = value.exercise
            standProgress = value.stand
        }
        let state = store.activityState
        let snapshot = PiboCompanionSnapshot(
            schemaVersion: 1,
            petName: String((store.petName.isEmpty ? "Pibo" : store.petName).prefix(24)),
            dayStart: Calendar.current.startOfDay(for: now),
            generatedAt: now,
            publicStateID: state.rawValue,
            animationStateID: TodayPiboShareSnapshot.assetStateID(for: state),
            stateLabel: state.displayName,
            activeEnergy: record.flatMap { $0.activeEnergy > 0 ? $0.activeEnergy : nil },
            exerciseMinutes: record.flatMap { $0.exerciseMinutes > 0 ? $0.exerciseMinutes : nil },
            standHours: record.flatMap { $0.standMinutes > 0 ? $0.standMinutes / 60 : nil },
            moveProgress: moveProgress,
            exerciseProgress: exerciseProgress,
            standProgress: standProgress,
            sceneID: PiboFlatWorldScene.recommended(petName: store.petName),
            shadow: Self.shadowSnapshot(from: shadowView)
        )
        latest = snapshot
        send(snapshot)
    }

    private func send(_ snapshot: PiboCompanionSnapshot) {
        guard WCSession.isSupported(),
              let data = PiboCompanionSnapshotCoding.encode(snapshot) else { return }
        do {
            try WCSession.default.updateApplicationContext([
                PiboCompanionSnapshotCoding.applicationContextKey: data,
            ])
        } catch {
            LPLog.app.debug("watch snapshot deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func shadowSnapshot(from view: ShadowStateDTO?) -> PiboCompanionShadowSnapshot? {
        guard let friend = view?.friend,
              !friend.sharingPaused,
              let value = friend.snapshot,
              value.publicStateId != "dataUnknown" else { return nil }
        return PiboCompanionShadowSnapshot(
            displayName: String(friend.displayName.prefix(24)),
            publicStateID: value.publicStateId,
            publicBehaviorSubstateID: value.publicBehaviorSubstateId,
            visualVariantKey: value.visualVariantKey,
            revision: value.snapshotRevision,
            occurredAt: value.occurredAt,
            syncedAt: value.syncedAt
        )
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard message[PiboCompanionSnapshotCoding.requestKey] != nil,
                  let value = self?.latest,
                  let data = PiboCompanionSnapshotCoding.encode(value) else {
                replyHandler([:]); return
            }
            replyHandler([PiboCompanionSnapshotCoding.applicationContextKey: data])
        }
    }
}
