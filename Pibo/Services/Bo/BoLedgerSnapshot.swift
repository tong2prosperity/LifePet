import Foundation

enum BoEligibilitySource: String, Codable, Sendable {
    case temporaryCooperation
    case legacyOnboarding
    case legacyOnboardingMigration
}

/// Atomic on-device `bo` ledger. New fields decode with conservative defaults,
/// so upgrading never removes a mature item, inventory unit or spent history.
struct BoLedgerSnapshot: Codable, Equatable, Sendable {
    var energyPool: Double = 0
    var ripeCount: Int = 0
    var balance: Int = 0
    var spentTotal: Int = 0
    var lifetimeMinted: Int = 0
    var lifetimeCollected: Int = 0
    var firstBoMintedAt: Date?
    var firstBoCollectedAt: Date?
    var processedCollectionEventIDs: Set<String> = []
    var grantedEnergyByDay: [String: Double] = [:]
    /// Legacy day-level boundary retained for migration diagnostics.
    var startedOn: Date
    /// Exact eligibility boundary. It comes from story consent when that flow is
    /// enabled, or from legacy Onboarding completion while the flow is disabled.
    /// nil means preserve assets but mint nothing new.
    var acceptedAt: Date?
    /// Disambiguates the legacy `acceptedAt` storage name. New code treats the
    /// timestamp as an eligibility boundary, not necessarily story consent.
    var eligibilitySource: BoEligibilitySource?
    /// Allows a future story release to pause new accrual until explicit
    /// cooperation without deleting an older eligibility boundary or assets.
    var eligibilityEnabled: Bool
    /// Persisted at acceptance so later time-zone/DST changes cannot move the
    /// first complete eligible day.
    var firstEligibleAt: Date?
    var scoringVersion: UInt32

    private enum CodingKeys: String, CodingKey {
        case energyPool, ripeCount, balance, spentTotal, lifetimeMinted, lifetimeCollected
        case firstBoMintedAt, firstBoCollectedAt, processedCollectionEventIDs
        case grantedEnergyByDay, startedOn, acceptedAt, eligibilitySource, eligibilityEnabled
        case firstEligibleAt, scoringVersion
    }

    init(
        startedOn: Date,
        acceptedAt: Date? = nil,
        eligibilitySource: BoEligibilitySource? = nil,
        eligibilityEnabled: Bool? = nil,
        scoringVersion: UInt32
    ) {
        self.startedOn = startedOn
        self.acceptedAt = acceptedAt
        self.eligibilitySource = eligibilitySource
        self.eligibilityEnabled = eligibilityEnabled ?? (acceptedAt != nil)
        self.firstEligibleAt = acceptedAt.flatMap {
            let calendar = Calendar.current
            return calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: $0)
            )
        }
        self.scoringVersion = scoringVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEnergyPool = try values.decodeIfPresent(Double.self, forKey: .energyPool) ?? 0
        energyPool = decodedEnergyPool.isFinite ? max(0, decodedEnergyPool) : 0
        ripeCount = max(0, try values.decodeIfPresent(Int.self, forKey: .ripeCount) ?? 0)
        balance = max(0, try values.decodeIfPresent(Int.self, forKey: .balance) ?? 0)
        spentTotal = max(0, try values.decodeIfPresent(Int.self, forKey: .spentTotal) ?? 0)
        let decodedGrants = try values.decodeIfPresent(
            [String: Double].self,
            forKey: .grantedEnergyByDay
        ) ?? [:]
        grantedEnergyByDay = decodedGrants.filter { key, energy in
            !key.isEmpty && energy.isFinite && energy > 0
        }
        startedOn = try values.decodeIfPresent(Date.self, forKey: .startedOn) ?? .now
        acceptedAt = try values.decodeIfPresent(Date.self, forKey: .acceptedAt)
        eligibilitySource = try values.decodeIfPresent(
            BoEligibilitySource.self,
            forKey: .eligibilitySource
        )
        eligibilityEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .eligibilityEnabled
        ) ?? (acceptedAt != nil)
        firstEligibleAt = try values.decodeIfPresent(Date.self, forKey: .firstEligibleAt)
        scoringVersion = try values.decodeIfPresent(UInt32.self, forKey: .scoringVersion) ?? 0

        let collectedFloor = balance + spentTotal
        lifetimeCollected = max(
            collectedFloor,
            try values.decodeIfPresent(Int.self, forKey: .lifetimeCollected) ?? collectedFloor
        )
        let mintedFloor = ripeCount + lifetimeCollected
        lifetimeMinted = max(
            mintedFloor,
            try values.decodeIfPresent(Int.self, forKey: .lifetimeMinted) ?? mintedFloor
        )
        firstBoMintedAt = try values.decodeIfPresent(Date.self, forKey: .firstBoMintedAt)
        firstBoCollectedAt = try values.decodeIfPresent(Date.self, forKey: .firstBoCollectedAt)
        processedCollectionEventIDs = try values.decodeIfPresent(
            Set<String>.self,
            forKey: .processedCollectionEventIDs
        ) ?? []
    }
}
