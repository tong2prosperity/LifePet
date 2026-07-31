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
    private struct RandomBlinkSchedule {
        var nextStart: TimeInterval
        var activeStart: TimeInterval?
    }
    private var randomBlinks: [String: RandomBlinkSchedule] = [:]

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
            randomBlinks.removeAll()
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
        guard let cycle = part.gateCycle, cycle > 0 else {
            return 1
        }
        let offset = part.gateOffset ?? 0
        var phase = (elapsed / cycle + offset).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }

        let ranges = part.gateRanges ?? part.gateRange.map { [$0] } ?? []
        guard !ranges.isEmpty else { return 1 }
        return ranges.map { gateValue(phase: phase, range: $0, fade: part.gateFade ?? 0) }.max() ?? 0
    }

    private func gateValue(phase: Double, range: [Double], fade requestedFade: Double) -> CGFloat {
        guard range.count == 2 else { return 0 }
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

        let fade = min(requestedFade, span / 2)
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
        case "sigh-sequence":
            applySigh(part, character: character, elapsed: elapsed, strength: amplitude)
        case "bring-to-front":
            for selector in selectors(of: part) {
                character.node(forSelector: selector, stateID: stateID)?.zPosition = 100
            }
        case "shake":
            let x = sin(wave(part, elapsed: elapsed) * 2 * .pi * 5)
                * (part.amplitude ?? 1.2) * Double(strength)
            character.setBodyOffset(x: CGFloat(x), y: 0)
        case "bob":
            let y = sin(wave(part, elapsed: elapsed) * 2 * .pi)
                * (part.amplitude ?? 3) * Double(strength)
            character.setBodyOffset(x: 0, y: CGFloat(y))
        case "sway":
            let angle = sin(wave(part, elapsed: elapsed) * 2 * .pi)
                * (part.amplitude ?? 1.5) * Double(strength) * .pi / 180
            character.setBodyRotation(CGFloat(angle))
        case "pop-loop":
            applyPopLoop(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "bubble-breathe":
            applyBubble(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "wink-morph":
            applyWink(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        default:
            break
        }
    }

    private func applySigh(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let swell = part.swellDuration ?? 1.4
        let flatten = part.flattenDuration ?? 1
        let recover = part.recoverDuration ?? 2.6
        let pause = part.pauseDuration ?? 2.5
        let cycle = swell + flatten + recover + pause
        guard cycle > 0 else { return }
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let x: Double
        let y: Double
        if t < swell {
            let u = smoothstep(t / swell)
            x = 1 + (part.swellX ?? 0.016) * u
            y = 1 + (part.swellY ?? 0.04) * u
        } else if t < swell + flatten {
            let u = smoothstep((t - swell) / flatten)
            x = 1 + lerp(part.swellX ?? 0.016, -(part.flattenX ?? 0.028), u)
            y = 1 + lerp(part.swellY ?? 0.04, -(part.flattenY ?? 0.06), u)
        } else if t < swell + flatten + recover {
            let u = smoothstep((t - swell - flatten) / recover)
            x = 1 + lerp(-(part.flattenX ?? 0.028), 0, u)
            y = 1 + lerp(-(part.flattenY ?? 0.06), 0, u)
        } else {
            x = 1; y = 1
        }
        character.setBreath(
            x: 1 + (CGFloat(x) - 1) * strength,
            y: 1 + (CGFloat(y) - 1) * strength
        )
    }

    private func applyPopLoop(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let selectors = selectors(of: part)
        let cycle = part.cycleDuration ?? 4.6
        guard cycle > 0 else { return }
        for (index, selector) in selectors.enumerated() {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            var phase = elapsed / cycle + Double(index) * (part.phaseStep ?? 0.18)
            phase = phase.truncatingRemainder(dividingBy: 1)
            if phase < 0 { phase += 1 }
            let visible = part.visibilityFraction ?? 0.3
            let fade = part.fadeFraction ?? 0.14
            let range = part.scaleRange ?? [0.76, 1.04]
            let rotations = part.rotateRange ?? [0, 0]
            let translations = part.translateRange ?? [[0, 0], [0, 0]]
            let fromTranslation = translations.first ?? [0, 0]
            let toTranslation = translations.last ?? [0, 0]
            let visibleEnd = fade + visible
            let fadeOutEnd = visibleEnd + fade

            let alpha: Double
            let scale: Double
            let rotation: Double
            let translation: CGPoint
            if phase < fade, fade > 0 {
                let u = phase / fade
                alpha = u
                scale = lerp(range.first ?? 1, range.last ?? 1, smoothBack(u))
                rotation = rotations.first ?? 0
                translation = CGPoint(x: CGFloat(fromTranslation.first ?? 0),
                                      y: CGFloat(fromTranslation.count > 1 ? fromTranslation[1] : 0))
            } else if phase < visibleEnd, visible > 0 {
                let u = (phase - fade) / visible
                alpha = 1
                scale = range.last ?? 1
                rotation = lerp(rotations.first ?? 0, rotations.last ?? 0, u)
                translation = CGPoint(
                    x: CGFloat(lerp(fromTranslation.first ?? 0, toTranslation.first ?? 0, u)),
                    y: CGFloat(lerp(fromTranslation.count > 1 ? fromTranslation[1] : 0,
                                    toTranslation.count > 1 ? toTranslation[1] : 0, u))
                )
            } else if phase < fadeOutEnd, fade > 0 {
                let u = (phase - visibleEnd) / fade
                alpha = 1 - u
                scale = lerp(range.last ?? 1, range.first ?? 1, u)
                rotation = rotations.last ?? 0
                translation = CGPoint(x: CGFloat(toTranslation.first ?? 0),
                                      y: CGFloat(toTranslation.count > 1 ? toTranslation[1] : 0))
            } else {
                node.alpha = 0
                continue
            }
            node.alpha = CGFloat(max(0, alpha)) * strength
            character.setSparkleTransform(
                offset: translation,
                rotationDegrees: CGFloat(rotation),
                scale: CGFloat(scale),
                selector: selector,
                for: node
            )
        }
    }

    private func applyBubble(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let phase = (sin(wave(part, elapsed: elapsed) * 2 * .pi - .pi / 2) + 1) / 2
        let scale = lerp(part.minScale ?? 0.72, part.maxScale ?? 1.55, phase)
        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            character.setUniformScale(
                1 + (CGFloat(scale) - 1) * strength,
                pivot: part.pivot,
                selector: selector,
                for: node
            )
        }
    }

    private func applyWink(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        guard strength > 0.5, let openPath = part.openPath,
              let cycle = part.gateCycle, cycle > 0,
              let range = part.gateRange, range.count == 2 else { return }
        var phase = (elapsed / cycle).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let start = range[0], end = range[1]
        let isActive = phase >= start && phase <= end
        let u = isActive ? (phase - start) / max(0.0001, end - start) : 0
        let closeEnd = part.closeFraction ?? 0.18
        let holdUntil = part.holdUntil ?? 0.74
        let morph: Double
        if !isActive { morph = 0 }
        else if u < closeEnd { morph = easeInOutSine(u / max(0.0001, closeEnd)) }
        else if u <= holdUntil { morph = 1 }
        else { morph = 1 - easeInOutSine((u - holdUntil) / max(0.0001, 1 - holdUntil)) }

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID),
                  let closedPath = character.basePath(forSelector: selector, stateID: stateID),
                  let parsedOpen = PiboCharacterGeometry.path(
                    svgPathData: openPath,
                    transform: character.transform(forSelector: selector)
                  ) else { continue }
            // The source preview uses topology-normalising path morphing. Native
            // CoreGraphics has no equivalent, so cross at the fully closed eye:
            // circle squashes out, the authored wink triangle grows in, and the
            // reverse happens on reopen. There is no discontinuous path swap.
            let usesClosed = morph >= 0.5
            node.path = usesClosed ? closedPath : parsedOpen
            let visibleScale = max(0.05, usesClosed ? (morph - 0.5) * 2 : 1 - morph * 2)
            character.setVerticalSquash(
                CGFloat(visibleScale),
                originY: nil,
                for: node,
                selector: selector
            )
        }
    }

    private func easeInOutSine(_ value: Double) -> Double {
        -(cos(.pi * min(max(value, 0), 1)) - 1) / 2
    }

    private func smoothBack(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private func smoothstep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

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
        let blink = part.blinkDuration ?? 0.16
        guard blink > 0 else { return }
        let squash: CGFloat
        if part.randomize == true {
            let minimumPeriod = part.minPeriod ?? 5
            let maximumPeriod = max(minimumPeriod, part.maxPeriod ?? 8.5)
            let key = stateID + ":" + selectors(of: part).joined(separator: ",")
            var schedule = randomBlinks[key] ?? RandomBlinkSchedule(
                nextStart: elapsed + Double.random(in: minimumPeriod...maximumPeriod),
                activeStart: nil
            )
            if schedule.activeStart == nil, elapsed >= schedule.nextStart {
                schedule.activeStart = elapsed
            }
            if let start = schedule.activeStart, elapsed - start <= blink {
                let u = max(0, elapsed - start) / blink
                let minimum = CGFloat(part.minScale ?? 0)
                squash = 1 - CGFloat(sin(u * .pi)) * (1 - minimum) * strength
            } else {
                if schedule.activeStart != nil {
                    schedule.activeStart = nil
                    schedule.nextStart = elapsed + Double.random(in: minimumPeriod...maximumPeriod)
                }
                squash = 1
            }
            randomBlinks[key] = schedule
        } else {
            let period = part.period ?? 4
            guard period > 0, blink > 0 else { return }
            let at = part.at ?? 1
            let windowStart = period * at - blink
            let phase = elapsed.truncatingRemainder(dividingBy: period)
            let isBlinking = phase > windowStart && phase <= windowStart + blink
            let u = isBlinking ? (phase - windowStart) / blink : 0
            let minimum = CGFloat(part.minScale ?? 0)
            squash = isBlinking
                ? 1 - CGFloat(sin(u * .pi)) * (1 - minimum) * strength
                : 1
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
                phase: phase,
                controlsOnly: part.controlsOnly == true
            )
        }
    }

    private func selectors(of part: PiboCharacterData.Idle.Part) -> [String] {
        let raw = part.selectorAll ?? part.selector ?? ""
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
