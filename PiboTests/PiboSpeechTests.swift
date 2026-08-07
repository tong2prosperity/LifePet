import XCTest
import PiboCore
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

    func testSleepingPatsDoNotConsumeOrdinarySpeechBudget() throws {
        let suiteName = "PiboSpeechSleepBudget.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PiboSpeechService(
            catalog: PiboSpeechCatalog(entries: []),
            defaults: defaults,
            now: { self.date },
            patSpeechRoll: { 0 }
        )
        let facts = PiboHomeSpeechFacts(connectionAccepted: true)

        for _ in 0..<3 {
            let sleeping = service.resolvePat(
                storyStage: .event01Completed,
                restingState: true,
                sleepingState: true,
                facts: facts
            )
            XCTAssertNil(sleeping.speech)
        }

        let active = service.resolvePat(
            storyStage: .event01Completed,
            restingState: false,
            sleepingState: false,
            facts: facts
        )
        XCTAssertTrue(active.shouldSpeak)
        XCTAssertNotNil(active.speech)
    }

    func testUnavailablePatContentDoesNotClaimThatPiboSpoke() throws {
        let suiteName = "PiboSpeechUnavailablePat.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PiboSpeechService(
            catalog: PiboSpeechCatalog(entries: []),
            defaults: defaults,
            now: { self.date },
            patSpeechRoll: { 0 }
        )

        let result = service.resolvePat(
            storyStage: .unresponded,
            restingState: false,
            sleepingState: false,
            facts: PiboHomeSpeechFacts()
        )

        XCTAssertNil(result.speech)
        XCTAssertFalse(result.shouldSpeak)
    }

    func testLegacyModeUsesNeutralTapPoolWithoutPretendingEvent01Completed() throws {
        let suiteName = "PiboSpeechLegacyNeutral.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PiboSpeechService(
            catalog: PiboSpeechCatalog(entries: []),
            defaults: defaults,
            now: { self.date },
            patSpeechRoll: { 0 }
        )

        let result = service.resolvePat(
            storyStage: .unresponded,
            restingState: false,
            sleepingState: false,
            facts: PiboHomeSpeechFacts(),
            neutralLegacyMode: true
        )

        XCTAssertTrue(result.shouldSpeak)
        XCTAssertTrue(result.speech?.id.hasPrefix("home.garbled.") == true)
    }

    func testFutureHomeSpeechFactsDoNotLockBudgetOrContent() throws {
        let suiteName = "PiboSpeechFutureHome.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var history = PiboHomeSpeechHistory(defaults: defaults)
        history.record(
            key: .tap01,
            at: date.addingTimeInterval(PiboCorePatAdapter.dailyWindowSeconds * 10),
            consumesPatBudget: true
        )

        let counts = history.speechCounts(at: date)
        XCTAssertEqual(counts.daily, 0)
        XCTAssertEqual(counts.recent, 0)
        XCTAssertTrue(history.excludedContentKeys(at: date).isEmpty)
    }

    func testFutureAuthoredSpeechTimestampDoesNotLockCooldown() {
        let suiteName = "PiboSpeechFutureCooldown.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let line = PiboSpeechEntry(
            id: "future",
            cue: "ambient.idle",
            surfaces: [.home],
            text: "future",
            cooldownHours: 24,
            topicCooldownHours: 24
        )
        var history = PiboSpeechHistory(defaults: defaults)
        history.record(
            line,
            topic: "ambient",
            opportunity: "future",
            scope: "home.idle",
            at: date.addingTimeInterval(86_400)
        )

        XCTAssertTrue(history.allows(line, topic: "ambient", at: date))
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
