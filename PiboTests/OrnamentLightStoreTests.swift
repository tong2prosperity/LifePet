import Foundation
import Testing
@testable import Pibo

/// 「点灯日」以**天亮**为界，不是午夜。三句需求是同一条规则的三个切面：
/// 天亮自动熄灯 / 白天也能点 / 白天点的要到第二天才熄。
@MainActor
private func makeStore(now: Date) -> (OrnamentLightStore, UserDefaults) {
    let suite = UserDefaults(suiteName: "ornament-light-\(UUID().uuidString)")!
    return (OrnamentLightStore(defaults: suite, calendar: calendar, now: now), suite)
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026, month: 8, day: day, hour: hour, minute: minute
    ))!
}

@MainActor
@Test func lightingDayRunsFromDaybreakNotMidnight() {
    // 午夜之后、天亮之前仍然属于前一个点灯日 —— 半夜两点点的灯是「昨晚」的灯。
    #expect(OrnamentLightStore.lightingDay(at: date(10, 2), calendar: calendar)
            == OrnamentLightStore.lightingDay(at: date(9, 23), calendar: calendar))
    // 天亮之后是新的一天。
    #expect(OrnamentLightStore.lightingDay(at: date(10, 9), calendar: calendar)
            != OrnamentLightStore.lightingDay(at: date(9, 23), calendar: calendar))
    // 同一个白天的不同时刻属于同一个点灯日。
    #expect(OrnamentLightStore.lightingDay(at: date(10, 9), calendar: calendar)
            == OrnamentLightStore.lightingDay(at: date(10, 22), calendar: calendar))
}

@MainActor
@Test func nightLampGoesOutAtDaybreak() {
    let (store, _) = makeStore(now: date(9, 23))
    store.light(.lantern, index: 0, now: date(9, 23))
    #expect(store.isLit(.lantern, index: 0))

    // 还在同一夜（凌晨两点）—— 不该熄。
    store.refresh(now: date(10, 2))
    #expect(store.isLit(.lantern, index: 0))

    // 天亮了 —— 熄。
    store.refresh(now: date(10, 9))
    #expect(!store.isLit(.lantern, index: 0))
}

@MainActor
@Test func daytimeLampSurvivesTheNightAndDiesNextMorning() {
    // 「白天也可以点亮，到第二天灯才会熄灭」——白天点的灯不能在当天的天亮
    // （已经过去了）被误判成过期。
    let (store, _) = makeStore(now: date(10, 14))
    store.light(.lantern, index: 2, now: date(10, 14))

    store.refresh(now: date(10, 23))
    #expect(store.isLit(.lantern, index: 2), "当晚必须还亮着")
    store.refresh(now: date(11, 3))
    #expect(store.isLit(.lantern, index: 2), "跨过午夜、天还没亮，仍然亮着")

    store.refresh(now: date(11, 9))
    #expect(!store.isLit(.lantern, index: 2), "第二天天亮才熄")
}

@MainActor
@Test func lampsAreLightOnlyAndIndependentPerBell() {
    let (store, _) = makeStore(now: date(10, 20))
    #expect(store.light(.lantern, index: 1, now: date(10, 20)))
    // 重复点同一盏不算变化 —— 调用方据此决定要不要给触觉反馈、要不要重播动画。
    #expect(!store.light(.lantern, index: 1, now: date(10, 20)))
    // 逐灯独立。
    #expect(!store.isLit(.lantern, index: 2))
    #expect(store.light(.lantern, index: 2, now: date(10, 21)))
    #expect(store.lit[.lantern] == [1, 2])
}

@MainActor
@Test func onlyRealLanternBellIndicesCanBePersisted() {
    let (store, _) = makeStore(now: date(10, 20))

    #expect(!store.light(.hammock, index: 0, now: date(10, 20)))
    #expect(!store.light(.lantern, index: -1, now: date(10, 20)))
    #expect(!store.light(.lantern, index: 3, now: date(10, 20)))
    #expect(store.lit.isEmpty)
}

@MainActor
@Test func litLampsSurviveRelaunchWithinTheSameLightingDay() {
    let suite = UserDefaults(suiteName: "ornament-light-\(UUID().uuidString)")!
    let first = OrnamentLightStore(defaults: suite, calendar: calendar, now: date(10, 21))
    first.light(.lantern, index: 0, now: date(10, 21))

    // 同一夜里冷启动 —— 灯还在。
    let sameNight = OrnamentLightStore(defaults: suite, calendar: calendar, now: date(11, 1))
    #expect(sameNight.isLit(.lantern, index: 0))

    // 隔天冷启动 —— 构造时就该对好日子，而不是等谁来调 `refresh`。
    let nextDay = OrnamentLightStore(defaults: suite, calendar: calendar, now: date(11, 10))
    #expect(!nextDay.isLit(.lantern, index: 0))
}

/// 四个铃铛的判定圆开到触控目标级别也不会互相偷点击 —— 这依赖实测的中心间距。
/// 挪动 `PiboOrnament` 里那四个点之前，这条会先响。
@Test func bellCentresStayFarEnoughApartForFingerSizedTargets() throws {
    let placement = try #require(PiboOrnament.ornament(.lantern)?.placement)
    // 素材有四个铃铛，只有三个不被 `forest_main_leaf_1` 盖住 —— 见 PiboOrnament
    // 里那段落位说明。
    #expect(placement.lights.count == 3)

    var minimum = CGFloat.greatestFiniteMagnitude
    for (index, light) in placement.lights.enumerated() {
        for other in placement.lights[(index + 1)...] {
            minimum = min(minimum, hypot(
                light.center.x - other.center.x,
                light.center.y - other.center.y
            ))
        }
    }
    // 命中半径取 max(radius * 1.7, 22)，最大 24pt。中心距必须大于它，否则
    // 「最近者胜」也救不了 —— 两盏灯的圆心会互相落进对方的圆里。
    #expect(minimum > 24, "最近的两个铃铛只差 \(minimum)pt")
}
