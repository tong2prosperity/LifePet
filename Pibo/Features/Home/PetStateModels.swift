import Foundation

// MARK: - Pet state machine (PRD §5)

/// 6-state pet visual machine. MVP only animates `.normal` and `.excited`;
/// the other four resolve to label-only placeholders so the rule layer can
/// already produce them once HealthKit data is wired.
enum PetState: String {
    case sick, sleeping, tired, normal, excited, blissful

    var tag: String {
        switch self {
        case .sick:     return "SICK"
        case .sleeping: return "SLEEPING"
        case .tired:    return "TIRED"
        case .normal:   return "NORMAL"
        case .excited:  return "EXCITED"
        case .blissful: return "BLISSFUL"
        }
    }

    var showsSparkles: Bool { self == .excited || self == .blissful }
}

// MARK: - Stats

enum StatKind: Hashable {
    case vitality   // 💪 体力
    case energy     // ⚡ 精力
    case mood       // ❤️ 心情

    var label: String {
        switch self {
        case .vitality: return AppLocalization.text("✦ 活力星光")
        case .energy:   return AppLocalization.text("☾ 静息星光")
        case .mood:     return AppLocalization.text("❤️ 心绪回声")
        }
    }

    var sourceCopy: String {
        switch self {
        case .vitality: return AppLocalization.text("步数 · 运动分钟 · 活动卡路里")
        case .energy:   return AppLocalization.text("睡眠 · 深睡 · REM")
        case .mood:     return AppLocalization.text("HRV · 心率稳定度")
        }
    }

    var supplementCopy: String {
        switch self {
        case .vitality: return AppLocalization.text("走 1000 步 +4 星光 / 运动 10 分钟 +10")
        case .energy:   return AppLocalization.text("每睡 1 小时 +6 星光 / 深睡多 30 分钟 +15")
        case .mood:     return AppLocalization.text("冥想 5 分钟 +15 / 深呼吸 1 次 +3")
        }
    }
}

struct Stat: Identifiable {
    let id = UUID()
    let kind: StatKind
    var value: Int  // 0...100
}

/// One stat's change between two recomputes — used by `HomeView` to fire a
/// sparkle burst + toast when HealthKit pushes new data.
///
/// `id` makes every emit unique even when two consecutive deltas have the
/// same `(kind, delta)` — without it, SwiftUI's `onChange` would skip the
/// second sparkle because `Equatable` would call them equal.
struct StatDelta: Equatable, Sendable {
    let id: UUID
    let kind: StatKind
    let delta: Int
    let reason: String?

    init(kind: StatKind, delta: Int, reason: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.delta = delta
        self.reason = reason
    }
}

// MARK: - Pending workout (PRD §4 — 新事件通知)

/// 一次"刚同步过来的运动"待用户确认。`HealthDataService` 检测到 fresh
/// workout（≤5 min ago）→ `PetStateStore` 把它装进 `pendingWorkout` 而不
/// 立刻呈现；`HomeView` 看到非 nil 时弹 `WorkoutAlertSheet`。用户确认后
/// `consume(...)` 记录变化、插 done 卡并触发动画；用户划走或点 backdrop
/// 时 `dismiss(...)` 静默保存记录（不丢数据）。
///
/// Replay workouts（>5min 旧）走老路径：直接插展示卡，**不**入这个队列，
/// 因为它们的 vitality 已经被 aggregate snapshot 吸收过。
struct PendingWorkout: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let kind: HealthEvent.WorkoutKind
    /// "跑步" / "走路" / …
    let label: String
    /// 「跑步完成」 / 「走路完成」 — sheet 的标题
    var titleLabel: String { AppLocalization.format("%@完成", label) }
    let durationMin: Int
    let kcal: Double?
    let endedAt: Date
    /// PRD §3：workout 仅入 vitality。其他两栏在 sheet 上显示 —。
    let gainVitality: Int
}

/// Maps the workout vitality score to a bounded, perceptually smooth growth
/// step. The minimum keeps short workouts visible; the cap makes the sprout a
/// cumulative reward instead of allowing one workout to complete it.
enum PiboSproutGrowthModel {
    static func increment(forVitalityScore score: Int) -> Double {
        let normalized = min(max(Double(score) / 60, 0), 1)
        let smooth = normalized * normalized * (3 - 2 * normalized)
        return 0.08 + (0.24 - 0.08) * smooth
    }

    static func target(current: Double, vitalityScore: Int) -> Double {
        min(1, max(0, current) + increment(forVitalityScore: vitalityScore))
    }
}

// MARK: - Step cards (PRD §4)

enum StepStatus: Hashable { case done, suggest }

enum StepKind: String, Hashable {
    case run, sleep, breath, meditate, walk

    var quitLabel: String {
        switch self {
        case .run:      return AppLocalization.text("跑步")
        case .sleep:    return AppLocalization.text("睡眠")
        case .breath:   return AppLocalization.text("深呼吸")
        case .meditate: return AppLocalization.text("冥想")
        case .walk:     return AppLocalization.text("走路")
        }
    }
}

struct StepItem: Identifiable, Hashable {
    let id = UUID()
    var status: StepStatus
    var kind: StepKind
    var actionLabel: String
    var titleValue: String
    var affects: StatKind
    var gain: Int
    var time: String
    var fromAutoSensor: Bool

    var displayTitleLead: String {
        switch status {
        case .suggest: return AppLocalization.format("建议: %@", actionLabel)
        case .done:    return actionLabel
        }
    }
}
