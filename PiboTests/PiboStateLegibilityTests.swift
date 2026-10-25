import CoreGraphics
import Foundation
import PiboCore
import Testing
@testable import Pibo

/// Pibo's state reads at a glance: words under its feet and forest light that
/// answers the Core state (HarmonyOS `test_state_legibility.mjs` and the mood
/// part of `test_forest_scene.mjs`, docs/harmony-first/2026-09-28-状态一眼可读.md).
@MainActor
struct PiboStateLegibilityTests {
    private static func caption(
        _ state: PiboActivityState,
        cause: PiboCoreStateCause = .normalRhythm,
        pending: PiboCoreStateCause? = nil,
        reason: PiboCorePatDataUnknownReason = .waitingData,
        realData: Bool = true
    ) -> PiboStateCaption {
        PiboStateCaption.resolve(.init(
            state: state,
            cause: cause,
            pendingCause: pending,
            dataUnknownReason: reason,
            hasRealHealthData: realData
        ))
    }

    private static func environment(at hour: Double, weather: PiboWeather = .clear) -> ForestEnvironmentSnapshot {
        ForestEnvironmentAdapter.resolve(PiboStageEnvironment(localHour: hour, weather: weather))
    }

    // MARK: Caption

    @Test func everyStateNamesItsCoreCause() {
        #expect(Self.caption(.energetic, cause: .recentWorkout).detail == "刚跟着你动了一会儿")
        #expect(Self.caption(.energetic, cause: .activityMilestone).detail == "今天跟着你走了很远")
        #expect(Self.caption(.energetic, cause: .goodSleep).detail == "昨晚睡得不错")
        #expect(Self.caption(.energetic).detail == "今天很轻快")
        #expect(Self.caption(.tired, cause: .insufficientSleep).detail == "昨晚没睡够")
        #expect(Self.caption(.tired).detail == "想慢一点")
        #expect(Self.caption(.waking, pending: .goodSleep).detail == "昨晚睡得不错")
        #expect(Self.caption(.waking, pending: .insufficientSleep).detail == "昨晚睡得有点少")
        #expect(Self.caption(.waking).detail == "还在醒神")
        #expect(Self.caption(.sleeping).detail == "到了你平常睡觉的时间")
        #expect(Self.caption(.sleeping, realData: false).detail == "到了睡觉的时间",
                "without records the window is Core's default, not the person's habit")
        #expect(Self.caption(.stable, cause: .goodSleep).detail == "昨晚睡得不错")
        #expect(Self.caption(.stable).detail == "和平常差不多")
    }

    @Test func noDataSaysWhyWithoutBlame() {
        let titles = Set(PiboCorePatDataUnknownReason.allReasons.map {
            Self.caption(.dataUnknown, reason: $0).title
        })
        #expect(titles == ["看不清你的日常"])
        #expect(Self.caption(.dataUnknown, reason: .authorization).detail == "还没连接健康记录")
        #expect(Self.caption(.dataUnknown, reason: .unavailable).detail == "健康服务暂时不可用")
        #expect(Self.caption(.dataUnknown, reason: .interruptedNoTrustedState).detail == "记录同步断了一下")
        #expect(Self.caption(.dataUnknown, reason: .waitingData).detail == "在等第一批记录")
    }

    @Test func captionsUseWordsNeverNumbers() {
        let causes: [PiboCoreStateCause] = [
            .missingData, .scheduledSleep, .scheduledWake, .normalRhythm,
            .goodSleep, .insufficientSleep, .recentWorkout, .activityMilestone,
        ]
        for state in PiboActivityState.allCases {
            for cause in causes {
                for reason in PiboCorePatDataUnknownReason.allReasons {
                    let caption = Self.caption(state, cause: cause, pending: cause, reason: reason)
                    #expect(caption.sentence.rangeOfCharacter(from: .decimalDigits) == nil, "\(caption.sentence)")
                    #expect(caption.sentence.hasPrefix("Pibo \(caption.title)，"))
                }
            }
        }
    }

    @Test func eachStateHasItsOwnTone() {
        let tones = PiboActivityState.allCases.map { Self.caption($0).tone }
        #expect(Set(tones.map { "\($0)" }).count == PiboActivityState.allCases.count)
    }

    @Test func voiceOverDescribesTheCurrentStatePat() {
        #expect(PiboCoreAnimationAdapter.accessibilityHint(for: .tired) == "点按可让它休息")
        #expect(PiboCoreAnimationAdapter.accessibilityHint(for: .dataUnknown) == "点按可摸一摸",
                "a pat no longer means a health prompt every time")
    }

    @Test func thePatAndTheCaptionAgreeOnWhyThereIsNoData() {
        #expect(HomePatInputProvider.dataUnknownReason(for: .needsAuthorization) == .authorization)
        #expect(HomePatInputProvider.dataUnknownReason(for: .unavailable) == .unavailable)
        #expect(HomePatInputProvider.dataUnknownReason(for: .temporarilyInterrupted(lastReadableAt: nil))
                == .interruptedNoTrustedState)
        #expect(HomePatInputProvider.dataUnknownReason(for: .noReadableData) == .waitingData)
    }

    @Test func thePresenterShowsAndHides() async {
        let presenter = HomeStateCaptionPresenter()
        presenter.show(after: .zero)
        for _ in 0..<20 where !presenter.isShown { await Task.yield() }
        #expect(presenter.isShown)
        presenter.hide()
        #expect(!presenter.isShown)
    }

    // MARK: Forest mood

    @Test func eachStateHasItsForestMood() {
        #expect(ForestMood(state: .energetic) == .bright)
        #expect(ForestMood(state: .tired) == .weary)
        #expect(ForestMood(state: .waking) == .dawn)
        #expect(ForestMood(state: .sleeping) == .hush)
        #expect(ForestMood(state: .dataUnknown) == .haze)
        #expect(ForestMood(state: .stable) == .neutral)
    }

    @Test func timeAndWeatherAloneCarryNoMood() {
        let noon = Self.environment(at: 12)
        for environment in [noon, Self.environment(at: 1)] {
            let light = environment.lighting
            #expect([light.sunWash, light.dawnWash, light.shade, light.haze] == [0, 0, 0, 0])
        }
        #expect(noon.applying(.neutral, weight: 1) == noon)
        #expect(noon.applying(.bright, weight: 0) == noon)
        #expect(noon.lighting.daylight == 1)
        #expect(Self.environment(at: 1).lighting.daylight == 0)
        #expect(Self.environment(at: 12, weather: .rain).lighting.daylight < 1, "rain dims the day")
    }

    @Test func energeticGetsSunByDayAndFirefliesByNight() {
        let noon = Self.environment(at: 12)
        let bright = noon.applying(.bright, weight: 1)
        #expect(bright.lighting.sunWash > 0.3)
        #expect(bright.lighting.midground.saturation > noon.lighting.midground.saturation)
        #expect(bright.lighting.midground.darkness <= noon.lighting.midground.darkness)
        #expect(bright.lighting.fireflyBirthRate == noon.lighting.fireflyBirthRate,
                "no fireflies in full daylight")

        let night = Self.environment(at: 1)
        let brightNight = night.applying(.bright, weight: 1)
        #expect(brightNight.lighting.sunWash == 0, "no sun at night; fireflies carry the mood instead")
        #expect(brightNight.lighting.fireflyBirthRate > night.lighting.fireflyBirthRate)
    }

    @Test func tiredGathersShadeAndStillsTheWind() {
        let noon = Self.environment(at: 12)
        let weary = noon.applying(.weary, weight: 1)
        #expect(weary.lighting.shade > 0.3 && weary.lighting.sunWash == 0)
        #expect(weary.lighting.midground.darkness > noon.lighting.midground.darkness)
        #expect(weary.lighting.midground.saturation < noon.lighting.midground.saturation)
        #expect(weary.wind.strength < noon.wind.strength)
        #expect(weary.lighting.water == noon.lighting.water, "the water keeps its own light")
        #expect(weary.lighting.pibo == noon.lighting.pibo, "Pibo keeps its own colours")
    }

    @Test func wakingNoDataAndSleepEachReadDifferently() {
        #expect(Self.environment(at: 7).applying(.dawn, weight: 1).lighting.dawnWash > 0.2)
        let noon = Self.environment(at: 12)
        let haze = noon.applying(.haze, weight: 1)
        #expect(haze.lighting.haze >= 0.5 && haze.lighting.shade == 0, "no data reads as mist, not a bad day")
        #expect(haze.lighting.midground.saturation < noon.lighting.midground.saturation)
        let night = Self.environment(at: 1)
        let hush = night.applying(.hush, weight: 1)
        #expect(hush.lighting.shade > 0.3)
        #expect(hush.lighting.midground.darkness > night.lighting.midground.darkness)
    }

    @Test func crossFadingTwoMoodsIsLinear() {
        let noon = Self.environment(at: 12)
        let weary = noon.applying(.weary, weight: 1)
        let bright = noon.applying(.bright, weight: 1)
        let mid = noon.applying(.weary, weight: 0.5).applying(.bright, weight: 0.5)
        #expect(abs(mid.lighting.shade - (weary.lighting.shade + bright.lighting.shade) / 2) < 0.0001)
        #expect(abs(mid.lighting.sunWash - (weary.lighting.sunWash + bright.lighting.sunWash) / 2) < 0.0001)
    }
}

private extension PiboCorePatDataUnknownReason {
    static let allReasons: [PiboCorePatDataUnknownReason] = [
        .authorization, .waitingData, .unavailable, .interruptedNoTrustedState,
    ]
}
