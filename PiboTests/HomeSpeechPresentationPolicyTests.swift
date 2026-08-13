import XCTest
@testable import Pibo

@MainActor
final class HomeSpeechPresentationPolicyTests: XCTestCase {
    func testResolvedPresentationsKeepTheirBubbleMetadata() {
        let expectations: [(PiboSpeechPresentation, PiboSpeechMood, Bool)] = [
            (.normal, .normal, false),
            (.angry, .angry, false),
            (.murmur, .murmur, false),
            (.story, .normal, true),
        ]

        for (presentation, expectedMood, expectedStoryClue) in expectations {
            let resolved = PiboSpeech(
                id: "id",
                text: "line",
                presentation: presentation,
                cueKey: "cue"
            )

            let line = HomeSpeechPresentationPolicy.line(for: resolved)

            XCTAssertEqual(line.text, "line")
            XCTAssertEqual(line.mood, expectedMood)
            XCTAssertEqual(line.isStoryClue, expectedStoryClue)
            XCTAssertEqual(line.source, .pibo)
            XCTAssertNil(line.data)
        }
    }

    func testLingerDurationsKeepTheirExistingPriorityAndValues() {
        let data = PiboSpeechData(prefix: "", value: "1", suffix: "")
        let factualSystemMurmur = PiboSpeechLine(
            text: "data",
            mood: .murmur,
            isStoryClue: true,
            source: .system,
            data: data
        )

        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(for: factualSystemMurmur),
            5.0
        )
        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(for: .system("system")),
            3.0
        )
        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(
                for: PiboSpeechLine(text: "murmur", mood: .murmur)
            ),
            3.4
        )
        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(
                for: PiboSpeechLine(text: "story", isStoryClue: true)
            ),
            3.4
        )
        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(
                for: PiboSpeechLine(text: "angry", mood: .angry)
            ),
            2.0
        )
        XCTAssertEqual(
            HomeSpeechPresentationPolicy.lingerDuration(
                for: PiboSpeechLine(text: "normal")
            ),
            2.0
        )
    }

    func testSleepPatRemainsASystemNotice() throws {
        let line = try XCTUnwrap(HomeSpeechPresentationPolicy.animationPatLine(
            contentID: "animation.sleep.pat",
            angry: true
        ))

        XCTAssertEqual(line.text, AppLocalization.narrative("home.sleep.pat"))
        XCTAssertEqual(line.source, .system)
        XCTAssertEqual(line.mood, .normal)
    }

    func testAwakeAndAngryContentKeepTheirMoodMapping() throws {
        let content: [(String, String)] = [
            ("animation.awake.pat", "home.awake.pat"),
            ("animation.angry.enter", "home.angry.enter"),
        ]

        for (contentID, localizationKey) in content {
            let calm = try XCTUnwrap(HomeSpeechPresentationPolicy.animationPatLine(
                contentID: contentID,
                angry: false
            ))
            let angry = try XCTUnwrap(HomeSpeechPresentationPolicy.animationPatLine(
                contentID: contentID,
                angry: true
            ))

            XCTAssertEqual(calm.text, AppLocalization.narrative(localizationKey))
            XCTAssertEqual(calm.mood, .normal)
            XCTAssertEqual(calm.source, .pibo)
            XCTAssertEqual(angry.text, calm.text)
            XCTAssertEqual(angry.mood, .angry)
            XCTAssertEqual(angry.source, .pibo)
        }
    }

    func testUnknownAnimationContentRemainsSilent() {
        XCTAssertNil(HomeSpeechPresentationPolicy.animationPatLine(
            contentID: "animation.future.pat",
            angry: false
        ))
    }
}
