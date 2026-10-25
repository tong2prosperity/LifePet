import CoreGraphics
import Testing
@testable import Pibo

@MainActor
struct PixelStageCoverageTests {
    @Test(arguments: [CGSize(width: 430, height: 932), CGSize(width: 402, height: 874),
                      CGSize(width: 393, height: 852), CGSize(width: 375, height: 812),
                      CGSize(width: 320, height: 568), CGSize(width: 430.5, height: 932.5)])
    func integerScaledForestCoversEveryScreenEdge(size: CGSize) throws {
        let renderer = PixelStageRenderer()
        let scale = max(1, Int((size.width / CGFloat(PixelStageRenderer.targetWidth)).rounded()))
        var look = PixelStageRenderer.Look()
        look.hour = 0
        let image = try #require(renderer.render(size: size, scale: scale, now: 1000, look: look))
        let width = CGFloat(image.width * scale), height = CGFloat(image.height * scale)
        #expect(width >= size.width, "integer scaling must not leave a vertical background strip")
        #expect(height >= size.height, "integer scaling must not leave a horizontal background strip")
        #expect(width - size.width < CGFloat(scale))
        #expect(height - size.height < CGFloat(scale))
    }
}
