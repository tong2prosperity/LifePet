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
        var projection: HomeFoodProjection?
        var failures = 0

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: nil,
            history: fixture.history,
            isCameraPresented: { false },
            presentProjection: { projection = $0 },
            presentFailure: { _ in failures += 1 },
            analyze: { _, _, _, _ in
                Issue.record("Non-meal captures must not start recognition")
                return false
            },
            makeStickerPNG: { _ in png },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        await task.value

        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
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

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            isCameraPresented: { false },
            presentProjection: { projection = $0 },
            presentFailure: { failure in
                #expect(failure == .saving)
                failures += 1
            },
            analyze: { _, _, _, _ in true },
            makeStickerPNG: { _ in nil },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        await task.value

        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(photo.pngData == Data([0xFF, 0xD8, 0xFF]))
        #expect(photo.sourceJPEGData == photo.pngData)
        #expect(projection?.pngData == photo.pngData)
        #expect(failures == 0)
    }

    @Test func presentsForestProjectionBeforeStartingRecognition() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var events: [String] = []
        var analyzedPhotoID: UUID?
        var presentedProjection: HomeFoodProjection?

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .lunch,
            history: fixture.history,
            isCameraPresented: { false },
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
                events.append("analyze")
                return true
            },
            makeStickerPNG: { _ in png },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        await task.value

        let photo = try #require(fixture.history.foodPhotos(on: .now).first)
        #expect(photo.meal == .lunch)
        #expect(analyzedPhotoID == photo.id)
        #expect(presentedProjection?.id == photo.id)
        #expect(presentedProjection?.pngData == png)
        #expect(events == ["project", "analyze"])
    }

    @Test func failedRecognitionKeepsProjectionAndReportsTransientFailure() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var events: [String] = []

        let task = HomePhotoSaveCoordinator.process(
            image: UIImage(),
            subjectLabel: "noodles",
            meal: .dinner,
            history: fixture.history,
            isCameraPresented: { false },
            presentProjection: { _ in events.append("project") },
            presentFailure: { failure in
                #expect(failure == .recognition)
                events.append("fail")
            },
            analyze: { _, _, _, _ in
                events.append("analyze")
                return false
            },
            makeStickerPNG: { _ in png },
            makeSourceJPEG: { _ in Data([0xFF, 0xD8, 0xFF]) }
        )
        await task.value

        #expect(!fixture.history.foodPhotos(on: .now).isEmpty)
        #expect(events == ["project", "analyze", "fail"])
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
