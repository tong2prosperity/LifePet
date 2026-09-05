import Foundation

/// Platform snapshot reconciliation. It does not derive health states or growth.
/// Persist the reconciled value, so an interruption survives a watch relaunch.
nonisolated struct PiboCompanionCache {
    private(set) var snapshot: PiboCompanionSnapshot?

    @discardableResult
    mutating func apply(_ incoming: PiboCompanionSnapshot, now: Date = .now) -> Bool {
        guard incoming.isAcceptable(now: now) else { return false }
        if let current = snapshot, incoming.generatedAt < current.generatedAt { return false }

        var next = incoming
        let samePet = incoming.petID != nil && incoming.petID == snapshot?.petID
        if samePet, let previous = snapshot, incoming.publicStateID == "dataUnknown",
           previous.publicStateID != "dataUnknown" {
            next.publicStateID = previous.publicStateID
            next.animationStateID = previous.animationStateID
            next.stateLabel = previous.stateLabel
            next.stateGeneratedAt = previous.stateGeneratedAt ?? previous.generatedAt
            next.patActionID = previous.patActionID
        }

        if var connection = next.shadowConnection {
            switch connection.status {
            case .none, .hidden:
                connection.snapshot = nil
            case .waiting, .active, .paused:
                if connection.snapshot?.isAcceptable(now: now) != true { connection.snapshot = nil }
                if samePet, let previous = snapshot?.shadowConnection,
                   previous.accountID == connection.accountID,
                   previous.relationshipID == connection.relationshipID,
                   previous.status != .hidden, previous.status != .none,
                   let retained = previous.snapshot, retained.isAcceptable(now: now),
                   connection.snapshot == nil || connection.snapshot!.revision < retained.revision {
                    connection.snapshot = retained
                }
            }
            next.shadowConnection = connection
        }
        snapshot = next
        return true
    }
}
