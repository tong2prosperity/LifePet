#if DEBUG
import Foundation

/// DEBUG-only requests raised from the developer settings page and consumed by
/// Home once it is back on screen. Nothing here reaches Release builds.
enum HomeDebugRequest: String {
    /// Decision 047 sample panel (labeled sample data, memory only).
    case statusObserverSample
    /// Replays the maturity motion without touching the ledger.
    case boRipePreview
    /// Plays the light growth hint without touching the ledger.
    case boGrowthHint
    /// Decision 054 companion tools (still governed by Core budgets).
    case companionPatReady
    case companionAbsenceShort
    case companionAbsenceLong
    case companionReset

    var companionCommand: String {
        switch self {
        case .companionPatReady: "pat-ready"
        case .companionAbsenceShort: "absence-short"
        case .companionAbsenceLong: "absence-long"
        case .companionReset: "reset"
        default: ""
        }
    }

    static let notification = Notification.Name("pibo.debug.homeRequest")

    func post() {
        NotificationCenter.default.post(name: Self.notification, object: rawValue)
    }
}
#endif
