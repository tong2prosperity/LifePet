import Foundation

/// Apple heartbeat-series RR → corrected NN-RMSSD.
///
/// HarmonyOS deliberately does not use this code: Huawei Health exposes an
/// already-computed RMSSD value and no public beat-to-beat RR series. Apple raw
/// RR intervals are classified and corrected with the Lipponen–Tarvainen (2019)
/// method before the standard NN-RMSSD formula is applied. HealthKit gaps remain
/// hard segment boundaries, so no difference is ever formed across missing data.
enum HRVAnalysis {
    enum CorrectionKind: String, Sendable, CaseIterable {
        case ectopic
        case missed
        case extra
        case longOrShort
    }

    struct CorrectionCounts: Sendable, Equatable {
        var ectopic = 0
        var missed = 0
        var extra = 0
        var longOrShort = 0

        var total: Int { ectopic + missed + extra + longOrShort }

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(
                ectopic: lhs.ectopic + rhs.ectopic,
                missed: lhs.missed + rhs.missed,
                extra: lhs.extra + rhs.extra,
                longOrShort: lhs.longOrShort + rhs.longOrShort
            )
        }
    }

    struct Measurement: Sendable, Equatable {
        /// Standard RMSSD over corrected normal-to-normal intervals, ms.
        var rmssd: Double
        /// Uncorrected successive-RR RMSSD, retained for local audit.
        var rawRMSSD: Double
        /// Mean corrected NN interval, ms.
        var meanNN: Double
        /// Original RR interval count across all contiguous runs.
        var rrCount: Int
        /// Corrected NN interval count across all contiguous runs.
        var nnCount: Int
        /// Corrected successive differences included in RMSSD.
        var diffs: Int
        /// Sum of corrected NN intervals; gaps are excluded.
        var durationSeconds: Double
        var corrections: CorrectionCounts

        var correctionRate: Double {
            guard rrCount > 0 else { return 0 }
            return Double(corrections.total) / Double(rrCount)
        }

        /// Evidence gate for baseline, stress classification and notifications.
        /// A value that fails this gate remains visible and persisted.
        var canUpdateTrends: Bool {
            durationSeconds >= minimumDurationSeconds
                && nnCount >= minimumNNCount
                && correctionRate <= maximumCorrectionRate
        }
    }

    static let minimumDurationSeconds = 60.0
    static let minimumNNCount = 30
    static let maximumCorrectionRate = 0.10

    /// Corrects every contiguous segment independently, then pools squared
    /// successive differences. `nil` means only that no segment contains a
    /// mathematically usable successive pair.
    static func analyze(_ segments: [[Double]]) -> Measurement? {
        var rawSquaredDifferenceSum = 0.0
        var rawDifferenceCount = 0
        var correctedSquaredDifferenceSum = 0.0
        var correctedDifferenceCount = 0
        var correctedSum = 0.0
        var rrCount = 0
        var nnCount = 0
        var counts = CorrectionCounts()

        for segment in segments {
            // An invalid interval is a hole in the time series, not a value that
            // can simply disappear. Filtering `[800, NaN, 900]` into
            // `[800, 900]` would invent a successive difference across that hole.
            for rr in contiguousValidRuns(in: segment) {
                rrCount += rr.count
                for (next, previous) in zip(rr.dropFirst(), rr.dropLast()) {
                    let difference = next - previous
                    rawSquaredDifferenceSum += difference * difference
                    rawDifferenceCount += 1
                }

                let correction = correct(rr)
                counts = counts + correction.counts
                nnCount += correction.nn.count
                correctedSum += correction.nn.reduce(0, +)
                for (next, previous) in zip(correction.nn.dropFirst(), correction.nn.dropLast()) {
                    let difference = next - previous
                    correctedSquaredDifferenceSum += difference * difference
                    correctedDifferenceCount += 1
                }
            }
        }

        guard rawDifferenceCount > 0, correctedDifferenceCount > 0, nnCount > 0 else {
            return nil
        }
        let rmssd = (correctedSquaredDifferenceSum / Double(correctedDifferenceCount)).squareRoot()
        let rawRMSSD = (rawSquaredDifferenceSum / Double(rawDifferenceCount)).squareRoot()
        let meanNN = correctedSum / Double(nnCount)
        let durationSeconds = correctedSum / 1_000
        guard rmssd.isFinite, rawRMSSD.isFinite, meanNN.isFinite,
              durationSeconds.isFinite else { return nil }
        return Measurement(
            rmssd: rmssd,
            rawRMSSD: rawRMSSD,
            meanNN: meanNN,
            rrCount: rrCount,
            nnCount: nnCount,
            diffs: correctedDifferenceCount,
            durationSeconds: durationSeconds,
            corrections: counts
        )
    }

    static func rmssd(_ rrMs: [Double]) -> Double? {
        analyze([rrMs])?.rmssd
    }

    private static func contiguousValidRuns(in intervals: [Double]) -> [[Double]] {
        var result: [[Double]] = []
        var current: [Double] = []
        for interval in intervals {
            guard interval.isFinite, interval > 0 else {
                if !current.isEmpty { result.append(current) }
                current = []
                continue
            }
            current.append(interval)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Lipponen–Tarvainen 2019

    private struct ArtifactIndices {
        var ectopic: [Int] = []
        var missed: [Int] = []
        var extra: [Int] = []
        var longOrShort: [Int] = []

        var counts: CorrectionCounts {
            CorrectionCounts(
                ectopic: Set(ectopic).count,
                missed: Set(missed).count,
                extra: Set(extra).count,
                longOrShort: Set(longOrShort).count
            )
        }
    }

    private struct CorrectedSegment {
        var nn: [Double]
        var counts: CorrectionCounts
    }

    private static func correct(_ rr: [Double]) -> CorrectedSegment {
        guard rr.count >= 2 else { return CorrectedSegment(nn: rr, counts: .init()) }
        var peaks = [0.0]
        peaks.reserveCapacity(rr.count + 1)
        for interval in rr { peaks.append((peaks.last ?? 0) + interval) }

        let artifacts = findArtifacts(peaks: peaks)
        let correctedPeaks = correctArtifacts(artifacts, peaks: peaks)
        let nn = zip(correctedPeaks.dropFirst(), correctedPeaks.dropLast()).map(-)
        return CorrectedSegment(nn: nn, counts: artifacts.counts)
    }

    private static func findArtifacts(peaks: [Double]) -> ArtifactIndices {
        let c1 = 0.13
        let c2 = 0.17
        let alpha = 5.2
        let thresholdWindow = 91
        let medianWindow = 11

        var rr = [0.0]
        rr.append(contentsOf: zip(peaks.dropFirst(), peaks.dropLast()).map(-))
        if rr.count > 1 { rr[0] = rr.dropFirst().reduce(0, +) / Double(rr.count - 1) }

        var drr = [0.0]
        drr.append(contentsOf: zip(rr.dropFirst(), rr.dropLast()).map(-))
        if drr.count > 1 { drr[0] = drr.dropFirst().reduce(0, +) / Double(drr.count - 1) }

        let threshold1 = rollingThreshold(drr, alpha: alpha, width: thresholdWindow)
        for index in drr.indices {
            drr[index] = threshold1[index] == 0 ? .nan : drr[index] / threshold1[index]
        }

        var s12 = Array(repeating: 0.0, count: drr.count)
        var s22 = Array(repeating: 0.0, count: drr.count)
        for index in drr.indices {
            if drr[index] > 0 {
                s12[index] = max(reflected(drr, index - 1), reflected(drr, index + 1))
            } else if drr[index] < 0 {
                s12[index] = min(reflected(drr, index - 1), reflected(drr, index + 1))
            }
            if drr[index] >= 0 {
                s22[index] = min(reflected(drr, index + 1), reflected(drr, index + 2))
            } else if drr[index] < 0 {
                s22[index] = max(reflected(drr, index + 1), reflected(drr, index + 2))
            }
        }

        let medianRR = rollingMedian(rr, width: medianWindow)
        var mrr = zip(rr, medianRR).map(-)
        for index in mrr.indices where mrr[index] < 0 { mrr[index] *= 2 }
        let threshold2 = rollingThreshold(mrr, alpha: alpha, width: thresholdWindow)
        for index in mrr.indices {
            mrr[index] = threshold2[index] == 0 ? .nan : mrr[index] / threshold2[index]
        }

        var result = ArtifactIndices()
        var index = 0
        while index < rr.count - 2 {
            if abs(drr[index]) <= 1 {
                index += 1
                continue
            }
            let ectopicPositive = drr[index] > 1 && s12[index] < (-c1 * drr[index] - c2)
            let ectopicNegative = drr[index] < -1 && s12[index] > (-c1 * drr[index] + c2)
            if ectopicPositive || ectopicNegative {
                result.ectopic.append(index)
                index += 1
                continue
            }
            if !(abs(drr[index]) > 1 || abs(mrr[index]) > 3) {
                index += 1
                continue
            }

            var candidates = [index]
            if abs(drr[index + 1]) < abs(drr[index + 2]) { candidates.append(index + 1) }
            for candidate in candidates {
                let longBeat = drr[candidate] > 1 && s22[candidate] < -1
                let longOrShort = abs(mrr[candidate]) > 3
                let shortBeat = drr[candidate] < -1 && s22[candidate] > 1
                guard longBeat || longOrShort || shortBeat else {
                    index += 1
                    continue
                }

                let missing = abs(rr[candidate] / 2 - medianRR[candidate]) < threshold2[candidate]
                let extra = abs(rr[candidate] + rr[candidate + 1] - medianRR[candidate]) < threshold2[candidate]
                if shortBeat && extra {
                    result.extra.append(candidate)
                } else if longBeat && missing {
                    result.missed.append(candidate)
                } else {
                    result.longOrShort.append(candidate)
                }
                index += 1
            }
        }
        return result
    }

    private static func correctArtifacts(_ artifacts: ArtifactIndices, peaks: [Double]) -> [Double] {
        var corrected = peaks
        var missed = artifacts.missed
        var ectopic = artifacts.ectopic
        var longOrShort = artifacts.longOrShort

        let extra = Array(Set(artifacts.extra)).sorted()
        if !extra.isEmpty {
            corrected = corrected.enumerated().filter { !extra.contains($0.offset) }.map(\.element)
            missed = updatedIndices(after: extra, indices: missed, delta: -1)
            ectopic = updatedIndices(after: extra, indices: ectopic, delta: -1)
            longOrShort = updatedIndices(after: extra, indices: longOrShort, delta: -1)
        }

        let validMissed = Array(Set(missed)).sorted().filter { $0 > 1 && $0 < corrected.count }
        if !validMissed.isEmpty {
            let additions = validMissed.map { index in
                (index, corrected[index - 1] + (corrected[index] - corrected[index - 1]) / 2)
            }
            for (offset, addition) in additions.enumerated() {
                corrected.insert(addition.1, at: addition.0 + offset)
            }
            ectopic = updatedIndices(after: validMissed, indices: ectopic, delta: 1)
            longOrShort = updatedIndices(after: validMissed, indices: longOrShort, delta: 1)
        }

        corrected = correctMisaligned(ectopic, peaks: corrected)
        corrected = correctMisaligned(longOrShort, peaks: corrected)
        return corrected
    }

    private static func correctMisaligned(_ indices: [Int], peaks: [Double]) -> [Double] {
        var result = peaks
        let original = peaks
        for index in Set(indices).sorted()
        where index > 1 && index < original.count - 1 {
            result[index] = original[index - 1] + (original[index + 1] - original[index - 1]) / 2
        }
        return result.sorted()
    }

    static func updatedIndices(after sources: [Int], indices: [Int], delta: Int) -> [Int] {
        // `sources` and `indices` share the same pre-edit coordinate space. Do
        // not compare a partially shifted index with the next unshifted source:
        // removing 10 and 20 must map original 21 to 19, not 20.
        let sortedSources = Array(Set(sources)).sorted()
        let remapped = indices.map { index in
            let precedingEdits = sortedSources.lazy.filter { $0 < index }.count
            return index + delta * precedingEdits
        }
        return Array(Set(remapped)).sorted()
    }

    private static func rollingThreshold(_ values: [Double], alpha: Double, width: Int) -> [Double] {
        rollingWindows(values, width: width).map { window in
            alpha * (quantile(window.map(abs), probability: 0.75)
                     - quantile(window.map(abs), probability: 0.25)) / 2
        }
    }

    private static func rollingMedian(_ values: [Double], width: Int) -> [Double] {
        rollingWindows(values, width: width).map {
            quantile($0, probability: 0.5)
        }
    }

    private static func rollingWindows(_ values: [Double], width: Int) -> [[Double]] {
        let half = width / 2
        return values.indices.map { index in
            let lower = max(values.startIndex, index - half)
            let upper = min(values.endIndex, index + half + 1)
            return Array(values[lower..<upper])
        }
    }

    /// Linear quantile interpolation, matching the reference implementation's
    /// rolling pandas quantiles.
    private static func quantile(_ values: [Double], probability: Double) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let position = Double(sorted.count - 1) * probability
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        return sorted[lower] + (position - Double(lower)) * (sorted[upper] - sorted[lower])
    }

    /// NumPy-style `reflect` padding without repeating the edge value.
    private static func reflected(_ values: [Double], _ rawIndex: Int) -> Double {
        guard values.count > 1 else { return values.first ?? 0 }
        var index = rawIndex
        while index < 0 || index >= values.count {
            if index < 0 { index = -index }
            if index >= values.count { index = 2 * values.count - 2 - index }
        }
        return values[index]
    }
}
