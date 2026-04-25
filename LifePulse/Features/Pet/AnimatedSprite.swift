import SwiftUI

/// Renders a `SpriteSequence` as a frame-by-frame animated `Image`. The frame
/// is recomputed on every TimelineView tick from `t - startedAt`; nothing
/// mutates state from inside the render closure.
///
/// Lifecycle:
/// - `onAppear` and a `sequence` change reset the start time.
/// - `oneShot` sequences schedule a sleep-then-callback Task that fires
///   `onCompleted` exactly once at `totalDuration`. The task is cancelled and
///   replaced on every reset, so rapid sequence flips don't pile up.
struct AnimatedSprite: View {
    let sequence: SpriteSequence
    /// Called once when a `.oneShot` sequence finishes. No-op for `.loop`.
    var onCompleted: (() -> Void)? = nil

    @State private var startedAt: Date = .now
    @State private var finishTask: Task<Void, Never>? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            Image(sequence.assetName(at: currentFrame(at: ctx.date)))
                .interpolation(.none)   // 像素艺术：禁用 anti-alias 缩放
                .resizable()
                .scaledToFit()
        }
        .onAppear { reset() }
        .onChange(of: sequence) { _, _ in reset() }
        .onDisappear { finishTask?.cancel() }
        .accessibilityHidden(true)
    }

    private func currentFrame(at t: Date) -> Int {
        let elapsed = t.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        let raw = Int(elapsed / sequence.frameDuration)
        switch sequence.mode {
        case .loop:    return raw % sequence.frameCount
        case .oneShot: return min(raw, sequence.frameCount - 1)
        }
    }

    private func reset() {
        startedAt = Date()
        finishTask?.cancel()
        guard sequence.mode == .oneShot, let onCompleted else {
            finishTask = nil
            return
        }
        let duration = sequence.totalDuration
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if Task.isCancelled { return }
            onCompleted()
        }
    }
}

#Preview("Egg hatch · oneShot") {
    AnimatedSprite(sequence: .eggHatch)
        .frame(width: 160, height: 160)
        .padding(LP.Spacing.s5)
        .lpPaper(.app)
}

#Preview("Blob run · loop") {
    AnimatedSprite(sequence: .blobRun)
        .frame(width: 160, height: 160)
        .padding(LP.Spacing.s5)
        .lpPaper(.app)
}
