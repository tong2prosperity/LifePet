import CoreGraphics
import Foundation

/// Continuous visual fill for the head-top `bo` container.
///
/// Core owns how health evidence becomes energy and how much energy forms one
/// `bo`. This type only maps Core's persisted 0...1 progress onto a root-outward
/// reveal; it deliberately contains no scoring thresholds.
struct PiboBoContainerProgress: Equatable {
    private(set) var displayed: CGFloat
    private(set) var target: CGFloat

    private var start: CGFloat
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0

    init(_ progress: CGFloat = 0) {
        let value = Self.normalized(progress)
        displayed = value
        target = value
        start = value
    }

    mutating func set(_ progress: CGFloat) {
        let value = Self.normalized(progress)
        displayed = value
        target = value
        start = value
        elapsed = 0
        duration = 0
    }

    mutating func animate(from start: CGFloat, to target: CGFloat, duration: TimeInterval) {
        self.start = Self.normalized(start)
        self.target = Self.normalized(target)
        displayed = self.start
        elapsed = 0
        self.duration = max(0, duration)
        if self.duration == 0 { displayed = self.target }
    }

    /// Advances the lab's ease-in-out fill curve. Returns whether the visible
    /// crop changed, allowing the renderer to avoid rebuilding a mask at rest.
    @discardableResult
    mutating func update(deltaTime: TimeInterval, reduceMotion: Bool) -> Bool {
        guard duration > 0, displayed != target else { return false }
        let previous = displayed
        if reduceMotion {
            displayed = target
            duration = 0
            return displayed != previous
        }

        elapsed = min(duration, elapsed + max(0, deltaTime))
        let t = CGFloat(elapsed / duration)
        let eased = t * t * (3 - 2 * t)
        displayed = start + (target - start) * eased
        if elapsed >= duration {
            displayed = target
            duration = 0
        }
        return displayed != previous
    }

    /// Builds a reveal that expands out of the resolved body attachment. A
    /// wide moving half-plane can intersect a curled part of the silhouette
    /// before the visible stem, which reads as growth starting in mid-air. A
    /// root-centred radius guarantees that every revealed pixel is spatially
    /// downstream of the connection, independent of pose or canvas direction.
    static func revealPath(
        in bounds: CGRect,
        root: CGPoint,
        tip: CGPoint,
        progress: CGFloat
    ) -> CGPath? {
        guard !bounds.isNull,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              root.x.isFinite,
              root.y.isFinite,
              tip.x.isFinite,
              tip.y.isFinite
        else { return nil }

        let amount = normalized(progress)
        guard amount > 0 else { return nil }

        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        func distance(to point: CGPoint) -> CGFloat {
            hypot(point.x - root.x, point.y - root.y)
        }
        let fullRadius = max(corners.map(distance(to:)).max() ?? 0, distance(to: tip))
        guard fullRadius > 0.001 else { return CGPath(rect: bounds, transform: nil) }
        let radius = fullRadius * amount
        return CGPath(
            ellipseIn: CGRect(
                x: root.x - radius,
                y: root.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
    }

    /// Resolves the actual body attachment used by the renderer. Most authored
    /// poses already put `root` inside Pibo. A few derived lying/downward poses
    /// leave the leaf base outside the body silhouette; for those, walk toward
    /// the closest interior sample and stop just inside the boundary so the
    /// container has a real, overlap-safe connection instead of floating.
    static func bodyAttachmentPoint(from root: CGPoint, in body: CGPath) -> CGPoint? {
        let bounds = body.boundingBoxOfPath
        guard !bounds.isNull,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              root.x.isFinite,
              root.y.isFinite
        else { return nil }
        if body.contains(root) { return root }

        let divisions = 24
        var nearestInterior: CGPoint?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for row in 0 ... divisions {
            let y = bounds.minY + bounds.height * CGFloat(row) / CGFloat(divisions)
            for column in 0 ... divisions {
                let x = bounds.minX + bounds.width * CGFloat(column) / CGFloat(divisions)
                let candidate = CGPoint(x: x, y: y)
                guard body.contains(candidate) else { continue }
                let distance = hypot(candidate.x - root.x, candidate.y - root.y)
                if distance < nearestDistance {
                    nearestInterior = candidate
                    nearestDistance = distance
                }
            }
        }
        guard let target = nearestInterior else { return nil }

        var outside = root
        var inside = target
        for _ in 0 ..< 18 {
            let midpoint = CGPoint(
                x: (outside.x + inside.x) * 0.5,
                y: (outside.y + inside.y) * 0.5
            )
            if body.contains(midpoint) {
                inside = midpoint
            } else {
                outside = midpoint
            }
        }

        let towardInterior = CGVector(dx: target.x - inside.x, dy: target.y - inside.y)
        let length = hypot(towardInterior.dx, towardInterior.dy)
        guard length > 0.001 else { return inside }
        let inset = min(max(min(bounds.width, bounds.height) * 0.012, 1), length)
        return CGPoint(
            x: inside.x + towardInterior.dx / length * inset,
            y: inside.y + towardInterior.dy / length * inset
        )
    }

    /// Resolves a connector endpoint that is guaranteed to sit inside the
    /// current `bo` silhouette. The authored root is only semantic metadata;
    /// during a morph it may sit beside the curved leaf rather than inside it.
    /// First enter the real path, then move a short distance toward the authored
    /// tip when that candidate remains inside, giving the round connector cap a
    /// stable overlap instead of merely touching an antialiased boundary.
    static func boInteriorConnectionPoint(
        from root: CGPoint,
        toward tip: CGPoint,
        in bo: CGPath,
        overlap: CGFloat = 4
    ) -> CGPoint? {
        let entry: CGPoint?
        if bo.contains(root) {
            entry = root
        } else {
            // The semantic axis normally runs through the leaf. Try that short,
            // cheap route before falling back to the general 2-D body search;
            // this function also runs while the idle path is animated.
            var firstInterior: CGPoint?
            let steps = 48
            for step in 1 ... steps {
                let amount = CGFloat(step) / CGFloat(steps)
                let candidate = CGPoint(
                    x: root.x + (tip.x - root.x) * amount,
                    y: root.y + (tip.y - root.y) * amount
                )
                if bo.contains(candidate) {
                    firstInterior = candidate
                    break
                }
            }
            entry = firstInterior ?? bodyAttachmentPoint(from: root, in: bo)
        }
        guard let entry else { return nil }
        let delta = CGVector(dx: tip.x - entry.x, dy: tip.y - entry.y)
        let length = hypot(delta.dx, delta.dy)
        guard length > 0.001, overlap > 0 else { return entry }

        let distance = min(overlap, length)
        let unit = CGVector(dx: delta.dx / length, dy: delta.dy / length)
        // Search from the desired overlap back toward the known-interior entry.
        // The returned point is therefore always inside even for curled paths.
        for step in stride(from: 16, through: 1, by: -1) {
            let candidateDistance = distance * CGFloat(step) / 16
            let candidate = CGPoint(
                x: entry.x + unit.dx * candidateDistance,
                y: entry.y + unit.dy * candidateDistance
            )
            if bo.contains(candidate) { return candidate }
        }
        return entry
    }

    static func normalized(_ progress: CGFloat) -> CGFloat {
        min(max(progress.isFinite ? progress : 0, 0), 1)
    }
}
