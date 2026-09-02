import Foundation
import Testing
@testable import Pibo

@MainActor
struct StatusObserverPresentationStoreTests {
    @Test func pinnedChoicePersistsPerPetWhileExpansionDoesNot() throws {
        let suite = "StatusObserverPresentationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "test.status-observer"
        let firstPet = UUID()
        let secondPet = UUID()

        let firstStore = StatusObserverPresentationStore(
            defaults: defaults,
            persistenceKey: key
        )
        #expect(firstStore.togglePinned(petID: firstPet))
        firstStore.setExpanded(true)
        #expect(firstStore.isPinned(petID: firstPet))
        #expect(!firstStore.isPinned(petID: secondPet))
        #expect(firstStore.expanded)

        let restored = StatusObserverPresentationStore(
            defaults: defaults,
            persistenceKey: key
        )
        #expect(restored.isPinned(petID: firstPet))
        #expect(!restored.isPinned(petID: secondPet))
        #expect(!restored.expanded)
    }

    @Test func unpinCollapsesAndResetRemovesAllPersistedChoices() throws {
        let suite = "StatusObserverPresentationStoreReset.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "test.status-observer"
        let pet = UUID()
        let store = StatusObserverPresentationStore(defaults: defaults, persistenceKey: key)

        store.togglePinned(petID: pet)
        store.setExpanded(true)
        #expect(!store.togglePinned(petID: pet))
        #expect(!store.expanded)

        store.togglePinned(petID: pet)
        store.reset()
        #expect(!store.isPinned(petID: pet))
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func invalidPersistedIdentifiersAreIgnored() throws {
        let suite = "StatusObserverPresentationStoreInvalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "test.status-observer"
        let pet = UUID()
        defaults.set(["not-a-uuid", pet.uuidString], forKey: key)

        let store = StatusObserverPresentationStore(defaults: defaults, persistenceKey: key)

        #expect(store.isPinned(petID: pet))
    }
}
