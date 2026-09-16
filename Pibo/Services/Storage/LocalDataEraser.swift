import Foundation
import os

/// Local data erase after a confirmed account deletion.
///
/// Two phases, mirroring HarmonyOS `LocalDataEraser`:
///
/// 1. **Schedule** (at deletion time): write a marker file. Live stores keep
///    their in-memory state and would re-flush UserDefaults / SwiftData if the
///    files were deleted underneath them, so nothing is removed from disk here.
///    The app shell instead resets its stores in memory and returns to first run.
/// 2. **Erase** (`eraseIfScheduled`, the very first line of `PiboApp.init`,
///    before any store, ModelContainer or UserDefaults reader exists): delete
///    the app's defaults domain, the App Group defaults, the sandbox's
///    Documents / Application Support / Caches / tmp contents and the App Group
///    container files. iOS cannot relaunch itself, so this runs on the next
///    cold launch; the marker is removed last so an interrupted erase retries.
///
/// Keychain tokens are cleared by `AuthService.deleteAccount` before scheduling.
nonisolated enum LocalDataEraser {
    static let markerFileName = "pibo_account_erase.pending"

    struct Locations: Sendable {
        /// Where the marker lives. Kept in Application Support (never iCloud-
        /// backed Documents) and skipped by the sweep until the very end.
        var markerDirectory: URL
        /// Directories whose *contents* are removed.
        var directories: [URL]
        /// UserDefaults suites (by name) whose persistent domains are removed.
        var defaultsDomains: [String]

        static var live: Locations {
            let fm = FileManager.default
            let support = (try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )) ?? URL.applicationSupportDirectory
            var directories = [
                support,
                URL.documentsDirectory,
                URL.cachesDirectory,
                fm.temporaryDirectory,
            ]
            if let group = fm.containerURL(
                forSecurityApplicationGroupIdentifier: PiboWidgetConstants.appGroupID
            ) {
                // Library/Preferences is owned by cfprefsd and handled through
                // `removePersistentDomain`; every other group file is ours.
                let contents = (try? fm.contentsOfDirectory(
                    at: group, includingPropertiesForKeys: nil
                )) ?? []
                for url in contents where url.lastPathComponent != "Library" {
                    directories.append(url)
                }
                let library = group.appending(path: "Library")
                let libraryContents = (try? fm.contentsOfDirectory(
                    at: library, includingPropertiesForKeys: nil
                )) ?? []
                for url in libraryContents where url.lastPathComponent != "Preferences" {
                    directories.append(url)
                }
            }
            var domains = [PiboWidgetConstants.appGroupID]
            if let bundleID = Bundle.main.bundleIdentifier { domains.append(bundleID) }
            return Locations(
                markerDirectory: support,
                directories: directories,
                defaultsDomains: domains
            )
        }
    }

    static func markerURL(in locations: Locations = .live) -> URL {
        locations.markerDirectory.appending(path: markerFileName)
    }

    static func isScheduled(locations: Locations = .live) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(in: locations).path)
    }

    /// Writes the pending marker. Returns `false` if even that failed.
    @discardableResult
    static func schedule(locations: Locations = .live, now: Date = .now) -> Bool {
        let url = markerURL(in: locations)
        do {
            try FileManager.default.createDirectory(
                at: locations.markerDirectory, withIntermediateDirectories: true
            )
            try Data(String(now.timeIntervalSince1970).utf8).write(to: url, options: .atomic)
            return true
        } catch {
            LPLog.app.error("schedule local erase failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Runs the scheduled erase, synchronously, if the marker exists. Must be
    /// called before anything opens persistent state.
    @discardableResult
    static func eraseIfScheduled(locations: Locations = .live) -> Bool {
        guard isScheduled(locations: locations) else { return false }
        LPLog.app.notice("erasing local data after account deletion")
        let fm = FileManager.default
        let marker = markerURL(in: locations).standardizedFileURL
        for domain in locations.defaultsDomains {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        }
        for directory in locations.directories {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                try? fm.removeItem(at: directory)
                continue
            }
            let contents = (try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            for url in contents where url.standardizedFileURL != marker {
                do {
                    try fm.removeItem(at: url)
                } catch {
                    LPLog.app.error("erase \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        try? fm.removeItem(at: marker)
        return true
    }
}
