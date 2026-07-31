import CoreGraphics
import Foundation

/// Drives one state change end to end: the morph, the decoration crossfades, the
/// landing pulse, and the idle animation's amplitude duck.
///
/// The rhythm is the design package's, arrived at over four rejected versions
/// (DESIGN-NOTES §2) and not free to re-tune here: a pure **acceleration** curve
/// that spends its first half covering 17% of the distance and hits the line at
/// 2.3× average speed, then a damped "biu" on landing. Deceleration-into-bounce
/// was tried and rejected as two disconnected motions; overshoot easing was
/// rejected outright because an eased `t > 1` combined with polygon-sampled
/// morphing produces spikes.
@MainActor
final class PiboStateTransition {
    /// Idle amplitude multiplier. Every idle primitive scales by this, and
    /// path-level primitives additionally refuse to run below
    /// `pathPrimitiveMinAmplitude` — otherwise they cache a mid-morph frame as
    /// their rest shape and the character is permanently deformed.
    private(set) var idleAmplitude: CGFloat = 1

    /// Container scale for the landing pulse.
    private(set) var settleScale: CGFloat = 1
    private(set) var presentationScaleX: CGFloat = 1
    private(set) var presentationScaleY: CGFloat = 1

    /// 登场的整体缩放与金光强度。没有登场的状态恒为 1 / 0。
    private(set) var introScale: CGFloat = 1
    private(set) var introGlow: CGFloat = 0
    private(set) var introGlowColor: String?
    /// 登场期间常规连招暂停。
    var suppressesIdle: Bool {
        phase == .intro || phase == .bounceExiting || phase == .bounceEntering
    }

    private(set) var fromStateID: String
    private(set) var toStateID: String
    /// Eased progress, not raw time.
    private(set) var progress: CGFloat = 1

    var isRunning: Bool { phase != .idle }
    private(set) var visualAlpha: CGFloat = 1
    private(set) var crossesZone = false
    var displayStateID: String {
        if phase == .bounceExiting { return fromStateID }
        return crossesZone && progress < 0.5 ? fromStateID : toStateID
    }
    /// 形状落定。剧本用它开始计时保持。
    var onSettled: (() -> Void)?
    /// 登场（若有）也结束了，连招可以从 0 起播。
    var onIntroFinished: (() -> Void)?

    private enum Phase {
        case idle
        case morphing
        case settling
        case bounceExiting
        case bounceEntering
        /// 只有 muscle / pigu 有。期间常规连招暂停 —— 亮相是定格 pose。
        case intro
    }

    private let data: PiboCharacterData
    private let easing: PiboUnitBezier
    private let bounceExitEasing = PiboUnitBezier([0.58, 0.02, 0.9, 0.45])
    private let bounceEnterEasing = PiboUnitBezier([0.18, 0.82, 0.25, 1])
    private var phase: Phase = .idle
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var playsIntro = true

    init(data: PiboCharacterData, stateID: String) {
        self.data = data
        easing = PiboUnitBezier(data.transition.easingBezier)
        fromStateID = stateID
        toStateID = stateID
    }

    /// Starts a transition to `stateID`. Re-targeting mid-flight restarts from
    /// the shape currently on screen rather than snapping.
    func transition(to stateID: String, playsIntro: Bool = true) {
        guard stateID != toStateID, data.states[stateID] != nil else { return }
        fromStateID = isRunning ? currentVisualStateID() : toStateID
        toStateID = stateID
        duration = Self.duration(from: fromStateID, to: stateID, data: data) / 1000
        crossesZone = Self.zone(of: fromStateID, data: data) != Self.zone(of: stateID, data: data)
        elapsed = 0
        progress = 0
        self.playsIntro = playsIntro
        phase = .morphing
    }

    func snap(to stateID: String) {
        guard data.states[stateID] != nil else { return }
        fromStateID = stateID
        toStateID = stateID
        progress = 1
        elapsed = 0
        phase = .idle
        idleAmplitude = 1
        visualAlpha = 1
        crossesZone = false
        settleScale = 1
        presentationScaleX = 1
        presentationScaleY = 1
        introScale = 1
        introGlow = 0
        introGlowColor = nil
        playsIntro = true
    }

    /// Business-state changes in the integrated `pibo_context` preview remount
    /// directly in the destination pose. Keep this separate from `snap(to:)`
    /// so callers that represent a real state change also restart the authored
    /// idle timeline, matching that remount behavior.
    func hardCut(to stateID: String) {
        guard data.states[stateID] != nil,
              stateID != toStateID || isRunning else { return }
        snap(to: stateID)
        onSettled?()
        onIntroFinished?()
    }

    /// `pibo_context` business fallback: shrink the old player in place for
    /// 190 ms, hard-swap state and placement, then squash/stretch the new
    /// player in for 520 ms.
    func bounceCut(to stateID: String) {
        guard data.states[stateID] != nil,
              stateID != toStateID || isRunning else { return }
        fromStateID = displayStateID
        toStateID = stateID
        progress = 0
        elapsed = 0
        crossesZone = Self.zone(of: fromStateID, data: data) != Self.zone(of: stateID, data: data)
        idleAmplitude = 0
        visualAlpha = 1
        settleScale = 1
        introScale = 1
        introGlow = 0
        introGlowColor = nil
        presentationScaleX = 1
        presentationScaleY = 1
        phase = .bounceExiting
    }

    /// Starts the destination state's authored one-shot intro without first
    /// morphing or playing the settle pulse. The achievement presentation uses
    /// the same contract as `pibo_context`: white convergence → hard cut to the
    /// target pose → that pose's own intro. It must not layer a second, invented
    /// scale animation on top.
    func startAuthoredIntro() {
        guard let intro = data.states[toStateID]?.idle?.intro else {
            phase = .idle
            onIntroFinished?()
            return
        }
        elapsed = 0
        progress = 1
        idleAmplitude = 1
        visualAlpha = 1
        settleScale = 1
        introScale = 1
        introGlow = 0
        introGlowColor = intro.glow
        phase = .intro
    }

    func update(deltaTime: TimeInterval) {
        guard phase != .idle else { return }
        let step = max(0, deltaTime)
        if phase == .bounceExiting || phase == .bounceEntering {
            updateBounce(deltaTime: step)
            return
        }
        elapsed += step

        switch phase {
        case .idle:
            break

        case .morphing:
            let t = duration > 0 ? min(1, elapsed / duration) : 1
            progress = crossesZone ? (t < 0.5 ? 0 : 1) : CGFloat(easing(t))
            visualAlpha = crossesZone ? CGFloat(abs(2 * t - 1)) : 1
            idleAmplitude = duckAmplitude(morphFraction: t)
            if t >= 1 {
                progress = 1
                visualAlpha = 1
                fromStateID = toStateID
                phase = .settling
                elapsed = 0
                onSettled?()
            }

        case .settling:
            let settleDuration = data.settlePulse.durationMs / 1000
            let u = settleDuration > 0 ? min(1, elapsed / settleDuration) : 1
            settleScale = Self.pulse(u, data.settlePulse)
            idleAmplitude = restoreAmplitude(settleElapsed: elapsed)
            if u >= 1 {
                settleScale = 1
                idleAmplitude = 1
                if playsIntro, let intro = data.states[toStateID]?.idle?.intro {
                    introGlowColor = intro.glow
                    phase = .intro
                    elapsed = 0
                } else {
                    phase = .idle
                    onIntroFinished?()
                }
            }

        case .bounceExiting, .bounceEntering:
            break

        case .intro:
            let intro = data.states[toStateID]?.idle?.intro
            let introDuration = intro?.duration ?? 0
            let u = introDuration > 0 ? min(1, elapsed / introDuration) : 1
            // 单周期阻尼正弦：膨胀 → 缩回 → 收住。
            let swell = exp(-2.5 * u) * sin(2 * .pi * u)
            introScale = 1 + CGFloat((intro?.scale ?? 0) * swell)
            // 金光快起慢收，自行消散。
            introGlow = CGFloat(u < 0.18 ? u / 0.18 : pow(1 - (u - 0.18) / 0.82, 1.6))
            if u >= 1 {
                introScale = 1
                introGlow = 0
                introGlowColor = nil
                phase = .idle
                // 连招时间轴在登场结束后才从自己的 0 秒起播。
                onIntroFinished?()
            }
        }
    }

    /// Cancels the pulse immediately — an interrupted transition must clear the
    /// container transform rather than leave the character mid-squash.
    func interrupt() {
        settleScale = 1
        introScale = 1
        introGlow = 0
        introGlowColor = nil
        visualAlpha = 1
        presentationScaleX = 1
        presentationScaleY = 1
    }

    // MARK: - Private

    private func updateBounce(deltaTime: TimeInterval) {
        var remaining = deltaTime
        while remaining >= 0 {
            switch phase {
            case .bounceExiting:
                let phaseRemaining = max(0, 0.190 - elapsed)
                let consumed = min(remaining, phaseRemaining)
                elapsed += consumed
                remaining -= consumed
                let raw = min(1, elapsed / 0.190)
                let t = CGFloat(bounceExitEasing(raw))
                let scale = Self.keyframeValue(
                    progress: t,
                    offsets: [0, 0.42, 1],
                    values: [1, 0.84, 0.04]
                )
                presentationScaleX = scale
                presentationScaleY = scale
                visualAlpha = Self.keyframeValue(
                    progress: t,
                    offsets: [0, 0.42, 1],
                    values: [1, 1, 0]
                )
                if elapsed < 0.190 { return }

                // State and placement switch together at the authored cut.
                fromStateID = toStateID
                progress = 1
                elapsed = 0
                presentationScaleX = 0.04
                presentationScaleY = 0.04
                visualAlpha = 0
                phase = .bounceEntering

            case .bounceEntering:
                let phaseRemaining = max(0, 0.520 - elapsed)
                let consumed = min(remaining, phaseRemaining)
                elapsed += consumed
                remaining -= consumed
                let raw = min(1, elapsed / 0.520)
                let t = CGFloat(bounceEnterEasing(raw))
                let offsets: [CGFloat] = [0, 0.38, 0.60, 0.76, 0.90, 1]
                presentationScaleX = Self.keyframeValue(
                    progress: t,
                    offsets: offsets,
                    values: [0.04, 1.18, 0.88, 1.07, 0.98, 1]
                )
                presentationScaleY = Self.keyframeValue(
                    progress: t,
                    offsets: offsets,
                    values: [0.04, 0.86, 1.12, 0.95, 1.025, 1]
                )
                visualAlpha = Self.keyframeValue(
                    progress: t,
                    offsets: offsets,
                    values: [0, 1, 1, 1, 1, 1]
                )
                if elapsed < 0.520 { return }

                presentationScaleX = 1
                presentationScaleY = 1
                visualAlpha = 1
                idleAmplitude = 1
                crossesZone = false
                elapsed = 0
                phase = .idle
                onSettled?()
                onIntroFinished?()
                return

            default:
                return
            }

            if remaining <= 0 { return }
        }
    }

    private static func keyframeValue(
        progress: CGFloat,
        offsets: [CGFloat],
        values: [CGFloat]
    ) -> CGFloat {
        guard offsets.count == values.count, let first = values.first else { return 1 }
        if progress <= offsets[0] { return first }
        for index in 1..<offsets.count where progress <= offsets[index] {
            let span = offsets[index] - offsets[index - 1]
            let local = span > 0 ? (progress - offsets[index - 1]) / span : 1
            return values[index - 1] + (values[index] - values[index - 1]) * local
        }
        return values.last ?? first
    }

    /// Which state the character visually reads as right now, used when a new
    /// transition pre-empts one in flight.
    private func currentVisualStateID() -> String {
        progress > 0.5 ? toStateID : fromStateID
    }

    /// Ground ⇄ nest is a 90 ms hard cut, not a morph: the positions differ so
    /// much that interpolating between them is meaningless. It stays a very short
    /// transition rather than a zero-frame swap so decorations still crossfade
    /// and the landing pulse still fires — "landing with a thud", not a flicker.
    private static func duration(from: String, to: String, data: PiboCharacterData) -> Double {
        return zone(of: from, data: data) == zone(of: to, data: data)
            ? data.transition.durationMs
            : data.transition.crossZoneDurationMs
    }

    private static func zone(of stateID: String, data: PiboCharacterData) -> String {
        data.transition.zones.first { $0.value.contains(stateID) }?.key ?? "ground"
    }

    private func duckAmplitude(morphFraction t: Double) -> CGFloat {
        let duckFraction = data.idleBlend.duckFraction
        let floorValue = CGFloat(data.idleBlend.duckToAmplitude)
        guard duckFraction > 0 else { return floorValue }
        let u = min(1, t / duckFraction)
        // Sine ease so the idle motion does not stop abruptly the instant a
        // transition begins.
        let eased = sin(CGFloat(u) * .pi / 2)
        return 1 - (1 - floorValue) * eased
    }

    private func restoreAmplitude(settleElapsed: TimeInterval) -> CGFloat {
        let restoreDuration = data.idleBlend.restoreFraction * duration
        let floorValue = CGFloat(data.idleBlend.duckToAmplitude)
        guard restoreDuration > 0 else { return 1 }
        let u = min(1, settleElapsed / restoreDuration)
        let eased = sin(CGFloat(u) * .pi / 2)
        return floorValue + (1 - floorValue) * eased
    }

    /// `s(u) = 1 + A · e^(−damp·u) · sin(cycles · 2π · u)`.
    /// Peaks ≈105.3% at 67 ms, dips ≈98.8% at 254 ms, then holds. An earlier,
    /// stronger 111% / 95% version was rejected as "too violent" — this is the
    /// softened "just a small swell".
    private static func pulse(_ u: Double, _ spec: PiboCharacterData.SettlePulse) -> CGFloat {
        let value = 1 + spec.amplitude * exp(-spec.damp * u) * sin(spec.cycles * 2 * .pi * u)
        return CGFloat(value)
    }
}
