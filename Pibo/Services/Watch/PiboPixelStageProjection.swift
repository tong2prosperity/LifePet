import Observation

/// Updated by the day's controller, never from per-frame rendering.
@MainActor @Observable
final class PiboPixelStageProjection {
    static let shared = PiboPixelStageProjection()
    private(set) var form = 0
    private(set) var stuck = false

    func update(form: Int, stuck: Bool) {
        if self.form != form { self.form = form }
        if self.stuck != stuck { self.stuck = stuck }
    }
}
