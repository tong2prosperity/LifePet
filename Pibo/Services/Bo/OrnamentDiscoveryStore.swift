import Foundation

@MainActor
final class OrnamentDiscoveryStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func markPending(_ id: PiboOrnament.ID, petID: UUID) { defaults.set(id.rawValue, forKey: key(petID)) }
    func pending(petID: UUID) -> PiboOrnament.ID? { defaults.string(forKey: key(petID)).flatMap(PiboOrnament.ID.init(rawValue:)) }
    func complete(_ id: PiboOrnament.ID, petID: UUID) {
        guard pending(petID: petID) == id else { return }
        defaults.removeObject(forKey: key(petID))
    }
    private func key(_ petID: UUID) -> String { "pibo.bo.ornamentDiscovery.pending.\(petID.uuidString.lowercased()).v1" }
}
