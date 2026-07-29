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

    /// 登场的整体缩放与金光强度。没有登场的状态恒为 1 / 0。
    private(set) var introScale: CGFloat = 1
    private(set) var introGlow: CGFloat = 0
    private(set) var introGlowColor: String?
    /// 登场期间常规连招暂停。
    var suppressesIdle: Bool { phase == .intro }

    private(set) var fromStateID: String
    private(set) var toStateID: String
    /// Eased progress, not raw time.
    private(set) var progress: CGFloat = 1

    var isRunning: Bool { phase != .idle }
    /// 形状落定。剧本用它开始计时保持。
    var onSettled: (() -> Void)?
    /// 登场（若有）也结束了，连招可以从 0 起播。
    var onIntroFinished: (() -> Void)?

    private enum Phase {
        case idle
        case morphing
        case settling
        /// 只有 muscle / pigu 有。期间常规连招暂停 —— 亮相是定格 pose。
        case intro
    }

    private let data: PiboCharacterData
    private let easing: PiboUnitBezier
    private var phase: Phase = .idle
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0

    init(data: PiboCharacterData, stateID: String) {
        self.data = data
        easing = PiboUnitBezier(data.transition.easingBezier)
        fromStateID = stateID
        toStateID = stateID
    }

    /// Starts a transition to `stateID`. Re-targeting mid-flight restarts from
    /// the shape currently on screen rather than snapping.
    func transition(to stateID: String) {
        guard stateID != toStateID, data.states[stateID] != nil else { return }
        fromStateID = isRunning ? currentVisualStateID() : toStateID
        toStateID = stateID
        duration = Self.duration(from: fromStateID, to: stateID, data: data) / 1000
        elapsed = 0
        progress = 0
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
        settleScale = 1
        introScale = 1
        introGlow = 0
        introGlowColor = nil
    }

    func update(deltaTime: TimeInterval) {
        guard phase != .idle else { return }
        elapsed += max(0, deltaTime)

        switch phase {
        case .idle:
            break

        case .morphing:
            let t = duration > 0 ? min(1, elapsed / duration) : 1
            progress = CGFloat(easing(t))
            idleAmplitude = duckAmplitude(morphFraction: t)
            if t >= 1 {
                progress = 1
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
                if let intro = data.states[toStateID]?.idle?.intro {
                    introGlowColor = intro.glow
                    phase = .intro
                    elapsed = 0
                } else {
                    phase = .idle
                    onIntroFinished?()
                }
            }

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
    }

    // MARK: - Private

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
        let zones = data.transition.zones
        func zone(of stateID: String) -> String {
            zones.first { $0.value.contains(stateID) }?.key ?? "ground"
        }
        return zone(of: from) == zone(of: to)
            ? data.transition.durationMs
            : data.transition.crossZoneDurationMs
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
