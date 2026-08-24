import SwiftData
import Testing
import UIKit
@testable import Pibo

@Suite(.serialized)
@MainActor
struct HomePhotoSaveCoordinatorTests {
    @Test func persistsCutoutForNonMealCapture() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var projection: HomeFoodProjection?
        var failures = 0

        let outcome = await HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: nil,
            history: fixture.history,
            presentProjection: { projection = $0 },
            presentFailure: { _ in failures += 1 },
            analyze: { _, _, _, _ in
                Issue.record("Non-meal captures must not start recognition")
                return .failed
            },
            makeSticker: { _ in .init(pngData: png, isCutout: true) },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(outcome == .saved)
        #expect(photo.pngData == png)
        #expect(photo.sourceJPEGData == Data([0xFF, 0xD8, 0xFF]))
        #expect(photo.subjectLabel == "noodles")
        #expect(photo.meal == nil)
        #expect(projection == nil)
        #expect(failures == 0)
    }

    @Test func failedStickerGenerationFallsBackToOriginalAndStillPersists() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        var projection: HomeFoodProjection?
        var failures = 0

        let outcome = await HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            presentProjection: { projection = $0 },
            presentFailure: { failure in
                #expect(failure == .saving)
                failures += 1
            },
            analyze: { _, _, _, _ in .food(Self.analysis()) },
            makeSticker: { _ in nil },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(outcome == .saved)
        #expect(photo.pngData == Data([0xFF, 0xD8, 0xFF]))
        #expect(photo.sourceJPEGData == photo.pngData)
        #expect(projection?.pngData == photo.pngData)
        #expect(failures == 0)
    }

    @Test func recognizesBeforePersistingAndPreparingForestProjection() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var events: [String] = []
        var analyzedPhotoID: UUID?
        var presentedProjection: HomeFoodProjection?

        let outcome = await HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            presentProjection: { projection in
                #expect(projection.meal == .lunch)
                presentedProjection = projection
                events.append("project")
            },
            presentFailure: { _ in Issue.record("Successful recognition must not fail") },
            analyze: { photoID, _, hint, meal in
                #expect(hint == "noodles")
                #expect(meal == .lunch)
                analyzedPhotoID = photoID
                #expect(fixture.history.foodPhotos(on: .now).isEmpty)
                events.append("recognize")
                return .food(Self.analysis())
            },
            makeSticker: { _ in .init(pngData: png, isCutout: true) },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(outcome == .saved)
        #expect(photo.meal == .lunch)
        #expect(analyzedPhotoID == photo.id)
        #expect(presentedProjection?.id == photo.id)
        #expect(presentedProjection?.pngData == png)
        #expect(photo.analysis?.isFood == true)
        #expect(events == ["recognize", "project"])
    }

    @Test func nonFoodCreatesNeitherHistoryNorProjection() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var events: [String] = []

        let outcome = await HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .dinner,
            history: fixture.history,
            presentProjection: { _ in events.append("project") },
            presentFailure: { _ in Issue.record("A valid non-food decision is not a transport failure") },
            analyze: { _, _, _, _ in
                events.append("recognize")
                return .notFood
            },
            makeSticker: { _ in .init(pngData: png, isCutout: true) },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        #expect(outcome == .notFood)
        #expect(fixture.history.foodPhotos(on: .now).isEmpty)
        #expect(events == ["recognize"])
    }

    @Test func failedRecognitionCreatesNeitherHistoryNorProjection() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        var events: [String] = []

        let outcome = await HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: nil,
            meal: .dinner,
            history: fixture.history,
            presentProjection: { _ in events.append("project") },
            presentFailure: { failure in
                #expect(failure == .recognition)
                events.append("fail")
            },
            analyze: { _, _, _, _ in
                events.append("recognize")
                return .failed
            },
            makeSticker: { _ in Issue.record("Cutout must wait for the food gate"); return nil },
            makeSourceJPEG: { _ in Issue.record("Persistence must wait for the food gate"); return nil }
        )

        #expect(outcome == .failed)
        #expect(fixture.history.foodPhotos(on: .now).isEmpty)
        #expect(events == ["recognize", "fail"])
    }

    private static func analysis() -> FoodAnalysis {
        FoodAnalysis(
            isFood: true,
            foodPresenceConfidence: 0.96,
            dishName: "番茄鸡蛋面",
            totalCalories: 520,
            confidence: 0.82,
            items: [FoodItem(
                name: "面条",
                calories: 420,
                quantity: "1 碗",
                estimatedGrams: 320
            )],
            proteinG: 18,
            carbG: 72,
            fatG: 14,
            assumptions: ["按一碗估算"],
            note: "份量按画面估算。",
            piboObservation: "红色和黄色放在了一起。"
        )
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
