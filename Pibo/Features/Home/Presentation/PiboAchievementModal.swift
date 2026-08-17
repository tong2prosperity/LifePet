import AVFoundation
import SpriteKit
import SwiftUI

struct PiboAchievementModal: View {
    let payload: PiboAnimationAchievementPayload
    let onConfirm: () -> Void

    @State private var showCharacter = false

    private static let convergenceDuration = Duration.milliseconds(1_220)

    private var copy: String {
        switch PiboCoreAnimationAdapter.achievementContentID(kind: payload.kind, modal: true) {
        case "animation.pigu.modal": AppLocalization.text("你动起来以后，我这里也有了变化。")
        case "animation.muscle.modal": AppLocalization.text("走了这么远，我也想试试这个姿势。")
        default: ""
        }
    }

    var body: some View {
        VStack(spacing: LP.Spacing.l) {
            ZStack {
                if showCharacter {
                    PiboAchievementCharacterView(stateID: payload.stateID)
                } else {
                    PiboWhiteConvergenceView()
                }
            }
            .frame(height: 300)
            .accessibilityHidden(true)

            VStack(spacing: LP.Spacing.s) {
                Text(copy)
                    .lpText(LP.Typography.uiH3)
                    .foregroundStyle(LP.Content.primary)
                    .multilineTextAlignment(.center)

                if let duration = payload.workoutDurationMinutes,
                   let label = payload.workoutLabel {
                    Text(AppLocalization.format("%@ · %d 分钟", label, duration))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.secondary)
                } else {
                    Text(AppLocalization.text("今天 8,000 步"))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.secondary)
                }
            }

            LPButton(variant: .primary, action: onConfirm) {
                Text(AppLocalization.text("确定"))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("pibo.animation.achievement.confirm")
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.vertical, LP.Spacing.l)
        .presentationDetents([.large])
        .presentationBackground {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xDFF7ED), location: 0),
                    .init(color: Color(hex: 0xEEF8D8), location: 0.52),
                    .init(color: Color(hex: 0xFFF4CD), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .presentationDragIndicator(.hidden)
        .task(id: payload.id) {
            showCharacter = false
            try? await Task.sleep(for: Self.convergenceDuration)
            guard !Task.isCancelled else { return }
            // The source prototype performs a true hard cut here. The target's
            // own authored intro supplies the Q 弹; a crossfade or extra scale
            // produces a different switch and was explicitly rejected.
            showCharacter = true
        }
    }
}

/// Temporary native renderer for the authored 170–250 convergence timing. It
/// keeps the App dependency-free; the versioned HEVC-alpha derivative can take
/// over this seam without changing the Modal lifecycle.
private struct PiboWhiteConvergenceView: View {
    @State private var scale: CGFloat = 1.45
    @State private var opacity = 0.82

    var body: some View {
        if let url = Bundle.main.url(
            forResource: "pibo-white-converge-hevc-alpha",
            withExtension: "mov",
            subdirectory: "Character"
        ) ?? Bundle.main.url(forResource: "pibo-white-converge-hevc-alpha", withExtension: "mov") {
            PiboAlphaVideoView(url: url, playbackRate: 1.35 / 1.22)
                .scaleEffect(scale)
                .opacity(opacity)
                .task {
                    // Exact outer Lottie-host timeline from pibo_context. The
                    // MOV contains the authored 170–250 frames; this supplies
                    // the separate convergence zoom/fade used by the prototype.
                    withAnimation(.timingCurve(0.22, 0.58, 0.25, 1, duration: 1.22 * 0.46)) {
                        scale = 1.78
                        opacity = 0.96
                    }
                    try? await Task.sleep(for: .seconds(1.22 * 0.46))
                    guard !Task.isCancelled else { return }
                    withAnimation(.timingCurve(0.18, 0.72, 0.22, 1, duration: 1.22 * 0.42)) {
                        scale = 3.08
                        opacity = 0.98
                    }
                    try? await Task.sleep(for: .seconds(1.22 * 0.42))
                    guard !Task.isCancelled else { return }
                    withAnimation(.timingCurve(0.22, 0.76, 0.18, 1, duration: 1.22 * 0.12)) {
                        scale = 3.2
                        opacity = 0
                    }
                }
        }
    }
}

private struct PiboAlphaVideoView: UIViewRepresentable {
    let url: URL
    let playbackRate: Float

    func makeUIView(context: Context) -> AlphaPlayerView {
        let view = AlphaPlayerView()
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        player.playImmediately(atRate: playbackRate)
        return view
    }

    func updateUIView(_ view: AlphaPlayerView, context: Context) {}

    static func dismantleUIView(_ view: AlphaPlayerView, coordinator: Void) {
        view.playerLayer.player?.pause()
        view.playerLayer.player = nil
    }
}

private final class AlphaPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { nil }
}

private struct PiboAchievementCharacterView: UIViewRepresentable {
    let stateID: String

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.presentScene(PiboAchievementCharacterScene(stateID: stateID))
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {}
}

@MainActor
private final class PiboAchievementCharacterScene: SKScene {
    private let stateID: String
    private var character: PiboVectorCharacter?
    private var animator: PiboIdleAnimator?
    private var intro: PiboStateTransition?
    private var previousUpdateTime: TimeInterval?

    init(stateID: String) {
        self.stateID = stateID
        super.init(size: CGSize(width: 300, height: 300))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        guard let data = PiboCharacterData.shared,
              let character = PiboVectorCharacter(stateID: stateID, data: data) else { return }
        self.character = character
        let animator = PiboIdleAnimator(data: data)
        self.animator = animator
        let intro = PiboStateTransition(data: data, stateID: stateID)
        intro.onIntroFinished = { [weak animator] in animator?.restartTimeline() }
        self.intro = intro
        addChild(character.rootNode)
        // Achievement art is authored on a 300×300 Figma frame. Keep that
        // frame's original scale and registration in the Modal: `fit(...)` is
        // for placing Pibo on a world surface and replaces `rootNode.position`,
        // which would move these poses out of the Modal's centered artboard.
        character.setState(stateID)
        layoutCharacter()
        intro.startAuthoredIntro()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCharacter()
    }

    private func layoutCharacter() {
        character?.rootNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func update(_ currentTime: TimeInterval) {
        guard let character, let intro else { return }
        let delta = previousUpdateTime.map { max(0, currentTime - $0) } ?? 0
        previousUpdateTime = currentTime
        intro.update(deltaTime: delta)
        character.setSettleScale(intro.introScale)
        character.setGlow(colorHex: intro.introGlowColor, intensity: intro.introGlow)
        character.resetIdleTransforms()
        if !intro.suppressesIdle {
            animator?.apply(
                idle: PiboCharacterData.shared?.states[stateID]?.idle,
                stateID: stateID,
                character: character,
                time: currentTime,
                amplitude: 1
            )
        }
    }
}
