import Foundation
import Observation
import PiboCore
import os

/// Local-first ledger. Core owns every score, threshold and carry calculation;
/// this store owns ordering, persistence, consent gating and event idempotency.
@MainActor
@Observable
final class BoLedgerStore {
    private(set) var state: BoLedgerSnapshot

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private let syncPersistenceKey: String
    @ObservationIgnored private weak var progressFeedback: BoProgressFeedbackStore?
    @ObservationIgnored private var syncState: BoLedgerSyncState

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.boLedger,
        syncPersistenceKey: String = PiboPersistenceKeys.Defaults.boLedgerSync,
        startedOn: Date = Date(),
        acceptedAt: Date? = nil,
        eligibilitySource: BoEligibilitySource? = .temporaryCooperation,
        eligibilityEnabled: Bool? = nil,
        progressFeedback: BoProgressFeedbackStore? = nil
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.syncPersistenceKey = syncPersistenceKey
        self.progressFeedback = progressFeedback
        self.syncState = BoLedgerSyncState(deviceID: UUID())

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
            LPLog.bo.notice("ledger created startedOn=\(Self.dayKey(resolved), privacy: .public)")
        }
        restoreSyncState()
        // Re-encode legacy state and seed a merge-safe bootstrap for other devices.
        commit()
    }

    var balance: Int { state.balance }
    /// Every formed `bo` is immediately usable. `balance` remains only as a
    /// migration bucket for assets collected by builds that still had a pluck
    /// inventory; new product flows never require that intermediate step.
    var availableBo: Int {
        PiboCoreBoEconomy.availableBo(
            ripeCount: state.ripeCount,
            storedCount: state.balance
        )
    }
    var hasRipeBo: Bool { state.ripeCount > 0 }
    var lifetimeMinted: Int { state.lifetimeMinted }
    var lifetimeCollected: Int { state.lifetimeCollected }
    var unlockedItems: UInt32 { state.unlockedItems }

    var growthStage: PiboCoreBoGrowthStage {
        PiboCoreBoEconomy.growthStage(
            energyPool: state.energyPool,
            ripeCount: state.ripeCount
        )
    }

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
        commit()
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
            appendSyncRecord(
                kind: .healthRecord,
                semanticKey: "bo.health.day:\(key)",
                occurredAt: max(entry.day, state.acceptedAt ?? entry.day),
                acceptedAt: state.acceptedAt,
                payload: BoLedgerSyncPayload(targetEnergy: target)
            )
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
        commit()
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
        appendSyncRecord(
            kind: .ledgerEvent,
            semanticKey: "bo.collect",
            occurredAt: date,
            payload: BoLedgerSyncPayload(amount: 1, eventID: eventID)
        )
        commit()
        LPLog.bo.notice("plucked → balance=\(self.state.balance, privacy: .public)")
        return true
    }

    @discardableResult
    func spend(_ cost: Int) -> Bool {
        guard cost > 0 else { return false }
        let result = PiboCoreBoEconomy.applyInvestment(
            ripeCount: state.ripeCount,
            storedCount: state.balance,
            cost: cost
        )
        guard result.succeeded else { return false }
        state.ripeCount = result.newRipeCount
        state.balance = result.newStoredCount
        state.spentTotal += result.spentCount
        appendSyncRecord(
            kind: .ledgerEvent,
            semanticKey: "bo.spend",
            occurredAt: .now,
            payload: BoLedgerSyncPayload(amount: Double(result.spentCount))
        )
        commit()
        LPLog.bo.notice(
            "invested=\(result.spentCount, privacy: .public) → available=\(self.availableBo, privacy: .public)"
        )
        return true
    }

    func hasProcessedBonusEnergy(eventID: String) -> Bool {
        state.processedBonusEnergyEventIDs.contains(eventID)
    }

    /// Applies one Core-authorized activity bonus exactly once. The progress
    /// store owns task/reward policy; the ledger only carries its granted
    /// energy into the same pool used by health-derived growth.
    @discardableResult
    func grantBonusEnergy(
        eventID: String,
        grantedEnergy: Double,
        at date: Date = .now
    ) -> Bool {
        guard state.eligibilityEnabled,
              !eventID.isEmpty,
              eventID.hasPrefix("walk-doodle:"),
              !state.processedBonusEnergyEventIDs.contains(eventID),
              grantedEnergy.isFinite,
              grantedEnergy > 0
        else { return false }

        let previousEnergyPool = state.energyPool
        let result = PiboCoreBoEconomy.applyEnergy(
            energyPool: previousEnergyPool,
            grantedEnergy: grantedEnergy
        )
        state.energyPool = result.newEnergyPool
        state.processedBonusEnergyEventIDs.insert(eventID)
        if state.processedBonusEnergyEventIDs.count > 512 {
            state.processedBonusEnergyEventIDs = Set(
                state.processedBonusEnergyEventIDs.sorted().suffix(512)
            )
        }
        if result.mintedCount > 0 {
            state.ripeCount += result.mintedCount
            state.lifetimeMinted += result.mintedCount
            if state.firstBoMintedAt == nil { state.firstBoMintedAt = date }
        }
        appendSyncRecord(
            kind: .domainEvent,
            semanticKey: "bo.bonus.energy",
            occurredAt: date,
            payload: BoLedgerSyncPayload(amount: grantedEnergy, eventID: eventID)
        )
        commit()
        progressFeedback?.recordLedgerUpdate(
            previousEnergyPool: previousEnergyPool,
            newEnergyPool: state.energyPool,
            mintedCount: result.mintedCount
        )
        LPLog.bo.notice(
            "bonus energy=\(grantedEnergy, privacy: .public) source=walk-doodle minted=\(result.mintedCount, privacy: .public)"
        )
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
        syncState.outbox.removeAll()
        syncState.activeRequestID = nil
        syncState.activeRecordIDs.removeAll()
        commit()
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
        commit()
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
        commit()
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

    /// Unions permanent platform inventory through Core's monotonic migration rule.
    func mergeUnlockedItems(_ bitmask: UInt32) {
        let merged = PiboCoreBoEconomy.mergeLegacyBootstrap(
            bootstrap(),
            bootstrap(unlockedItems: bitmask)
        )
        guard merged.unlockedItems != state.unlockedItems else { return }
        applyBootstrap(merged)
        commit()
    }

    func recordUnlockedItem(_ coreID: PiboCoreUnlockableItemID, eventID: String) {
        guard (0...30).contains(coreID.rawValue) else { return }
        let bit = UInt32(1) << UInt32(coreID.rawValue)
        guard state.unlockedItems & bit == 0 else { return }
        state.unlockedItems |= bit
        appendSyncRecord(
            kind: .ledgerEvent,
            semanticKey: "bo.ornament.unlock",
            occurredAt: .now,
            payload: BoLedgerSyncPayload(itemID: Int(coreID.rawValue), eventID: eventID)
        )
        commit()
    }

    /// Freezes at most 200 records. The UUID and record set remain stable on retry.
    func syncRequest() -> BoLedgerSyncRequest {
        if syncState.activeRequestID == nil {
            let selected = Array(syncState.outbox.prefix(200))
            syncState.activeRequestID = UUID()
            syncState.activeRecordIDs = selected.map(\.recordID)
            persist()
        }
        let active = Set(syncState.activeRecordIDs)
        let records = syncState.outbox.filter { active.contains($0.recordID) }
        return BoLedgerSyncRequest(
            requestID: (syncState.activeRequestID ?? UUID()).uuidString.lowercased(),
            deviceID: syncState.deviceID.uuidString.lowercased(),
            cursor: syncState.cursor,
            epoch: 1,
            healthRecords: records.filter { $0.kind == .healthRecord },
            domainEvents: records.filter { $0.kind == .domainEvent },
            ledgerEvents: records.filter { $0.kind == .ledgerEvent }
        )
    }

    @discardableResult
    func acknowledgeSync(_ response: BoLedgerSyncResponse) -> UInt32 {
        let active = Set(syncState.activeRecordIDs)
        syncState.outbox.removeAll { active.contains($0.recordID) }
        syncState.activeRequestID = nil
        syncState.activeRecordIDs.removeAll()
        for entry in response.changes where entry.cursor > syncState.cursor {
            applyRemoteEntry(entry)
        }
        syncState.cursor = max(syncState.cursor, response.nextCursor)
        persist()
        return state.unlockedItems
    }

    func hasPendingSyncRecords() -> Bool { !syncState.outbox.isEmpty }

    private func bootstrap(unlockedItems: UInt32? = nil) -> PiboCoreBoLedgerBootstrap {
        PiboCoreBoLedgerBootstrap(
            energyPool: state.energyPool,
            ripeCount: state.ripeCount,
            storedCount: state.balance,
            spentTotal: state.spentTotal,
            lifetimeMinted: state.lifetimeMinted,
            lifetimeCollected: state.lifetimeCollected,
            unlockedItems: unlockedItems ?? state.unlockedItems
        )
    }

    private func applyBootstrap(_ value: PiboCoreBoLedgerBootstrap) {
        let merged = PiboCoreBoEconomy.mergeLegacyBootstrap(bootstrap(), value)
        state.energyPool = merged.energyPool
        state.ripeCount = merged.ripeCount
        state.balance = merged.storedCount
        state.spentTotal = merged.spentTotal
        state.lifetimeMinted = merged.lifetimeMinted
        state.lifetimeCollected = merged.lifetimeCollected
        state.unlockedItems = merged.unlockedItems
    }

    private func applyRemoteEntry(_ entry: BoLedgerSyncEntryDTO) {
        if entry.semanticKey == "bo.bootstrap" {
            let payload = entry.payload
            applyBootstrap(PiboCoreBoLedgerBootstrap(
                energyPool: max(0, payload.energyPool ?? 0),
                ripeCount: max(0, payload.ripeCount ?? 0),
                storedCount: max(0, payload.storedCount ?? 0),
                spentTotal: max(0, payload.spentTotal ?? 0),
                lifetimeMinted: max(0, payload.lifetimeMinted ?? 0),
                lifetimeCollected: max(0, payload.lifetimeCollected ?? 0),
                unlockedItems: payload.unlockedItems ?? 0
            ))
            return
        }
        let prefix = "bo.health.day:"
        guard entry.semanticKey.hasPrefix(prefix),
              let candidate = entry.payload.targetEnergy,
              candidate.isFinite, candidate > 0 else { return }
        let day = String(entry.semanticKey.dropFirst(prefix.count))
        let existing = state.grantedEnergyByDay[day] ?? 0
        let target = PiboCoreBoEconomy.mergeEnergyGrantTarget(
            existing: existing,
            candidate: candidate
        )
        guard target > existing else { return }
        state.grantedEnergyByDay[day] = target
        let result = PiboCoreBoEconomy.applyEnergy(
            energyPool: state.energyPool,
            grantedEnergy: target - existing
        )
        state.energyPool = result.newEnergyPool
        state.ripeCount += result.mintedCount
        state.lifetimeMinted += result.mintedCount
    }

    private func commit() {
        appendSyncRecord(
            kind: .ledgerEvent,
            semanticKey: "bo.bootstrap",
            occurredAt: .now,
            payload: BoLedgerSyncPayload(
                energyPool: state.energyPool,
                ripeCount: state.ripeCount,
                storedCount: state.balance,
                spentTotal: state.spentTotal,
                lifetimeMinted: state.lifetimeMinted,
                lifetimeCollected: state.lifetimeCollected,
                unlockedItems: state.unlockedItems
            )
        )
        persist()
    }

    private func appendSyncRecord(
        kind: BoLedgerSyncKind,
        semanticKey: String,
        occurredAt: Date,
        acceptedAt: Date? = nil,
        payload: BoLedgerSyncPayload
    ) {
        guard occurredAt.timeIntervalSince1970.isFinite,
              !semanticKey.isEmpty, semanticKey.count <= 160 else { return }
        syncState.sequence &+= 1
        syncState.outbox.append(BoLedgerSyncRecord(
            kind: kind,
            recordID: "\(syncState.deviceID.uuidString.lowercased()):\(syncState.sequence)",
            semanticKey: semanticKey,
            scoringVersion: max(1, state.scoringVersion),
            occurredAt: occurredAt,
            acceptedAt: acceptedAt,
            payload: payload
        ))
    }

    private func restoreSyncState() {
        guard let data = defaults.data(forKey: syncPersistenceKey),
              var decoded = try? JSONDecoder().decode(BoLedgerSyncState.self, from: data)
        else { return }
        let queued = Set(decoded.outbox.map(\.recordID))
        decoded.activeRecordIDs = decoded.activeRecordIDs.filter(queued.contains)
        if decoded.activeRequestID != nil, decoded.activeRecordIDs.isEmpty {
            decoded.activeRequestID = nil
        }
        syncState = decoded
    }

    private func persist() {
        guard let snapshotData = try? JSONEncoder().encode(state),
              let syncData = try? JSONEncoder().encode(syncState) else { return }
        defaults.set(snapshotData, forKey: persistenceKey)
        defaults.set(syncData, forKey: syncPersistenceKey)
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
