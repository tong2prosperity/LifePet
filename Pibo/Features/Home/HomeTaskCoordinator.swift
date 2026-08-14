import Foundation

/// Preserves the ordered effects shared by Home's clock-driven tasks and
/// system date-change notifications.
@MainActor
enum HomeTaskCoordinator {
    struct Handlers {
        let refreshClock: () -> Void
        let refreshAnimation: () -> Void
        let refreshAnimationAt: (Date) -> Void
        let refreshOrnamentLights: (Date) -> Void
    }

    static func minuteElapsed(
        at date: Date,
        handlers: Handlers
    ) {
        handlers.refreshAnimation()
        // Minute precision is enough to detect dawn crossings. The light store
        // makes repeated refreshes inexpensive when nothing changed.
        handlers.refreshOrnamentLights(date)
    }

    static func systemDateChanged(handlers: Handlers) {
        handlers.refreshClock()
        handlers.refreshAnimation()
    }

    static func angryStateExpired(
        at date: Date,
        handlers: Handlers
    ) {
        handlers.refreshAnimationAt(date)
    }
}
