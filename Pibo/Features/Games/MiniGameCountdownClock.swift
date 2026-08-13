import Foundation

struct MiniGameCountdownClock {
    let duration: TimeInterval

    private(set) var isRunning: Bool
    private var elapsedBeforeRun: TimeInterval
    private var runStartedAt: TimeInterval

    init(duration: TimeInterval, startsRunning: Bool = false) {
        self.duration = duration
        self.isRunning = startsRunning
        self.elapsedBeforeRun = 0
        self.runStartedAt = ProcessInfo.processInfo.systemUptime
    }

    mutating func reset(startsRunning: Bool = false) {
        elapsedBeforeRun = 0
        runStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = startsRunning
    }

    mutating func pause(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRunning else { return }
        elapsedBeforeRun = elapsed(at: now)
        runStartedAt = now
        isRunning = false
    }

    mutating func resume(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !isRunning, elapsedBeforeRun < duration else { return }
        runStartedAt = now
        isRunning = true
    }

    func elapsed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        min(
            duration,
            elapsedBeforeRun + (isRunning ? max(0, now - runStartedAt) : 0)
        )
    }

    func secondsLeft(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        max(0, Int(ceil(duration - elapsed(at: now))))
    }
}
