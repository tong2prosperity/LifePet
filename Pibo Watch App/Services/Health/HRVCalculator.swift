import Foundation

struct HRVCalculator: Sendable {
    let windowSize: Int
    private(set) var rrIntervalsMs: [Double] = []

    init(windowSize: Int = 30) {
        self.windowSize = windowSize
    }

    mutating func append(_ rrMs: Double) {
        rrIntervalsMs.append(rrMs)
        if rrIntervalsMs.count > windowSize {
            rrIntervalsMs.removeFirst(rrIntervalsMs.count - windowSize)
        }
    }

    mutating func reset() {
        rrIntervalsMs.removeAll(keepingCapacity: true)
    }

    /// RMSSD — root mean square of successive RR-interval differences, in ms.
    var rmssd: Double? {
        guard rrIntervalsMs.count >= 2 else { return nil }
        let diffs = zip(rrIntervalsMs.dropFirst(), rrIntervalsMs.dropLast()).map { $0 - $1 }
        let squared = diffs.map { $0 * $0 }
        let mean = squared.reduce(0, +) / Double(squared.count)
        return mean.squareRoot()
    }
}
