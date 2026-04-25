import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [VitalSession] = []
    private(set) var snapshotsBySession: [UUID: [VitalSnapshot]] = [:]

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String = "sessions.json") {
        let base: URL
        if let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = dir
        } else {
            base = FileManager.default.temporaryDirectory
        }
        self.fileURL = base.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    private struct Persisted: Codable {
        var sessions: [VitalSession]
        var snapshotsBySession: [UUID: [VitalSnapshot]]
    }

    func apply(_ message: ConnectivityMessage) {
        switch message {
        case .sessionStarted(let session):
            upsert(session)
        case .snapshot(let snapshot):
            append(snapshot)
        case .sessionEnded(let id, let endedAt):
            if var session = sessions.first(where: { $0.id == id }) {
                session.endedAt = endedAt
                upsert(session)
            }
        }
    }

    func upsert(_ session: VitalSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persist()
    }

    func append(_ snapshot: VitalSnapshot) {
        snapshotsBySession[snapshot.sessionID, default: []].append(snapshot)
        persist()
    }

    func snapshots(for sessionID: UUID) -> [VitalSnapshot] {
        snapshotsBySession[sessionID] ?? []
    }

    func latestSnapshot(for sessionID: UUID) -> VitalSnapshot? {
        snapshotsBySession[sessionID]?.last
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let p = try decoder.decode(Persisted.self, from: data)
            self.sessions = p.sessions
            self.snapshotsBySession = p.snapshotsBySession
            print("[LifePulse] SessionStore loaded \(p.sessions.count) sessions from \(fileURL.path)")
        } catch {
            print("[LifePulse] SessionStore decode failed: \(error)")
        }
    }

    private func persist() {
        let snapshot = Persisted(sessions: sessions, snapshotsBySession: snapshotsBySession)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[LifePulse] SessionStore persist failed: \(error)")
        }
    }
}
