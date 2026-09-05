/// Physical input acceptance only. Core owns the reaction selected afterward.
nonisolated enum PiboPatGesturePolicy {
    static let requiredTapCount = 2

    static func accepts(tapCount: Int) -> Bool { tapCount == requiredTapCount }
}
