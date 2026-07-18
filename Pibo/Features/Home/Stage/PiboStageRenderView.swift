import Foundation
import Observation
import SpriteKit
import SwiftUI
import UIKit

/// Runtime cadence for the home stage. Ambient and authored animation stays at
/// 60Hz; only direct finger tracking may use ProMotion. Low Power Mode caps the
/// scene at 30Hz.
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
    private(set) var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    func setDirectManipulation(active: Bool, displayMaximum: Int) {
        guard displayMaximum > 60, directManipulationActive != active else { return }
        directManipulationActive = active
    }

    func refreshLowPowerMode() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard lowPowerModeEnabled != enabled else { return }
        lowPowerModeEnabled = enabled
    }

    func renderMode(isPaused: Bool) -> PiboStageRenderMode {
        if isPaused { return .paused }
        if lowPowerModeEnabled { return .lowPower }
        if directManipulationActive { return .interactive }
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
