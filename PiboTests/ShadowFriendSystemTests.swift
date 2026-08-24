import Foundation
import Testing
@testable import Pibo

@MainActor
@Suite(.serialized)
struct ShadowFriendSystemTests {
    @Test func inviteURLsAndShortCredentialsReachOnePreviewSeam() {
        let service = ShadowService()

        #expect(service.handleInviteURL(URL(string: "pibo://shadow/invite/AB12CD34EF")!))
        #expect(service.incomingCredential == "AB12CD34EF")

        #expect(service.handleInviteURL(URL(string: "https://pibo.example/shadow/invite/ZX98YU76TR")!))
        #expect(service.incomingCredential == "ZX98YU76TR")
        #expect(!service.handleInviteURL(URL(string: "https://pibo.example/not-shadow/ZX98YU76TR")!))
    }

    @Test func accountCacheStripsCredentialsAndPendingEvents() throws {
        let fixture = DefaultsFixture()
        let store = ShadowFriendStore(defaults: fixture.defaults)
        _ = store.activate(userID: "user-a")
        let source = state(
            relationshipID: "relationship-a",
            pendingLight: light(id: "light-a"),
            outgoingInvitation: invitation(id: "invite-a")
        )

        store.applyServerView(source)
        let cached = store.activate(userID: "user-a")

        #expect(cached?.friend?.displayName == "小岚")
        #expect(cached?.pendingLight == nil)
        #expect(cached?.outgoingInvitation == nil)
        #expect(cached?.endedEvent == nil)
    }

    @Test func snapshotRevisionIsMonotonicAndSignatureDedupes() {
        let fixture = DefaultsFixture()
        let store = ShadowFriendStore(defaults: fixture.defaults)
        _ = store.activate(userID: "user-a")
        let view = state(relationshipID: "relationship-a")
        store.applyServerView(view)
        let draft = ShadowSnapshotDraft(
            displayName: "FISH",
            publicStateId: "stable",
            publicBehaviorSubstateId: "stable.idle",
            visualVariantKey: PiboAnimationResourceID.stable,
            occurredAt: .now
        )

        let first = store.snapshotRequest(view: view, draft: draft)
        #expect(first?.snapshotRevision == 1)
        if let first { store.confirmSnapshot(first) }
        #expect(store.snapshotRequest(view: view, draft: draft) == nil)
        #expect(store.snapshotRequest(view: view, draft: draft, force: true)?.snapshotRevision == 2)
    }

    @Test func lightQueueIsLatestOnlyExpiringAndAccountIsolated() {
        let fixture = DefaultsFixture()
        let store = ShadowFriendLightStore(defaults: fixture.defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.activate(userID: "user-a", now: now)
        #expect(store.enqueue(id: "one", senderName: " 小岚 ", receivedAt: now))
        #expect(store.enqueue(id: "two", senderName: "阿禾", receivedAt: now.addingTimeInterval(2)))
        #expect(store.presentable(now: now.addingTimeInterval(3))?.id == "two")
        #expect(store.presentable(now: now.addingTimeInterval(PendingShadowFriendLight.ttl + 3)) == nil)

        #expect(store.enqueue(id: "three", senderName: "小岚", receivedAt: now))
        store.activate(userID: "user-b", now: now)
        #expect(store.pending == nil)
        store.activate(userID: "user-a", now: now)
        #expect(store.pending?.id == "three")
    }

    @Test func unknownHealthStateNeverBecomesPublicSnapshot() {
        let draft = ShadowSnapshotValues.makeDraft(
            ownerName: "FISH",
            state: .dataUnknown,
            decision: nil,
            animationStateID: PiboAnimationResourceID.stable,
            occurredAt: nil,
            hasHammock: false
        )
        #expect(draft == nil)
    }

    @Test func publicStateCopyIsDirectAndUnknownStatesStayNeutral() {
        #expect(ShadowFriendPresentationValues.stateSentence("sleeping") == "正在睡觉")
        #expect(ShadowFriendPresentationValues.stateSentence("energetic") == "有精神，正在活动")
        #expect(ShadowFriendPresentationValues.stateSentence("future_state") == "状态平稳")
    }

    @Test func updateAgeUsesTheServerSyncTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ShadowSnapshotDTO(
            publicStateId: "stable",
            publicBehaviorSubstateId: "stable.idle",
            visualVariantKey: PiboAnimationResourceID.stable,
            snapshotRevision: 2,
            occurredAt: now.addingTimeInterval(-600),
            syncedAt: now.addingTimeInterval(-125)
        )
        #expect(ShadowFriendPresentationValues.relativeUpdate(snapshot, now: now) == "2 分钟前更新")
    }

    @Test func unknownVisualVariantFallsBackToItsPublicState() {
        #expect(ShadowSnapshotValues.renderableStateID("future.variant", publicStateID: "tired")
            == PiboAnimationStateMap.ambientStateID(for: .tired))
    }

    private func state(
        relationshipID: String,
        pendingLight: ShadowLightDTO? = nil,
        outgoingInvitation: ShadowInvitationDTO? = nil
    ) -> ShadowStateDTO {
        ShadowStateDTO(
            state: .activeFresh,
            cursor: 8,
            serverTime: .now,
            relationshipId: relationshipID,
            connectedAt: .now.addingTimeInterval(-60),
            mySharingPaused: false,
            mySnapshotRevision: 0,
            outgoingInvitation: outgoingInvitation,
            friend: ShadowFriendDTO(
                displayName: "小岚",
                sharingPaused: false,
                snapshot: ShadowSnapshotDTO(
                    publicStateId: "stable",
                    publicBehaviorSubstateId: "stable.idle",
                    visualVariantKey: PiboAnimationResourceID.stable,
                    snapshotRevision: 3,
                    occurredAt: .now.addingTimeInterval(-30),
                    syncedAt: .now.addingTimeInterval(-20)
                )
            ),
            pendingLight: pendingLight,
            endedEvent: nil,
            blockedCount: 0
        )
    }

    private func invitation(id: String) -> ShadowInvitationDTO {
        ShadowInvitationDTO(
            id: id,
            displayName: "FISH",
            inviteUrl: "https://pibo.example/shadow/invite/TOKEN",
            token: "TOKEN",
            shortCode: "AB12CD34EF",
            expiresAt: .now.addingTimeInterval(72 * 3600)
        )
    }

    private func light(id: String) -> ShadowLightDTO {
        ShadowLightDTO(
            id: id,
            senderName: "小岚",
            createdAt: .now,
            expiresAt: .now.addingTimeInterval(PendingShadowFriendLight.ttl)
        )
    }
}

private struct DefaultsFixture {
    let suiteName = "ShadowFriendSystemTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }
}
