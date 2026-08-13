import Foundation

struct MiniGameBestScoreStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bestScore(for kind: MiniGameKind) -> Int {
        defaults.integer(forKey: key(for: kind))
    }

    @discardableResult
    func record(_ score: Int, for kind: MiniGameKind) -> Bool {
        let key = key(for: kind)
        guard score > defaults.integer(forKey: key) else { return false }
        defaults.set(score, forKey: key)
        return true
    }

    func scoreText(_ score: Int, for kind: MiniGameKind) -> String {
        let best = max(score, bestScore(for: kind))
        return best > 0 ? "\(score) / \(best)" : "\(score)"
    }

    private func key(for kind: MiniGameKind) -> String {
        PiboPersistenceKeys.Defaults.miniGameBestScorePrefix + kind.rawValue
    }
}

struct MiniGameReward: Equatable {
    let petals: Int
    let balance: Int

    static let none = MiniGameReward(petals: 0, balance: 0)
}

struct MiniGameRewardStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func petalBalance() -> Int {
        defaults.integer(forKey: PiboPersistenceKeys.Defaults.miniGamePetalBalance)
    }

    @discardableResult
    func grantPetals(for score: Int, kind: MiniGameKind) -> MiniGameReward {
        let petals = Self.petals(for: score, kind: kind)
        guard petals > 0 else {
            return MiniGameReward(petals: 0, balance: petalBalance())
        }
        let balance = petalBalance() + petals
        defaults.set(balance, forKey: PiboPersistenceKeys.Defaults.miniGamePetalBalance)
        return MiniGameReward(petals: petals, balance: balance)
    }

    static func petals(for score: Int, kind: MiniGameKind) -> Int {
        PiboCoreMiniGameAdapter.petals(score: score, kind: kind)
    }
}

enum MiniGameScoring {
    static func starCount(score: Int, kind: MiniGameKind) -> Int {
        PiboCoreMiniGameAdapter.stars(score: score, kind: kind)
    }

    static func starText(score: Int, kind: MiniGameKind) -> String {
        let stars = starCount(score: score, kind: kind)
        let filled = String(repeating: "★", count: stars)
        let empty = String(repeating: "☆", count: max(0, 3 - stars))
        return "评价 \(filled)\(empty)"
    }

    static func resultMessage(kind: MiniGameKind, score: Int, best: Int, newBest: Bool, reward: MiniGameReward, fallback: String) -> String {
        let base = fallback
        let bestText = best > 0 ? "最高 \(best)" : "最高 \(score)"
        let recordText = newBest ? "新纪录 \(score)" : bestText
        let rewardText = reward.petals > 0 ? "收集到 \(reward.petals) 片花瓣 · 共 \(reward.balance)" : "花瓣先攒着"
        return "\(base)\n\(starText(score: score, kind: kind))\n\(recordText)\n\(rewardText)"
    }
}

func miniGameScoreText(for kind: MiniGameKind, score: Int) -> String {
    MiniGameBestScoreStore().scoreText(score, for: kind)
}

func miniGameRecordedResult(for kind: MiniGameKind, score: Int, fallback: String) -> String {
    let store = MiniGameBestScoreStore()
    let newBest = store.record(score, for: kind)
    let best = store.bestScore(for: kind)
    let reward = MiniGameRewardStore().grantPetals(for: score, kind: kind)
    miniGameTrackResult(kind: kind, score: score, reward: reward, newBest: newBest)
    return MiniGameScoring.resultMessage(kind: kind, score: score, best: best, newBest: newBest, reward: reward, fallback: fallback)
}

func miniGameTrackResult(kind: MiniGameKind, score: Int, reward: MiniGameReward, newBest: Bool = false) {
    Analytics.track(
        .miniGameFinish,
        screen: "mini_game",
        [
            "game": .string(kind.rawValue),
            "score": .int(score),
            "petals": .int(reward.petals),
            "new_best": .bool(newBest)
        ]
    )
}
