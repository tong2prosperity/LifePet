import Foundation
import WatchKit

final class CRCHapticGuide {
    private let device = WKInterfaceDevice.current()
    private var lastPhase: CRCBreathingPhase?
    private var lastPlayedAt = Date.distantPast
    private var isEnabled = true

    func start() {
        isEnabled = true
        lastPhase = nil
        lastPlayedAt = .distantPast
    }

    func stop() {
        isEnabled = false
        lastPhase = nil
    }

    func update(phase: CRCBreathingPhase, syncScore: Double) {
        guard isEnabled else { return }
        let now = Date()
        guard phase != lastPhase,
              now.timeIntervalSince(lastPlayedAt) > 1.2 else { return }

        switch phase {
        case .inhale:
            device.play(.start)
        case .exhale:
            device.play(.directionDown)
        }

        if syncScore < 45 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard self?.isEnabled == true else { return }
                self?.device.play(.click)
            }
        }

        lastPhase = phase
        lastPlayedAt = now
    }
}
