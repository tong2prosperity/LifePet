import SwiftUI
import Testing
import SwiftData
@testable import Pibo

@MainActor
struct FootprintsMealCrashReproTests {
    @Test func testOpeningMealDetailInHistory() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self,
            configurations: config
        )
        let history = HealthHistoryStore(context: container.mainContext)
        let store = PetStateStore(demoMode: true)
        let days = PiboDayStore()
        let polaroids = PolaroidStore()
        let timeline = PiboTimelineStore()

        // 1. Add a FoodPhoto
        let testPNG = UIImage(systemName: "fork.knife")!.pngData()!
        let photo = history.addFoodPhoto(
            pngData: testPNG,
            capturedAt: .now,
            subjectLabel: "Test Salad",
            mealType: .lunch,
            analysis: FoodAnalysis(
                isFood: true,
                dishName: "Test Salad",
                totalCalories: 350,
                items: [FoodItem(name: "Lettuce", calories: 50, quantity: "1 bowl")],
                proteinG: 12,
                carbG: 20,
                fatG: 15,
                piboObservation: "Yummy salad."
            )
        )

        // 2. Query facts and diary items
        let facts = footprintsDayFacts(
            day: .now,
            history: history,
            days: days,
            polaroids: polaroids,
            timeline: timeline
        )
        let items = footprintsDiaryItems(day: .now, facts: facts)
        #expect(!items.isEmpty)
        let mealItem = try #require(items.first(where: { $0.kind == .meal }))
        #expect(mealItem.ref == photo.id.uuidString)

        // 3. Render MealDetailView the exact way PiboHistoryView does (WITHOUT recognizer):
        let view = MealDetailView(
            photoId: mealItem.ref,
            mealTypeRaw: mealItem.mealTypeRaw,
            onClose: {}
        )
        .environment(history)
        .environment(store)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        host.view.layoutIfNeeded()
    }

    @Test func testOpeningMealDetailWithRecognizerInEnvironment() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self, WalkDoodleRecord.self,
            configurations: config
        )
        let history = HealthHistoryStore(context: container.mainContext)
        let store = PetStateStore(demoMode: true)
        let recognizer = FoodRecognitionService()

        let testPNG = UIImage(systemName: "fork.knife")!.pngData()!
        let photo = history.addFoodPhoto(
            pngData: testPNG,
            capturedAt: .now,
            subjectLabel: "Test Soup",
            mealType: .dinner
        )

        let view = MealDetailView(
            photoId: photo.id.uuidString,
            mealTypeRaw: "dinner",
            onClose: {}
        )
        .environment(history)
        .environment(store)
        .environment(recognizer)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        host.view.layoutIfNeeded()
    }
}
