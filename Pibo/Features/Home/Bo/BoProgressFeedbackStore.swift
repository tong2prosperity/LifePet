import Foundation
import Observation
import PiboCore
import os

enum BoProgressMilestone: Int, Codable, CaseIterable, Comparable, Sendable {
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    case nearMint = 90

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init?(_ event: PiboCoreBoProgressEvent) {
        switch event {
        case .quarter: self = .quarter
        case .half: self = .half
        case .threeQuarters: self = .threeQuarters
        case .nearMint: self = .nearMint
        case .none, .minted: return nil
        }
    }

    var message: String {
        if self == .nearMint {
            return AppLocalization.text("bo 快形成了 · 90%")
        }
        return AppLocalization.format("bo 正在形成 · %d%%", rawValue)
    }
}

struct PendingBoProgressFeedback: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let milestone: BoProgressMilestone
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
           let decoded = try? JSONDecoder().decode(PendingBoProgressFeedback.self, from: data) {
            pending = decoded
        }
    }

    /// Records one already-committed ledger change. Core selects the single
    /// highest crossed boundary; a mint cancels any fractional reminder.
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
        if event == .minted {
            clear()
        } else if let milestone = BoProgressMilestone(event) {
            enqueue(milestone)
        }
        return event
    }

    func enqueue(_ milestone: BoProgressMilestone) {
        let resolved = max(pending?.milestone ?? milestone, milestone)
        pending = PendingBoProgressFeedback(id: UUID(), milestone: resolved)
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
