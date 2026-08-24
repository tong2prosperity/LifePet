import Foundation
import Observation
import PiboCore
import os

enum BoProgressMilestone: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    case nearMint = 90
    case minted = 100

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init?(_ event: PiboCoreBoProgressEvent) {
        switch event {
        case .quarter: self = .quarter
        case .half: self = .half
        case .threeQuarters: self = .threeQuarters
        case .nearMint: self = .nearMint
        case .minted: self = .minted
        case .none: self = .none
        }
    }

    var message: String {
        switch self {
        case .minted: AppLocalization.text("一枚 bo 成熟了")
        case .nearMint: AppLocalization.text("bo 快形成了")
        case .none, .quarter, .half, .threeQuarters:
            AppLocalization.text("bo 又长了一点")
        }
    }
}

struct PendingBoProgressFeedback: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let milestone: BoProgressMilestone
    let previousEnergyPool: Double
    let newEnergyPool: Double
    let mintedCount: Int

    var isPresentable: Bool {
        previousEnergyPool.isFinite
            && newEnergyPool.isFinite
            && mintedCount >= 0
            && (mintedCount > 0 || newEnergyPool > previousEnergyPool)
    }
}

struct BoProgressPresentation: Equatable, Sendable {
    let milestone: BoProgressMilestone
    let message: String
    let fact: String
    let previousProgress: Double
    let currentProgress: Double
    let previousMature: Bool
    let mature: Bool
}

/// Durable presentation queue for one bo progress acknowledgement.
///
/// It accepts committed ledger balances only. Health scoring, daily caps and
/// minting remain in Core/the ledger; the badge only receives the resulting
/// milestone ID.
@MainActor
@Observable
final class BoProgressFeedbackStore {
    private(set) var pending: PendingBoProgressFeedback?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = "pibo.bo.progress-feedback.v1"
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode(PendingBoProgressFeedback.self, from: data),
           decoded.isPresentable {
            pending = decoded
        } else if defaults.object(forKey: persistenceKey) != nil {
            // Milestone-only requests from the old counter UI have no causal
            // energy span and cannot be reconstructed truthfully.
            defaults.removeObject(forKey: persistenceKey)
        }
    }

    /// Records one already-committed ledger change. Core selects the single
    /// highest crossed boundary. Every positive committed change is retained,
    /// including a mint or growth too small to cross a named boundary.
    @discardableResult
    func recordLedgerUpdate(
        previousEnergyPool: Double,
        newEnergyPool: Double,
        mintedCount: Int
    ) -> PiboCoreBoProgressEvent {
        let event = PiboCoreBoEconomy.progressEvent(
            previousEnergyPool: previousEnergyPool,
            newEnergyPool: newEnergyPool,
            mintedCount: mintedCount
        )
        if mintedCount > 0 || newEnergyPool > previousEnergyPool {
            enqueue(
                BoProgressMilestone(event) ?? .none,
                previousEnergyPool: previousEnergyPool,
                newEnergyPool: newEnergyPool,
                mintedCount: mintedCount
            )
        }
        return event
    }

    func enqueue(
        _ milestone: BoProgressMilestone,
        previousEnergyPool: Double,
        newEnergyPool: Double,
        mintedCount: Int
    ) {
        guard previousEnergyPool.isFinite,
              newEnergyPool.isFinite,
              mintedCount >= 0,
              mintedCount > 0 || newEnergyPool > previousEnergyPool
        else { return }
        let resolved = max(pending?.milestone ?? milestone, milestone)
        pending = PendingBoProgressFeedback(
            id: UUID(),
            milestone: resolved,
            previousEnergyPool: pending?.previousEnergyPool ?? previousEnergyPool,
            newEnergyPool: newEnergyPool,
            mintedCount: (pending?.mintedCount ?? 0) + mintedCount
        )
        persist()
        LPLog.bo.notice("progress feedback queued milestone=\(resolved.rawValue, privacy: .public)")
    }

    func consume(id: UUID) {
        guard pending?.id == id else { return }
        clear()
    }

    func clear() {
        pending = nil
        defaults.removeObject(forKey: persistenceKey)
    }

    private func persist() {
        guard let pending, let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: persistenceKey)
    }
}
