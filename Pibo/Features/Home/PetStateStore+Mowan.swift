import SwiftUI
import os

// MARK: - 魔丸态 derived model (pibo-home-features-spec.md)
//
// The new home reads state + copy **directly** from raw HealthKit + time of day
// — no 体力/精力/心情 layer. This extension is the whole derived surface the new
// UI (greeting / SpriteKit stage / 拍一拍 / 拔毛 / Dashboard) consumes. Stored
// hooks (`patSpeechTimes`, `pluckSleepUntil`, `lastPluckedDay`, raw accessors)
// live on `PetStateStore` itself.

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

    /// Pibo's spoken-line pool for this state (spec §3.3) — garbled-but-readable
    /// syllable fragments. `pat()` / `idleMutter()` draw from here.
    var speechPool: [String] {
        switch self {
        case .deepSleep: return ["...zzz...", "...花...睡了...", "...暗...", "...静..."]
        case .waking:    return ["...亮...？", "...花...醒了...", "...嗯...", "...花...精神..."]
        case .active:    return ["...热...", "...跳...", "...花...高兴...", "...发芽了啵！", "...亮..."]
        case .irritated: return ["...花...没精神...", "...暗...", "...不舒服...", "...花...蔫了...", "...别..."]
        case .idle:      return ["...云...在飘...", "...风...", "...颜色...好看...", "...形状...怪...", "...嗯...", "...？"]
        case .disturbed: return ["...别碰...", "...吵...", "...烦...", "...走..."]
        }
    }
}

/// 拔毛 grade (spec §3.5) — derived from last night's sleep + today's movement.
enum PluckGrade: String {
    case good   // 好 — 饱满鲜亮翠绿
    case fair   // 中 — 普通黄绿
    case poor   // 坏 — 干瘪灰褐

    var seedColor: Color {
        switch self {
        case .good: return Color(hex: 0x3FBF6E)
        case .fair: return Color(hex: 0xBFC75A)
        case .poor: return Color(hex: 0x9A8C6A)
        }
    }

    var piboLines: [String] {
        switch self {
        case .good: return ["...给...你...", "...花...送的...", "...拿着..."]
        case .fair: return ["...掉...", "...小...", "...嗯..."]
        case .poor: return ["...干...", "...皱...", "...花...不好..."]
        }
    }
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

    /// Whether ≥3 pat-lines landed in the last 10 minutes (the 被打扰 trigger
    /// and the 10-min speech cap share this count).
    private var recentPatCount: Int {
        let cutoff = Date().addingTimeInterval(-PiboCorePatAdapter.recentWindowSeconds)
        return patSpeechTimes.filter { $0 > cutoff }.count
    }

    /// Derived 6-state per spec §3.1 priority. Falls back to a time-only read
    /// until real HealthKit data lands (so an empty device / demo doesn't read
    /// as 烦躁).
    var activityState: PiboActivityState {
        let now = Date()
        return PiboCoreActivityAdapter.state(
            localHour: Double(Calendar.current.component(.hour, from: now)),
            recentPatCount: recentPatCount,
            postPluckSleep: pluckSleepUntil.map { $0 > now } ?? false,
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

    // MARK: 拍一拍 (spec §3.2 + Figma 76:6758)

    /// React to a pat. 不理睬 = Pibo 扭过头背对用户 (no text); otherwise a line
    /// with a mood (生气 also turns away). Caps: ≤3 lines / 10 min, ≤9 / 24h;
    /// under the caps 30% speak / 70% cold shoulder. A spoken line has a 25%
    /// chance of being the next 故事线 clue instead of state-pool copy.
    func pat() -> PatResponse {
        let now = Date()
        let in24h = patSpeechTimes.filter {
            now.timeIntervalSince($0) < PiboCorePatAdapter.dailyWindowSeconds
        }
        let in10m = patSpeechTimes.filter {
            now.timeIntervalSince($0) < PiboCorePatAdapter.recentWindowSeconds
        }
        // Prune so the array doesn't grow unbounded.
        patSpeechTimes = in24h

        let decision = PiboCorePatAdapter.decide(
            spokenIn24Hours: in24h.count,
            spokenIn10Minutes: in10m.count,
            speechRoll: Double.random(in: 0..<1),
            storyRoll: Double.random(in: 0..<1),
            hasUnrevealedStory: story.hasUnrevealedClue
        )
        guard decision != .ignored else { return .ignored }

        // 故事线: patting can shake the next clue loose (app 叙事).
        if decision == .storySpeech, let clue = story.revealNextClue() {
            patSpeechTimes.append(now)
            return PatResponse(line: PiboSpeechLine(text: clue.line, isStoryClue: true))
        }

        guard let text = activityState.speechPool.randomElement() else { return .ignored }
        patSpeechTimes.append(now)
        let mood = speechMood
        return PatResponse(line: PiboSpeechLine(text: text, mood: mood),
                           turnsAway: mood == .angry)
    }

    /// Bubble treatment for the current state: 烦躁/被打扰 grumble in the black
    /// 生气 bubble, 深眠 talks in its sleep (呓语), everything else is 正常.
    private var speechMood: PiboSpeechMood {
        PiboCoreActivityAdapter.speechMood(for: activityState)
    }

    /// Idle self-mutter (spec §3.3): ~20% chance, drawn from the 发呆 pool,
    /// drifting by as a 呓语. Driven by a timer in the view, not a pat — does
    /// not consume the caps.
    func idleMutter() -> PiboSpeechLine? {
        guard PiboCorePatAdapter.shouldIdleMutter(
            roll: Double.random(in: 0..<1)
        ) else { return nil }
        guard let text = PiboActivityState.idle.speechPool.randomElement() else { return nil }
        return PiboSpeechLine(text: text, mood: .murmur)
    }

    // MARK: 拔毛 (spec §3.5)

    /// 22:00–02:00 collection window.
    var pluckWindowOpen: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return PiboCorePluckAdapter.windowOpen(localHour: Double(h))
    }

    /// True when the window is open and the user hasn't collected tonight.
    /// "Tonight" anchors on the date the window opened (a 00:30 collection
    /// belongs to the previous calendar day's evening).
    var pluckAvailable: Bool {
        guard pluckWindowOpen else { return false }
        return lastPluckedDay.map { !Calendar.current.isDate($0, inSameDayAs: pluckNightAnchor) } ?? true
    }

    /// The calendar day that "owns" the current 22:00–02:00 window — the
    /// evening's date even when collected after midnight.
    private var pluckNightAnchor: Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: Date())
        let base = h < 2 ? Date().addingTimeInterval(-3 * 3600) : Date()
        return cal.startOfDay(for: base)
    }

    /// Grade tonight's 花籽 from sleep + movement (spec §3.5).
    var pluckGrade: PluckGrade {
        PiboCorePluckAdapter.grade(
            sleepHours: rawSleepHours,
            steps: rawSteps,
            hasWorkoutToday: hasWorkoutToday
        )
    }

    /// Collect tonight's 花籽. Records the night, drops Pibo into a 5-min 深眠,
    /// and returns the grade so the view can animate the seed + line.
    @discardableResult
    func pluck() -> PluckGrade {
        let grade = pluckGrade
        lastPluckedDay = pluckNightAnchor
        pluckSleepUntil = Date().addingTimeInterval(5 * 60)
        LPLog.petState.notice("拔毛 collected grade=\(grade.rawValue, privacy: .public)")
        return grade
    }

}
