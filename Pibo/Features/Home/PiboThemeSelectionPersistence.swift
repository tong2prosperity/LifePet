import Foundation

enum PiboThemeSelectionPersistence {
    static func restore(from defaults: UserDefaults = .standard) -> String {
        let persistedID = defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID)
        let resolvedID = PiboThemeCatalog.resolvedThemeID(persistedID)
        if persistedID != nil, persistedID != resolvedID {
            defaults.removeObject(forKey: PiboPersistenceKeys.Defaults.selectedThemeID)
        }
        return resolvedID
    }

    static func save(_ id: String, to defaults: UserDefaults = .standard) {
        guard PiboThemeCatalog.theme(id: id) != nil else { return }
        defaults.set(id, forKey: PiboPersistenceKeys.Defaults.selectedThemeID)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: PiboPersistenceKeys.Defaults.selectedThemeID)
    }
}
