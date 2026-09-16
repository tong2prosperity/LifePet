import Foundation
import Testing
@testable import Pibo

@MainActor
struct StatusObserverPresentationStoreTests {
    @Test func viewingIsTransientAndResetsExpansion() {
        let store = StatusObserverPresentationStore()
        #expect(!store.isOpen)
        store.open()
        store.setExpanded(true)
        #expect(store.isOpen && store.expanded && !store.usesSample)
        store.close()
        #expect(!store.isOpen && !store.expanded)
        store.open()
        #expect(!store.expanded, "reopening never restores the previous expansion")
    }

    @Test func sampleModeEndsWithTheView() {
        let store = StatusObserverPresentationStore()
        store.open(sample: true)
        #if DEBUG
        #expect(store.usesSample)
        #endif
        store.close()
        #expect(!store.usesSample)
    }

    @Test func freshStoreIgnoresTheLegacyPin() throws {
        let key = PiboPersistenceKeys.Defaults.wellnessObserverPinnedPetIDs
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set([UUID().uuidString], forKey: key)
        #expect(!StatusObserverPresentationStore().isOpen)
    }
}
