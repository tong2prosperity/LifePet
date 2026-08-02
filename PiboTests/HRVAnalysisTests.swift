import XCTest
@testable import Pibo

/// Pins the RMSSD contract in `HRVAnalysis.analyze`.
///
/// Artifact rejection here has failed in both directions, and the tests are
/// organised around that. The first rule filtered on the successive difference
/// itself (reject when `|b − a| > 0.2 · a`), which could only bias RMSSD
/// downward and did so harder the higher the true HRV. Its replacement, a flat
/// 250 ms, was too loose at the other end: one mis-detected beat survived and
/// nearly doubled a quiet wearer's reading. So the properties fixed below are —
/// an artifact-free window must survive **intact**, rejection must key off an
/// interval being an outlier rather than off the size of the thing being
/// measured, and the outlier threshold must scale with the wearer.
@MainActor
final class HRVAnalysisTests: XCTestCase {

    // MARK: - Fixtures

    /// A strong but entirely physiological respiratory oscillation: RR swinging
    /// 727…1073 ms (HR ≈ 56–83) on a ~6-beat breathing cycle. Every successive
    /// difference here is real signal.
    private func rsaSeries(count: Int = 48, mean: Double = 900, amplitude: Double = 200) -> [Double] {
        (0..<count).map { mean + amplitude * sin(Double($0) * .pi / 3) }
    }

    /// A quiet resting wearer: RR alternating 900/918, i.e. RMSSD exactly 18 ms
    /// by inspection. This is the regime a fixed 250 ms threshold cannot police —
    /// real differences are an order of magnitude below it.
    private func lowHRVSeries(count: Int = 42) -> [Double] {
        (0..<count).map { $0.isMultiple(of: 2) ? 900.0 : 918.0 }
    }

    /// The textbook definition, with no artifact handling at all — the value
    /// `analyze` must reproduce exactly when there is nothing to reject.
    private func referenceRMSSD(_ rr: [Double]) -> Double {
        let diffs = zip(rr.dropFirst(), rr.dropLast()).map(-)
        return (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
    }

    // MARK: - Clean windows must pass through untouched

    func testConstantAlternationMatchesHandComputedRMSSD() throws {
        // 42 intervals alternating 900/940 → every successive difference is ±40,
        // so RMSSD is exactly 40 by inspection.
        let rr = (0..<42).map { $0.isMultiple(of: 2) ? 900.0 : 940.0 }

        let analysis = try XCTUnwrap(HRVAnalysis.analyze([rr]))

        XCTAssertEqual(analysis.rmssd, 40, accuracy: 1e-9)
        XCTAssertEqual(analysis.diffs, rr.count - 1)
        XCTAssertEqual(analysis.flagged, 0)
    }

    /// The core regression. A large, smooth RSA oscillation is exactly what the
    /// old 20%-of-previous-RR rule destroyed: it rejected the 727→900 rise
    /// (173 ms > 0.2 · 727) while keeping the identical 900→727 fall, deleting
    /// one difference per breathing cycle and pulling RMSSD down with it.
    /// Nothing here is an artifact, so nothing may be dropped.
    func testRespiratoryOscillationSurvivesArtifactRejectionIntact() throws {
        let rr = rsaSeries()

        let analysis = try XCTUnwrap(HRVAnalysis.analyze([rr]))

        XCTAssertEqual(analysis.flagged, 0, "a smooth oscillation contains no artifacts")
        XCTAssertEqual(analysis.diffs, rr.count - 1, "every successive difference must be counted")
        XCTAssertEqual(analysis.rmssd, referenceRMSSD(rr), accuracy: 1e-9)
        XCTAssertEqual(analysis.meanRR, rr.reduce(0, +) / Double(rr.count), accuracy: 1e-9)
    }

    // MARK: - Artifacts must be rejected

    /// A premature beat writes a short interval followed by a compensatory long
    /// one. Both break the local pattern, so both are flagged — as is the
    /// neighbour whose local median they drag — and every difference touching
    /// them leaves the sum. RMSSD stays near the clean value instead of being
    /// swamped by one bad beat, and the window still yields a reading.
    func testEctopicPairIsRejectedRatherThanSwampingRMSSD() throws {
        let clean = rsaSeries()
        var dirty = clean
        dirty[20] = 450     // premature beat
        dirty[21] = 1350    // compensatory pause

        let cleanRMSSD = try XCTUnwrap(HRVAnalysis.analyze([clean])).rmssd
        let analysis = try XCTUnwrap(HRVAnalysis.analyze([dirty]),
                                     "one ectopic must not cost the whole reading")

        // The test has teeth only if the raw series really is wrecked.
        XCTAssertGreaterThan(referenceRMSSD(dirty), 1.5 * cleanRMSSD)

        XCTAssertGreaterThanOrEqual(analysis.flagged, 2)
        XCTAssertLessThan(analysis.rmssd, 1.3 * cleanRMSSD)
        XCTAssertGreaterThan(analysis.rmssd, 0.7 * cleanRMSSD)
    }

    /// Past the artifact budget the surviving beats are no longer a fair sample
    /// of the window — and since rejection removes the extremes, what's left
    /// reads systematically low. Discard the window instead of reporting it.
    func testWindowIsDiscardedWhenArtifactShareExceedsBudget() {
        var rr = rsaSeries()
        for i in [6, 16, 26, 36] { rr[i] = 2500 }   // 4/48 ≈ 8.3% > 5%

        XCTAssertNil(HRVAnalysis.analyze([rr]))
    }

    // MARK: - The threshold must scale with the wearer

    /// The field regression. At RMSSD 18 ms a beat landing 150 ms off its
    /// neighbours is unmistakably an artifact, yet it sits well inside the flat
    /// 250 ms threshold that used to apply — and RMSSD being a root-mean-square,
    /// the two differences it creates swamp the forty real ones. This is what
    /// reported 31 ms on a wearer a reference device read at 17 ms.
    func testModerateArtifactAtLowHRVIsRejected() throws {
        let clean = lowHRVSeries()
        var dirty = clean
        dirty[20] += 150

        // The test has teeth only if the uncorrected series really is wrecked:
        // one beat nearly doubles the textbook value.
        XCTAssertGreaterThan(referenceRMSSD(dirty), 1.8 * referenceRMSSD(clean))

        let analysis = try XCTUnwrap(HRVAnalysis.analyze([dirty]))

        XCTAssertEqual(analysis.flagged, 1)
        XCTAssertEqual(analysis.diffs, dirty.count - 3, "both differences touching the bad beat leave the sum")
        XCTAssertEqual(analysis.rmssd, referenceRMSSD(clean), accuracy: 1e-9)
    }

    /// The mechanism behind the test above, pinned directly: a quiet window
    /// derives a tight threshold, a strongly oscillating one saturates at the
    /// 250 ms ceiling. The ceiling is what guarantees this change can only ever
    /// tighten — high-HRV windows behave exactly as they did before.
    func testThresholdAdaptsDownForQuietWindowsAndSaturatesForLoudOnes() {
        let quiet = HRVAnalysis.measure([lowHRVSeries()])
        let loud = HRVAnalysis.measure([rsaSeries()])

        XCTAssertLessThan(quiet.artifactThresholdMs, 100)
        XCTAssertGreaterThan(quiet.artifactThresholdMs, 3 * referenceRMSSD(lowHRVSeries()),
                             "real beat-to-beat variation must stay far inside the threshold")
        XCTAssertEqual(loud.artifactThresholdMs, 250)
    }

    /// A robust dispersion estimate is what makes it safe to derive the threshold
    /// from the measured quantity: the artifacts being hunted must not be able to
    /// widen the threshold enough to hide behind. Five of them, scattered, still
    /// all get caught.
    func testScatteredArtifactsCannotInflateTheirOwnThreshold() throws {
        let clean = lowHRVSeries(count: 120)
        var dirty = clean
        for i in [20, 40, 60, 80, 100] { dirty[i] += 150 }

        let analysis = try XCTUnwrap(HRVAnalysis.analyze([dirty]))

        XCTAssertEqual(analysis.flagged, 5)
        XCTAssertEqual(analysis.rmssd, referenceRMSSD(clean), accuracy: 1e-9)
    }

    /// An unusually rigid series must not derive a threshold so tight that its
    /// own ordinary variation reads as artifact — the floor exists for exactly
    /// this, and a window with nothing wrong in it must come back untouched.
    func testRigidSeriesIsNotShreddedByItsOwnTightThreshold() throws {
        // RR alternating 900/904: RMSSD 4 ms, deviations of 2 ms.
        let rr = (0..<42).map { $0.isMultiple(of: 2) ? 900.0 : 904.0 }

        let analysis = try XCTUnwrap(HRVAnalysis.analyze([rr]))

        XCTAssertEqual(analysis.flagged, 0)
        XCTAssertEqual(analysis.diffs, rr.count - 1)
        XCTAssertEqual(analysis.rmssd, 4, accuracy: 1e-9)
    }

    func testTooFewSurvivingDifferencesYieldsNoReading() {
        XCTAssertNil(HRVAnalysis.analyze([rsaSeries(count: 10)]))
        XCTAssertNil(HRVAnalysis.analyze([]))
        XCTAssertNil(HRVAnalysis.analyze([[900]]))
    }

    /// A window that fails the trust gates must still report its numbers. The
    /// gates are strict enough to drop real readings, and they arrive only every
    /// 2–5h — a rejection that collapses to a bare `nil` leaves "为什么压力记录是
    /// 空的" with no way to tell artifacts apart from a short series.
    func testRejectedWindowStillReportsItsNumbers() {
        var rr = rsaSeries()
        for i in [6, 16, 26, 36] { rr[i] = 2500 }

        XCTAssertNil(HRVAnalysis.analyze([rr]))

        let measurement = HRVAnalysis.measure([rr])
        XCTAssertFalse(HRVAnalysis.isTrustworthy(measurement))
        XCTAssertEqual(measurement.rrCount, rr.count)
        XCTAssertGreaterThan(measurement.flagged, 4)
        XCTAssertGreaterThan(measurement.diffs, 0)
        XCTAssertGreaterThan(measurement.meanRR, 0)
    }

    /// Degenerate input must not divide by zero on its way to being rejected.
    func testEmptyInputMeasuresToZeroWithoutTrapping() {
        for empty in [[], [[]], [[900.0]]] as [[[Double]]] {
            let measurement = HRVAnalysis.measure(empty)
            XCTAssertEqual(measurement.rmssd, 0)
            XCTAssertEqual(measurement.diffs, 0)
            XCTAssertFalse(HRVAnalysis.isTrustworthy(measurement))
        }
    }

    // MARK: - Gap boundaries

    /// Beats lost to a dropout split the run. The interval before the hole and
    /// the interval after it are not temporally adjacent, so no difference may
    /// be formed across the boundary — which is what a single flat array would
    /// silently do.
    func testGapBoundaryProducesNoCrossSegmentDifference() throws {
        let first = rsaSeries(count: 24, mean: 900)
        let second = rsaSeries(count: 24, mean: 600)   // HR jumps across the hole

        let split = try XCTUnwrap(HRVAnalysis.analyze([first, second]))
        let flattened = try XCTUnwrap(HRVAnalysis.analyze([first + second]))

        // The hazard, stated directly: dropping the boundary invents one extra
        // "successive" difference between two intervals that never touched.
        XCTAssertEqual(flattened.diffs, first.count + second.count - 1)
        XCTAssertEqual(split.diffs, (first.count - 1) + (second.count - 1))

        // Both runs carry the same oscillation, so the honest answer is just that
        // oscillation — the step between them must not enter the sum.
        XCTAssertEqual(split.rmssd, referenceRMSSD(first), accuracy: 1e-9)
    }
}
