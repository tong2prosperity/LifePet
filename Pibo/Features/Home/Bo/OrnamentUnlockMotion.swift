import SwiftUI

enum OrnamentUnlockMotion {
    static let materializationMilliseconds: Int64 = 1_120
    static let flightMilliseconds: Int64 = 280
    static let layerMilliseconds: Int64 = 200
    static let confirmationMilliseconds: Int64 = 240
    static let easingBezier = [0.22, 1.0, 0.36, 1.0]

    static let materializationDuration: Duration = .milliseconds(materializationMilliseconds)
    static let flightDuration = Double(flightMilliseconds) / 1_000
    static let layerDuration = Double(layerMilliseconds) / 1_000
    static let confirmationDuration = Double(confirmationMilliseconds) / 1_000

    static func constructionAnimation(duration: Double) -> Animation {
        .timingCurve(
            easingBezier[0],
            easingBezier[1],
            easingBezier[2],
            easingBezier[3],
            duration: duration
        )
    }
}
