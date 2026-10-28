import Foundation
import SwiftData
import Testing
import PiboCore
import SwiftUI
import UIKit
@testable import Pibo

@Suite(.serialized)
@MainActor
struct CompanionFeedbackFixTests {
    @Test func sleepNeverRoundsIntoTheNextMinute() {
        #expect(SleepDurationText.minutes(7 * 3600 + 43 * 60 + 59.99) == 463)
        #expect(SleepDurationText.minutes(59.9) == 0)
        #expect(SleepDurationText.minutes(.nan) == 0)
        #expect(SleepDurationText.minutes(.infinity) == 0)
        #expect(SleepDurationText.minutes(7.733333333333333 * 3600) == 464)
    }

    @Test func patsCountBeforeOpeningWishesAndBeforeHealthRefresh() throws {
        let key = "FeedbackPatTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date()
        let growth = GrowthStore(defaults: defaults)
        let wishes = WishStore(defaults: defaults)
        wishes.restore(raw: """
        {"day":"\(growthDayKey(now))","slots":[{"kind":2,"target":3}]}
        """)
        let coordinator = GrowthCoordinator()
        coordinator.bind(growth: growth, wishes: wishes)
        for _ in 0..<3 { _ = coordinator.onPat(now: now) }
        #expect(growth.countToday(.pat, now: now) == 3)
        #expect(wishes.slots.first?.done == true)
        #expect(wishes.slots.first?.awardedXP == PiboCoreGrowth.award(.wish, countedToday: 0).xp)
        let xp = growth.totalXP
        _ = coordinator.onPat(now: now)
        #expect(growth.totalXP == xp + PiboCoreGrowth.award(.pat, countedToday: 3).xp)
        #expect(growth.countToday(.wish, now: now) == 1)
        let restored = WishStore(defaults: defaults)
        #expect(restored.slots.first?.awardedXP == wishes.slots.first?.awardedXP)
        for _ in 0..<12 { _ = coordinator.onPat(now: now) }
        #expect(growth.countToday(.pat, now: now) == 16)
        #expect(growth.countToday(.wish, now: now) == 1)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        // A previously planned day works before the current HealthKit refresh too.
        wishes.restore(raw: """
        {"day":"\(growthDayKey(tomorrow))","slots":[{"kind":2,"target":3}]}
        """)
        _ = coordinator.onPat(now: tomorrow)
        #expect(growth.countToday(.pat, now: tomorrow) == 1)
        #expect(wishes.slots.first(where: { $0.kind == .pats })?.done != true)
        _ = coordinator.onPat(now: tomorrow)
        _ = coordinator.onPat(now: tomorrow)
        #expect(growth.countToday(.pat, now: tomorrow) == 3)
        #expect(growth.countToday(.wish, now: tomorrow) == 1)
        #expect(wishes.slots.first(where: { $0.kind == .pats })?.done == true)
    }

    @Test func playfulDodgeStaysInForestAndNextPatStopsIt() {
        let layout = pixelForestLayout(136, 291)
        let director = PixelDayDirector()
        director.configure(layout, .clearing)
        director.patted(1000)
        director.playPatWishDodge(1000)
        #expect(director.playingPatWish)
        let bounds = pixelWalkBounds(layout, .clearing)
        for tick in 0..<60 {
            let frame = director.step(1000 + Double(tick) * 50, hold: false)
            #expect(frame.x >= Double(bounds.minX))
            #expect(frame.x <= Double(bounds.maxX))
        }
        director.patted(4000)
        #expect(!director.playingPatWish)
        let stopped = director.step(4000, hold: false)
        let later = director.step(4500, hold: false)
        #expect(stopped.x == later.x)
    }

    @Test func metadataKeepsIdentityAndNutritionAcrossMealChanges() async throws {
        let container = try ModelContainer(for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self,
                                           WalkDoodleRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let history = HealthHistoryStore(context: container.mainContext)
        let photo = history.addFoodPhoto(pngData: Data([1]), capturedAt: .now, mealType: .dinner,
            analysis: FoodAnalysis(isFood: true, dishName: "甜汤", totalCalories: 340,
                items: [], proteinG: 3, carbG: 75, fatG: 2, piboObservation: "杯里有桂花。"))
        let id = photo.id
        let sample = history.foodSampleNumber(id)
        #expect(history.updateMealMetadata(id: id, name: "  桂花芋圆  ", meal: .breakfast))
        #expect(photo.id == id)
        #expect(photo.dishName == "桂花芋圆")
        #expect(photo.analysis?.dishName == "桂花芋圆")
        #expect(photo.analysis?.proteinG == 3)
        #expect(photo.meal == .breakfast)
        #expect(photo.userEditedDishName)
        #expect(history.foodSampleNumber(id) == sample)
        #expect(history.foodPhotos(on: .now).count == 1)
        #expect(!history.updateMealMetadata(id: id, name: "   ", meal: .lunch))
        #expect(photo.meal == .breakfast)
        // Render the real editor with an isolated in-memory meal for visual QA.
        let view = MealDetailView(photoId: id.uuidString, mealTypeRaw: "dinner", onClose: {})
            .environment(history)
        let host = UIHostingController(rootView: view)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pibo-feedback-meal-editor.png")
        try image.pngData()?.write(to: url)
        window.isHidden = true
    }
}
