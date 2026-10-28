import Foundation

/// Presentation only. Preserve completed minutes; never round a measured night up.
enum SleepDurationText {
    static func minutes(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        // The tiny tolerance only removes binary conversion noise from hours → seconds.
        return Int(min((seconds + 0.000001) / 60, Double(Int.max / 2)))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let value = minutes(seconds)
        if value < 60 { return AppLocalization.format("%d 分钟", value) }
        return AppLocalization.format("%d 小时 %d 分", value / 60, value % 60)
    }
}
