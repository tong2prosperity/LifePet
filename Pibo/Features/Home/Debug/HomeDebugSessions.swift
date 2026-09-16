#if DEBUG
import Foundation
import PiboCore

/// In-memory bo container for the DEV dock. Production Core decides collection
/// and reserve conversion; nothing here touches the real ledger or sync.
@MainActor
@Observable
final class HomeDebugBoSession {
    private(set) var pool: Double = 0
    private(set) var ripe: UInt32 = 0
    private(set) var balance: UInt32 = 0

    init(preset: String) {
        let unit = PiboCoreBoEconomy.energyPerBo
        ripe = ["ripe", "reserve", "effect"].contains(preset) ? 1 : 0
        pool = switch preset {
        case "reserve": unit * 2
        case "almost": unit * 0.9
        case "charging": unit * 0.4
        default: 0
        }
    }

    var hasRipe: Bool { ripe > 0 }
    var progress: Double { ripe > 0 ? 1 : min(1, pool / max(0.001, PiboCoreBoEconomy.energyPerBo)) }
    var growthStage: PiboCoreBoGrowthStage {
        PiboCoreBoEconomy.growthStage(energyPool: pool, ripeCount: Int(ripe))
    }

    func collect() -> Bool {
        let result = PiboBoContainer.step(pool: pool, ripe: ripe, stored: balance, collect: true)
        guard result.collected else { return false }
        pool = result.energyPool
        ripe = result.ripeCount
        balance = result.storedCount
        return true
    }
}

/// One of the 27 Core pat contexts, rehearsed against an isolated conversation
/// store so the real cursor, events and history are never advanced.
struct HomePatDebugScenario: Equatable {
    let id: String
    let title: String
    let state: PiboActivityState
    var stableThinking = false
    var ambientEvent: PiboCorePatEvent = .none
    var event: PiboCorePatEvent = .none
    var dataUnknownReason: PiboCorePatDataUnknownReason = .waitingData
    var touchDiscoveryCompleted = 3
    var needsPriorTurn = false

    static let all: [HomePatDebugScenario] = [
        .init(id: "stable.touchDiscovery", title: "初次被拍", state: .stable, touchDiscoveryCompleted: 0),
        .init(id: "stable.idle", title: "日常回应", state: .stable),
        .init(id: "stable.thinking", title: "正在想事", state: .stable, stableThinking: true),
        .init(id: "stable.steps", title: "今日步数", state: .stable, event: .steps),
        .init(id: "stable.sleep", title: "昨晚睡眠", state: .stable, event: .sleep),
        .init(id: "stable.sleepTogether", title: "一起睡过", state: .stable, event: .sleepTogether),
        .init(id: "energetic.ready", title: "精神正好", state: .energetic),
        .init(id: "energetic.workout.run", title: "刚跑完步", state: .energetic, event: .workoutRun),
        .init(id: "energetic.workout.walk", title: "刚走完路", state: .energetic, event: .workoutWalk),
        .init(id: "energetic.workout.cycle", title: "刚骑完车", state: .energetic, event: .workoutCycle),
        .init(id: "energetic.workout.swim", title: "刚游完泳", state: .energetic, event: .workoutSwim),
        .init(id: "energetic.workout.hiit", title: "刚做完训练", state: .energetic, event: .workoutHiit),
        .init(id: "energetic.workout.yoga", title: "刚做完瑜伽", state: .energetic, event: .workoutYoga),
        .init(id: "energetic.workout.other", title: "其他运动", state: .energetic, event: .workoutOther),
        .init(id: "energetic.activityMilestone", title: "达到里程碑", state: .energetic, event: .activityMilestone),
        .init(id: "energetic.goodSleep", title: "睡得很好", state: .energetic, event: .goodSleep),
        .init(id: "tired.insufficientSleep", title: "睡眠不足", state: .tired, event: .insufficientSleep),
        .init(id: "tired.awake", title: "还醒着", state: .tired),
        .init(id: "tired.resting", title: "已经坐下", state: .tired, needsPriorTurn: true),
        .init(id: "waking.orienting", title: "刚刚醒来", state: .waking),
        .init(id: "waking.recovering", title: "醒来恢复中", state: .waking, ambientEvent: .insufficientSleep),
        .init(id: "waking.greeted", title: "已经问候", state: .waking, needsPriorTurn: true),
        .init(id: "sleeping.asleep", title: "正在睡觉", state: .sleeping),
        .init(id: "dataUnknown.authorization", title: "尚未授权", state: .dataUnknown, dataUnknownReason: .authorization),
        .init(id: "dataUnknown.waitingData", title: "等待首批数据", state: .dataUnknown),
        .init(id: "dataUnknown.unavailable", title: "服务不可用", state: .dataUnknown, dataUnknownReason: .unavailable),
        .init(id: "dataUnknown.interruptedNoTrustedState", title: "同步中断", state: .dataUnknown, dataUnknownReason: .interruptedNoTrustedState),
    ]
}

@MainActor
final class HomePatDebugSession {
    private(set) var scenarioIndex: Int
    private(set) var store: PiboPatConversationStore
    private var suiteName: String

    init(scenarioIndex: Int = 0) {
        self.scenarioIndex = scenarioIndex
        suiteName = "pibo.debug.pat.\(UUID().uuidString)"
        store = PiboPatConversationStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        prepare()
    }

    var scenario: HomePatDebugScenario { HomePatDebugScenario.all[scenarioIndex] }

    func advanceScenario() {
        scenarioIndex = (scenarioIndex + 1) % HomePatDebugScenario.all.count
        reset()
    }

    func reset() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        suiteName = "pibo.debug.pat.\(UUID().uuidString)"
        store = PiboPatConversationStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        prepare()
    }

    func input() -> PiboPatConversationInput {
        let scenario = scenario
        var input = PiboPatConversationInput(
            state: scenario.state,
            episodeKey: "debug:\(scenario.id)",
            stableThinking: scenario.stableThinking,
            ambientEvent: scenario.ambientEvent,
            dataUnknownReason: scenario.dataUnknownReason,
            storyStage: "unresponded",
            values: ["steps": "8,246", "sleepDuration": "7.8 小时"]
        )
        if scenario.event != .none {
            input.events = [PiboPatEventCandidate(
                event: scenario.event,
                token: "debug:\(scenario.id):\(UUID().uuidString)",
                values: input.values
            )]
        }
        return input
    }

    func resolve() -> PiboPatResolution {
        store.resolve(input())
    }

    private func prepare() {
        store.debugSetTouchDiscoveryCompleted(scenario.touchDiscoveryCompleted)
        if scenario.needsPriorTurn {
            _ = store.resolve(input(), at: Date().addingTimeInterval(-3600))
        }
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}
#endif
