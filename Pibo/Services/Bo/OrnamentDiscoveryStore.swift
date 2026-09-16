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
    /// Decision 048: after the next target is revealed its function half sheet
    /// opens once per pet and target; any close path counts as introduced.
    func needsIntroduction(_ id: PiboOrnament.ID, petID: UUID) -> Bool {
        !defaults.bool(forKey: introductionKey(id, petID))
    }
    func completeIntroduction(_ id: PiboOrnament.ID, petID: UUID) {
        defaults.set(true, forKey: introductionKey(id, petID))
    }
    private func introductionKey(_ id: PiboOrnament.ID, _ petID: UUID) -> String {
        "pibo.bo.ornamentIntroduced.\(petID.uuidString.lowercased()).\(id.rawValue).v1"
    }
    private func key(_ petID: UUID) -> String { "pibo.bo.ornamentDiscovery.pending.\(petID.uuidString.lowercased()).v1" }
}
