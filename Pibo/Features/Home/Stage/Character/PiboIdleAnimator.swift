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
    private let designFrame: CGSize

    private var timelineStart: TimeInterval?
    private var activeStateID: String?
    private struct RandomBlinkSchedule {
        var nextStart: TimeInterval
        var activeStart: TimeInterval?
    }
    private var randomBlinks: [String: RandomBlinkSchedule] = [:]

    init(data: PiboCharacterData) {
        pathPrimitiveMinAmplitude = CGFloat(data.idleBlend.pathPrimitiveMinAmplitude)
        designFrame = CGSize(width: data.designFrame.width, height: data.designFrame.height)
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
        return ranges.map { gateValue(phase: phase, range: $0, fade: part.gateFade ?? 0.05) }.max() ?? 0
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
        return CGFloat(easeInOut(min(rise, fall)))
    }

    /// A gate window that a primitive traverses itself, rather than being
    /// enveloped by. `path-bulge` and `pulse-scale` run one damped oscillation
    /// across the whole window, so they need its local progress, not its
    /// amplitude — driving them from a free-running period instead makes pigu's
    /// 屁股 duang·duang a continuous jiggle at the wrong rate.
    private func gateSpan(
        _ part: PiboCharacterData.Idle.Part,
        elapsed: TimeInterval,
        fallbackPeriod: Double
    ) -> Double? {
        guard let cycle = part.gateCycle, cycle > 0,
              let range = part.gateRange, range.count == 2 else {
            let period = part.duration ?? part.period ?? fallbackPeriod
            guard period > 0 else { return nil }
            return elapsed.truncatingRemainder(dividingBy: period) / period
        }
        var phase = (elapsed / cycle + (part.gateOffset ?? 0)).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        guard phase >= range[0], phase <= range[1], range[1] > range[0] else { return nil }
        return (phase - range[0]) / (range[1] - range[0])
    }

    /// `"165px 292px"` / `"50% 100%"` → a point in design coordinates.
    private func origin(_ raw: String?) -> CGPoint? {
        guard let raw else { return nil }
        let tokens = raw.split(separator: " ").map(String.init)
        guard tokens.count == 2 else { return nil }
        func value(_ token: String, span: CGFloat) -> CGFloat? {
            if token.hasSuffix("%") {
                return Double(token.dropLast()).map { CGFloat($0) / 100 * span }
            }
            if token.hasSuffix("px") {
                return Double(token.dropLast(2)).map { CGFloat($0) }
            }
            return Double(token).map { CGFloat($0) }
        }
        guard let x = value(tokens[0], span: designFrame.width),
              let y = value(tokens[1], span: designFrame.height) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Authored degrees → SpriteKit radians.
    ///
    /// The design frame is Y-down and `PiboCharacterGeometry.designTransform`
    /// flips it, so the same numeric angle that reads clockwise in the source
    /// SVG reads counter-clockwise once the geometry is in scene space. Every
    /// authored angle therefore changes sign on the way in. It matters most
    /// where the motion is one-directional — `unipolar`, `hold`, the ✨'s
    /// `rotate` — because a symmetric swing only shifts by half a period.
    private func radians(designDegrees: Double) -> CGFloat {
        CGFloat(-designDegrees * .pi / 180)
    }

    private func easeInOut(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    /// Phase within a part's own oscillation.
    private func wave(
        _ part: PiboCharacterData.Idle.Part,
        elapsed: TimeInterval,
        defaultPeriod: Double = 1
    ) -> Double {
        let period = part.duration ?? part.period ?? defaultPeriod
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
            applyRotate(
                part,
                stateID: stateID,
                character: character,
                elapsed: elapsed,
                gate: gateValue,
                amplitude: amplitude
            )
        case "blink":
            applyBlink(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "waggle-sequence":
            applyWaggle(part, character: character, elapsed: elapsed, strength: strength)
        case "pulse-scale":
            applyPulseScale(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "sparkle-fly":
            applySparkle(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
        case "path-bulge":
            guard amplitude > pathPrimitiveMinAmplitude else { break }
            applyPathBulge(part, stateID: stateID, character: character, elapsed: elapsed, strength: amplitude)
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
            // A rotation about the authored pivot, not a horizontal slide: angry
            // trembles in place on its feet.
            let degrees = (part.amplitude ?? 1)
                * sin(wave(part, elapsed: elapsed, defaultPeriod: 0.3) * 2 * .pi)
                * Double(strength)
            character.setBodyTransform(.init(
                rotation: radians(designDegrees: degrees),
                origin: origin(part.origin)
            ))
        case "bob":
            // Half wave: the float only ever rises off the resting waterline.
            let lift = (part.amplitude ?? 3)
                * (0.5 + 0.5 * sin(wave(part, elapsed: elapsed, defaultPeriod: 1) * 2 * .pi))
                * Double(strength)
            character.setBodyTransform(.init(
                offset: CGPoint(x: 0, y: CGFloat(-lift)),
                origin: origin(part.origin)
            ))
        case "sway":
            let degrees = (part.amplitude ?? 2)
                * sin(wave(part, elapsed: elapsed, defaultPeriod: 1.5) * 2 * .pi)
                * Double(strength)
            character.setBodyTransform(.init(
                rotation: radians(designDegrees: degrees),
                origin: origin(part.origin)
            ))
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
        let swellX = part.swellX ?? 0.01
        let flattenX = part.flattenX ?? 0.018
        let swellY = part.swellY ?? 0.028
        let flattenY = part.flattenY ?? 0.042
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        var x = 1.0
        var y = 1.0
        if t < swell {
            // Volume-preserving: the silhouette narrows as it rises.
            let u = easeInOutSine(t / swell)
            x = 1 - swellX * u
            y = 1 + swellY * u
        } else if t < swell + flatten {
            let u = easeInOutSine((t - swell) / flatten)
            x = lerp(1 - swellX, 1 + flattenX, u)
            y = lerp(1 + swellY, 1 - flattenY, u)
        } else if t < swell + flatten + recover {
            let u = easeInOutSine((t - swell - flatten) / recover)
            x = lerp(1 + flattenX, 1, u)
            y = lerp(1 - flattenY, 1, u)
        }
        character.setBodyTransform(.init(
            scaleX: 1 + (CGFloat(x) - 1) * strength,
            scaleY: 1 + (CGFloat(y) - 1) * strength,
            origin: origin(part.origin)
        ))
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
                rotation: radians(designDegrees: rotation),
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
        let swell: Double
        if verticalOnly {
            // Symmetric wave — always either expanding or contracting, so there
            // is no implicit pause at the baseline.
            swell = (part.amplitude ?? 0.018)
                * sin(wave(part, elapsed: elapsed, defaultPeriod: 3.5) * 2 * .pi)
        } else {
            // Half wave: `breathe` only ever swells outward from the rest shape.
            swell = (part.amplitude ?? 0.02)
                * (0.5 + 0.5 * sin(wave(part, elapsed: elapsed, defaultPeriod: 2) * 2 * .pi))
        }
        let scale = 1 + CGFloat(swell) * strength
        character.setBodyTransform(.init(
            scaleX: verticalOnly ? 1 : scale,
            scaleY: scale,
            origin: origin(part.origin)
        ))
    }

    /// Breathing and the intermittent hop have to be one primitive: both write
    /// the root transform, and two independent writers would fight.
    private func applyBreatheHop(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        // Vertical only, like the `breathe-y` it is built from.
        let swell = CGFloat(sin(wave(part, elapsed: elapsed, defaultPeriod: 3.2) * 2 * .pi))
            * CGFloat(part.amplitude ?? 0.03) * strength

        let hopPeriod = part.hopPeriod ?? 7
        let hopDuration = part.hopDuration ?? 0.8
        var lift = 0.0
        if hopPeriod > 0, hopDuration > 0 {
            // The hop lands at the END of the period — the long stretch of plain
            // breathing comes first, then "跳一跳".
            let phase = elapsed.truncatingRemainder(dividingBy: hopPeriod)
            if phase > hopPeriod - hopDuration {
                let u = (phase - (hopPeriod - hopDuration)) / hopDuration
                let bounces = max(1, part.hopBounces ?? 2)
                let index = floor(u * bounces)
                let local = u * bounces - index
                // The second bounce is visibly lower, then it lands back into
                // the breath seamlessly.
                let height = (part.hopHeight ?? 8) * (index == 0 ? 1 : 0.55)
                lift = height * sin(local * .pi) * Double(strength)
            }
        }

        character.setBodyTransform(.init(
            scaleY: 1 + swell,
            offset: CGPoint(x: 0, y: CGFloat(-lift)),
            origin: origin(part.origin)
        ))
    }

    private func applyWaggle(
        _ part: PiboCharacterData.Idle.Part,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let cycle = part.cycleDuration ?? part.duration ?? 2.4
        // Deliberately small: a large whole-body swing throws the extremities
        // around and drowns out whichever local move is the point of the combo.
        let extent = part.amplitude ?? 3
        let rest = part.restFraction ?? 0.25
        let motion = 1 - rest
        guard cycle > 0, motion > 0 else {
            character.setBodyTransform(.init(origin: origin(part.origin)))
            return
        }
        // Ramp / hold / ramp / hold / ramp = 4 / 0.4 / 4 / 0.4 / 4 of the motion
        // budget: the body sweeps continuously and only kisses each extreme,
        // rather than slamming and freezing.
        let unit = motion / 12.8
        let rampLeftEnd = 4 * unit
        let holdLeftEnd = rampLeftEnd + 0.4 * unit
        let rampToRightEnd = holdLeftEnd + 4 * unit
        let holdRightEnd = rampToRightEnd + 0.4 * unit
        let phase = elapsed.truncatingRemainder(dividingBy: cycle) / cycle

        let degrees: Double
        if phase < rampLeftEnd {
            degrees = -extent * easeInOutSine(phase / rampLeftEnd)
        } else if phase < holdLeftEnd {
            degrees = -extent
        } else if phase < rampToRightEnd {
            degrees = -extent + 2 * extent
                * easeInOutSine((phase - holdLeftEnd) / (rampToRightEnd - holdLeftEnd))
        } else if phase < holdRightEnd {
            degrees = extent
        } else if phase < motion {
            degrees = extent
                * (1 - easeInOutSine((phase - holdRightEnd) / (motion - holdRightEnd)))
        } else {
            degrees = 0
        }

        character.setBodyTransform(.init(
            rotation: radians(designDegrees: degrees * Double(strength)),
            origin: origin(part.origin)
        ))
    }

    // MARK: - Element primitives

    private func applyRotate(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        gate: CGFloat,
        amplitude: CGFloat
    ) {
        let swing: Double
        if part.hold == true {
            // Lift, stay, lower — not an oscillation. "From standing to a cheeky
            // raised foot", which reads as a pose rather than a wag; the gate's
            // own fade supplies the rise and the fall.
            swing = -1
        } else if part.unipolar == true {
            // One direction only: no half-cycle pressing back the other way.
            swing = -abs(sin(wave(part, elapsed: elapsed) * 2 * .pi))
        } else {
            swing = sin(wave(part, elapsed: elapsed) * 2 * .pi)
        }
        // The source also supports a scalar `bias` here (a constant offset that
        // parks a limb away from its rest pose). Our decoded `bias` is the
        // path-bulge vector form, and no authored rotate part uses it, so it is
        // deliberately not wired rather than half-wired.
        let degrees = (part.amplitude ?? 8) * Double(gate) * swing * Double(amplitude)
        let angle = radians(designDegrees: degrees)

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

    private func applyBlink(
        _ part: PiboCharacterData.Idle.Part,
        stateID: String,
        character: PiboVectorCharacter,
        elapsed: TimeInterval,
        strength: CGFloat
    ) {
        let blink = part.blinkDuration ?? 0.16
        guard blink > 0 else { return }
        // Never fully closed: a lid squashed to zero disappears instead of
        // reading as a blink.
        let minimum = CGFloat(part.minScale ?? 0.1)
        let squash: CGFloat
        if part.randomize == true {
            let minimumPeriod = part.minPeriod ?? 2.6
            let maximumPeriod = max(minimumPeriod, part.maxPeriod ?? 5.8)
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
            let period = part.period ?? 3.5
            guard period > 0, blink > 0 else { return }
            let at = part.at ?? 1
            let windowStart = period * at - blink
            let phase = elapsed.truncatingRemainder(dividingBy: period)
            let isBlinking = phase > windowStart && phase <= windowStart + blink
            let u = isBlinking ? (phase - windowStart) / blink : 0
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
        // One damped oscillation across the gate window, not a free-running one
        // that the window merely fades in and out.
        guard let u = gateSpan(part, elapsed: elapsed, fallbackPeriod: 1) else {
            for selector in selectors(of: part) {
                guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
                character.setUniformScale(1, pivot: part.pivot, selector: selector, for: node)
            }
            return
        }
        let damp = part.damp ?? 3.5
        let cycles = part.cycles ?? 1.5
        let value = exp(-damp * u) * sin(cycles * 2 * .pi * u)
        // Clamped: an intro boost can push the amplitude past 1 and a negative
        // scale would flip the element inside out.
        let scale = max(0.05, 1 + CGFloat(value) * CGFloat(part.amplitude ?? 0.1) * strength)

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
        var phase = ((elapsed - offset * cycle) / cycle).truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let span = range[1] - range[0]
        // `gateOffset` aligns the window with the wink. A window that wraps the
        // cycle boundary would otherwise also catch t≈0, flashing a sparkle the
        // moment the state is entered — before any wink has happened.
        let visible = elapsed >= offset * cycle
            && span > 0
            && phase >= range[0]
            && phase <= range[1]
            && strength > 0.5
        guard visible else {
            for selector in selectors(of: part) {
                character.node(forSelector: selector, stateID: stateID)?.alpha = 0
            }
            return
        }
        let u = (phase - range[0]) / span

        // Flies out fast and coasts: travel, spin and the growth phase all ride
        // the same easeOutCubic.
        let eased = 1 - pow(1 - u, 3)

        let scaleFrom = CGFloat(part.scaleFrom ?? 0.2)
        let scalePeak = CGFloat(part.scalePeak ?? 1.15)
        let scaleEnd = CGFloat(part.scaleEnd ?? 0.75)
        let scale = u < 0.35
            ? scaleFrom + (scalePeak - scaleFrom) * CGFloat(1 - pow(1 - u / 0.35, 3))
            : scalePeak + (scaleEnd - scalePeak) * CGFloat((u - 0.35) / 0.65)
        // Quick fade in over the first 18%, fade out over the last 45%.
        let fade: CGFloat = u < 0.18
            ? CGFloat(u / 0.18)
            : (u > 0.55 ? CGFloat(1 - (u - 0.55) / 0.45) : 1)

        for selector in selectors(of: part) {
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            node.alpha = min(max(fade, 0), 1) * strength
            let travel = CGPoint(
                x: CGFloat(part.dx ?? 12) * CGFloat(eased),
                y: CGFloat(part.dy ?? -14) * CGFloat(eased)
            )
            character.setSparkleTransform(
                offset: travel,
                rotation: radians(designDegrees: (part.rotate ?? 80) * eased),
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
        let radius = CGFloat(part.radius ?? 60)
        guard radius > 0 else { return }
        // Same as `pulse-scale`: the damped "duang duang" spans the gate window.
        guard let u = gateSpan(part, elapsed: elapsed, fallbackPeriod: 1) else { return }
        let damp = part.damp ?? 3.2
        let cycles = part.cycles ?? 2
        let envelope = CGFloat(exp(-damp * u) * sin(cycles * 2 * .pi * u))
        let magnitude = envelope * CGFloat(part.amplitude ?? 0.12) * strength
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
