import Foundation
import Observation
import os

/// 已解锁物件的集合。
///
/// 和 `BoLedgerStore` 分开，是因为两者的**失效语义不同**：账本是余额，可以增可以减；
/// 解锁是一次性的既成事实，只增不减。混在一份状态里，将来任何一次账本重置都会顺手
/// 把用户已经换到的东西一起抹掉。
@MainActor
@Observable
final class OrnamentUnlockStore {

    private(set) var unlocked: Set<PiboOrnament.ID>
    private(set) var hasSeenUnlockGuide: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.boUnlockedOrnaments
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.hasSeenUnlockGuide = defaults.bool(
            forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen
        )

        let stored = (defaults.array(forKey: persistenceKey) as? [String]) ?? []
        var resolved = Set(stored.compactMap(PiboOrnament.ID.init(rawValue:)))
        // 开局即赠的物件每次都补齐 —— 它们本来就在场景里，靠存储去记「有没有」
        // 只会多一条可能出错的路径。
        for ornament in PiboOrnament.all where ornament.isGrantedAtStart {
            resolved.insert(ornament.id)
        }
        self.unlocked = resolved
        persist()
    }

    func isUnlocked(_ id: PiboOrnament.ID) -> Bool { unlocked.contains(id) }

    var nextLocked: PiboOrnament? {
        PiboOrnament.ordered.first { !unlocked.contains($0.id) }
    }

    func canUnlock(_ id: PiboOrnament.ID, balance: Int) -> Bool {
        guard let nextLocked else { return false }
        return nextLocked.id == id && balance >= nextLocked.cost
    }

    func shouldHighlightUnlockGuide(balance: Int) -> Bool {
        guard !hasSeenUnlockGuide, let first = PiboOrnament.ordered.first else { return false }
        return !isUnlocked(first.id) && balance >= first.cost
    }

    func markUnlockGuideSeen() {
        guard !hasSeenUnlockGuide else { return }
        hasSeenUnlockGuide = true
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen)
    }

    /// 记录一次解锁。**不碰余额** —— 扣费由调用方先在账本上完成，成功了再调这里，
    /// 免得两份状态各自为政。
    func markUnlocked(_ id: PiboOrnament.ID) {
        guard !unlocked.contains(id) else { return }
        unlocked.insert(id)
        persist()
        LPLog.bo.notice("ornament unlocked=\(id.rawValue, privacy: .public)")
    }

    /// 场景要画的那些物件（开局即赠的除外 —— 它们已经是森林底图的一部分）。
    var renderableLayers: [PiboOrnament] {
        PiboOrnament.ordered.filter { unlocked.contains($0.id) && $0.placement != nil }
    }

    func reset() {
        unlocked = Set(PiboOrnament.all.filter(\.isGrantedAtStart).map(\.id))
        persist()
    }

    private func persist() {
        defaults.set(unlocked.map(\.rawValue).sorted(), forKey: persistenceKey)
    }
}
