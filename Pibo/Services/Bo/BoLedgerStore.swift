import Foundation
import Observation
import PiboCore
import os

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

/// Local-first ledger. Core owns every score, threshold and carry calculation;
/// this store owns ordering, persistence, consent gating and event idempotency.
@MainActor
@Observable
final class BoLedgerStore {
    private(set) var state: BoLedgerSnapshot

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private weak var progressFeedback: BoProgressFeedbackStore?

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.boLedger,
        startedOn: Date = Date(),
        acceptedAt: Date? = nil,
        eligibilitySource: BoEligibilitySource? = .temporaryCooperation,
        eligibilityEnabled: Bool? = nil,
        progressFeedback: BoProgressFeedbackStore? = nil
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.progressFeedback = progressFeedback

        let version = PiboCoreBoEconomy.scoringVersion
        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode(BoLedgerSnapshot.self, from: data) {
            state = decoded
            if let acceptedAt,
               let eligibilitySource,
               state.acceptedAt == nil || state.eligibilitySource != eligibilitySource {
                let wasUnbounded = state.acceptedAt == nil
                state.acceptedAt = acceptedAt
                state.eligibilitySource = eligibilitySource
                state.startedOn = Calendar.current.startOfDay(for: acceptedAt)
                state.firstEligibleAt = Self.firstEligibleDate(for: acceptedAt)
                if wasUnbounded { state.grantedEnergyByDay.removeAll() }
            }
            if state.acceptedAt != nil, state.firstEligibleAt == nil {
                state.firstEligibleAt = state.acceptedAt.map {
                    Self.firstEligibleDate(for: $0)
                }
            }
            if let eligibilityEnabled {
                state.eligibilityEnabled = eligibilityEnabled
            }
            if decoded.scoringVersion != version {
                LPLog.bo.notice(
                    "scoring version drift \(decoded.scoringVersion, privacy: .public)→\(version, privacy: .public), ledger kept as-is"
                )
                state.scoringVersion = version
            }
            repairOversizedEnergyPoolIfNeeded()
            // Re-encode after a legacy decode so lifetime floors become durable.
            persist()
        } else {
            let calendar = Calendar.current
            let resolved = max(
                calendar.startOfDay(for: startedOn),
                calendar.startOfDay(for: Date())
            )
            state = BoLedgerSnapshot(
                startedOn: resolved,
                acceptedAt: acceptedAt,
                eligibilitySource: eligibilitySource,
                eligibilityEnabled: eligibilityEnabled,
                scoringVersion: version
            )
            persist()
            LPLog.bo.notice("ledger created startedOn=\(Self.dayKey(resolved), privacy: .public)")
        }
    }

    var balance: Int { state.balance }
    var hasRipeBo: Bool { state.ripeCount > 0 }
    var lifetimeMinted: Int { state.lifetimeMinted }
    var lifetimeCollected: Int { state.lifetimeCollected }

    var growthProgress: Double {
        if state.ripeCount > 0 { return 1 }
        let perBo = PiboCoreBoEconomy.energyPerBo
        guard perBo > 0 else { return 0 }
        return min(1, max(0, state.energyPool / perBo))
    }

    func setAcceptedAtIfNeeded(_ date: Date) {
        guard state.acceptedAt == nil else { return }
        setEligibilityBoundary(date, source: .temporaryCooperation)
    }

    /// Replaces the eligibility boundary only when its semantic source changes.
    /// Existing minted/collected assets and day bookmarks are preserved, so a
    /// release-scope migration can neither claw back nor double-grant `bo`.
    func setEligibilityBoundary(_ date: Date, source: BoEligibilitySource) {
        guard date.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970 > 0,
              state.acceptedAt == nil
                || state.eligibilitySource != source
                || !state.eligibilityEnabled
        else { return }
        let wasUnbounded = state.acceptedAt == nil
        state.acceptedAt = date
        state.eligibilitySource = source
        state.eligibilityEnabled = true
        state.startedOn = Calendar.current.startOfDay(for: date)
        state.firstEligibleAt = Self.firstEligibleDate(for: date)
        if wasUnbounded {
            // A nil boundary cannot legitimately have eligible bookmarks.
            state.grantedEnergyByDay.removeAll()
        }
        persist()
        LPLog.bo.notice(
            "bo eligibility boundary recorded source=\(source.rawValue, privacy: .public)"
        )
    }

    func recompute(history: HealthHistoryStore, now: Date = Date()) {
        guard state.eligibilityEnabled, state.acceptedAt != nil else { return }
        let records = history
            .verifiedHealthRecords(from: scanCutoff(now: now), to: now)
            .filter(\.hasCoreBoEvidence)
        recompute(days: records.map { (day: $0.date, metrics: PiboCoreBoAdapter.metrics(for: $0)) }, now: now)
    }

    /// Daily history cannot split all sources at an arbitrary second. The first
    /// eligible bucket is therefore the first whole day after `acceptedAt`, a
    /// conservative boundary that can never ingest pre-consent health data.
    func recompute(days: [(day: Date, metrics: PiboCoreBoDailyMetrics)], now: Date = Date()) {
        guard state.eligibilityEnabled, state.acceptedAt != nil else { return }
        let perBo = PiboCoreBoEconomy.energyPerBo
        guard perBo > 0 else {
            LPLog.bo.error("energyPerBo is not positive — skipping recompute")
            return
        }

        let cutoff = scanCutoff(now: now)
        let poolBefore = state.energyPool
        var minted = 0
        var changed = false

        for entry in days.filter({ $0.day >= cutoff }).sorted(by: { $0.day < $1.day }) {
            let key = Self.dayKey(entry.day)
            let target = PiboCoreBoEconomy.scoreDay(entry.metrics).energy
            guard target.isFinite, target > 0 else { continue }
            if state.grantedEnergyByDay[key] == nil {
                for legacyKey in Self.legacyDayKeys(entry.day) {
                    if let legacyGrant = state.grantedEnergyByDay.removeValue(forKey: legacyKey) {
                        state.grantedEnergyByDay[key] = legacyGrant
                        changed = true
                        break
                    }
                }
            }
            let delta = target - (state.grantedEnergyByDay[key] ?? 0)
            guard delta > 0 else { continue }

            state.grantedEnergyByDay[key] = target
            let result = PiboCoreBoEconomy.applyEnergy(
                energyPool: state.energyPool,
                grantedEnergy: delta
            )
            state.energyPool = result.newEnergyPool
            if result.mintedCount > 0 {
                state.ripeCount += result.mintedCount
                state.lifetimeMinted += result.mintedCount
                if state.firstBoMintedAt == nil { state.firstBoMintedAt = now }
                minted += result.mintedCount
            }
            changed = true
        }

        guard changed else { return }
        prunePastBookmarks(now: now)
        persist()
        progressFeedback?.recordLedgerUpdate(
            previousEnergyPool: poolBefore,
            newEnergyPool: state.energyPool,
            mintedCount: minted
        )
        if minted > 0 {
            LPLog.bo.notice("minted=\(minted, privacy: .public) ripe=\(self.state.ripeCount, privacy: .public)")
        }
    }

    @discardableResult
    func pluck(eventID: String = UUID().uuidString, at date: Date = .now) -> Bool {
        guard !eventID.isEmpty,
              !state.processedCollectionEventIDs.contains(eventID),
              state.ripeCount > 0 else {
            return false
        }
        state.ripeCount -= 1
        state.balance += 1
        state.lifetimeCollected += 1
        if state.firstBoCollectedAt == nil { state.firstBoCollectedAt = date }
        state.processedCollectionEventIDs.insert(eventID)
        persist()
        LPLog.bo.notice("plucked → balance=\(self.state.balance, privacy: .public)")
        return true
    }

    @discardableResult
    func spend(_ cost: Int) -> Bool {
        guard cost > 0, state.balance >= cost else { return false }
        state.balance -= cost
        state.spentTotal += cost
        persist()
        LPLog.bo.notice("spent=\(cost, privacy: .public) → balance=\(self.state.balance, privacy: .public)")
        return true
    }

    func reset(startedOn: Date = Date()) {
        state = BoLedgerSnapshot(
            startedOn: Calendar.current.startOfDay(for: startedOn),
            acceptedAt: nil,
            eligibilitySource: nil,
            eligibilityEnabled: false,
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        persist()
        LPLog.bo.notice("ledger reset")
    }

    #if DEBUG
    func debugSet(balance: Int? = nil, ripe: Int? = nil, progress: Double? = nil) {
        if let balance {
            state.balance = max(0, balance)
            state.lifetimeCollected = max(state.lifetimeCollected, state.balance + state.spentTotal)
        }
        if let ripe {
            state.ripeCount = max(0, ripe)
            state.lifetimeMinted = max(
                state.lifetimeMinted,
                state.ripeCount + state.lifetimeCollected
            )
        }
        if let progress {
            state.energyPool = PiboCoreBoEconomy.energyPerBo * min(1, max(0, progress))
        }
        persist()
    }

    @discardableResult
    func debugApplyWorkout(durationMinutes: Int) -> Double {
        guard durationMinutes > 0 else { return growthProgress }
        let metrics = PiboCoreBoAdapter.metrics(
            sleepTotal: 0,
            sleepDeep: 0,
            sleepREM: 0,
            awakeSeconds: 0,
            awakeSegmentCount: nil,
            steps: 0,
            exerciseMinutes: durationMinutes,
            hrv: 0,
            restingHR: 0
        )
        let scoredEnergy = PiboCoreBoEconomy.scoreDay(metrics).energy
        guard scoredEnergy.isFinite, scoredEnergy > 0 else { return growthProgress }

        let previousEnergyPool = state.energyPool
        let result = PiboCoreBoEconomy.applyEnergy(
            energyPool: previousEnergyPool,
            grantedEnergy: scoredEnergy
        )
        state.energyPool = result.newEnergyPool
        state.ripeCount += result.mintedCount
        state.lifetimeMinted += result.mintedCount
        if result.mintedCount > 0, state.firstBoMintedAt == nil { state.firstBoMintedAt = .now }
        persist()
        progressFeedback?.recordLedgerUpdate(
            previousEnergyPool: previousEnergyPool,
            newEnergyPool: state.energyPool,
            mintedCount: result.mintedCount
        )
        return growthProgress
    }
    #endif

    private static let scanWindowDays = 400

    private func repairOversizedEnergyPoolIfNeeded() {
        let result = PiboCoreBoEconomy.applyEnergy(
            energyPool: state.energyPool,
            grantedEnergy: 0
        )
        guard result.mintedCount > 0 else { return }
        state.energyPool = result.newEnergyPool
        state.ripeCount += result.mintedCount
        state.lifetimeMinted += result.mintedCount
        if state.firstBoMintedAt == nil { state.firstBoMintedAt = .now }
        LPLog.bo.notice(
            "repaired oversized persisted pool; recovered=\(result.mintedCount, privacy: .public)"
        )
    }

    private func scanCutoff(now: Date) -> Date {
        guard state.eligibilityEnabled, state.acceptedAt != nil else { return .distantFuture }
        let calendar = Calendar.current
        let earliest = calendar.date(
            byAdding: .day,
            value: -Self.scanWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? state.acceptedAt ?? .distantFuture
        let firstWholeDay = state.firstEligibleAt
            ?? state.acceptedAt.map { Self.firstEligibleDate(for: $0) }
            ?? .distantFuture
        return max(firstWholeDay, earliest)
    }

    private func prunePastBookmarks(now: Date) {
        let cutoff = Int64(scanCutoff(now: now).timeIntervalSince1970.rounded())
        state.grantedEnergyByDay = state.grantedEnergyByDay.filter { key, _ in
            guard key.hasPrefix("epoch:"),
                  let seconds = Int64(key.dropFirst("epoch:".count))
            else {
                // Keep unmatched legacy keys until their corresponding record
                // is seen and migrated during recompute.
                return true
            }
            return seconds >= cutoff
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    private static let legacyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        "epoch:\(Int64(date.timeIntervalSince1970.rounded()))"
    }

    private static func legacyDayKey(_ date: Date) -> String {
        legacyDayFormatter.timeZone = .current
        return legacyDayFormatter.string(from: date)
    }

    /// Old bookmarks stored a calendar date without its time zone. Recover the
    /// offset encoded by a persisted start-of-day instant before falling back
    /// to the device's current zone, so travel cannot double-grant that day.
    private static func legacyDayKeys(_ date: Date) -> [String] {
        var keys = [legacyDayKey(date)]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.startOfDay(for: date)
        let baseOffset = -Int(date.timeIntervalSince(start).rounded())
        let possibleOffsets = [baseOffset, baseOffset + 24 * 3_600, baseOffset - 24 * 3_600]
            .filter { (-12 * 3_600...14 * 3_600).contains($0) }
        for offset in possibleOffsets {
            guard let originalZone = TimeZone(secondsFromGMT: offset) else { continue }
            legacyDayFormatter.timeZone = originalZone
            let original = legacyDayFormatter.string(from: date)
            if !keys.contains(original) { keys.append(original) }
        }
        return keys
    }

    private static func firstEligibleDate(for acceptedAt: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: acceptedAt)
        ) ?? acceptedAt
    }
}
