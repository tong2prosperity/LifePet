import XCTest
@testable import Pibo

#if DEBUG
final class HomeDebugLaunchOptionsTests: XCTestCase {
    func testDefaultsDoNotRequestAnyAutomation() {
        let options = HomeDebugLaunchOptions(arguments: ["Pibo"])

        XCTAssertFalse(options.hidesTuningPanel)
        XCTAssertNil(options.forcedAnimationStateID)
        XCTAssertNil(options.forestHourOverride)
        XCTAssertFalse(options.simulatesMeal)
        XCTAssertFalse(options.opensGames)
        XCTAssertFalse(options.opensHistory)
        XCTAssertFalse(options.showsMorningSleep)
        XCTAssertFalse(options.hasAchievementArgument)
        XCTAssertNil(options.achievementKind)
        XCTAssertNil(options.bounceTargetStateID)
        XCTAssertNil(options.selectedStateIDAfterDelay)
        XCTAssertNil(options.boProgressMilestone)
        XCTAssertFalse(options.opensBoPanel)
        XCTAssertFalse(options.opensStressCard)
    }

    func testEverySupportedArgumentKeepsItsParsedValue() {
        let options = HomeDebugLaunchOptions(arguments: [
            "Pibo",
            "-PiboHideTuning",
            "-PiboAnimationState=pibo-state-waking-hammock-idle",
            "-PiboForestHour=6.5",
            "-PiboSimulateMeal",
            "-PiboOpenGames",
            "-PiboOpenHistory",
            "-PiboShowMorningSleep",
            "-PiboShowAchievement=pigu",
            "-PiboBounceTo=angry",
            "-PiboSelectStateAfter=dive",
            "-PiboBoProgress=75",
            "-PiboOpenBoPanel",
            "-PiboOpenStressCard",
        ])

        XCTAssertTrue(options.hidesTuningPanel)
        XCTAssertEqual(options.forcedAnimationStateID, "pibo-state-waking-hammock-idle")
        XCTAssertEqual(options.forestHourOverride, .value(6.5))
        XCTAssertTrue(options.simulatesMeal)
        XCTAssertTrue(options.opensGames)
        XCTAssertTrue(options.opensHistory)
        XCTAssertTrue(options.showsMorningSleep)
        XCTAssertTrue(options.hasAchievementArgument)
        XCTAssertEqual(options.achievementKind?.rawValue, "pigu")
        XCTAssertEqual(options.bounceTargetStateID, "angry")
        XCTAssertEqual(options.selectedStateIDAfterDelay, "dive")
        XCTAssertEqual(options.boProgressMilestone?.rawValue, 75)
        XCTAssertTrue(options.opensBoPanel)
        XCTAssertTrue(options.opensStressCard)
    }

    func testAutoAndInvalidForestHoursBothPreserveNilOverrideValue() {
        let automatic = HomeDebugLaunchOptions(arguments: ["-PiboForestHour=auto"])
        let invalid = HomeDebugLaunchOptions(arguments: ["-PiboForestHour=invalid"])

        XCTAssertEqual(automatic.forestHourOverride, .value(nil))
        XCTAssertEqual(invalid.forestHourOverride, .value(nil))
    }

    func testInvalidValuesDoNotTriggerTypedAutomation() {
        let options = HomeDebugLaunchOptions(
            arguments: [
                "-PiboAnimationState=future",
                "-PiboShowAchievement=future",
                "-PiboBounceTo=future",
                "-PiboSelectStateAfter=future",
                "-PiboBoProgress=74",
            ],
            availableAnimationStateIDs: PiboAnimationStateMap.available
        )

        XCTAssertNil(options.forcedAnimationStateID)
        XCTAssertTrue(options.hasAchievementArgument)
        XCTAssertNil(options.achievementKind)
        XCTAssertNil(options.bounceTargetStateID)
        XCTAssertNil(options.selectedStateIDAfterDelay)
        XCTAssertNil(options.boProgressMilestone)
    }

    func testFirstPrefixedArgumentStillWins() {
        let options = HomeDebugLaunchOptions(arguments: [
            "-PiboAnimationState=future",
            "-PiboAnimationState=pibo-state-waking-hammock-idle",
            "-PiboForestHour=auto",
            "-PiboForestHour=12",
        ])

        XCTAssertNil(options.forcedAnimationStateID)
        XCTAssertEqual(options.forestHourOverride, .value(nil))
    }

    func testBooleanFlagsRequireAnExactArgument() {
        let options = HomeDebugLaunchOptions(arguments: [
            "-PiboOpenGames=true",
            "prefix-PiboOpenHistory",
            "-PiboShowMorningSleepLater",
            "-PiboOpenBoPanelNow",
            "-PiboOpenStressCardLater",
        ])

        XCTAssertFalse(options.opensGames)
        XCTAssertFalse(options.opensHistory)
        XCTAssertFalse(options.showsMorningSleep)
        XCTAssertFalse(options.opensBoPanel)
        XCTAssertFalse(options.opensStressCard)
    }
}
#endif
