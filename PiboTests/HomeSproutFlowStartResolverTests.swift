import Foundation
import XCTest
@testable import Pibo

@MainActor
final class HomeSproutFlowStartResolverTests: XCTestCase {
    func testMissingWorkoutStopsBeforeReadingAnyOtherInput() {
        var reads: [String] = []

        let request = HomeSproutFlowStartResolver.resolve(
            pendingWorkout: read("workout", nil, into: &reads),
            phase: read("phase", .idle, into: &reads),
            sheetPresented: read("sheet", false, into: &reads),
            fullScreenFeaturePresented: read("cover", false, into: &reads),
            growthStart: read("start", 0.2, into: &reads),
            growthTarget: { _ in read("target", 0.4, into: &reads) },
            canSprout: read("canSprout", true, into: &reads),
            animationStyle: read("style", .stagePlaceholder, into: &reads)
        )

        XCTAssertNil(request)
        XCTAssertEqual(reads, ["workout"])
    }

    func testBlockedPresentationPreservesGuardReadOrder() {
        var reads: [String] = []

        let request = HomeSproutFlowStartResolver.resolve(
            pendingWorkout: read("workout", workout(), into: &reads),
            phase: read("phase", .idle, into: &reads),
            sheetPresented: read("sheet", true, into: &reads),
            fullScreenFeaturePresented: read("cover", false, into: &reads),
            growthStart: read("start", 0.2, into: &reads),
            growthTarget: { _ in read("target", 0.4, into: &reads) },
            canSprout: read("canSprout", true, into: &reads),
            animationStyle: read("style", .stagePlaceholder, into: &reads)
        )

        XCTAssertNil(request)
        XCTAssertEqual(reads, ["workout", "phase", "sheet"])
    }

    func testStageCloseupPackagesTheOriginalInputsInOrder() throws {
        var reads: [String] = []
        let workout = workout()

        let request = try XCTUnwrap(HomeSproutFlowStartResolver.resolve(
            pendingWorkout: read("workout", workout, into: &reads),
            phase: read("phase", .idle, into: &reads),
            sheetPresented: read("sheet", false, into: &reads),
            fullScreenFeaturePresented: read("cover", false, into: &reads),
            growthStart: read("start", 0.2, into: &reads),
            growthTarget: { _ in read("target", 0.4, into: &reads) },
            canSprout: read("canSprout", true, into: &reads),
            animationStyle: read("style", .stagePlaceholder, into: &reads)
        ))

        XCTAssertEqual(request.workoutID, workout.id)
        XCTAssertEqual(request.growthStart, 0.2)
        XCTAssertEqual(request.growthTarget, 0.4)
        XCTAssertEqual(request.animation, .stageCloseup)
        XCTAssertEqual(
            reads,
            ["workout", "phase", "sheet", "cover", "start", "target", "canSprout", "style"]
        )
    }

    func testLottieAndInPlaceRoutesStayDistinct() throws {
        let workout = workout()
        var inPlaceStyleRead = false
        let lottie = try XCTUnwrap(HomeSproutFlowStartResolver.resolve(
            pendingWorkout: workout,
            phase: .idle,
            sheetPresented: false,
            fullScreenFeaturePresented: false,
            growthStart: 0.2,
            growthTarget: { _ in 0.4 },
            canSprout: true,
            animationStyle: .lottie(asset: "sprout")
        ))
        let inPlace = try XCTUnwrap(HomeSproutFlowStartResolver.resolve(
            pendingWorkout: workout,
            phase: .idle,
            sheetPresented: false,
            fullScreenFeaturePresented: false,
            growthStart: 0.2,
            growthTarget: { _ in 0.4 },
            canSprout: false,
            animationStyle: read(
                "style",
                .lottie(asset: "must-not-be-read"),
                into: &inPlaceStyleRead
            )
        ))

        XCTAssertEqual(lottie.animation, .lottieCloseup(asset: "sprout"))
        XCTAssertEqual(inPlace.animation, .inPlaceGrowth)
        XCTAssertFalse(inPlaceStyleRead)
    }

    private func workout() -> PendingWorkout {
        PendingWorkout(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .run,
            label: "跑步",
            durationMin: 24,
            kcal: 180,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000),
            gainVitality: 20
        )
    }

    private func read<T>(_ name: String, _ value: T, into reads: inout [String]) -> T {
        reads.append(name)
        return value
    }

    private func read<T>(_ name: String, _ value: T, into didRead: inout Bool) -> T {
        didRead = true
        return value
    }
}
