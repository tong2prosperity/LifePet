import Foundation
import os

nonisolated enum PiboPersistenceKeys {
    enum Defaults {
        static let onboardingDone = "pibo.onboardingDone.v1"
        static let onboardingResumeAuth = "pibo.onboarding.resumeAuth.v1"
        static let hatched = "pibo.hatched.v1"
        static let appLanguage = "pibo.appLanguage.v1"
        static let selectedThemeID = "pibo.theme.selectedID.v1"
        static let ambientSoundEnabled = "pibo.audio.ambientEnabled.v1"

        static let identityCurrentPetId = "pibo.identity.currentPetId.v1"
        static let identityPetName = "pibo.identity.petName.v1"
        static let identityOwnerName = "pibo.identity.ownerName.v1"
        static let identityBirthDate = "pibo.identity.birthDate.v1"

        static let workoutAnchor = "pibo.healthkit.workoutAnchor.v1"
        static let healthKitAuthorized = "pibo.healthkit.authorized.v1"

        static let lastSeenDate = "pibo.dayRollover.lastSeenDate.v1"
        static let lastDecayAt = "pibo.decay.lastDecayAt.v1"
        static let pendingWorkout = "pibo.pendingWorkout.v1"
        static let debugHistorySeedState = "pibo.debug.historySeedState.v1"
        static let huarongRoadDifficulty = "pibo.games.huarongRoad.difficulty.v1"
        static let huarongRoadBestMovesPrefix = "pibo.games.huarongRoad.bestMoves.v1."
        static let memoryMatrixDifficulty = "pibo.games.memoryMatrix.difficulty.v1"
        static let dualNBackLevel = "pibo.games.dualNBack.level.v1"
        static let miniGameBestScorePrefix = "pibo.games.bestScore.v1."
        static let miniGamePetalBalance = "pibo.games.petalBalance.v1"
        static let idleGardenLastCollectAt = "pibo.games.idleGarden.lastCollectAt.v1"
        static let idleGardenSeeds = "pibo.games.idleGarden.seeds.v1"
        static let idleGardenPlantedPlots = "pibo.games.idleGarden.plantedPlots.v1"

        static let lifepetMigrationDone = "pibo.migration.lifepet.v1.done"

        static let legacyPairs: [(legacy: String, current: String)] = [
            ("lifepet.onboardingDone", onboardingDone),
            ("lifepet.hatched", hatched),
            ("lifepet.identity.currentPetId.v1", identityCurrentPetId),
            ("lifepet.identity.petName.v1", identityPetName),
            ("lifepet.identity.ownerName.v1", identityOwnerName),
            ("lifepet.identity.birthDate.v1", identityBirthDate),
            ("lifepet.healthkit.workoutAnchor.v1", workoutAnchor),
            ("lifepet.healthkit.authorized.v1", healthKitAuthorized),
            ("lifepet.dayRollover.lastSeenDate.v1", lastSeenDate),
            ("lifepet.decay.lastDecayAt.v1", lastDecayAt),
            ("lifepet.pendingWorkout.v1", pendingWorkout),
        ]
    }

    enum Paths {
        static let historyDirectory = "pibo/history"
        static let legacyHistoryDirectory = "lifepet/history"
    }
}

nonisolated enum PiboPersistenceMigrator {
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard !defaults.bool(forKey: PiboPersistenceKeys.Defaults.lifepetMigrationDone) else {
            return
        }

        migrateDefaults(defaults)
        migrateHistory(fileManager)
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.lifepetMigrationDone)
    }

    private static func migrateDefaults(_ defaults: UserDefaults) {
        for pair in PiboPersistenceKeys.Defaults.legacyPairs {
            guard defaults.object(forKey: pair.current) == nil,
                  let legacyValue = defaults.object(forKey: pair.legacy)
            else { continue }

            defaults.set(legacyValue, forKey: pair.current)
        }
    }

    private static func migrateHistory(_ fileManager: FileManager) {
        guard let support = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return }

        let legacy = support.appendingPathComponent(
            PiboPersistenceKeys.Paths.legacyHistoryDirectory,
            isDirectory: true
        )
        let current = support.appendingPathComponent(
            PiboPersistenceKeys.Paths.historyDirectory,
            isDirectory: true
        )

        guard fileManager.fileExists(atPath: legacy.path) else { return }

        do {
            if fileManager.fileExists(atPath: current.path) {
                try mergeDirectory(from: legacy, into: current, fileManager: fileManager)
            } else {
                try fileManager.createDirectory(
                    at: current.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: legacy, to: current)
            }
            LPLog.app.notice("Migrated legacy lifepet history to pibo history")
        } catch {
            LPLog.app.error("Legacy history migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func mergeDirectory(
        from source: URL,
        into destination: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for case let sourceURL as URL in enumerator {
            let prefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
            let relativePath = sourceURL.path.replacingOccurrences(
                of: prefix,
                with: "",
                options: [.anchored]
            )
            let destinationURL = destination.appendingPathComponent(relativePath)
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else if !fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }
}
