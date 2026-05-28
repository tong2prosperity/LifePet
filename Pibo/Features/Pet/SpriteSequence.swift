import Foundation

/// One animation: a numbered run of frames inside a namespaced asset folder,
/// played at a given fps, looping or one-shot. The actual PNGs live in
/// `Assets.xcassets/sprites/<kind>/frame_NN.imageset`.
struct SpriteSequence: Equatable, Hashable {
    /// Asset path prefix — frames are referenced as
    /// `"\(assetPrefix)/frame_\(NN)"`. Matches the namespace folder layout in
    /// the asset catalog.
    let assetPrefix: String
    let frameCount: Int
    let fps: Double
    let mode: Mode

    enum Mode: Hashable { case loop, oneShot }

    var frameDuration: TimeInterval { 1.0 / fps }
    var totalDuration: TimeInterval { frameDuration * Double(frameCount) }

    /// Asset name for a given frame index (clamped to valid range).
    func assetName(at frame: Int) -> String {
        let clamped = max(0, min(frame, frameCount - 1))
        return "\(assetPrefix)/frame_\(String(format: "%02d", clamped))"
    }
}

// MARK: - Built-in sequences

extension SpriteSequence {
    /// 蛋孵化 — 10 帧，8fps，单次。结束后 `AnimatedSprite.onCompleted` 触发。
    static let eggHatch = SpriteSequence(
        assetPrefix: "sprites/egg_hatch",
        frameCount: 10, fps: 8, mode: .oneShot
    )

    /// 躺平 idle — 6 帧，4fps。`.normal` / `.sick` 复用。
    static let blobLying = SpriteSequence(
        assetPrefix: "sprites/blob_lying",
        frameCount: 6, fps: 4, mode: .loop
    )

    /// 走 — 8 帧，12fps。`.tired` 用。
    static let blobWalk = SpriteSequence(
        assetPrefix: "sprites/blob_walk",
        frameCount: 8, fps: 12, mode: .loop
    )

    /// 跑 — 8 帧，16fps。`.excited` / `.blissful` 用。
    static let blobRun = SpriteSequence(
        assetPrefix: "sprites/blob_run",
        frameCount: 8, fps: 16, mode: .loop
    )

    /// 睡 — 6 帧，6fps。`.sleeping` 用。
    static let blobSleep = SpriteSequence(
        assetPrefix: "sprites/blob_sleep",
        frameCount: 6, fps: 6, mode: .loop
    )
}
