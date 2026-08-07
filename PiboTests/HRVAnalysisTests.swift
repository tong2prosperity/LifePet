import XCTest
@testable import Pibo

/// Pins the Apple RR → corrected NN-RMSSD contract. The correction stage follows
/// Lipponen–Tarvainen (2019); measurement visibility is independent from whether
/// the evidence is eligible to change personal trends.
@MainActor
final class HRVAnalysisTests: XCTestCase {
    private func referenceRMSSD(_ segments: [[Double]]) -> Double? {
        var squaredDifferences: [Double] = []
        for rr in segments {
            for (next, previous) in zip(rr.dropFirst(), rr.dropLast()) {
                let difference = next - previous
                squaredDifferences.append(difference * difference)
            }
        }
        guard !squaredDifferences.isEmpty else { return nil }
        return (squaredDifferences.reduce(0, +) / Double(squaredDifferences.count)).squareRoot()
    }

    private func physiologicalSeries(count: Int = 80) -> [Double] {
        (0..<count).map { index in
            let respiratory = 55.0 * sin(Double(index) * .pi / 4.0)
            let smallVariation = Double(index % 5 - 2) * 3.0
            return 900.0 + respiratory + smallVariation
        }
    }

    func testCleanSeriesPassesThroughAsNNIntervals() throws {
        let rr = physiologicalSeries()
        let measurement = try XCTUnwrap(HRVAnalysis.analyze([rr]))

        XCTAssertEqual(measurement.rmssd, try XCTUnwrap(referenceRMSSD([rr])), accuracy: 1e-9)
        XCTAssertEqual(measurement.rawRMSSD, measurement.rmssd, accuracy: 1e-9)
        XCTAssertEqual(measurement.rrCount, rr.count)
        XCTAssertEqual(measurement.nnCount, rr.count)
        XCTAssertEqual(measurement.diffs, rr.count - 1)
        XCTAssertEqual(measurement.corrections.total, 0)
        XCTAssertTrue(measurement.canUpdateTrends)
    }

    func testEctopicPairIsCorrectedInsteadOfInflatingRMSSD() throws {
        let clean = physiologicalSeries()
        var dirty = clean
        dirty[35] = 430
        dirty[36] = 1_420

        let cleanRMSSD = try XCTUnwrap(referenceRMSSD([clean]))
        let measurement = try XCTUnwrap(HRVAnalysis.analyze([dirty]))

        XCTAssertGreaterThan(measurement.rawRMSSD, cleanRMSSD * 2)
        XCTAssertGreaterThan(measurement.corrections.total, 0)
        XCTAssertLessThan(abs(measurement.rmssd - cleanRMSSD),
                          abs(measurement.rawRMSSD - cleanRMSSD))
    }

    func testShortOrHeavilyCorrectedEvidenceStillProducesAVisibleValue() throws {
        var rr = physiologicalSeries(count: 24)
        rr[8] = 420
        rr[9] = 1_450
        rr[16] = 390
        rr[17] = 1_500

        let measurement = try XCTUnwrap(HRVAnalysis.analyze([rr]))

        XCTAssertGreaterThan(measurement.rmssd, 0)
        XCTAssertFalse(measurement.canUpdateTrends)
    }

    func testGapBoundaryDoesNotInventCrossSegmentDifference() throws {
        let first = Array(physiologicalSeries(count: 40))
        let second = physiologicalSeries(count: 40).map { $0 - 180 }
        let split = try XCTUnwrap(HRVAnalysis.analyze([first, second]))
        let flattened = try XCTUnwrap(HRVAnalysis.analyze([first + second]))

        XCTAssertEqual(split.diffs, first.count + second.count - 2)
        XCTAssertNotEqual(split.rawRMSSD, flattened.rawRMSSD)
    }

    func testInvalidIntervalCreatesAnotherHardBoundary() throws {
        let split = try XCTUnwrap(HRVAnalysis.analyze([[800, 810, .nan, 1_000, 1_020]]))
        let explicit = try XCTUnwrap(HRVAnalysis.analyze([[800, 810], [1_000, 1_020]]))

        XCTAssertEqual(split.rawRMSSD, explicit.rawRMSSD, accuracy: 1e-9)
        XCTAssertEqual(split.diffs, explicit.diffs)
    }

    func testMultipleEditsRemapFromTheOriginalCoordinateSpace() {
        XCTAssertEqual(
            HRVAnalysis.updatedIndices(after: [10, 20], indices: [9, 15, 21, 30], delta: -1),
            [9, 14, 19, 28]
        )
    }

    func testOverflowCannotEscapeAsAStoredMeasurement() {
        XCTAssertNil(HRVAnalysis.analyze([[Double.greatestFiniteMagnitude,
                                           Double.greatestFiniteMagnitude / 4]]))
    }

    func testEligibilityNeedsDurationNNCountAndLowCorrectionRate() throws {
        let eligible = try XCTUnwrap(HRVAnalysis.analyze([physiologicalSeries()]))
        let shortDuration = try XCTUnwrap(HRVAnalysis.analyze([
            (0..<60).map { $0.isMultiple(of: 2) ? 400.0 : 420.0 }
        ]))
        let tooFewNN = try XCTUnwrap(HRVAnalysis.analyze([
            (0..<29).map { $0.isMultiple(of: 2) ? 2_100.0 : 2_120.0 }
        ]))

        XCTAssertTrue(eligible.canUpdateTrends)
        XCTAssertFalse(shortDuration.canUpdateTrends)
        XCTAssertFalse(tooFewNN.canUpdateTrends)
    }

    func testNoSuccessivePairIsTheOnlyNilCase() {
        XCTAssertNil(HRVAnalysis.analyze([]))
        XCTAssertNil(HRVAnalysis.analyze([[]]))
        XCTAssertNil(HRVAnalysis.analyze([[900]]))
        XCTAssertNil(HRVAnalysis.analyze([[900], [600]]))
    }
}
