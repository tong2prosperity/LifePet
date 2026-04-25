import Foundation
import os

/// On-disk persistence for `DailySnapshot`. Files live under
/// `~/Library/Application Support/lifepet/history/<petId>/<yyyy-MM-dd>.json`,
/// one file per (pet, day).
///
/// Why per-day files instead of one JSONL per pet:
/// - Atomic write only touches today's file → past days can't corrupt under
///   concurrent reads.
/// - "Read last 7 days" is 7 small reads (~300 bytes each) — cheap.
/// - Listing by date is filename enumeration, no parsing.
/// - Manual inspection during demo is trivial (`cat 2026-04-25.json`).
///
/// Why an `actor`: writes happen from `PetStateStore.recompute()` (MainActor)
/// fire-and-forget; serializing them through an actor keeps disk I/O off the
/// main thread without per-call queue plumbing. Reads are async too — fine
/// because consumers (catalog view, HRV baseline) all do the work in `Task`s.
actor DailySnapshotStore {

    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Memoized "yyyy-MM-dd" formatter — `DateFormatter` init is non-trivial
    /// and we hit this on every write/read.
    private let filenameFormatter: DateFormatter

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            // Application Support is the right home: persisted across launches,
            // not user-visible (Documents would surface in Files.app), survives
            // app updates. iOS auto-creates the parent on first directory call.
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            self.rootURL = support.appendingPathComponent("lifepet/history", isDirectory: true)
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        self.filenameFormatter = fmt

        LPLog.snapshot.notice("store rooted at \(self.rootURL.path, privacy: .public)")
    }

    // MARK: - Paths

    private func dirURL(for petId: UUID) -> URL {
        rootURL.appendingPathComponent(petId.uuidString, isDirectory: true)
    }

    private func fileURL(petId: UUID, date: Date) -> URL {
        let key = filenameFormatter.string(from: Calendar.current.startOfDay(for: date))
        return dirURL(for: petId).appendingPathComponent("\(key).json")
    }

    // MARK: - Write

    /// Overwrite (or create) the snapshot file for `(petId, snapshot.date)`.
    /// Atomic — partial writes can't corrupt an existing day's record.
    /// Errors are logged and swallowed: a failed snapshot write should never
    /// take down the home screen, and the next `recompute()` will retry.
    func write(_ snapshot: DailySnapshot) {
        let url = fileURL(petId: snapshot.petId, date: snapshot.date)
        do {
            let dir = dirURL(for: snapshot.petId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            LPLog.snapshot.debug("wrote \(snapshot.petId.uuidString.prefix(8), privacy: .public)/\(url.lastPathComponent, privacy: .public) v=\(snapshot.vitality, privacy: .public) e=\(snapshot.energy, privacy: .public) m=\(snapshot.mood, privacy: .public) (\(data.count, privacy: .public)B)")
        } catch {
            LPLog.snapshot.error("write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Read

    /// Returns `nil` for "no snapshot on disk" (a normal case — pet was idle
    /// that day, or the day pre-dated the snapshot store) AND for decode
    /// failures (logged). Callers should treat both as "no data."
    func read(petId: UUID, date: Date) -> DailySnapshot? {
        let url = fileURL(petId: petId, date: date)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(DailySnapshot.self, from: data)
        } catch {
            LPLog.snapshot.error("decode failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Last `days` days ending today, ascending by date. Days with no
    /// snapshot are skipped — the result length is `≤ days`. Use this for
    /// the HRV 7-day baseline + chronic-death judgments.
    func recent(petId: UUID, days: Int) -> [DailySnapshot] {
        guard days > 0 else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [DailySnapshot] = []
        out.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let s = read(petId: petId, date: d) {
                out.append(s)
            }
        }
        return out
    }

    /// Inclusive `[from, through]`, ascending by date. Same skip-on-miss
    /// semantics as `recent`. Used by the catalog detail view to render the
    /// per-pet 3-stat series across its full lifespan.
    func range(petId: UUID, from start: Date, through end: Date) -> [DailySnapshot] {
        let cal = Calendar.current
        var out: [DailySnapshot] = []
        var cursor = cal.startOfDay(for: start)
        let stop = cal.startOfDay(for: end)
        guard cursor <= stop else { return [] }
        while cursor <= stop {
            if let s = read(petId: petId, date: cursor) {
                out.append(s)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}
