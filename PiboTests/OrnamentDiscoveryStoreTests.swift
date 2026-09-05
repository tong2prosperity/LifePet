import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct OrnamentDiscoveryStoreTests {
    @Test func pendingDiscoverySurvivesInterruptionAndIsScopedPerPibo() throws {
        let suite = "OrnamentDiscoveryStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstPibo = UUID()
        let secondPibo = UUID()

        OrnamentDiscoveryStore(defaults: defaults).markPending(.statusObserver, petID: firstPibo)
        let relaunched = OrnamentDiscoveryStore(defaults: defaults)
        #expect(relaunched.pending(petID: firstPibo) == .statusObserver)
        #expect(relaunched.pending(petID: secondPibo) == nil)

        relaunched.complete(.chime, petID: firstPibo)
        #expect(relaunched.pending(petID: firstPibo) == .statusObserver)
        relaunched.complete(.statusObserver, petID: firstPibo)
        #expect(relaunched.pending(petID: firstPibo) == nil)
    }
}
