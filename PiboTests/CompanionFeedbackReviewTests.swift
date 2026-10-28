import Foundation
import SwiftData
import Testing
import PiboCore
@testable import Pibo

@Suite(.serialized)
@MainActor
struct CompanionFeedbackReviewTests {
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let key = "FeedbackReview.\(UUID())"
        return (try #require(UserDefaults(suiteName: key)), key)
    }

    @Test func unfinishedSettlementCanReplayAfterEitherStoreRestarts() throws {
        let (defaults, key) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date()
        let wishes = WishStore(defaults: defaults)
        wishes.restore(raw: """
        {"day":"\(growthDayKey(now))","slots":[{"kind":2,"target":3}]}
        """)
        let facts = WishFacts(now: now, localHour: 12, cameraEnabled: false,
                              companionEnabled: false, pats: 3, meals: 0, answers: 0)
        let slot = try #require(wishes.update(facts).first)
        // Crash boundary A: completed on disk but no ledger write yet.
        #expect(WishStore(defaults: defaults).update(facts).count == 1)
        let growth = GrowthStore(defaults: defaults)
        let receipt = growth.settleWish(slot, now: now)
        let expected = PiboCoreGrowth.award(.wish, countedToday: 0).xp
        #expect(receipt.xp == expected)
        // Crash boundary B: XP committed but wish acknowledgement not written yet.
        let restored = GrowthStore(defaults: defaults)
        #expect(restored.peek()?.xp == expected, "the persisted effect must include its real XP")
        let retry = restored.settleWish(slot, now: now)
        #expect(!retry.isNew)
        #expect(retry.xp == expected)
        #expect(restored.totalXP == growth.totalXP)
        #expect(restored.countToday(.wish, now: now) == 1)
        let restoredWishes = WishStore(defaults: defaults)
        restoredWishes.recordReward(for: slot, xp: retry.xp)
        #expect(restoredWishes.update(facts).isEmpty)
        #expect(restoredWishes.slots.first?.awardedXP == expected)
    }

    @Test func earlyPatDoesNotFreezeAnUninformedDailyPlan() throws {
        let (defaults, key) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date()
        let growth = GrowthStore(defaults: defaults)
        let wishes = WishStore(defaults: defaults)
        let coordinator = GrowthCoordinator()
        coordinator.bind(growth: growth, wishes: wishes)
        _ = coordinator.onPat(now: now)
        #expect(growth.countToday(.pat, now: now) == 1)
        #expect(wishes.day.isEmpty)
        #expect(wishes.slots.isEmpty)
        let facts = WishFacts(now: now, localHour: 12, cameraEnabled: false,
                              companionEnabled: false, pats: 1, meals: 0, answers: 0)
        _ = wishes.update(facts)
        let plan = PiboCoreWishes.plan(daySeed: UInt64(growthDaySeed(now)),
            baselineSteps: nil, baselineActiveMinutes: nil, baselineSleepMinutes: nil,
            cameraEnabled: false, companionEnabled: false)
        #expect(wishes.slots.map(\.kind) == plan.map(\.kind))
        #expect(wishes.slots.first(where: { $0.kind == .pats })?.value == 1)
    }

    @Test func resultWaitsForObservationAndCompetingPresentations() {
        let state = HomePresentationState()
        let id = UUID()
        let projection = HomeFoodProjection(id: id, pngData: Data([1]), meal: .dinner,
            dishName: "甜汤", observation: "杯里有桂花。", isCutout: false)
        state.showCamera = true
        state.prepareFoodProjection(projection)
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
        state.showCamera = false
        state.presentPreparedFoodProjection()
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
        state.foodProjection = nil
        state.activeSheet = .healthDataStatus
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
        state.activeSheet = nil
        state.sheetDismissalInProgress = true
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
        state.sheetDismissalInProgress = false
        #expect(!state.presentPendingMealResultIfPossible(canPresent: false))
        #expect(state.presentPendingMealResultIfPossible(canPresent: true))
        #expect(state.activeSheet == .meal(.dinner, photoId: id.uuidString))
        #expect(state.pendingMealResult == nil)
        state.activeSheet = nil
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
    }

    @Test func logoutCancelsAQueuedResult() {
        let state = HomePresentationState()
        state.prepareFoodProjection(.init(id: UUID(), pngData: Data(), meal: .lunch,
            dishName: "午餐", observation: "", isCutout: false))
        state.closeAccountSurfacesForSessionEnd()
        #expect(state.foodProjection == nil)
        #expect(state.pendingMealResult == nil)
        #expect(!state.presentPendingMealResultIfPossible(canPresent: true))
    }

    @Test func playfulSpeechSharesCooldownAndPreservesUnseenChapter() throws {
        let (defaults, key) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let conversation = PiboPatConversationStore(catalog: PiboPatCatalog(units: [
            .init(state: "energetic", context: "workout.run", action: .play, speaker: .pibo,
                  lines: [.init(text: "第一句", stages: nil), .init(text: "第二句", stages: nil)])
        ]), defaults: defaults)
        let now = Date()
        let input = PiboPatConversationInput(state: .energetic, episodeKey: "run", storyStage: "unresponded",
            events: [.init(event: .workoutRun, token: "run-1")])
        #expect(conversation.claimExternalSpeech(input, at: now))
        #expect(!conversation.claimExternalSpeech(input, at: now.addingTimeInterval(1)))
        #expect(!conversation.resolve(input, at: now.addingTimeInterval(2)).speechAccepted)
        let first = conversation.resolve(input, at: now.addingTimeInterval(3))
        #expect(first.text == "第一句")
        #expect(!conversation.claimExternalSpeech(input, at: now.addingTimeInterval(4)))
        #expect(conversation.claimExternalSpeech(input, at: now.addingTimeInterval(6)))
        #expect(conversation.resolve(input, at: now.addingTimeInterval(9)).text == "第二句")
    }

    @Test func metadataDraftIsStableAcrossRetryAndInvalidEditsAreLocal() throws {
        let container = try ModelContainer(for: HealthDayRecord.self, WorkoutRecord.self,
            FoodPhoto.self, WalkDoodleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let history = HealthHistoryStore(context: container.mainContext)
        var analysis = FoodAnalysis(isFood: true, dishName: "甜汤", totalCalories: 340,
            items: [], proteinG: 3, carbG: 75, fatG: 2)
        let photo = history.addFoodPhoto(pngData: Data([1]), capturedAt: .now, mealType: .dinner, analysis: analysis)
        var draft = MealMetadataDraft(photo: photo, fallbackMeal: .lunch)
        analysis.dishName = "桂花甜汤"
        #expect(history.applyFoodRecognition(id: photo.id, analysis: analysis))
        #expect(!draft.changed, "a retry cannot turn an untouched draft into a manual rename")
        draft = MealMetadataDraft(photo: photo, fallbackMeal: .lunch)
        draft.name = " "
        #expect(draft.changed)
        #expect(photo.dishName == "桂花甜汤", "discarding the local draft leaves the record alone")
        draft = MealMetadataDraft(photo: photo, fallbackMeal: .lunch)
        draft.meal = .breakfast
        #expect(history.updateMealMetadata(id: draft.photoID, name: draft.name, meal: draft.meal))
        #expect(!photo.userEditedDishName)
        #expect(photo.meal == .breakfast)
        #expect(history.updateMealMetadata(id: photo.id, name: "我的甜汤", meal: .breakfast))
        #expect(history.applyFoodRecognition(id: photo.id, analysis: analysis))
        #expect(photo.dishName == "我的甜汤")
        #expect(photo.analysis?.dishName == "我的甜汤")
        #expect(photo.meal == .breakfast)
        #expect(!history.applyFoodRecognition(id: UUID(), analysis: analysis))
        let previous = photo.analysisJSON
        analysis.proteinG = .nan
        #expect(!history.updateMealMetadata(id: photo.id, name: "不应保存", meal: .lunch, portionAnalysis: analysis))
        #expect(photo.analysisJSON == previous)
        #expect(photo.dishName == "我的甜汤")
        #expect(photo.meal == .breakfast)
    }
}
