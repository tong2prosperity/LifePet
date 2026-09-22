import SpriteKit
import UIKit

@MainActor
enum PiboShareCharacterRenderer {
    /// `boFillProgress` mirrors what Home's stage is showing. Without it the
    /// sprout renders as the empty container shell (决定 048), which reads as a
    /// washed-out bo in an exported card.
    static func image(
        stateID: String,
        boFillProgress: CGFloat,
        side: CGFloat = 600
    ) -> UIImage? {
        guard let data = PiboCharacterData.shared,
              let character = PiboVectorCharacter(stateID: stateID, data: data) else { return nil }
        let scene = SKScene(size: CGSize(width: side, height: side))
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        character.setState(stateID)
        character.setBoFillProgress(boFillProgress)
        character.rootNode.position = CGPoint(x: side / 2, y: side / 2)
        character.rootNode.setScale(side / 300)
        scene.addChild(character.rootNode)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.allowsTransparency = true
        view.presentScene(scene)
        guard let texture = view.texture(from: scene) else { return nil }
        return UIImage(cgImage: texture.cgImage())
    }
}
