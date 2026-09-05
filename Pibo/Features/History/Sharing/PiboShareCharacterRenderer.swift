import SpriteKit
import UIKit

@MainActor
enum PiboShareCharacterRenderer {
    static func image(stateID: String, side: CGFloat = 600) -> UIImage? {
        guard let data = PiboCharacterData.shared,
              let character = PiboVectorCharacter(stateID: stateID, data: data) else { return nil }
        let scene = SKScene(size: CGSize(width: side, height: side))
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        character.setState(stateID)
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
