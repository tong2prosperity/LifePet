import Foundation
import Testing
import PiboCore
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PixelWishFlowTests {
    @Test(arguments: [false, true])
    func answerWishBypassesPatContinuationAndRecordsBothReplyKinds(custom: Bool) throws {
        let key = "PixelWishFlowTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date().timeIntervalSince1970
        let store = PiboCompanionStore(defaults: defaults, clock: { now })
        let controller = HomeCompanionController(store: store, catalog: try #require(PiboCompanionCatalog.bundled() as PiboCompanionCatalog?), clock: { now })
        var answers = 0
        var wishing = true
        controller.environment = .init(appActive: { true }, state: { .stable },
                                       hasAnswerWish: { wishing }, onAnswer: { answers += 1; wishing = false })
        #expect(controller.wishPromptReady)
        #expect(controller.consumePatTextOpportunity(), "the very first double tap offers the wish question")
        #expect(controller.active != nil)
        #expect(!controller.wishPromptReady, "do not draw a second thought bubble during the question")
        if custom {
            #expect(controller.submitReply("想去看看雨"))
            #expect(!controller.submitReply("重复回复"))
        } else {
            let option = try #require(controller.active?.prompt.options.first)
            controller.choose(option.id)
            controller.choose(option.id)
        }
        #expect(answers == 1, "repeated UI callbacks cannot award the same answer twice")
        #expect(store.answeredTotal == 1)
        #expect(!wishing)
        controller.leaveHome()
    }

    @Test func thoughtAndPromptHonorSleepingPresentationAndDailyCoreBudget() throws {
        let key = "PixelWishBudgetTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date().timeIntervalSince1970
        let store = PiboCompanionStore(defaults: defaults, clock: { now })
        let controller = HomeCompanionController(store: store, catalog: try #require(PiboCompanionCatalog.bundled() as PiboCompanionCatalog?), clock: { now })
        var state = PiboActivityState.sleeping
        var overlay = false
        controller.environment = .init(appActive: { true }, state: { state }, overlayOpen: { overlay }, hasAnswerWish: { true })
        #expect(!controller.wishPromptReady)
        #expect(!controller.offerWishPrompt())
        state = .stable
        overlay = true
        #expect(!controller.offerWishPrompt())
        overlay = false
        #expect(store.canOfferPromptsToday())
        // Core, rather than a copied daily limit, decides when the budget is spent.
        for _ in 0..<20 { store.recordLineShown(now: now, proactive: false, prompt: true, topic: nil) }
        #expect(!store.canOfferPromptsToday())
        #expect(!controller.wishPromptReady)
        #expect(!controller.offerWishPrompt())
    }

    @Test func wishCompletesOnceAndYesterdayDoesNotLightTodaysBubble() throws {
        let key = "PixelWishStoreTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date()
        let store = WishStore(defaults: defaults)
        store.restore(raw: """
        {"day":"\(growthDayKey(now))","slots":[{"kind":4,"target":1}],"eveningOffered":false}
        """)
        #expect(store.hasUncompletedWish(.answerPrompt, now: now))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(!store.hasUncompletedWish(.answerPrompt, now: tomorrow))
        let facts = WishFacts(now: now, localHour: 12, cameraEnabled: true, companionEnabled: true,
                              pats: 0, meals: 0, answers: 1)
        #expect(store.update(facts).map(\.kind) == [.answerPrompt])
        #expect(store.update(facts).isEmpty)
        #expect(!store.hasUncompletedWish(.answerPrompt, now: now))
    }
}
