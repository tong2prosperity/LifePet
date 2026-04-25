import Foundation
import os

/// Owns the pet's identity bits — `currentPetId` (UUID), `petName`,
/// `ownerName`, `birthDate` — and persists them to UserDefaults. Separated
/// from `PetStateStore` so the catalog / history layers can talk about
/// *which* pet without going through the day-bound state machine, and so the
/// "what day are we on" computation has a stable anchor (`birthDate`)
/// instead of the previous hardcoded `dayCount = 7`.
///
/// Lifecycle:
/// - **First launch** — no persisted record → `init` seeds a fresh pet with a
///   new UUID, default `BEAN` / `FISH`, `birthDate = startOfDay(today)`.
/// - **Subsequent launches** — values restored from UserDefaults.
/// - **Demo mode opt-in** — `seedDemoBirth()` backdates `birthDate` so the
///   home screen reads "已陪伴第 7 天" out of the box (matches the demo copy
///   the prototype + PRD lock in).
/// - **Reset** — `resetToFreshPet()` mints a new UUID and re-seeds defaults.
///   Hackathon semantics: reset = "next pet, fresh start"; existing snapshots
///   (when persistence ships) stay accessible by `currentPetId`.
/// `nonisolated` rather than the project-default `@MainActor`: the class only
/// reads / writes `UserDefaults` (already thread-safe) and exposes value-typed
/// fields. Keeping it actor-free lets `PetStateStore.init`'s default argument
/// (`identity: PetIdentityStore = PetIdentityStore()`) compile from the
/// synthesized nonisolated default-arg getter, and lets `LifePulseApp.init`
/// (also nonisolated) construct it directly. SwiftUI's `@Observable` does not
/// require MainActor — the observation tracking machinery is thread-safe.
@Observable
nonisolated final class PetIdentityStore {

    // MARK: - Persistence keys

    private static let petIdKey     = "lifepet.identity.currentPetId.v1"
    private static let petNameKey   = "lifepet.identity.petName.v1"
    private static let ownerNameKey = "lifepet.identity.ownerName.v1"
    private static let birthDateKey = "lifepet.identity.birthDate.v1"

    // MARK: - Identity (each `didSet` writes through to UserDefaults)

    var currentPetId: UUID {
        didSet { UserDefaults.standard.set(currentPetId.uuidString, forKey: Self.petIdKey) }
    }
    var petName: String {
        didSet { UserDefaults.standard.set(petName, forKey: Self.petNameKey) }
    }
    var ownerName: String {
        didSet { UserDefaults.standard.set(ownerName, forKey: Self.ownerNameKey) }
    }
    /// Always normalized to `startOfDay`. Day computations elsewhere assume
    /// midnight-aligned anchors; storing the seed time would make
    /// `daysSinceBirth` race the user's wake-up.
    var birthDate: Date {
        didSet {
            UserDefaults.standard.set(birthDate.timeIntervalSince1970, forKey: Self.birthDateKey)
        }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        if let idStr = defaults.string(forKey: Self.petIdKey), let id = UUID(uuidString: idStr) {
            self.currentPetId = id
            self.petName = defaults.string(forKey: Self.petNameKey) ?? "BEAN"
            self.ownerName = defaults.string(forKey: Self.ownerNameKey) ?? "FISH"
            let ts = defaults.double(forKey: Self.birthDateKey)
            let restored = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
            self.birthDate = Calendar.current.startOfDay(for: restored)
            LPLog.identity.notice("restored pet=\(self.petName, privacy: .public) id=\(id.uuidString, privacy: .public) day=\(Self.daysSince(self.birthDate), privacy: .public)")
        } else {
            self.currentPetId = UUID()
            self.petName = "BEAN"
            self.ownerName = "FISH"
            self.birthDate = Calendar.current.startOfDay(for: Date())
            LPLog.identity.notice("seeded fresh pet id=\(self.currentPetId.uuidString, privacy: .public)")
            // didSet doesn't fire from init — write seeds explicitly.
            defaults.set(currentPetId.uuidString, forKey: Self.petIdKey)
            defaults.set(petName, forKey: Self.petNameKey)
            defaults.set(ownerName, forKey: Self.ownerNameKey)
            defaults.set(birthDate.timeIntervalSince1970, forKey: Self.birthDateKey)
        }
    }

    // MARK: - Derived

    /// "已陪伴第 N 天" — birth day = day 1. Always ≥ 1 (a backdated `birthDate`
    /// in the future, e.g. from clock skew, still reads as day 1 instead of 0
    /// or negative).
    var daysSinceBirth: Int { Self.daysSince(birthDate) }

    private static func daysSince(_ birth: Date) -> Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: birth)
        let to = cal.startOfDay(for: Date())
        let d = cal.dateComponents([.day], from: from, to: to).day ?? 0
        return max(1, d + 1)
    }

    // MARK: - Mutations

    /// Mint a new pet UUID + reset name / birth to defaults. Called from
    /// `PetStateStore.reset()`. Doesn't touch HealthKit, snapshots, or any
    /// other persisted state — those are owned by their respective stores.
    func resetToFreshPet() {
        currentPetId = UUID()
        petName = "BEAN"
        ownerName = "FISH"
        birthDate = Calendar.current.startOfDay(for: Date())
        LPLog.identity.notice("reset → new pet id=\(self.currentPetId.uuidString, privacy: .public)")
    }

    /// Backdate `birthDate` to `today − 6` so `daysSinceBirth == 7`. Called
    /// when the user picks "用 Demo 数据继续" in onboarding so the demo path
    /// matches the locked-in `D07` copy without additional flags.
    ///
    /// Idempotent: re-applying on day N yields the same display ("第 7 天")
    /// because birthDate moves with `today`. The cost is that demo `dayCount`
    /// never advances past 7 — that's the right behavior; demo is a snapshot,
    /// not a simulation.
    func seedDemoBirth() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        birthDate = cal.date(byAdding: .day, value: -6, to: today) ?? today
        LPLog.identity.notice("demo birth seeded — daysSinceBirth=\(self.daysSinceBirth, privacy: .public)")
    }
}
