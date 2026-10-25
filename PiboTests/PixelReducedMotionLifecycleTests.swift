import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import Pibo

/// Exercise the real SwiftUI timer: rendering the renderer directly cannot catch
/// a host that stops delivering every frame when Reduce Motion is enabled.
@Suite(.serialized)
@MainActor
struct PixelReducedMotionLifecycleTests {
    @Test func reducedMotionStillCompletesScriptedStateChanges() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        var look = PixelStageRenderer.Look()
        look.reduceMotion = true
        var started = false
        var completed = 0
        let stage = PixelStageView(look: look, onStageReady: { renderer in
            started = renderer.director.perform([
                pixelStoryAct(.beckon, 150),
                pixelStoryCall { completed += 1 }
            ], interrupt: true)
        })
        window.rootViewController = UIHostingController(rootView: stage)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(1200))
        #expect(started)
        #expect(completed == 1, "Reduce Motion must not freeze functional script callbacks")
    }
}
