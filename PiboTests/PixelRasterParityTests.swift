import CryptoKit
import CoreGraphics
import Foundation
import PiboCore
import Testing
@testable import Pibo

/// Captured from HarmonyPibo's production ArkTS draw functions, 2026-10-23.
/// A Swift refactor must keep the same logical pixels (including JS rounding).
@MainActor
struct PixelRasterParityTests {
    private let forestHashes = [
        "6bbcf2ac0f8914d4cf5e1d1040839cefff2c96f16df1d94725a7fc704de8a78d",
        "a0c4a116b5d06f58d69a542e85df205fa6ae692b8f9223edad4bf28be3f00242",
        "c47e667b058fb7c353b74733626e967c3e1a5438a031feacfb4e8fde8473c382",
        "3b683528f826ee1e9464cf41c4dc4a078b3f51c4d34370802dc3108f964150ed",
        "192f0c63a3877467b72384b57646a7ed9eb72a76de61eca8f54548572eb2f492",
        "e8972264bf0b55a8358986461af359e13da27518be3a5a095574d4a830ee428e",
        "9e8b023b2b9b046113f2baa6c9e82b4251c5aff34b795f83f5c1941542f27471",
        "8550f0040b6b1c6ae1ae0fb24dad0041330839d3fabb3521e58458e5edfecdc2",
        "7aea98ffbd7db77b3996f91a9b376bb0ee91fd640af323ab84ce95dc0bb27d51",
        "614fa151c8def4e01c26fd94c67f26a3850df53abe2bb11da96e69ab52695d21",
        "ba36e5b31bbc062e5ba35ff53dac4288360fbd40d41de7dba41c462965626af3",
        "276ce9f6fdd1931fbba36e3e83f1348d1983e992ad5b6abb4ccff4c5d345a1c6",
        "d14f822f893ea3713097feccd733a322031c9ce29398814e393606021eb71e13",
        "b807d1213737e4bbdb82ce5a99bac8dc853e1c3ff411930c647d3b33799a340a",
        "66b120d6eeeef0962b3f00190a7d4ef1febf0472f4a3e9824977afb326516ffa",
        "553750120792f139a74486c2e969607781a16b93597c730019aaae6f9199fbf2",
        "f3d0855b1a61cb2b400d3aa01a49e0428cfe0bb4fd52ba01e50707fc64a51c2f",
        "c338d3d52386f6ff613d562fbe19ad08ce35e5f0fd566b78a1346f3f6086870b",
        "45b61e81920c612e1e26f78573a5b7f49c5193f1a3faaac00079fd3ffd0bd434",
        "66165b0db641367198958d56fcb9a7dac4197416a6d66ffa3e45bba6a6d3a40f",
        "ef7c2e8246c97aec3779926b659da4baf3fed04b0ba8b74439d66c9af6370e30",
        "6a54a197073648882ada1b877ae6231e74dab5a4e05bea630085135fedfc189e",
        "5c4151631eff81205d9317b7f89d48ddc79ba133a45a7cff0453b22ac764d88b",
        "43e7fe6a3de11de25d16a69814e7587e6d6c31431d586259b89e6e695ba664b4",
    ]
    private let formHashes = [
        "fd9f9b2a7ed7e7500b5479c575f243a14811160119227c2d4b439209086919d9",
        "9732f0339ab45a391692a5a727ed351434109d928f8ea1a00c16f533683b4ae8",
        "bd5cf5b08e8abf416547d7f4310787516b06891f4697d267f30adcbaefac06ad",
        "f2186d67faa14812ec63a33bb75679baab4c3a2d5331366a3720ff9001461a1e",
        "01204233fd42f7ac8e435fd2e2688b4d8d17e258265a609cc8388fe691dd9475",
        "1e70f9171d788384d9645415a9e5530d7f5be2a26b60cf24806da8f5eb75d566",
        "857f050da52ce9eb466a8029ad23a0def4ba16ec1267d90db6e7857d16f12948",
        "ac6d221c38032bd62d838b85e64a33d9fba4e1af13949f75a34fa56a8cff2067",
        "6a87f854139c93ef61ea57490a625d0ee98b8bcd723dc02b7d67b3116c717c38",
        "41438553ac00eece1a0de5f1c1baca35ab446bb816817c450fff6b3c57f236ed",
    ]

    @Test func forestAndCharacterMatchHarmony() {
        for mood in PixelMood.allCases {
            for state in 0..<6 {
                let frame = PixelFrame(168, 364)
                let layout = pixelForestLayout(168, 364)
                drawPixelForestStatic(frame, layout, 2026, mood)
                drawPixelForestLife(frame, layout, 2026, mood, mood == .rain, 1700)
                let look = PiboPixelLook()
                look.bodyStage = state % 3
                look.leafStage = state % 5
                look.leafGrowth = 0.7
                look.leafRipe = true
                look.accessoryMask = 15
                let pose = piboPixelPose(PiboPixelActivity(rawValue: state)!, timeMs: 1700, patAgeMs: 300, look: look)
                drawPiboPixel(frame, 84, Double(layout.groundY), pose)
                #expect(digest(frame) == forestHashes[mood.rawValue * 6 + state], "mood=\(mood), state=\(state)")
            }
        }
    }

    @Test func allFormsMatchHarmony() {
        for form in 1...10 {
            let frame = PixelFrame(88, 88)
            let look = PiboFormLook()
            look.form = PiboForm(rawValue: form)!
            look.timeMs = 1700
            look.stuck = true
            look.badge = .stable
            drawPiboForm(frame, 44, 64, look)
            #expect(digest(frame) == formHashes[form - 1], "form=\(form)")
        }
    }

    private func digest(_ frame: PixelFrame) -> String {
        SHA256.hash(data: Data(frame.data)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
struct PixelPresentationSafetyTests {
    @Test func ripeInstructionWaitsForAVisibleIdleLeafAndYieldsToThePull() {
        let renderer = PixelStageRenderer()
        var look = PixelStageRenderer.Look()
        look.leafRipe = true
        let size = CGSize(width: 402, height: 874)
        let now = Date().timeIntervalSince1970 * 1000
        _ = renderer.render(size: size, scale: 3, now: now, look: look)
        #expect(renderer.showsRipePullHint)
        renderer.leafPan(-30, ripe: true)
        #expect(!renderer.showsRipePullHint, "the instruction must not cover the active pull")
        renderer.leafPanEnd()
        look.holdPibo = true
        _ = renderer.render(size: size, scale: 3, now: now + 50, look: look)
        #expect(!renderer.showsRipePullHint, "Pibo's dialogue owns the space above the leaf")
        look.holdPibo = false
        look.piboVisible = false
        _ = renderer.render(size: size, scale: 3, now: now + 100, look: look)
        #expect(!renderer.showsRipePullHint)
    }

    @Test func hiddenActorCannotSpeakThroughForegroundScenery() {
        let frame = PixelFrame(12, 12)
        let visibility = PixelActorVisibility()
        frame.clear(.groundLight)
        visibility.begin(frame, x: 0, y: 0, width: 12, height: 12)
        frame.fillRect(3, 3, 9, 9, .bodyLight)
        visibility.mark(frame)
        #expect(visibility.readable(frame))
        frame.fillRect(3, 3, 9, 8, .treeDark)
        #expect(!visibility.readable(frame), "one remaining sliver is not an identifiable speaking Pibo")
    }

    @Test func coreMotionGravityUnitsAreConvertedBeforeTheCoreShakeDecision() {
        let resting = PixelShakeSampler.peakMetersPerSecondSquared(x: 0, y: 0, z: 1)
        #expect(abs(resting - 9.80665) < 0.00001)
        #expect(!PiboCoreGrowth.shakeDetected(peakAcceleration: resting, secondsSinceLast: 60))
        let shake = PixelShakeSampler.peakMetersPerSecondSquared(x: 3, y: 0, z: 0)
        #expect(PiboCoreGrowth.shakeDetected(peakAcceleration: shake, secondsSinceLast: 60))
    }
}
