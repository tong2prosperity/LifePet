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
        shadowAccountID: String,
        shadowHidden: Bool,
        ledger: BoLedgerStore,
        unlocks: OrnamentUnlockStore,
        availability: HealthDataService.DataAvailability,
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
        let hasHammock = unlocks.grants(.sleepReview)
        let animationID = PiboAnimationStateMap.presentedAmbientStateID(
            semanticStateID: PiboCoreAnimationAdapter.ambientStateID(for: state),
            state: state,
            hasHammock: hasHammock
        )
        let snapshot = PiboCompanionSnapshot(
            schemaVersion: 2,
            petName: String((store.petName.isEmpty ? "Pibo" : store.petName).prefix(24)),
            dayStart: Calendar.current.startOfDay(for: now),
            generatedAt: now,
            publicStateID: state.rawValue,
            animationStateID: animationID,
            stateLabel: state.displayName,
            activeEnergy: record.flatMap { $0.activeEnergy > 0 ? $0.activeEnergy : nil },
            exerciseMinutes: record.flatMap { $0.exerciseMinutes > 0 ? $0.exerciseMinutes : nil },
            standHours: record.flatMap { $0.standMinutes > 0 ? $0.standMinutes / 60 : nil },
            moveProgress: moveProgress,
            exerciseProgress: exerciseProgress,
            standProgress: standProgress,
            sceneID: PiboFlatWorldScene.recommended(petName: store.petName),
            shadow: nil,
            petID: store.identity.currentPetId,
            stateGeneratedAt: now,
            patActionID: PiboCoreAnimationAdapter.contextualAction(for: state).rawValue,
            growth: PiboCompanionGrowth(
                stage: Self.growthStageID(ledger.growthStage),
                progress: ledger.growthProgress,
                ripeCount: ledger.state.ripeCount
            ),
            capabilities: Self.capabilities(unlocks),
            healthMessage: Self.healthMessage(availability),
            shadowConnection: Self.shadowConnection(
                from: shadowView, accountID: shadowAccountID, hidden: shadowHidden
            ),
            standMinutes: record.flatMap { $0.standMinutes > 0 ? $0.standMinutes : nil }
        )
        latest = snapshot
        send(snapshot)
    }

    private func send(_ snapshot: PiboCompanionSnapshot) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled,
              let data = PiboCompanionSnapshotCoding.encode(snapshot) else { return }
        do {
            try WCSession.default.updateApplicationContext([
                PiboCompanionSnapshotCoding.applicationContextKey: data,
            ])
        } catch {
            LPLog.app.debug("watch snapshot deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func shadowConnection(
        from view: ShadowStateDTO?, accountID: String, hidden: Bool
    ) -> PiboCompanionShadowConnection {
        guard !accountID.isEmpty, let view, view.state.isActive,
              let relationshipID = view.relationshipId, !relationshipID.isEmpty else {
            return PiboCompanionShadowConnection(
                status: .none, accountID: accountID, relationshipID: "", displayName: "", snapshot: nil
            )
        }
        let friend = view.friend
        let trimmedName = friend?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = String((trimmedName.isEmpty ? "远方的 Pibo" : trimmedName).prefix(24))
        let snapshot = friend?.snapshot.map { value in
            PiboCompanionShadowSnapshot(
                displayName: name,
                publicStateID: value.publicStateId,
                publicBehaviorSubstateID: value.publicBehaviorSubstateId,
                visualVariantKey: value.visualVariantKey,
                revision: value.snapshotRevision,
                occurredAt: value.occurredAt,
                syncedAt: value.syncedAt
            )
        }
        return PiboCompanionShadowConnection(
            status: hidden ? .hidden : friend?.sharingPaused == true ? .paused : snapshot == nil ? .waiting : .active,
            accountID: accountID,
            relationshipID: relationshipID,
            displayName: name,
            snapshot: hidden ? nil : snapshot
        )
    }

    private static func growthStageID(_ stage: PiboCoreBoGrowthStage) -> String {
        switch stage {
        case .dormant: "dormant"
        case .sprouting: "sprouting"
        case .forming: "forming"
        case .ripe: "ripe"
        }
    }

    private static func capabilities(_ unlocks: OrnamentUnlockStore) -> [PiboCompanionCapability] {
        PiboOrnament.ordered.compactMap { ornament in
            let capability: PiboCoreUnlockableCapability
            let detail: String
            switch ornament.id {
            case .hammock: (capability, detail) = (.sleepReview, "会使用吊床，和你回看睡眠")
            case .statusObserver: (capability, detail) = (.recoveryStatus, "能和你一起查看个人准备度")
            case .chime: (capability, detail) = (.walkEchoCollection, "能收藏并重播散步回声")
            case .lantern: (capability, detail) = (.lanternLighting, "能点亮森林里的共光声景")
            }
            guard unlocks.grants(capability) else { return nil }
            return PiboCompanionCapability(id: ornament.id.rawValue, title: ornament.localizedName, detail: detail)
        }
    }

    private static func healthMessage(_ availability: HealthDataService.DataAvailability) -> String? {
        switch availability {
        case .available: nil
        case .checking: "iPhone 正在读取健康数据"
        case .needsAuthorization: "请在 iPhone 的 Pibo 中连接健康数据"
        case .unavailable: "iPhone 暂时无法读取健康数据"
        case .noReadableData: "还没有可读取的健康记录，Pibo 会继续等你"
        case .temporarilyInterrupted: "健康同步暂时中断，保留最近可信的状态"
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            guard let self, let latest = self.latest else { return }
            self.send(latest)
        }
    }

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
