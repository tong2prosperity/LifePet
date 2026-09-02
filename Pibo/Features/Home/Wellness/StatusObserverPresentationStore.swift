import Foundation
import Observation

/// Owns only the status observer's platform presentation state. The pinned
/// choice is per Pibo and durable; expansion is deliberately session-only.
@MainActor
@Observable
final class StatusObserverPresentationStore {
    private(set) var expanded = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private var pinnedPetIDs: Set<String>

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.wellnessObserverPinnedPetIDs
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        pinnedPetIDs = Set(
            (defaults.stringArray(forKey: persistenceKey) ?? [])
                .filter { UUID(uuidString: $0) != nil }
        )
    }

    func isPinned(petID: UUID) -> Bool {
        pinnedPetIDs.contains(petID.uuidString)
    }

    @discardableResult
    func togglePinned(petID: UUID) -> Bool {
        let key = petID.uuidString
        let isNowPinned: Bool
        if pinnedPetIDs.remove(key) != nil {
            expanded = false
            isNowPinned = false
        } else {
            pinnedPetIDs.insert(key)
            isNowPinned = true
        }
        persist()
        return isNowPinned
    }

    func setExpanded(_ expanded: Bool) {
        self.expanded = expanded
    }

    func reset() {
        pinnedPetIDs.removeAll()
        expanded = false
        defaults.removeObject(forKey: persistenceKey)
    }

    private func persist() {
        defaults.set(pinnedPetIDs.sorted(), forKey: persistenceKey)
    }
}
