import CoreGraphics
import Foundation
import SpriteKit

/// Runs one state's idle choreography.
///
/// The model is the design package's, and the reason for it is worth keeping in
/// view: the designer's decisive note on the first pass was *"don't split
/// everything up, it feels stiff — it has to be continuous, a smooth little
/// combo"*. So every move in a state shares **one** timeline of `gateCycle`
/// seconds and occupies a window on it (`gateRange`, eased at the edges by
/// `gateFade`), instead of each running on its own period and drifting into
/// collisions.
///
/// Two structural differences from the web engine, both in our favour:
///
/// - Path-level primitives deform a **freshly rebuilt** base path every frame
///   rather than caching a rest shape of their own. The web version had to cache
///   `d0`, which is how a primitive starting mid-morph could bake an
///   intermediate frame in as the rest shape and deform the character forever
///   (SPEC §7.6). That failure mode does not exist here.
/// - Transform primitives write to `SKNode` transforms, which the rebuild never
///   touches, so idle and morph cannot fight over the same property (SPEC §7.7).
@MainActor
final class PiboIdleAnimator {
    /// Path-level primitives stay off until the morph is essentially done. Kept
    /// even though our base-path handling makes the original bug impossible:
    /// deforming a shape that is still travelling reads as noise.
    private let pathPrimitiveMinAmplitude: CGFloat

    private var timelineStart: TimeInterval?
    private var activeStateID: String?

    init(data: PiboCharacterData) {
        pathPrimitiveMinAmplitude = CGFloat(data.idleBlend.pathPrimitiveMinAmplitude)
    }

    /// Restarts the shared timeline. Called when a state settles so a combo
    /// always begins at its own zero rather than wherever the clock happens to be.
    func restartTimeline() {
        timelineStart = nil
    }

    func apply(
        idle: PiboCharacterData.Idle?,
        stateID: String,
        character: PiboVectorCharacter,
        time: TimeInterval,
        amplitude: CGFloat
    ) {
        if activeStateID != stateID {
            activeStateID = stateID
            timelineStart = nil
        }
        guard let idle else { return }
        if timelineStart == nil { timelineStart = time }
        let elapsed = time - (timelineStart ?? time)

        for part in idle.resolvedParts {
            apply(part: part, stateID: stateID, character: character, elapsed: elapsed, amplitude: amplitude)
        }
    }

    // MARK: - Gate

    /// A part's activity on the shared timeline: 0 outside its window, ramping
    /// through `gateFade` at each edge, 1 in the middle. Parts with no gate are
    /// always on.
    private func gate(_ part: PiboCharacterData.Idle.Part, elapsed: TimeInterval) -> CGFloat {
        guard let cycle = part.gateCycle, cycle > 0, let range = part.gateRange, range.count == 2 else {
            return 1
        }
        let offset = part.gateOffset ?? 0
        var phase = (elapsed / cycle + offset).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }

        let (start, end) = (range[0], range[1])
        let inside: Bool
        let localPosition: Double
        let span: Double
        if start <= end {
            inside = phase >= start && phase <= end
            localPosition = phase - start
            span = end - start
        } else {
            // Window wraps past the end of the cycle.
            inside = phase >= start || phase <= end
            localPosition = phase >= start ? phase - start : phase + (1 - start)
            span = (1 - start) + end
        }
        guard inside, span > 0 else { return 0 }

        let fade = min(part.gateFade ?? 0, span / 2)
        guard fade > 0 else { return 1 }
        let rise = min(1, localPosition / fade)
        let fall = min(1, (span - localPosition) / fade)
        let edge = min(rise, fall)
        // Smoothstep so a window opening does not snap the motion on.
        return CGFloat(edge * edge * (3 - 2 * edge))
    }

    /// Phase within a part's own oscillation.
    private func wave(_ part: PiboCharacterData.Idle.Part, elapsed: TimeInterval) -> Double {
        let period = part.duration ?? part.period ?? 1
        guard period > 0 else { return 0 }
        return (elapsed / period + (part.phase ?? 0)).truncatingRemainder(dividingBy: 1)
    }

    // MARK: - Dispatch

    private func apply(
        part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        amplitude: CGFloat
    ) {
        let gateValue = gate(part, elapsed: elapsed)
        let strength = amplitude * gateValue

        switch part.kind {
        case "breathe", "breathe-y":
            applyBreathe(part, character: character, elapsed: elapsed, strength: strength, verticalOnly: part.kind == "breathe-y")
        case "breathe-hop":
            applyBreatheHop(part, character: character, elapsed: elapsed, strength: strength)
        case "rotate-around-point":
            applyRotate(part, stateID: stateID, character: character, elapsed: elapsed, strength: strength)
        case "blink":
            applyBlink(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "waggle-sequence":
            applyWaggle(part, character: character, elapsed: elapsed, strength: strength)
        case "pulse-scale":
            applyPulseScale(part, stateID: stateID, character: character, elapsed: elapsed, strength: strength)
        case "sparkle-fly":
            applySparkle(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "path-bulge":
            guard amplitude > pathPrimitiveMinAmplitude else { break }
            applyPathBulge(part, stateID: stateID, character: character, elapsed: elapsed, strength: strength)
        case "path-wiggle":
            guard amplitude > pathPrimitiveMinAmplitude else { break }
            applyPathWiggle(part, stateID: stateID, character: character, elapsed: elapsed, strength: strength)
        default:
            break
        }
    }

    // MARK: - Whole-body primitives

    private func applyBreathe(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat,
        verticalOnly: Bool
    ) {
        let swell = CGFloat(sin(wave(part, elapsed: elapsed) * 2 * .pi)) * CGFloat(part.amplitude ?? 0.03) * strength
        character.setBreath(x: verticalOnly ? 1 : 1 + swell, y: 1 + swell)
    }

    /// Breathing and the intermittent hop have to be one primitive: both write
    /// the root transform, and two independent writers would fight.
    private func applyBreatheHop(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let swell = CGFloat(sin(wave(part, elapsed: elapsed) * 2 * .pi)) * CGFloat(part.amplitude ?? 0.03) * strength
        character.setBreath(x: 1 + swell, y: 1 + swell)

        let hopPeriod = part.hopPeriod ?? 0
        let hopDuration = part.hopDuration ?? 0
        guard hopPeriod > 0, hopDuration > 0 else {
            character.setHopOffset(0)
            return
        }
        let phase = elapsed.truncatingRemainder(dividingBy: hopPeriod)
        guard phase < hopDuration else {
            character.setHopOffset(0)
            return
        }
        let u = phase / hopDuration
        let bounces = part.hopBounces ?? 1
        // Damped bounce: each successive hop is visibly smaller.
        let height = CGFloat(part.hopHeight ?? 0) * strength
        let value = abs(sin(u * .pi * bounces)) * exp(-2.2 * u)
        character.setHopOffset(height * CGFloat(value))
    }

    private func applyWaggle(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let cycle = part.cycleDuration ?? part.duration ?? 1
        guard cycle > 0 else { return }
        let rest = part.restFraction ?? 0
        let phase = elapsed.truncatingRemainder(dividingBy: cycle) / cycle
        let active = max(0, 1 - rest)
        guard active > 0, phase < active else {
            character.setBodyRotation(0)
            return
        }
        let u = phase / active
        // Deliberately small: a large whole-body swing throws the extremities
        // around and drowns out whichever local move is the point of the combo.
        let angle = CGFloat(sin(u * 2 * .pi * 2)) * CGFloat(part.amplitude ?? 1.5) * .pi / 180
        character.setBodyRotation(angle * strength)
    }

    // MARK: - Element primitives

    private func applyRotate(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let degrees = CGFloat(part.amplitude ?? 0)
        let raw = sin(wave(part, elapsed: elapsed) * 2 * .pi)
        let swing: Double
        if part.hold == true {
            // Lift, stay, lower — not an oscillation. "From standing to a cheeky
            // raised foot", which reads as a pose rather than a wag.
            swing = smoothPulse(wave(part, elapsed: elapsed))
        } else if part.unipolar == true {
            swing = (raw + 1) / 2
        } else {
            swing = raw
        }
        let angle = degrees * .pi / 180 * CGFloat(swing) * strength

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            guard let pivot = part.pivot, pivot.count == 2 else {
                node.zRotation = angle
                continue
            }
            let transform = character.transform(forSelector: selector)
            let anchor = CGPoint(x: pivot[0], y: pivot[1]).applying(transform)
            character.setRotation(angle, about: anchor, for: node)
        }
    }

    /// 0 → 1 → hold → 0, with eased shoulders.
    private func smoothPulse(_ t: Double) -> Double {
        let rise = 0.22, fall = 0.78
        if t < rise { let u = t / rise; return u * u * (3 - 2 * u) }
        if t < fall { return 1 }
        let u = (1 - t) / (1 - fall)
        return u * u * (3 - 2 * u)
    }

    private func applyBlink(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let period = part.period ?? 4
        let blink = part.blinkDuration ?? 0.16
        guard period > 0, blink > 0 else { return }
        let at = part.at ?? 0
        var phase = (elapsed / period - at).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let window = blink / period

        let squash: CGFloat
        if phase < window {
            let u = phase / window
            squash = 1 - CGFloat(sin(u * .pi)) * strength
        } else {
            squash = 1
        }

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            // Multi-layer eyes share one squash centre, otherwise the pupil and
            // its highlight close about different lines and slide apart.
            let centre = part.originY.map { CGFloat($0) }
            character.setVerticalSquash(squash, originY: centre, for: node, selector: selector)
        }
    }

    private func applyPulseScale(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let damp = part.damp ?? 3
        let cycles = part.cycles ?? 1
        let period = part.duration ?? part.period ?? 1
        guard period > 0 else { return }
        let u = elapsed.truncatingRemainder(dividingBy: period) / period
        let value = exp(-damp * u) * sin(cycles * 2 * .pi * u)
        let scale = max(0.05, 1 + CGFloat(value) * CGFloat(part.amplitude ?? 0.2) * strength)

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            character.setUniformScale(scale, pivot: part.pivot, selector: selector, for: node)
        }
    }

    private func applySparkle(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let cycle = part.gateCycle ?? 6
        guard cycle > 0, let range = part.gateRange, range.count == 2 else { return }
        let offset = part.gateOffset ?? 0
        var phase = (elapsed / cycle + offset).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let span = range[1] - range[0]
        guard span > 0, phase >= range[0], phase <= range[1] else {
            for selector in selectors(of: part) {
                character.node(forSelector: selector, stateID: stateID)?.alpha = 0
            }
            return
        }
        let u = (phase - range[0]) / span

        // Fade in, fly out while turning and growing, fade away.
        let fade: CGFloat = u < 0.2
            ? CGFloat(u / 0.2)
            : (u > 0.65 ? CGFloat((1 - u) / 0.35) : 1)
        let scaleFrom = CGFloat(part.scaleFrom ?? 0.4)
        let scalePeak = CGFloat(part.scalePeak ?? 1.2)
        let scaleEnd = CGFloat(part.scaleEnd ?? 0.8)
        let scale = u < 0.5
            ? scaleFrom + (scalePeak - scaleFrom) * CGFloat(u / 0.5)
            : scalePeak + (scaleEnd - scalePeak) * CGFloat((u - 0.5) / 0.5)

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            node.alpha = min(max(fade, 0), 1) * strength
            let travel = CGPoint(
                x: CGFloat(part.dx ?? 0) * CGFloat(u),
                y: CGFloat(part.dy ?? 0) * CGFloat(u)
            )
            character.setSparkleTransform(
                offset: travel,
                rotationDegrees: CGFloat(part.rotate ?? 0) * CGFloat(u),
                scale: scale,
                selector: selector,
                for: node
            )
        }
    }

    // MARK: - Path primitives

    /// Radial swell with Gaussian falloff: "the bum sticks out more" while the
    /// face does not move at all. `bias` adds a directional push so the outer
    /// edge reads as tipping further out rather than just inflating.
    private func applyPathBulge(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        guard let centre = part.center, centre.count == 2 else { return }
        let radius = CGFloat(part.radius ?? 40)
        guard radius > 0 else { return }
        let damp = part.damp ?? 3
        let cycles = part.cycles ?? 2
        let period = part.duration ?? part.period ?? 1
        guard period > 0 else { return }
        let u = elapsed.truncatingRemainder(dividingBy: period) / period
        let envelope = CGFloat(exp(-damp * u) * sin(cycles * 2 * .pi * u))
        let magnitude = envelope * CGFloat(part.amplitude ?? 0.1) * strength
        guard abs(magnitude) > 0.0005 else { return }

        for selector in selectors(of: part) {
            guard let base = character.basePath(forSelector: selector, stateID: stateID),
                  let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            let transform = character.transform(forSelector: selector)
            let anchor = CGPoint(x: centre[0], y: centre[1]).applying(transform)
            let scaledRadius = radius * abs(transform.a)
            let bias = CGVector(
                dx: CGFloat(part.bias?.first ?? 0) * transform.a,
                dy: CGFloat(part.bias?.count ?? 0) > 1 ? CGFloat(part.bias?[1] ?? 0) * transform.d : 0
            )
            node.path = PiboCharacterGeometry.bulged(
                base,
                centre: anchor,
                radius: scaledRadius,
                magnitude: magnitude,
                bias: bias
            )
        }
    }

    /// Jelly wobble along the outline. Small on purpose — it is a texture on top
    /// of the sprout's swing, not a motion of its own.
    private func applyPathWiggle(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let period = part.period ?? 0.45
        guard period > 0 else { return }
        let amplitude = CGFloat(part.amplitude ?? 1.3) * strength
        guard abs(amplitude) > 0.01 else { return }
        let waves = CGFloat(part.waves ?? 3)
        let phase = CGFloat(elapsed / period * 2 * .pi)

        for selector in selectors(of: part) {
            guard let base = character.basePath(forSelector: selector, stateID: stateID),
                  let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            let transform = character.transform(forSelector: selector)
            node.path = PiboCharacterGeometry.wiggled(
                base,
                amplitude: amplitude * abs(transform.a),
                waves: waves,
                phase: phase
            )
        }
    }

    private func selectors(of part: PiboCharacterData.Idle.Part) -> [String] {
        let raw = part.selectorAll ?? part.selector ?? ""
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
