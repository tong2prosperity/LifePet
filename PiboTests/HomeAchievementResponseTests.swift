import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeAchievementResponseTests {
    private final class Fixture {
        let response = HomeAchievementResponseController()
        var now = Date()
        var pending: PiboAnimationAchievementPayload?
        var line: PiboSpeechLine?
        var completions: [UUID] = []
        var appActive = true
        var blocked = false
        var actorPresent = true
        var stateID = "pibo-state-stable-forest-idle"

        init(kind: PiboAnimationAchievementKind = .pigu) {
            pending = .init(id: UUID(), kind: kind, occurredAt: now,
                            workoutLabel: kind == .pigu ? "跑步" : nil,
                            workoutDurationMinutes: kind == .pigu ? 24 : nil)
            response.environment = .init(
                pending: { self.pending }, appActive: { self.appActive }, blocked: { self.blocked },
                actorPresent: { self.actorPresent }, animationStateID: { self.stateID },
                currentLine: { self.line }, steps: { 9123 }, show: { self.line = $0 },
                dismiss: { self.line = nil }, complete: { payload in
                    guard self.pending?.id == payload.id else { return }
                    self.completions.append(payload.id)
                    self.pending = nil
                })
        }

        func tick(_ seconds: Double = 0) {
            now = now.addingTimeInterval(seconds)
            response.reconcile(now: now)
        }

        func cleanup() { response.environment = .init(); response.finish() }
    }

    @Test func workoutRespondsInPlaceAndCompletesWithoutAButton() throws {
        let f = Fixture()
        defer { f.cleanup() }
        let id = try #require(f.pending?.id)
        f.tick()
        #expect(f.response.active?.id == id)
        #expect(f.line?.text == AppLocalization.text("你动起来以后，我这里也有了变化。"))
        #expect(f.line?.fact == AppLocalization.format("%@ · %d 分钟", "跑步", 24))
        f.tick(7.2)
        #expect(f.response.active == nil)
        #expect(f.line == nil)
        #expect(f.completions == [id])
        f.response.finish()
        #expect(f.completions == [id])
    }

    @Test func busySleepingAndHiddenForestsDeferTheSameResponse() {
        let f = Fixture()
        defer { f.cleanup() }
        f.blocked = true
        f.tick()
        #expect(f.response.active == nil)
        f.blocked = false
        f.actorPresent = false
        f.tick()
        #expect(f.response.active == nil)
        f.actorPresent = true
        f.stateID = PiboAnimationResourceID.sleepingHammockA
        f.tick()
        #expect(f.response.active == nil)
        f.stateID = PiboAnimationResourceID.stable
        f.tick()
        #expect(f.response.active != nil)
    }

    @Test func tappingOrOpeningAnOverlayEndsOnlyTheCurrentResponse() {
        let f = Fixture()
        defer { f.cleanup() }
        f.tick()
        f.blocked = true
        f.tick()
        #expect(f.response.active == nil)
        #expect(f.completions.count == 1)
    }

    @Test(arguments: [1.0, 4.0])
    func leavingReplaysOnlyAnUnseenResponse(seconds: Double) {
        let f = Fixture()
        defer { f.cleanup() }
        f.tick()
        f.now = f.now.addingTimeInterval(seconds)
        f.response.leaveHome(now: f.now)
        #expect(f.response.active == nil)
        #expect(f.line == nil)
        #expect((f.pending != nil) == (seconds < 3))
        if seconds < 3 { f.tick(); #expect(f.response.active != nil) }
        else { #expect(f.completions.count == 1) }
    }

    @Test func replacementWorkoutIsNotConsumedByThePreviousResponse() throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.tick()
        let next = PiboAnimationAchievementPayload(id: UUID(), kind: .pigu, occurredAt: f.now,
                                                   workoutLabel: "走路", workoutDurationMinutes: 30)
        f.pending = next
        f.tick()
        #expect(f.pending?.id == next.id)
        #expect(f.completions.isEmpty)
        f.tick()
        #expect(f.response.active?.id == next.id)
        f.response.finish()
        #expect(f.completions == [next.id])
    }

    @Test func endingDoesNotDismissAnotherSpeakersLine() {
        let f = Fixture()
        defer { f.cleanup() }
        f.tick()
        let other = PiboSpeechLine(text: "别的声音")
        f.line = other
        f.tick()
        #expect(f.line == other)
        #expect(f.completions.count == 1)
    }

    @Test func yesterdayDoesNotReplayAndStepFactUsesTheActualCount() {
        let f = Fixture(kind: .muscle)
        defer { f.cleanup() }
        let current = f.pending!
        f.pending = .init(id: current.id, kind: .muscle, occurredAt: f.now.addingTimeInterval(-86400),
                          workoutLabel: nil, workoutDurationMinutes: nil)
        f.tick()
        #expect(f.response.active == nil)
        f.pending = current
        f.tick()
        #expect(f.line?.fact == AppLocalization.format("今天 %@ 步", 9123.formatted()))
    }
}
