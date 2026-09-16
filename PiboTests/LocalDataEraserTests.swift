import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
struct LocalDataEraserTests {
    private func makeLocations() throws -> (LocalDataEraser.Locations, URL, String) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LocalDataEraserTests-\(UUID().uuidString)")
        let support = root.appending(path: "Support")
        let caches = root.appending(path: "Caches")
        let groupFile = root.appending(path: "group-widget.json")
        for dir in [support, caches] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let suite = "LocalDataEraserTests.\(UUID().uuidString)"
        let locations = LocalDataEraser.Locations(
            markerDirectory: support,
            directories: [support, caches, groupFile],
            defaultsDomains: [suite]
        )
        return (locations, root, suite)
    }

    @Test func nothingHappensWithoutAScheduledMarker() throws {
        let (locations, root, suite) = try makeLocations()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = locations.directories[0].appending(path: "PiboHistory.store")
        try Data("x".utf8).write(to: store)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "kept")
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!LocalDataEraser.eraseIfScheduled(locations: locations))
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(defaults.bool(forKey: "kept"))
    }

    @Test func scheduledEraseWipesFilesDefaultsAndMarker() throws {
        let (locations, root, suite) = try makeLocations()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let support = locations.directories[0]
        let caches = locations.directories[1]
        let groupFile = locations.directories[2]
        let storeFiles = ["PiboHistory.store", "PiboHistory.store-wal", "PiboHistory.store-shm"]
            .map { support.appending(path: $0) }
        for url in storeFiles { try Data("x".utf8).write(to: url) }
        try fm.createDirectory(at: support.appending(path: "pibo/history"), withIntermediateDirectories: true)
        try Data("y".utf8).write(to: caches.appending(path: "thumb.png"))
        try Data("z".utf8).write(to: groupFile)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("secret", forKey: "pibo.onboarding.narrative.v2")
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LocalDataEraser.schedule(locations: locations))
        #expect(LocalDataEraser.isScheduled(locations: locations))
        // Scheduling alone deletes nothing: live stores would re-flush.
        #expect(storeFiles.allSatisfy { fm.fileExists(atPath: $0.path) })

        #expect(LocalDataEraser.eraseIfScheduled(locations: locations))
        #expect(!storeFiles.contains { fm.fileExists(atPath: $0.path) })
        #expect(!fm.fileExists(atPath: support.appending(path: "pibo").path))
        #expect(try fm.contentsOfDirectory(atPath: caches.path).isEmpty)
        #expect(!fm.fileExists(atPath: groupFile.path))
        #expect(UserDefaults(suiteName: suite)?.string(forKey: "pibo.onboarding.narrative.v2") == nil)
        #expect(!LocalDataEraser.isScheduled(locations: locations))
        // Consumed: the next launch does not erase again.
        #expect(!LocalDataEraser.eraseIfScheduled(locations: locations))
    }
}
