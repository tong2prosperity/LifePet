import Foundation

nonisolated struct PiboCompanionShadowSnapshot: Codable, Equatable, Sendable {
    let displayName: String
    let publicStateID: String
    let publicBehaviorSubstateID: String
    let visualVariantKey: String
    let revision: Int64
    let occurredAt: Date
    let syncedAt: Date

    func isAcceptable(now: Date = .now) -> Bool {
        Self.publicStateIDs.contains(publicStateID)
            && !publicBehaviorSubstateID.isEmpty
            && publicBehaviorSubstateID.count <= 80
            && !visualVariantKey.isEmpty
            && visualVariantKey.count <= 160
            && !displayName.isEmpty
            && displayName.count <= 24
            && revision >= 0
            && occurredAt.timeIntervalSince1970.isFinite
            && syncedAt.timeIntervalSince1970.isFinite
            && occurredAt <= now.addingTimeInterval(300)
            && syncedAt <= now.addingTimeInterval(300)
    }

    private static let publicStateIDs: Set<String> = [
        "sleeping", "waking", "stable", "energetic", "tired",
    ]
}

/// A projection to the owner's paired watch. Own growth is deliberately separate
/// from Shadow's public, consented state; it is never included in a friend snapshot.
nonisolated struct PiboCompanionSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let petName: String
    let dayStart: Date
    let generatedAt: Date
    var publicStateID: String
    var animationStateID: String
    var stateLabel: String
    let activeEnergy: Double?
    let exerciseMinutes: Int?
    let standHours: Int?
    let moveProgress: Double?
    let exerciseProgress: Double?
    let standProgress: Double?
    let sceneID: PiboFlatWorldScene
    let shadow: PiboCompanionShadowSnapshot?

    // The new watch can still decode stored v1 snapshots from an older phone.
    var petID: UUID?
    var stateGeneratedAt: Date?
    var patActionID: String?
    var growth: PiboCompanionGrowth?
    var capabilities: [PiboCompanionCapability]?
    var healthMessage: String?
    var shadowConnection: PiboCompanionShadowConnection?
    var standMinutes: Int?
    /// Optional v2 extension; old watch/phone snapshots continue to decode.
    var pixel: PiboCompanionPixelState? = nil

    func isAcceptable(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard (1...2).contains(schemaVersion),
              Self.publicStateIDs.contains(publicStateID),
              !petName.isEmpty, petName.count <= 24,
              !stateLabel.isEmpty, stateLabel.count <= 24,
              !animationStateID.isEmpty, animationStateID.count <= 160,
              generatedAt.timeIntervalSince1970.isFinite,
              dayStart.timeIntervalSince1970.isFinite,
              generatedAt <= now.addingTimeInterval(300),
              stateGeneratedAt.map({ $0.timeIntervalSince1970.isFinite && $0 <= now.addingTimeInterval(300) }) ?? true,
              growth.map({ $0.isAcceptable }) ?? true,
              pixel.map({ $0.isAcceptable }) ?? true,
              capabilities.map({ $0.count <= 16 && $0.allSatisfy(\.isAcceptable) }) ?? true,
              healthMessage.map({ $0.count <= 200 }) ?? true,
              patActionID.map({ Self.patActionIDs.contains($0) }) ?? true,
              shadowConnection.map({ $0.isAcceptable }) ?? true,
              Self.isValidFact(activeEnergy),
              Self.isValidFact(exerciseMinutes.map(Double.init)),
              Self.isValidFact(standHours.map(Double.init)),
              Self.isValidFact(standMinutes.map(Double.init)),
              Self.isValidProgress(moveProgress),
              Self.isValidProgress(exerciseProgress),
              Self.isValidProgress(standProgress) else { return false }
        return schemaVersion == 1 || (petID != nil && shadowConnection != nil)
    }

    /// Daily facts expire independently of pet identity, growth and relationships.
    func hasCurrentActivity(now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(dayStart, inSameDayAs: now)
            && now.timeIntervalSince(generatedAt) <= 86_400
    }

    private static let publicStateIDs: Set<String> = [
        "dataUnknown", "sleeping", "waking", "stable", "energetic", "tired",
    ]

    private static let patActionIDs: Set<String> = [
        "checkConnection", "letSleep", "morningGreeting", "checkIn", "play", "rest",
    ]

    private static func isValidFact(_ value: Double?) -> Bool {
        value.map { $0.isFinite && $0 >= 0 } ?? true
    }

    private static func isValidProgress(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...1).contains($0) } ?? true
    }
}

nonisolated struct PiboCompanionGrowth: Codable, Equatable, Sendable {
    /// All three values come from the phone's Core-backed ledger, never taps.
    let stage: String
    let progress: Double
    let ripeCount: Int

    var isAcceptable: Bool {
        ["dormant", "sprouting", "forming", "ripe"].contains(stage)
            && progress.isFinite && (0...1).contains(progress) && ripeCount >= 0
    }
}

nonisolated struct PiboCompanionCapability: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String

    var isAcceptable: Bool {
        !id.isEmpty && id.count <= 80 && !title.isEmpty && title.count <= 40 && detail.count <= 160
    }
}

nonisolated struct PiboCompanionShadowConnection: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case none, hidden, waiting, active, paused }
    let status: Status
    let accountID: String
    let relationshipID: String
    let displayName: String
    var snapshot: PiboCompanionShadowSnapshot?

    var isAcceptable: Bool {
        guard accountID.count <= 160, relationshipID.count <= 160, displayName.count <= 24 else { return false }
        switch status {
        case .none, .hidden: return true
        case .waiting, .active, .paused:
            return !accountID.isEmpty && !relationshipID.isEmpty && !displayName.isEmpty
        }
    }
}

nonisolated enum PiboCompanionSnapshotCoding {
    static let applicationContextKey = "pibo.companion.snapshot.v1"
    static let requestKey = "pibo.companion.request.v1"
    static let collectKey = "pibo.companion.collect.v1"

    static func encode(_ value: PiboCompanionSnapshot) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode(_ data: Data?) -> PiboCompanionSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PiboCompanionSnapshot.self, from: data)
    }
}

nonisolated struct PiboCompanionPixelState: Codable, Hashable, Sendable {
    var level: Int
    var bodyStage: Int
    var leafStage: Int
    var accessoryMask: Int
    var form: Int
    var formStuck: Bool
    var balance: Int
    /// Phone-issued token identifies the current container, not a watch tap.
    var collectionToken: String?
    var wishes: [PiboCompanionWish]
    var steps: Int?
    var finds: [Int]
    var thought: Bool
    var stations: [PiboCompanionExploreStation] = []
    var patLine: String = ""
    var patCooldownSeconds: Double = 3
    var boProgress: Double? = nil

    var isAcceptable: Bool {
        (1...1000).contains(level) && (0...2).contains(bodyStage) && (0...4).contains(leafStage)
            && (0...15).contains(accessoryMask) && (0...10).contains(form) && balance >= 0
            && (collectionToken.map { !$0.isEmpty && $0.count <= 160 } ?? true)
            && wishes.count <= 4 && wishes.allSatisfy(\.isAcceptable)
            && (steps.map { $0 >= 0 } ?? true)
            && finds.count <= 24 && finds.allSatisfy { (0...123).contains($0) }
            && stations.count <= 8 && stations.allSatisfy(\.isAcceptable)
            && patLine.count <= 120 && patCooldownSeconds.isFinite && patCooldownSeconds >= 0
            && (boProgress.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
}

nonisolated struct PiboCompanionExploreStation: Codable, Hashable, Sendable {
    var title: String
    var steps: Int
    var item: Int

    var isAcceptable: Bool {
        !title.isEmpty && title.count <= 40 && steps > 0 && (0...123).contains(item)
    }
}

nonisolated struct PiboCompanionWish: Codable, Hashable, Sendable {
    var kind: Int
    var title: String
    var done: Bool
    var fraction: Double

    var isAcceptable: Bool {
        (0...5).contains(kind) && !title.isEmpty && title.count <= 80
            && fraction.isFinite && (0...1).contains(fraction)
    }
}
