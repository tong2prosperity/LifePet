#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import Foundation

/// Live Activity for an in-progress 地图涂鸦 walk (Dynamic Island + Lock Screen):
/// shows 正在行走 with live 距离 / 路线面积 and a self-counting timer, plus a 结束
/// button. Started / updated / ended by `WalkDoodleSession`; rendered by
/// `WalkDoodleLiveActivity` in the widget extension.
nonisolated struct WalkDoodleActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var distanceMeters: Double
        var areaSquareMeters: Double
        /// Walk start — the LA renders elapsed client-side via `Text(_:style:.timer)`,
        /// so duration ticks every second without us pushing per-second updates.
        var startedAt: Date
        var pointCount: Int
    }

    var petName: String
}

/// Cross-process "stop this walk" flag, written by `StopWalkDoodleIntent` (which
/// runs in the app process when the LA button is tapped) and polled by the live
/// `WalkDoodleSession` on its 1-second ticker. App-Group UserDefaults keeps it
/// simple — no Darwin C interop, no URL scheme, no app-only types in the intent.
nonisolated enum WalkDoodleStopSignal {
    private static let key = "pibo.walkdoodle.stopRequestedAt.v1"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    /// Mark a stop request (called from the LA 结束 button's intent).
    static func requestStop(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    /// True if a stop was requested at/after `baseline` (the session's start).
    static func isStopRequested(since baseline: Date) -> Bool {
        let ts = defaults.double(forKey: key)
        return ts > 0 && ts >= baseline.timeIntervalSince1970
    }

    /// Clear any stale flag (called when a new walk starts).
    static func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// The 结束 button on the Live Activity. `LiveActivityIntent` runs `perform()` in
/// the **app** process; it ends the activity (covers the rare app-killed case) and
/// raises the stop flag the live session polls. Self-contained — references only
/// ActivityKit + the App-Group flag, so it compiles cleanly into both the app and
/// the widget extension.
nonisolated struct StopWalkDoodleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "结束涂鸦"
    static var description = IntentDescription("结束当前的地图涂鸦")

    init() {}

    func perform() async throws -> some IntentResult {
        WalkDoodleStopSignal.requestStop()
        for activity in Activity<WalkDoodleActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
#endif
