#if DEBUG
import Foundation

/// Explicit, in-memory visual fixtures. They never enter WCSession, defaults,
/// HealthKit, a bo ledger, or a backend. Release has no preview entry point.
enum WatchCompanionPreview {
    static func snapshotIfRequested() -> PiboCompanionSnapshot? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PiboWatchPreview"),
              arguments.indices.contains(index + 1) else { return nil }
        let scenario = arguments[index + 1]
        let now = Date()
        let date = scenario == "cached" ? now.addingTimeInterval(-172_800) : now
        let unknown = scenario == "unknown"
        let state = ["sleeping", "waking", "energetic", "tired"].contains(scenario) ? scenario : unknown ? "dataUnknown" : "stable"
        let action: String = switch state {
        case "sleeping": "letSleep"
        case "waking": "morningGreeting"
        case "energetic": "play"
        case "tired": "rest"
        case "dataUnknown": "checkConnection"
        default: "checkIn"
        }
        let friend = PiboCompanionShadowSnapshot(
            displayName: "小岚", publicStateID: "stable", publicBehaviorSubstateID: "stable.idle",
            visualVariantKey: "pibo-state-stable-forest-idle", revision: 3,
            occurredAt: date, syncedAt: date
        )
        return PiboCompanionSnapshot(
            schemaVersion: 2, petName: "Pibo", dayStart: Calendar.current.startOfDay(for: date),
            generatedAt: date, publicStateID: state, animationStateID: "preview-\(state)",
            stateLabel: WatchPiboStatusStore.stateLabel(for: state),
            activeEnergy: 186, exerciseMinutes: 22, standHours: 1,
            moveProgress: 0.5, exerciseProgress: 0.7, standProgress: 0.5,
            sceneID: .riverValley, shadow: nil,
            petID: UUID(uuidString: "D1111111-1111-1111-1111-111111111111")!,
            stateGeneratedAt: date, patActionID: action,
            growth: unknown ? nil : PiboCompanionGrowth(
                stage: scenario == "ripe" ? "ripe" : "forming",
                progress: scenario == "ripe" ? 1 : 0.64, ripeCount: scenario == "ripe" ? 1 : 0
            ),
            capabilities: [PiboCompanionCapability(id: "hammock", title: "吊床", detail: "会使用吊床，和你回看睡眠")],
            healthMessage: unknown ? "还没有可读取的健康记录，Pibo 会继续等你" : nil,
            shadowConnection: PiboCompanionShadowConnection(
                status: scenario == "cached" ? .paused : .active,
                accountID: "preview", relationshipID: "preview-friend", displayName: "小岚", snapshot: friend
            )
        )
    }
}
#endif
