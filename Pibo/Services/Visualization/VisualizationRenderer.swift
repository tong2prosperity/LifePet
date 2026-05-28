import Foundation
import SwiftUI

struct VisualizationFrame: Sendable, Hashable {
    var bins: [Float]
    var heartRate: Double?
    var hrv: Double?
}

@Observable
final class VisualizationRenderer {
    var frame: VisualizationFrame = VisualizationFrame(bins: [], heartRate: nil, hrv: nil)

    func ingestBins(_ bins: [Float]) {
        frame.bins = bins
    }

    func ingestVitals(_ snapshot: VitalSnapshot) {
        frame.heartRate = snapshot.first(of: .heartRate)?.value
        frame.hrv = snapshot.first(of: .hrv)?.value
    }
}
