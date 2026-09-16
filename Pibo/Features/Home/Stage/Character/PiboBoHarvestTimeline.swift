import CoreGraphics
import PiboCore

/// Presentation clock for decision 048's pull-to-collect gesture.
///
/// Core decides the gesture phases (`PiboBoContainer.pullPhase`: touching,
/// ready at 46 pt, release at 76 pt) and the ledger decides whether a unit was
/// really collected. This value type only turns those facts into a pose over
/// time — pull, blink, gaze and the energy flight — so the SpriteKit renderer
/// can stay a thin writer and the timing can be tested without a scene.
struct PiboBoHarvestTimeline: Equatable {
    enum Phase: Equatable {
        case idle
        /// The finger is on the container. `pull` follows it directly.
        case dragging
        /// Released without collecting: the pull springs back.
        case settling
        /// A committed collection is playing out.
        case releasing(elapsed: Double, initialPull: CGFloat)
    }

    enum Event: Equatable {
        /// The energy reached the balance (haptic + receive cue).
        case received
        /// The whole presentation ended; the real pose may resume.
        case finished
    }

    struct DragResult: Equatable {
        let corePhase: Int32
        /// First crossing of the ready threshold during this drag.
        let armed: Bool
        /// Core reported the release threshold for a ripe container.
        let shouldRelease: Bool
    }

    static let releaseDuration: Double = 1.18
    static let reducedReleaseDuration: Double = 0.12
    static let flightDuration: Double = 0.62
    static let recoilDuration: Double = 0.40
    static let settleDuration: Double = 0.36

    private(set) var phase: Phase = .idle
    /// 0...1 normalized pull. Unripe containers cap at 0.26 so a light pull
    /// still answers the finger without suggesting collection.
    private(set) var pull: CGFloat = 0
    private(set) var blink: CGFloat = 1
    private(set) var gaze: CGFloat = 0
    /// 0...1 along the flight curve while visible, otherwise nil.
    private(set) var flightProgress: CGFloat?
    private(set) var flightOpacity: CGFloat = 0
    private var armed = false
    private var receivedFired = false

    var isReleasing: Bool {
        if case .releasing = phase { return true }
        return false
    }

    mutating func beginDrag() {
        guard !isReleasing else { return }
        phase = .dragging
        armed = false
    }

    /// `upward` is the finger's upward travel in points since touch-down.
    mutating func drag(upward: CGFloat, ripe: Bool) -> DragResult {
        guard phase == .dragging else {
            return DragResult(corePhase: 0, armed: false, shouldRelease: false)
        }
        let distance = max(0, upward.isFinite ? upward : 0)
        let corePhase = PiboBoContainer.pullPhase(ripe: ripe ? 1 : 0, distance: Double(distance))
        pull = min(ripe ? 1 : 0.26, distance / 90)
        var newlyArmed = false
        if corePhase >= 2, !armed {
            armed = true
            newlyArmed = true
        }
        return DragResult(corePhase: corePhase, armed: newlyArmed, shouldRelease: corePhase == 3)
    }

    /// A light tap on the container: a small, immediate stretch that springs back.
    mutating func tap() {
        guard !isReleasing else { return }
        pull = max(pull, 0.12)
        phase = .settling
    }

    mutating func cancelDrag() {
        guard !isReleasing else { return }
        armed = false
        phase = pull > 0 ? .settling : .idle
    }

    mutating func beginRelease() {
        guard !isReleasing else { return }
        phase = .releasing(elapsed: 0, initialPull: pull)
        receivedFired = false
        armed = false
    }

    mutating func reset() {
        self = PiboBoHarvestTimeline()
    }

    mutating func advance(deltaTime: Double, reduceMotion: Bool) -> [Event] {
        let dt = max(0, min(deltaTime.isFinite ? deltaTime : 0, 0.1))
        switch phase {
        case .idle, .dragging:
            return []
        case .settling:
            if reduceMotion {
                pull = 0
            } else {
                pull = max(0, pull - CGFloat(dt / Self.settleDuration))
            }
            if pull == 0 { phase = .idle }
            return []
        case .releasing(let elapsed, let initialPull):
            let now = elapsed + dt
            phase = .releasing(elapsed: now, initialPull: initialPull)
            var events: [Event] = []
            let duration = reduceMotion ? Self.reducedReleaseDuration : Self.releaseDuration
            let flight = min(1, now / Self.flightDuration)
            if reduceMotion {
                flightProgress = nil
                flightOpacity = 0
                pull = 0
                blink = 1
                gaze = 0
            } else {
                flightProgress = flight < 1 ? CGFloat(1 - pow(1 - flight, 2)) : nil
                flightOpacity = flight < 0.88 ? 1 : CGFloat(max(0, (1 - flight) / 0.12))
                let recoil = CGFloat(max(0, 1 - now / Self.recoilDuration))
                pull = initialPull * recoil * recoil
                blink = now < 0.09 ? 0.15 : 1
                gaze = now < 0.8 ? 1 : CGFloat(max(0, (Self.releaseDuration - now) / 0.38))
            }
            if !receivedFired, now >= (reduceMotion ? 0 : Self.flightDuration) {
                receivedFired = true
                events.append(.received)
            }
            if now >= duration {
                self = PiboBoHarvestTimeline()
                events.append(.finished)
            }
            return events
        }
    }

    /// Point on the flight's quadratic curve (scene space, Y-up).
    static func flightPoint(start: CGPoint, end: CGPoint, progress u: CGFloat) -> CGPoint {
        let control = CGPoint(x: start.x + 70, y: start.y + 150)
        let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u
        return CGPoint(
            x: a * start.x + b * control.x + c * end.x,
            y: a * start.y + b * control.y + c * end.y
        )
    }
}
