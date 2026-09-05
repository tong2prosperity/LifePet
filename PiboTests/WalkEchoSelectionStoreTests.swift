import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
struct WalkEchoSelectionStoreTests {
    @Test func missingSourceClearsTheStableSelection() throws {
        let suite = "WalkEchoSelectionStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WalkEchoSelectionStore(defaults: defaults)
        let petID = UUID()
        let routeID = UUID()

        store.select(routeID, petID: petID)
        #expect(store.validatedSelection(petID: petID, availableIDs: [routeID]) == routeID)
        #expect(store.validatedSelection(petID: petID, availableIDs: []) == nil)
        #expect(store.selectedID(petID: petID) == nil)
    }
}
