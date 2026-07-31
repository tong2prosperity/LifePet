import CoreGraphics
import Foundation

/// Runtime mirror of `pibo-assets/ios/character/PiboCharacterData.json`.
///
/// The JSON is produced by `tools/prematch/prematch.mjs`, which compiles the
/// designer's 12-state delivery package into something a native runtime can
/// consume directly: shared paths already resampled onto a common topology, so
/// morphing is a control-point lerp and no polygon-matching library is needed.
/// HarmonyOS reads the same file — keep this decoder tolerant of fields it does
/// not use rather than mirroring every key.
struct PiboCharacterData: Decodable {
    struct Size: Decodable {
        let width: CGFloat
        let height: CGFloat
    }

    struct Bounds: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    /// Behaviour constants carried over from the design package's SPEC so the
    /// numbers live in one place instead of being retyped per platform.
    struct Transition: Decodable {
        let durationMs: Double
        let easingBezier: [Double]
        let crossZoneDurationMs: Double
        let zones: [String: [String]]
        let decorationExitFraction: Double
        let decorationEnterDelayFraction: Double
        let decorationEnterFraction: Double
    }

    struct SettlePulse: Decodable {
        let amplitude: Double
        let damp: Double
        let cycles: Double
        let durationMs: Double
        let anchor: [Double]
    }

    struct IdleBlend: Decodable {
        let duckToAmplitude: Double
        let duckFraction: Double
        let restoreFraction: Double
        let pathPrimitiveMinAmplitude: Double
    }

    enum RenderMode: String, Decodable {
        /// Drawn from live geometry — participates in morphing or is deformed by
        /// a path-level idle primitive.
        case vector
        /// Rasterised once at load; only alpha and transform animate.
        case texture
    }

    struct Element: Decodable {
        let id: String
        let role: String
        let render: RenderMode
        let d: String
        let fill: String?
        let stroke: String?
        let strokeWidth: CGFloat?
        let lineCap: String?
        let lineJoin: String?
        let fillRule: String
        let opacity: CGFloat
        /// Visibility is owned by the idle animation (pigu's ✨), so the
        /// transition's fade timings must leave it alone; starts hidden.
        let idleOwned: Bool
        let layer: String

        var isShared: Bool { role == "shared" }
        var usesEvenOddFill: Bool { fillRule == "evenOdd" }
    }

    /// The sprout's local skeleton. The head rig bends the 毛 from root to tip,
    /// so it needs an axis rather than a canvas-aligned box — `awake` hangs out
    /// of the coconut hole with its root *above* its tip.
    struct Sprout: Decodable {
        let root: [CGFloat]
        let tip: [CGFloat]
        let bounds: Bounds

        var rootPoint: CGPoint { CGPoint(x: root[0], y: root[1]) }
        var tipPoint: CGPoint { CGPoint(x: tip[0], y: tip[1]) }
    }

    struct State: Decodable {
        let zone: String
        let hasIntro: Bool
        let introGlow: String?
        /// Ordered: array order is render order is the source SVG's layer order.
        let elements: [Element]
        let sprout: Sprout
        let idle: Idle?
    }

    /// One state's idle choreography, carried over verbatim from the design
    /// package. Every part shares a single `gateCycle` timeline and occupies a
    /// window on it — the designer's core note was "don't let the moves run on
    /// separate clocks, they drift apart and collide"; a combo has to read as one
    /// continuous motion.
    struct Idle: Decodable {
        let kind: String
        let parts: [Part]?
        let intro: Intro?
        private let singlePart: Part

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            parts = try container.decodeIfPresent([Part].self, forKey: .parts)
            intro = try container.decodeIfPresent(Intro.self, forKey: .intro)
            singlePart = try Part(from: decoder)
        }

        private enum CodingKeys: String, CodingKey { case kind, parts, intro }

        /// 闪亮登场。设计师要的是「切过去时第一次变化很强烈很快，闪亮登场秀肌肉
        /// 的感觉，后面默认态保持现状」。第一版做成「首轮连招压缩快放」被否了
        /// （「太夸张，快得卡顿」），最终是**单次膨胀→缩回→定格**加一层自行消散
        /// 的金光 —— 亮相是定格 pose，不是把动作演快。
        struct Intro: Decodable {
            let duration: Double
            let scale: Double
            let glow: String
        }

        /// Flattened view: a non-compound idle is a single part.
        var resolvedParts: [Part] {
            if let parts { return parts }
            return [singlePart]
        }

        struct Part: Decodable {
            let kind: String
            let selector: String?
            let selectorAll: String?

            let duration: Double?
            let period: Double?
            let amplitude: Double?
            let phase: Double?
            let origin: String?

            // Gate window on the shared timeline.
            let gateCycle: Double?
            let gateRange: [Double]?
            let gateRanges: [[Double]]?
            let gateFade: Double?
            let gateOffset: Double?

            // rotate-around-point
            let pivot: [Double]?
            /// Swings one way only, instead of oscillating through rest.
            let unipolar: Bool?
            /// Holds at the extreme instead of swinging back — "lifts into a
            /// cheeky pose" rather than wagging.
            let hold: Bool?

            // blink
            let blinkDuration: Double?
            let randomize: Bool?
            let minPeriod: Double?
            let maxPeriod: Double?
            let minScale: Double?
            /// Which phase of the period the blink lands on.
            let at: Double?
            let originY: Double?

            // breathe-hop
            let hopPeriod: Double?
            let hopHeight: Double?
            let hopBounces: Double?
            let hopDuration: Double?

            // path-bulge / pulse-scale
            let center: [Double]?
            let radius: Double?
            let damp: Double?
            let cycles: Double?
            /// Directional push on top of the radial swell, so the outer edge
            /// reads as "sticking out further" rather than just inflating.
            let bias: [Double]?

            // path-wiggle
            let waves: Double?
            let controlsOnly: Bool?

            // sigh-sequence
            let swellDuration: Double?
            let flattenDuration: Double?
            let recoverDuration: Double?
            let pauseDuration: Double?
            let swellY: Double?
            let flattenY: Double?
            let swellX: Double?
            let flattenX: Double?

            // waggle-sequence
            let cycleDuration: Double?
            let restFraction: Double?

            // sparkle-fly
            let dx: Double?
            let dy: Double?
            let rotate: Double?
            let scaleFrom: Double?
            let scalePeak: Double?
            let scaleEnd: Double?

            // pop-loop / bubble-breathe / wink-morph
            let visibilityFraction: Double?
            let fadeFraction: Double?
            let phaseStep: Double?
            let originSelf: Bool?
            let scaleRange: [Double]?
            let translateRange: [[Double]]?
            let rotateRange: [Double]?
            let maxScale: Double?
            let openPath: String?
            let closeFraction: Double?
            let holdUntil: Double?
        }
    }

    /// One shared path across all states. `resampled` carries equal-length point
    /// rings; `structured` carries a command sequence plus control points and
    /// interpolates exactly, keeping its béziers.
    struct Morph: Decodable {
        enum Strategy: String, Decodable {
            case resampled
            case structured
        }

        let strategy: Strategy
        let closed: Bool
        let sampleCount: Int?
        let points: [String: [CGFloat]]?
        let commands: [String]?
        let controls: [String: [CGFloat]]?

        func values(for stateID: String) -> [CGFloat]? {
            switch strategy {
            case .resampled: points?[stateID]
            case .structured: controls?[stateID]
            }
        }
    }

    let schemaVersion: Int
    let designFrame: Size
    let transition: Transition
    let settlePulse: SettlePulse
    let idleBlend: IdleBlend
    let sharedMorphPaths: [String]
    let states: [String: State]
    let morph: [String: Morph]
}

extension PiboCharacterData {
    enum LoadError: Error {
        case resourceMissing
    }

    /// Loaded once — the file is ~160 KB of geometry that never changes at runtime.
    static let shared: PiboCharacterData? = try? load()

    static func load(bundle: Bundle = .main) throws -> PiboCharacterData {
        let candidates = [
            bundle.url(forResource: "PiboCharacterData", withExtension: "json", subdirectory: "Character"),
            bundle.url(forResource: "PiboCharacterData", withExtension: "json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else { throw LoadError.resourceMissing }
        return try JSONDecoder().decode(PiboCharacterData.self, from: Data(contentsOf: url))
    }
}
