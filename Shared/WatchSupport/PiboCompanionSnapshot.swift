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
            && occurredAt <= now.addingTimeInterval(300)
            && syncedAt <= now.addingTimeInterval(300)
            && now.timeIntervalSince(syncedAt) <= 86_400
    }

    private static let publicStateIDs: Set<String> = [
        "sleeping", "waking", "stable", "energetic", "tired",
    ]
}

/// Privacy-minimized phone → watch projection. Raw health, readiness, stress,
/// scores, streaks, bo, and online-presence signals never cross this boundary.
nonisolated struct PiboCompanionSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let petName: String
    let dayStart: Date
    let generatedAt: Date
    let publicStateID: String
    let animationStateID: String
    let stateLabel: String
    let activeEnergy: Double?
    let exerciseMinutes: Int?
    let standHours: Int?
    let moveProgress: Double?
    let exerciseProgress: Double?
    let standProgress: Double?
    let sceneID: PiboFlatWorldScene
    let shadow: PiboCompanionShadowSnapshot?

    func isAcceptable(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard schemaVersion == 1,
              Self.publicStateIDs.contains(publicStateID),
              !petName.isEmpty, petName.count <= 24,
              !stateLabel.isEmpty, stateLabel.count <= 24,
              !animationStateID.isEmpty, animationStateID.count <= 160,
              generatedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(generatedAt) <= 86_400,
              calendar.isDate(dayStart, inSameDayAs: now),
              Self.isValidFact(activeEnergy),
              Self.isValidFact(exerciseMinutes.map(Double.init)),
              Self.isValidFact(standHours.map(Double.init)),
              Self.isValidProgress(moveProgress),
              Self.isValidProgress(exerciseProgress),
              Self.isValidProgress(standProgress) else { return false }
        return true
    }

    private static let publicStateIDs: Set<String> = [
        "sleeping", "waking", "stable", "energetic", "tired",
    ]

    private static func isValidFact(_ value: Double?) -> Bool {
        value.map { $0.isFinite && $0 >= 0 } ?? true
    }

    private static func isValidProgress(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...1).contains($0) } ?? true
    }
}

nonisolated enum PiboCompanionSnapshotCoding {
    static let applicationContextKey = "pibo.companion.snapshot.v1"
    static let requestKey = "pibo.companion.request.v1"

    static func encode(_ value: PiboCompanionSnapshot) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode(_ data: Data?) -> PiboCompanionSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PiboCompanionSnapshot.self, from: data)
    }
}
