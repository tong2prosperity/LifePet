import CoreGraphics
import SpriteKit
import UIKit

struct ShadowPiboStagePresentation: Equatable {
    var isVisible: Bool
    var stateID: String
    var friendName: String
    var statusText: String
    var manifestSequence: Int
    var lightReceiptSequence: Int

    static let hidden = ShadowPiboStagePresentation(
        isVisible: false,
        stateID: PiboAnimationResourceID.stable,
        friendName: "好友",
        statusText: "",
        manifestSequence: 0,
        lightReceiptSequence: 0
    )
}

/// A second renderer over the same authored state data. It owns no alternate
/// character assets: only the projection material and the secondary placement
/// differ from the local Pibo.
@MainActor
final class PiboShadowRenderer {
    let rootNode = SKNode()

    private let projectionNode = SKNode()
    private let lilyLine = SKShapeNode()
    private let vector: PiboVectorCharacter?
    private let transition: PiboStateTransition?
    private let idle: PiboIdleAnimator?
    private var stateID = PiboAnimationResourceID.stable
    private var lastManifestSequence = 0

    init() {
        guard let data = PiboCharacterData.shared,
              let vector = PiboVectorCharacter(
                  stateID: PiboAnimationResourceID.stable,
                  data: data,
                  projectionStyle: .friendShadow
              ) else {
            self.vector = nil
            transition = nil
            idle = nil
            return
        }
        self.vector = vector
        let transition = PiboStateTransition(data: data, stateID: vector.currentStateID)
        let idle = PiboIdleAnimator(data: data)
        transition.onIntroFinished = { [weak idle] in idle?.restartTimeline() }
        self.transition = transition
        self.idle = idle

        rootNode.zPosition = 21
        projectionNode.alpha = 0.75
        projectionNode.addChild(vector.rootNode)
        rootNode.addChild(lilyLine)
        rootNode.addChild(projectionNode)
        lilyLine.strokeColor = UIColor(red: 35 / 255, green: 190 / 255, blue: 148 / 255, alpha: 1)
        lilyLine.lineWidth = 1.5
        lilyLine.alpha = 0.32
        lilyLine.lineCap = .round
        rootNode.isHidden = true
    }

    func apply(_ presentation: ShadowPiboStagePresentation, reduceMotion: Bool) {
        rootNode.isHidden = !presentation.isVisible
        guard presentation.isVisible, vector != nil else { return }
        if presentation.stateID != stateID {
            stateID = presentation.stateID
            transition?.transition(to: presentation.stateID, playsIntro: false)
        }
        if presentation.manifestSequence > lastManifestSequence {
            lastManifestSequence = presentation.manifestSequence
            playManifest(reduceMotion: reduceMotion)
        }
    }

    func layout(sceneSize: CGSize) {
        guard let vector else { return }
        let mapper = ForestLayoutMapper(sceneSize: sceneSize)
        let artboard = CGRect(x: 240, y: 474, width: 174, height: 174)
        vector.setScale(artboard.width / 300 * mapper.scale)
        vector.rootNode.position = mapper.point(CGPoint(x: artboard.midX, y: artboard.midY))

        let line = CGMutablePath()
        line.move(to: mapper.point(CGPoint(x: 347, y: 442)))
        line.addLine(to: mapper.point(CGPoint(x: 327, y: 546)))
        lilyLine.path = line
        lilyLine.lineWidth = 1.5 * mapper.scale
    }

    func update(time: TimeInterval, deltaTime: TimeInterval, reduceMotion: Bool) {
        guard !rootNode.isHidden, let vector, let transition else { return }
        transition.update(deltaTime: deltaTime)
        vector.setTransition(
            from: transition.fromStateID,
            to: transition.toStateID,
            progress: transition.progress
        )
        vector.setSettleScale(transition.settleScale)
        vector.setPresentationScale(
            x: transition.presentationScaleX,
            y: transition.presentationScaleY
        )
        vector.resetIdleTransforms()
        if !transition.suppressesIdle {
            idle?.apply(
                idle: PiboCharacterData.shared?.states[transition.toStateID]?.idle,
                stateID: transition.toStateID,
                character: vector,
                time: time,
                amplitude: reduceMotion ? 0 : min(0.72, transition.idleAmplitude)
            )
        }
    }

    func contains(_ point: CGPoint, in scene: SKScene) -> Bool {
        guard !rootNode.isHidden, let vector else { return false }
        let local = vector.rootNode.convert(point, from: scene)
        return vector.renderedContentBounds.insetBy(dx: -12, dy: -12).contains(local)
    }

    private func playManifest(reduceMotion: Bool) {
        projectionNode.removeAction(forKey: "shadowManifest")
        lilyLine.removeAction(forKey: "shadowManifest")
        guard !reduceMotion else {
            projectionNode.alpha = 0.75
            projectionNode.setScale(1)
            lilyLine.alpha = 0.32
            return
        }
        projectionNode.alpha = 0
        projectionNode.setScale(0.92)
        lilyLine.alpha = 0
        projectionNode.run(
            .group([
                .fadeAlpha(to: 0.75, duration: 0.52),
                .scale(to: 1, duration: 0.52),
            ]),
            withKey: "shadowManifest"
        )
        lilyLine.run(.fadeAlpha(to: 0.32, duration: 0.52), withKey: "shadowManifest")
    }
}
