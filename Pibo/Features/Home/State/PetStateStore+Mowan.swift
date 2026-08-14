import SwiftUI
import os
import PiboCore

// MARK: - 魔丸态 derived model (pibo-home-features-spec.md)
//
// The new home reads state + copy **directly** from raw HealthKit + time of day
// — no 体力/精力/心情 layer. This extension is the whole derived surface the new
// UI (greeting / SpriteKit stage / 拍一拍 / 拔毛 / Dashboard) consumes. Stored
// raw accessors live on `PetStateStore` itself. Pat history and authored copy
// are intentionally outside this legacy state surface.

/// Pibo's one durable ambient state. Core derives this from the learned sleep
/// routine and direct health observations; interactions remain short events.
enum PiboActivityState: String, CaseIterable {
    case dataUnknown
    case sleeping
    case waking
    case stable
    case energetic
    case tired

    init(core: PiboCoreState) {
        self = switch core {
        case .dataUnknown: .dataUnknown
        case .sleeping: .sleeping
        case .waking: .waking
        case .stable: .stable
        case .energetic: .energetic
        case .tired: .tired
        }
    }

    var core: PiboCoreState {
        switch self {
        case .dataUnknown: .dataUnknown
        case .sleeping: .sleeping
        case .waking: .waking
        case .stable: .stable
        case .energetic: .energetic
        case .tired: .tired
        }
    }

    var displayName: String {
        switch self {
        case .dataUnknown: return AppLocalization.text("等待数据")
        case .sleeping:    return AppLocalization.text("睡眠")
        case .waking:      return AppLocalization.text("初醒")
        case .stable:      return AppLocalization.text("安稳")
        case .energetic:   return AppLocalization.text("精神很好")
        case .tired:       return AppLocalization.text("疲倦")
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

    /// Last Core decision published by Home's state controller. This is a
    /// snapshot for widgets and platform presentation, never a second derivation.
    var activityState: PiboActivityState {
        piboAmbientState
    }

}
