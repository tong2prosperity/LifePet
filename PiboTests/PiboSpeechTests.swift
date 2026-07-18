import XCTest
@testable import Pibo

@MainActor
final class PiboSpeechTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_784_131_200)

    func testHigherPriorityCueWinsWithoutCallerChoosingCopy() throws {
        let service = makeService(entries: [
            entry(id: "weather", cue: "weather.rain", text: "rain"),
            entry(id: "sleep", cue: "sleep.shorter", text: "少了 {minutes} 分钟"),
        ])

        let speech = try XCTUnwrap(service.resolve(
            cues: [.weather(.rain), .sleepShorter(minutes: 47)],
            context: .dashboard()
        ))

        XCTAssertEqual(speech.id, "sleep")
        XCTAssertEqual(speech.text, "少了 47 分钟")
    }

    func testDashboardSelectionIsStableAcrossRepeatedResolution() throws {
        let service = makeService(entries: [
            entry(id: "one", cue: "sleep.shorter", text: "one"),
            entry(id: "two", cue: "sleep.shorter", text: "two"),
        ])
        let cue = PiboSpeechCue.sleepShorter(minutes: 30)

        let first = try XCTUnwrap(service.resolve(cues: [cue], context: .dashboard()))
        let second = try XCTUnwrap(service.resolve(cues: [cue], context: .dashboard()))

        XCTAssertEqual(first, second)
    }

    func testEphemeralHomeOpportunityDoesNotReplay() throws {
        let service = makeService(entries: [
            PiboSpeechEntry(
                id: "idle",
                cue: "ambient.idle",
                surfaces: [.home],
                text: "……"
            ),
        ])
        let context = PiboSpeechContext.home(trigger: .idle)

        XCTAssertNotNil(service.resolve(cues: [.idle()], context: context))
        XCTAssertNil(service.resolve(cues: [.idle()], context: context))
    }

    func testNoMatchingAuthoredLineMeansSilence() {
        let service = makeService(entries: [])

        XCTAssertNil(service.resolve(
            cues: [.weather(.clear)],
            context: .home(trigger: .entered)
        ))
    }

    func testBundledCatalogLoadsAuthoredContent() {
        let catalog = PiboSpeechCatalog.bundled()

        XCTAssertFalse(catalog.entries(
            for: .sleepShorter(minutes: 20),
            context: .dashboard(),
            storyProgress: 0
        ).isEmpty)
    }

    private func makeService(entries: [PiboSpeechEntry]) -> PiboSpeechService {
        let suiteName = "PiboSpeechTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PiboSpeechService(
            catalog: PiboSpeechCatalog(entries: entries),
            defaults: defaults,
            now: { self.date }
        )
    }

    private func entry(id: String, cue: String, text: String) -> PiboSpeechEntry {
        PiboSpeechEntry(
            id: id,
            cue: cue,
            surfaces: [.dashboard],
            text: text
        )
    }
}
