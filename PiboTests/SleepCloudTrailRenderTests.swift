import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Pibo

/// Renders the real trail views offscreen. Asserts the renderer produces an
/// image; when `PIBO_RENDER_DIR` names an existing directory the PNGs are also
/// written there for visual review.
@MainActor
struct SleepCloudTrailRenderTests {
    private let base = Date(timeIntervalSince1970: 1_758_060_000)

    private func segments(_ plan: [(Double, Double, SleepStage)]) -> [SleepSegmentValue] {
        plan.map {
            SleepSegmentValue(
                start: base.addingTimeInterval($0.0 * 60),
                end: base.addingTimeInterval($0.1 * 60),
                stage: $0.2
            )
        }
    }

    private func render(_ name: String, _ view: some View, height: CGFloat) throws {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: height))
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size.width > 0)
        let dir = "/private/tmp/claude-501/-Users-trevorlink-Project-hackathon-Pibo/3bf5d23e-3e4b-42c9-a92e-1f6d05ee27f4/scratchpad/render"
        guard FileManager.default.fileExists(atPath: dir),
              let data = image.pngData() else { return }
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    @Test func rendersCardVariants() throws {
        let full = segments([
            (0, 12, .awake), (12, 60, .core), (60, 110, .deep), (110, 170, .core),
            (170, 173, .awake), (173, 200, .rem), (200, 260, .core), (260, 300, .deep),
            (300, 380, .core), (380, 420, .rem), (420, 425, .awake), (425, 480, .core),
        ])
        try render("card-full", HistorySleepCard(
            totalSeconds: 456 * 60,
            start: base.addingTimeInterval(12 * 60),
            end: base.addingTimeInterval(480 * 60),
            segments: full,
            onExpand: {}
        ).padding(12).background(Color(hex: 0xEAEEEF)), height: 460)

        let gapped = segments([
            (0, 90, .core), (90, 150, .deep), (210, 300, .core), (300, 340, .rem),
            (330, 360, .core),
        ])
        try render("card-gap-overlap", HistorySleepCard(
            totalSeconds: 340 * 60,
            start: base,
            end: base.addingTimeInterval(360 * 60),
            segments: gapped,
            onExpand: {}
        ).padding(12).background(Color(hex: 0xEAEEEF)), height: 460)

        try render("card-stageless", HistorySleepCard(
            totalSeconds: 420 * 60,
            start: base,
            end: base.addingTimeInterval(430 * 60),
            segments: [],
            onExpand: {}
        ).padding(12).background(Color(hex: 0xEAEEEF)), height: 300)
    }
}
