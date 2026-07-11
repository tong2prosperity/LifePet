import Foundation
import Observation
import SpriteKit
import SwiftUI
import UIKit

/// Runtime cadence for the home stage. Ambient animation stays fluid at 60Hz,
/// direct manipulation and authored reactions may use ProMotion, and Low Power
/// Mode deliberately caps the scene at 30Hz.
enum PiboStageRenderMode: Equatable {
    case ambient
    case interactive
    case lowPower
    case paused
}

@MainActor
@Observable
final class PiboStageRenderController {
    private(set) var directManipulationActive = false
    private(set) var effectBoostActive = false
    private(set) var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private var effectBoostDeadline = Date.distantPast
    @ObservationIgnored private var effectBoostTask: Task<Void, Never>?

    deinit {
        effectBoostTask?.cancel()
    }

    func setDirectManipulation(active: Bool) {
        directManipulationActive = active
    }

    func requestHighRefresh(for duration: TimeInterval) {
        guard duration > 0 else { return }
        effectBoostDeadline = max(effectBoostDeadline, Date().addingTimeInterval(duration))
        effectBoostActive = true
        scheduleEffectBoostExpiry()
    }

    func refreshLowPowerMode() {
        lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func renderMode(isPaused: Bool) -> PiboStageRenderMode {
        if isPaused { return .paused }
        if lowPowerModeEnabled { return .lowPower }
        if directManipulationActive || effectBoostActive { return .interactive }
        return .ambient
    }

    func preferredFramesPerSecond(isPaused: Bool, displayMaximum: Int) -> Int {
        switch renderMode(isPaused: isPaused) {
        case .paused:
            return 1
        case .lowPower:
            return 30
        case .ambient:
            return 60
        case .interactive:
            return min(max(displayMaximum, 60), 120)
        }
    }

    private func scheduleEffectBoostExpiry() {
        effectBoostTask?.cancel()
        let deadline = effectBoostDeadline
        effectBoostTask = Task { [weak self] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if Date() >= self.effectBoostDeadline {
                self.effectBoostActive = false
            } else {
                self.scheduleEffectBoostExpiry()
            }
        }
    }
}

/// A small SwiftUI bridge that exposes `SKView.preferredFramesPerSecond` for
/// live updates. SwiftUI's `SpriteView` accepts an initial preference but does
/// not expose the backing view needed for explicit cadence transitions.
struct PiboStageRenderView: UIViewRepresentable {
    let scene: PiboStageScene
    let preferredFramesPerSecond: Int

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.isOpaque = true
        view.allowsTransparency = false
        view.shouldCullNonVisibleNodes = true
        view.ignoresSiblingOrder = false
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
        }
        if view.preferredFramesPerSecond != preferredFramesPerSecond {
            view.preferredFramesPerSecond = preferredFramesPerSecond
        }
        view.isPaused = false
    }

    static func dismantleUIView(_ view: SKView, coordinator: Void) {
        view.isPaused = true
        view.presentScene(nil)
    }
}
