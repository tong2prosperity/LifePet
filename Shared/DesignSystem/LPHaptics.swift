#if os(iOS)
import UIKit

/// Lightweight haptic feedback helpers for tap actions.
///
/// Generators are cached per intensity to avoid recreating the underlying
/// `UIFeedbackGenerator` on every tap. All call sites use one of:
/// - `LPHaptics.tap()`     — soft default for most buttons
/// - `LPHaptics.confirm()` — medium impact for primary CTAs / commits
/// - `LPHaptics.decline()` — light tap for cancel / quit
/// - `LPHaptics.success()` — UINotification success after a positive flow
///
/// Calls are cheap (just `impactOccurred`); feel free to sprinkle them on
/// every Button action without worrying about perf.
@MainActor
enum LPHaptics {
    private static let softGen    = UIImpactFeedbackGenerator(style: .soft)
    private static let lightGen   = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen  = UIImpactFeedbackGenerator(style: .medium)
    private static let noticeGen  = UINotificationFeedbackGenerator()

    static func tap()     { softGen.impactOccurred() }
    static func confirm() { mediumGen.impactOccurred() }
    static func decline() { lightGen.impactOccurred() }
    static func success() { noticeGen.notificationOccurred(.success) }
}
#else
@MainActor
enum LPHaptics {
    static func tap()     {}
    static func confirm() {}
    static func decline() {}
    static func success() {}
}
#endif
