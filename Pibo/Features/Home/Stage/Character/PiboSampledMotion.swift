import CoreGraphics
import Foundation
import SpriteKit
import UIKit

/// Authored presentation samples from pibo-media. Channel order is the media
/// contract: x/y, sx/sy, angle, faceX/Y, eye, arms L/R, sprout, shadow.
struct PiboSampledClip: Decodable {
    let duration: Double
    let fps: Double
    let samples: [[CGFloat]]

    func pose(at seconds: Double) -> [CGFloat] {
        guard !samples.isEmpty else { return [] }
        let frame = max(0, min(Double(samples.count - 1), seconds * fps))
        let index = Int(frame)
        let a = samples[index], b = samples[min(index + 1, samples.count - 1)]
        guard a.count == 12, b.count == 12 else { return [] }
        return zip(a, b).map { $0 + ($1 - $0) * CGFloat(frame - Double(index)) }
    }
}

@MainActor
final class PiboSampledMotionPlayer {
    private var ambient = ""
    private var epoch: Double = 0
    private var patStart: Double?
    private var patRequested = false
    private var previous: [CGFloat] = []
    private var blendFrom: [CGFloat] = []

    func restartPat() { patRequested = true }
    func cancelPat() { patStart = nil; patRequested = false }
    func reset() {
        ambient = ""; epoch = 0; patStart = nil; patRequested = false
        previous = []; blendFrom = []
    }

    func pose(id: String, time: Double, clips: [String: PiboSampledClip], strength: CGFloat) -> [CGFloat] {
        if ambient != id {
            let pending = ambient.isEmpty && patRequested
            reset(); ambient = id; epoch = time; patRequested = pending
        }
        if patRequested, id == "stable", clips["pat"] != nil {
            blendFrom = previous; patStart = time; patRequested = false
        }
        guard var clip = clips[id], clip.duration > 0 else { return [] }
        var elapsed = max(0, time - epoch).truncatingRemainder(dividingBy: clip.duration)
        if let start = patStart, let pat = clips["pat"] {
            if time - start >= pat.duration {
                epoch = start + pat.duration; patStart = nil
                elapsed = max(0, time - epoch).truncatingRemainder(dividingBy: clip.duration)
            } else { clip = pat; elapsed = max(0, time - start) }
        }
        var result = clip.pose(at: elapsed)
        if patStart != nil, blendFrom.count == result.count {
            let u = CGFloat(min(1, elapsed / 0.12)), blend = u * u * (3 - 2 * u)
            result = zip(blendFrom, result).map { $0 + ($1 - $0) * blend }
        }
        previous = result
        return result.enumerated().map { index, value in
            if index == 7 { return value }
            let rest: CGFloat = [2, 3, 11].contains(index) ? 1 : 0
            return rest + (value - rest) * max(0, min(1, strength))
        }
    }

    static func apply(_ p: [CGFloat], to character: PiboVectorCharacter, stateID: String) {
        guard p.count == 12 else { return }
        character.setBodyTransform(.init(
            scaleX: p[2], scaleY: p[3], rotation: -p[4] * .pi / 180,
            offset: CGPoint(x: p[0], y: p[1]), origin: CGPoint(x: 150, y: 282)
        ))
        for name in ["lefteye", "righteye", "leftdot", "rightdot", "nose", "lefthand", "righthand", "bo", "boline", "leftleg", "rightleg"] {
            let selector = ["bo", "boline"].contains(name) ? "#path-\(name)" : "#orphan-\(name)-\(stateID)"
            guard let node = character.node(forSelector: selector, stateID: stateID) else { continue }
            let matrix = character.transform(forSelector: selector)
            let zero = CGPoint.zero.applying(matrix)
            var offset = CGPoint.zero
            if ["lefteye", "righteye", "leftdot", "rightdot", "nose"].contains(name) {
                offset = CGPoint(x: p[5], y: p[6])
                if name == "lefteye" || name == "righteye" {
                    character.setVerticalSquash(p[7], originY: 149.5, for: node, selector: selector)
                }
            }
            var degrees: CGFloat = 0
            var pivot = CGPoint.zero
            if name == "lefthand" { degrees = p[8]; pivot = CGPoint(x: 118.4, y: 169.7) }
            if name == "righthand" { degrees = p[9]; pivot = CGPoint(x: 197.8, y: 169.8) }
            if name == "bo" || name == "boline" { degrees = p[10]; pivot = CGPoint(x: 152, y: 95) }
            if ["lefthand", "righthand", "bo", "boline"].contains(name) {
                character.setRotation(-degrees * .pi / 180, about: pivot.applying(matrix), for: node)
            }
            if name == "leftleg" { offset.x = (132 - 150) * (1 / p[2] - 1) }
            if name == "rightleg" { offset.x = (158 - 150) * (1 / p[2] - 1) }
            let translated = offset.applying(matrix)
            node.position.x += translated.x - zero.x
            node.position.y += translated.y - zero.y
        }
    }
}
