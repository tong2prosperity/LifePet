import Foundation
import PiboCore

enum PiboCoreRhythmTapAdapter {
    struct Config {
        let beatInterval: TimeInterval
        let countIn: TimeInterval
        let session: TimeInterval
        let debounce: TimeInterval
        let nearWindow: TimeInterval
    }

    enum Judgement: Equatable {
        case miss
        case nearEarly
        case nearLate
        case exact
        case duplicate
    }

    struct JudgeResult {
        let beat: Int
        let newCombo: Int
        let scoreGain: Int
        let judgement: Judgement
    }

    struct ExpiryResult {
        let latestExpiredBeat: Int
        let advanced: Bool
        let missed: Bool
    }

    static let config: Config = {
        let value = PiboCoreRhythmTap.config
        return Config(
            beatInterval: value.beatInterval,
            countIn: value.countIn,
            session: value.session,
            debounce: value.debounce,
            nearWindow: value.nearWindow
        )
    }()

    static func judge(
        elapsed: TimeInterval,
        lastJudgedBeat: Int,
        combo: Int
    ) -> JudgeResult {
        let result = PiboCoreRhythmTap.judge(
            elapsed: elapsed,
            lastJudgedBeat: lastJudgedBeat,
            combo: combo
        )
        return JudgeResult(
            beat: result.beat,
            newCombo: result.newCombo,
            scoreGain: result.scoreGain,
            judgement: Judgement(result.judgement)
        )
    }

    static func resolveExpired(
        elapsed: TimeInterval,
        lastResolvedBeat: Int,
        lastJudgedBeat: Int
    ) -> ExpiryResult {
        let result = PiboCoreRhythmTap.resolveExpired(
            elapsed: elapsed,
            lastResolvedBeat: lastResolvedBeat,
            lastJudgedBeat: lastJudgedBeat
        )
        return ExpiryResult(
            latestExpiredBeat: result.latestExpiredBeat,
            advanced: result.advanced,
            missed: result.missed
        )
    }
}

private extension PiboCoreRhythmTapAdapter.Judgement {
    init(_ judgement: PiboCoreRhythmTapJudgement) {
        switch judgement {
        case .miss: self = .miss
        case .nearEarly: self = .nearEarly
        case .nearLate: self = .nearLate
        case .exact: self = .exact
        case .duplicate: self = .duplicate
        }
    }
}
