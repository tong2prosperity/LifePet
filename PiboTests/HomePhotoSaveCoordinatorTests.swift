import SwiftData
import Testing
import UIKit
@testable import Pibo

@Suite(.serialized)
@MainActor
struct HomePhotoSaveCoordinatorTests {
    @Test func missingImagePreservesPreflightOrderAndSkipsProcessing() {
        var events: [String] = []

        HomePhotoSaveCoordinator.handleSavedPhoto(
            image: nil,
            handlers: .init(
                logSaved: { events.append("log-saved") },
                clearInitialMeal: { events.append("clear-meal") },
                trackSaved: { events.append("track") },
                logMissingImage: { events.append("log-missing") },
                process: { _ in Issue.record("A missing image must not be processed") }
            )
        )

        #expect(events == ["log-saved", "clear-meal", "track", "log-missing"])
    }

    @Test func capturedImagePreservesPreflightOrderAndStartsProcessingLast() {
        var events: [String] = []
        let image = UIImage()

        HomePhotoSaveCoordinator.handleSavedPhoto(
            image: image,
            handlers: .init(
                logSaved: { events.append("log-saved") },
                clearInitialMeal: { events.append("clear-meal") },
                trackSaved: { events.append("track") },
                logMissingImage: { Issue.record("A captured image is not missing") },
                process: { processed in
                    #expect(processed === image)
                    events.append("process")
                }
            )
        )

        #expect(events == ["log-saved", "clear-meal", "track", "process"])
    }

    @Test func persistsCutoutForNonMealCapture() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var presentedMeal: MealType?

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: nil,
            history: fixture.history,
            isCameraPresented: { false },
            presentMeal: { presentedMeal = $0 },
            analyze: { _, _, _, _ in
                Issue.record("Non-meal captures must not start recognition")
            },
            makeStickerPNG: { _ in png }
        )
        await task.value

        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(photo.pngData == png)
        #expect(photo.subjectLabel == "noodles")
        #expect(photo.meal == nil)
        #expect(presentedMeal == nil)
    }

    @Test func failedStickerGenerationDoesNotPersistOrPresent() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        var presentedMeal: MealType?

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            isCameraPresented: { false },
            presentMeal: { presentedMeal = $0 },
            analyze: { _, _, _, _ in
                Issue.record("A failed cut-out must not start recognition")
            },
            makeStickerPNG: { _ in nil }
        )
        await task.value

        #expect(fixture.history.foodPhotos(on: .now).isEmpty)
        #expect(presentedMeal == nil)
    }

    @Test func presentsMealBeforeStartingRecognition() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var events: [String] = []
        var analyzedPhotoID: UUID?

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            isCameraPresented: { false },
            presentMeal: { meal in
                #expect(meal == .lunch)
                events.append("present")
            },
            analyze: { photoID, _, hint, meal in
                #expect(hint == "noodles")
                #expect(meal == .lunch)
                analyzedPhotoID = photoID
                events.append("analyze")
            },
            makeStickerPNG: { _ in png }
        )
        await task.value

        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(photo.meal == .lunch)
        #expect(analyzedPhotoID == photo.id)
        #expect(events == ["present", "analyze"])
    }

    private func makeFixture() throws -> (
        history: HealthHistoryStore,
        container: ModelContainer,
        defaults: UserDefaults,
        suite: String
    ) {
        let schema = Schema([
            HealthDayRecord.self,
            WorkoutRecord.self,
            FoodPhoto.self,
            WalkDoodleRecord.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "HomePhotoSaveCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        return (history, container, defaults, suite)
    }
}
