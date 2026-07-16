import Foundation
import PiboCore

enum PiboCoreSleepAdapter {
    static func samplesShareSession(gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.samplesShareSession(gapSeconds: gapSeconds)
    }

    static func segmentsShouldMerge(sameStage: Bool, gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.segmentsShouldMerge(sameStage: sameStage, gapSeconds: gapSeconds)
    }
}
