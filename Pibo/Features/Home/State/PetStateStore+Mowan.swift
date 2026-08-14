import SwiftUI
import os

// MARK: - 魔丸态 derived model (pibo-home-features-spec.md)
//
// The new home reads state + copy **directly** from raw HealthKit + time of day
// — no 体力/精力/心情 layer. This extension is the whole derived surface the new
// UI (greeting / SpriteKit stage / 拍一拍 / 拔毛 / Dashboard) consumes. Stored
// raw accessors live on `PetStateStore` itself. Pat history and authored copy
// are intentionally outside this legacy state surface.

/// Pibo's activity-zone state (spec §3.1). Priority on derivation:
/// 深眠 > 初醒 > 活跃/烦躁 > 发呆, with 被打扰 highest when triggered.
enum PiboActivityState: String, CaseIterable {
    case deepSleep   // 深眠
    case waking      // 初醒
    case active      // 活跃
    case irritated   // 烦躁
    case idle        // 发呆
    case disturbed   // 被打扰

    var displayName: String {
        switch self {
        case .deepSleep: return AppLocalization.text("深眠")
        case .waking:    return AppLocalization.text("初醒")
        case .active:    return AppLocalization.text("活跃")
        case .irritated: return AppLocalization.text("烦躁")
        case .idle:      return AppLocalization.text("发呆")
        case .disturbed: return AppLocalization.text("被打扰")
        }
    }

}

/// Legacy Core adapter result kept for ABI-facing integration tests. Product
/// presentation no longer grades or varies `bo` copy by this value.
enum PluckGrade: String {
    case good
    case fair
    case poor
}

extension PetStateStore {

    // MARK: Greeting (spec §2)

    /// Spec §2.1 time bands. Each maps to a copy pool; the line is drawn once
    /// per day (deterministic by day-of-year so it's stable until midnight).
    private func greetingPool(at date: Date) -> [String] {
        switch PiboCoreGreetingAdapter.band(at: date) {
        case .dawn:      return ["早上好", "起得早", "新的一天", "天亮了"]
        case .morning:   return ["上午好", "今天开始了", "该出门了", "准备好了？"]
        case .midday:    return ["中午好", "该休息了", "吃饭了", "歇会儿吧"]
        case .afternoon: return ["下午好", "还在忙？", "过半了", "加油"]
        case .dusk:      return ["傍晚了", "天快黑了", "该回家了", "快日落了"]
        case .evening:   return ["晚上好", "今天怎么样", "该放松了", "休息吧"]
        case .lateNight: return ["还没睡？", "深夜了", "该休息了", "夜猫子"]
        }
    }

    /// 称呼: Day 1–14 always 人; Day 15+ the user nickname (fallback 人).
    private var greetingAddress: String {
        let name = ownerName.trimmingCharacters(in: .whitespaces)
        return PiboCoreGreetingAdapter.usesOwnerName(
            dayCount: dayCount,
            hasOwnerName: !name.isEmpty
        ) ? name : AppLocalization.text("人")
    }

    /// Full greeting line `{称呼}，[文案]` (spec §2.1).
    var mowanGreeting: String {
        let now = Date()
        let pool = greetingPool(at: now)
        let index = PiboCoreGreetingAdapter.lineIndex(at: now, lineCount: pool.count)
        let line = pool[index]
        return "\(greetingAddress)，\(AppLocalization.text(line))"
    }

    /// Spec §2.2 — fixed format.
    var relationshipDayLabel: String {
        AppLocalization.format("与Pibo相识的第 %d 天", dayCount)
    }

    // MARK: Activity state (spec §3.1)

    /// Derived 6-state per spec §3.1 priority. Falls back to a time-only read
    /// until real HealthKit data lands (so an empty device / demo doesn't read
    /// as 烦躁).
    var activityState: PiboActivityState {
        let now = Date()
        return PiboCoreActivityAdapter.state(
            localHour: Double(Calendar.current.component(.hour, from: now)),
            recentPatCount: animationExperience.angryActive(at: now) ? 3 : 0,
            postPluckSleep: false,
            hasRealHealthData: hasRealHealthData,
            steps: rawSteps,
            hasWorkoutToday: hasWorkoutToday,
            sleepHours: rawSleepHours
        )
    }

    /// 初醒 sub-state: did the user sleep enough last night (≥7h)? `nil` when no
    /// sleep data, so the UI can fall back to the neutral 初醒 art.
    var wakingSleptEnough: Bool? {
        PiboCoreActivityAdapter.wakingSleptEnough(sleepHours: rawSleepHours)
    }

}
