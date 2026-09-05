import Foundation
import Testing
@testable import Pibo

struct PiboCompanionCacheTests {
    private let now = Date(timeIntervalSince1970: 1_788_400_000)
    private let petID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func crossDayReloadPreservesPetGrowthAndFriendButNotDailyFacts() throws {
        let earlier = now.addingTimeInterval(-172_800)
        let value = makeSnapshot(at: earlier, connection: connection(at: earlier))
        let encoded = try #require(PiboCompanionSnapshotCoding.encode(value))
        let decoded = try #require(PiboCompanionSnapshotCoding.decode(encoded))
        var cache = PiboCompanionCache()
        let didLoad = cache.apply(decoded, now: now)
        #expect(didLoad)
        #expect(cache.snapshot?.petName == "小波")
        #expect(cache.snapshot?.publicStateID == "tired")
        #expect(cache.snapshot?.growth == value.growth)
        #expect(cache.snapshot?.shadowConnection?.snapshot?.syncedAt == earlier)
        #expect(cache.snapshot?.hasCurrentActivity(now: now) == false)
    }

    @Test func unknownHealthPreservesTrustedPresentationAndItsTrueTimeAcrossRelaunch() throws {
        var cache = PiboCompanionCache()
        let earlier = now.addingTimeInterval(-60)
        let didLoad = cache.apply(makeSnapshot(at: earlier), now: now)
        #expect(didLoad)
        var unknown = makeSnapshot(at: now, state: "dataUnknown")
        unknown.healthMessage = "健康同步暂时中断"
        let didApplyUnknown = cache.apply(unknown, now: now)
        #expect(didApplyUnknown)
        #expect(cache.snapshot?.publicStateID == "tired")
        #expect(cache.snapshot?.patActionID == "rest")
        #expect(cache.snapshot?.stateGeneratedAt == earlier)
        #expect(cache.snapshot?.healthMessage == "健康同步暂时中断")

        let retained = try #require(cache.snapshot)
        let data = try #require(PiboCompanionSnapshotCoding.encode(retained))
        let decoded = try #require(PiboCompanionSnapshotCoding.decode(data))
        var restored = PiboCompanionCache()
        let didRestore = restored.apply(decoded, now: now)
        #expect(didRestore)
        #expect(restored.snapshot == cache.snapshot)
    }

    @Test func firstUnknownStateAndNewPetNeverInheritAnotherPetsPresentation() {
        var cache = PiboCompanionCache()
        let didLoadUnknown = cache.apply(makeSnapshot(at: now, state: "dataUnknown"), now: now)
        #expect(didLoadUnknown)
        #expect(cache.snapshot?.publicStateID == "dataUnknown")
        let didApplyKnown = cache.apply(makeSnapshot(at: now.addingTimeInterval(1)), now: now)
        #expect(didApplyKnown)
        var replacement = makeSnapshot(at: now.addingTimeInterval(2), state: "dataUnknown")
        replacement.petID = UUID()
        let didReplacePet = cache.apply(replacement, now: now)
        #expect(didReplacePet)
        #expect(cache.snapshot?.publicStateID == "dataUnknown")
        #expect(cache.snapshot?.patActionID == "checkConnection")
    }

    @Test func pausedAndTemporarilyMissingFriendSnapshotRetainConsentedProjection() {
        let earlier = now.addingTimeInterval(-200_000)
        var cache = PiboCompanionCache()
        let didLoad = cache.apply(makeSnapshot(at: earlier, connection: connection(at: earlier)), now: now)
        #expect(didLoad)
        var paused = connection(at: now, status: .paused)
        paused.snapshot = nil
        let didPause = cache.apply(makeSnapshot(at: now, connection: paused), now: now)
        #expect(didPause)
        #expect(cache.snapshot?.shadowConnection?.status == .paused)
        #expect(cache.snapshot?.shadowConnection?.snapshot?.syncedAt == earlier)
    }

    @Test func invalidOrOlderFriendStateCannotReplaceTheLatestValidRevision() {
        var cache = PiboCompanionCache()
        let retained = connection(at: now.addingTimeInterval(-30), revision: 8)
        let didLoad = cache.apply(makeSnapshot(at: now.addingTimeInterval(-20), connection: retained), now: now)
        #expect(didLoad)
        let invalid = connection(at: now, revision: 9, state: "dataUnknown")
        let didReceiveInvalidFriend = cache.apply(makeSnapshot(at: now, connection: invalid), now: now)
        #expect(didReceiveInvalidFriend)
        #expect(cache.snapshot?.shadowConnection?.snapshot?.revision == 8)
        let didReceiveOlderFriend = cache.apply(makeSnapshot(at: now.addingTimeInterval(1), connection: connection(at: now, revision: 7)), now: now)
        #expect(didReceiveOlderFriend)
        #expect(cache.snapshot?.shadowConnection?.snapshot?.revision == 8)
    }

    @Test(arguments: [PiboCompanionShadowConnection.Status.none, .hidden])
    func explicitRemovalAndHidingClearTheProjection(status: PiboCompanionShadowConnection.Status) {
        var cache = PiboCompanionCache()
        let didLoad = cache.apply(makeSnapshot(at: now, connection: connection(at: now)), now: now)
        #expect(didLoad)
        let removed = connection(at: now, status: status)
        let didRemove = cache.apply(makeSnapshot(at: now.addingTimeInterval(1), connection: removed), now: now)
        #expect(didRemove)
        #expect(cache.snapshot?.shadowConnection?.snapshot == nil)
        #expect(cache.snapshot?.shadowConnection?.status == status)
    }

    @Test func newAccountOrRelationshipCannotInheritOldFriendSnapshot() {
        for nextConnection in [
            connection(at: now, accountID: "account-b"),
            connection(at: now, relationshipID: "relationship-b"),
        ] {
            var cache = PiboCompanionCache()
            let didLoad = cache.apply(makeSnapshot(at: now, connection: connection(at: now)), now: now)
            #expect(didLoad)
            var waiting = nextConnection
            waiting.snapshot = nil
            let didChangeConnection = cache.apply(makeSnapshot(at: now.addingTimeInterval(1), connection: waiting), now: now)
            #expect(didChangeConnection)
            #expect(cache.snapshot?.shadowConnection?.snapshot == nil)
        }
    }

    @Test func lateAndInvalidPacketsCannotPoisonThePersistableSnapshot() {
        var cache = PiboCompanionCache()
        let accepted = makeSnapshot(at: now)
        let didLoad = cache.apply(accepted, now: now)
        #expect(didLoad)
        let didReceiveLate = cache.apply(makeSnapshot(at: now.addingTimeInterval(-1), state: "stable"), now: now)
        #expect(!didReceiveLate)
        let didReceiveFuture = cache.apply(makeSnapshot(at: now.addingTimeInterval(301)), now: now)
        #expect(!didReceiveFuture)
        var badGrowth = makeSnapshot(at: now.addingTimeInterval(1))
        badGrowth.growth = PiboCompanionGrowth(stage: "forming", progress: .infinity, ripeCount: 0)
        let didReceiveBadGrowth = cache.apply(badGrowth, now: now)
        #expect(!didReceiveBadGrowth)
        #expect(cache.snapshot == accepted)
    }

    @Test func ownGrowthAndMinutePrecisionNeverEnterThePublicFriendPayload() throws {
        let value = makeSnapshot(at: now, connection: connection(at: now))
        let data = try #require(PiboCompanionSnapshotCoding.encode(value))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["growth"] != nil)
        #expect(object["standMinutes"] as? Int == 17)
        let friend = try #require(object["shadowConnection"] as? [String: Any])
        let projection = try #require(friend["snapshot"] as? [String: Any])
        for key in ["growth", "bo", "activeEnergy", "standMinutes", "heartRate", "sleep", "readiness", "capabilities"] {
            #expect(projection[key] == nil)
        }
    }

    @Test func phoneProjectionKeepsPausedFriendAndHonorsHiddenOrSignedOutState() {
        let date = now.addingTimeInterval(-200_000)
        let view = ShadowStateDTO(
            state: .activePaused, cursor: 4, serverTime: now, relationshipId: "relationship-a",
            connectedAt: date, mySharingPaused: false, mySnapshotRevision: 2,
            outgoingInvitation: nil,
            friend: ShadowFriendDTO(displayName: "小岚", sharingPaused: true, snapshot: ShadowSnapshotDTO(
                publicStateId: "stable", publicBehaviorSubstateId: "stable.idle",
                visualVariantKey: "pibo-state-stable-forest-idle", snapshotRevision: 3,
                occurredAt: date, syncedAt: date
            )), pendingLight: nil, endedEvent: nil, blockedCount: 0
        )
        let paused = PiboCompanionSyncService.shadowConnection(from: view, accountID: "account-a", hidden: false)
        #expect(paused.status == .paused)
        #expect(paused.snapshot?.syncedAt == date)
        let hidden = PiboCompanionSyncService.shadowConnection(from: view, accountID: "account-a", hidden: true)
        #expect(hidden.status == .hidden)
        #expect(hidden.snapshot == nil)
        #expect(PiboCompanionSyncService.shadowConnection(from: view, accountID: "", hidden: false).status == .none)
    }

    private func makeSnapshot(
        at date: Date, state: String = "tired", connection: PiboCompanionShadowConnection? = nil
    ) -> PiboCompanionSnapshot {
        PiboCompanionSnapshot(
            schemaVersion: 2, petName: "小波", dayStart: Calendar.current.startOfDay(for: date),
            generatedAt: date, publicStateID: state, animationStateID: "pibo-state-\(state)-forest-idle",
            stateLabel: state, activeEnergy: 180, exerciseMinutes: 22, standHours: 0,
            moveProgress: 0.3, exerciseProgress: 0.7, standProgress: 0.4, sceneID: .rainGorge, shadow: nil,
            petID: petID, stateGeneratedAt: date, patActionID: state == "dataUnknown" ? "checkConnection" : "rest",
            growth: PiboCompanionGrowth(stage: "forming", progress: 0.64, ripeCount: 0), capabilities: [],
            healthMessage: nil,
            shadowConnection: connection ?? PiboCompanionShadowConnection(
                status: .none, accountID: "account-a", relationshipID: "", displayName: "", snapshot: nil
            ), standMinutes: 17
        )
    }

    private func connection(
        at date: Date, status: PiboCompanionShadowConnection.Status = .active,
        accountID: String = "account-a", relationshipID: String = "relationship-a",
        revision: Int64 = 3, state: String = "stable"
    ) -> PiboCompanionShadowConnection {
        PiboCompanionShadowConnection(
            status: status, accountID: accountID, relationshipID: relationshipID, displayName: "小岚",
            snapshot: PiboCompanionShadowSnapshot(
                displayName: "小岚", publicStateID: state, publicBehaviorSubstateID: "\(state).idle",
                visualVariantKey: "pibo-state-\(state)-forest-idle", revision: revision,
                occurredAt: date, syncedAt: date
            )
        )
    }
}
