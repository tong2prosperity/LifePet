import CoreGraphics
import Testing
@testable import Pibo

@MainActor
struct PiboBoContainerProgressTests {
    @Test func emptyBoKeepsItsShellAndHidesInjectedContent() throws {
        let character = try #require(PiboVectorCharacter(
            stateID: PiboAnimationStateMap.fallback,
            data: PiboCharacterData.shared
        ))

        character.setBoFillProgress(0)
        let presentation = character.boContainerPresentation

        #expect(presentation.progress == 0)
        #expect(presentation.shellVisible)
        #expect(!presentation.contentVisible)
        #expect(presentation.reveal.height == 0)
    }

    @Test func energyRevealsContentFromTheAuthoredRootTowardTheTip() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 100)
        let root = CGPoint(x: 10, y: 0)
        let tip = CGPoint(x: 10, y: 100)

        #expect(PiboBoContainerProgress.revealPath(
            in: bounds,
            root: root,
            tip: tip,
            progress: 0
        ) == nil)
        let partial = try #require(PiboBoContainerProgress.revealPath(
            in: bounds,
            root: root,
            tip: tip,
            progress: 0.375
        ))
        let full = try #require(PiboBoContainerProgress.revealPath(
            in: bounds,
            root: root,
            tip: tip,
            progress: 1
        ))

        #expect(partial.contains(root))
        #expect(partial.contains(CGPoint(x: 10, y: 35)))
        #expect(!partial.contains(CGPoint(x: 10, y: 45)))
        #expect(full.contains(CGPoint(x: bounds.minX, y: bounds.minY)))
        #expect(full.contains(CGPoint(x: bounds.maxX, y: bounds.maxY)))
    }

    @Test func downwardPoseStillRevealsFromItsRoot() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 100)
        let root = CGPoint(x: 10, y: 100)
        let tip = CGPoint(x: 10, y: 0)
        let partial = try #require(PiboBoContainerProgress.revealPath(
            in: bounds,
            root: root,
            tip: tip,
            progress: 0.25
        ))

        #expect(partial.contains(root))
        #expect(partial.contains(CGPoint(x: 10, y: 76)))
        #expect(!partial.contains(CGPoint(x: 10, y: 70)))
    }

    @Test func authoredRootIsPhysicallyInsidePibosBody() throws {
        let character = try #require(PiboVectorCharacter(
            stateID: PiboAnimationStateMap.fallback,
            data: PiboCharacterData.shared
        ))
        let axis = try #require(character.sproutAxis)
        let body = try #require(character.bodyPath())
        let root = axis.root.applying(character.designToNodeTransform)

        #expect(body.contains(root))
    }

    @Test func everyPoseResolvesAConnectionInsidePibosBody() throws {
        let data = try #require(PiboCharacterData.shared)
        for stateID in data.states.keys.sorted() {
            let character = try #require(PiboVectorCharacter(stateID: stateID, data: data))
            try expectVisibleConnection(character, context: stateID)
        }
    }

    @Test func everyStateTransitionKeepsBoConnectedAtIntermediateFrames() throws {
        let data = try #require(PiboCharacterData.shared)
        let stateIDs = data.states.keys.sorted()
        let checkpoints: [CGFloat] = [0.25, 0.5, 0.75]

        for from in stateIDs {
            for to in stateIDs where to != from {
                let character = try #require(PiboVectorCharacter(stateID: from, data: data))
                for progress in checkpoints {
                    character.setTransition(from: from, to: to, progress: progress)
                    try expectVisibleConnection(
                        character,
                        context: "\(from) → \(to) @ \(progress)"
                    )
                }
            }
        }
    }

    @Test func everyStatesIdleTimelineKeepsBoConnected() throws {
        let data = try #require(PiboCharacterData.shared)
        for stateID in data.states.keys.sorted() {
            let character = try #require(PiboVectorCharacter(stateID: stateID, data: data))
            let animator = PiboIdleAnimator(data: data)
            for frame in 0 ... 120 {
                character.resetIdleTransforms()
                animator.apply(
                    idle: data.states[stateID]?.idle,
                    stateID: stateID,
                    character: character,
                    time: Double(frame) * 0.1,
                    amplitude: 1
                )
                character.syncBoContainerPresentation()
                let intersection = character.boPresentedConnectionIntersections
                #expect(intersection.body, "Idle connector misses Pibo's body in \(stateID) @ \(frame)")
                #expect(intersection.bo, "Idle connector misses bo in \(stateID) @ \(frame)")
            }
        }
    }

    @Test func detachedLeafBaseBridgesToTheNearestBodyBoundary() throws {
        let body = CGPath(ellipseIn: CGRect(x: 0, y: 20, width: 100, height: 80), transform: nil)
        let detached = CGPoint(x: 50, y: 0)
        let attachment = try #require(
            PiboBoContainerProgress.bodyAttachmentPoint(from: detached, in: body)
        )

        #expect(body.contains(attachment))
        #expect(attachment.y > detached.y)
        #expect(attachment.y < 30)
        #expect(PiboBoContainerProgress.bodyAttachmentPoint(
            from: CGPoint(x: 50, y: 50),
            in: body
        ) == CGPoint(x: 50, y: 50))
    }

    @Test func connectorEndpointAlwaysEntersTheActualBoPath() throws {
        let bo = CGPath(ellipseIn: CGRect(x: 20, y: 20, width: 60, height: 80), transform: nil)
        let endpoint = try #require(PiboBoContainerProgress.boInteriorConnectionPoint(
            from: CGPoint(x: 50, y: 0),
            toward: CGPoint(x: 50, y: 100),
            in: bo
        ))

        #expect(bo.contains(endpoint))
        #expect(endpoint.y > 20)
    }

    @Test func fillAnimationUsesPersistedEndpointsAndSupportsReduceMotion() {
        var progress = PiboBoContainerProgress(0.36)
        progress.animate(from: 0.36, to: 0.44, duration: 1.05)

        #expect(progress.displayed == 0.36)
        progress.update(deltaTime: 0.525, reduceMotion: false)
        #expect(abs(progress.displayed - 0.40) < 0.0001)
        progress.update(deltaTime: 0.525, reduceMotion: false)
        #expect(abs(progress.displayed - 0.44) < 0.0001)

        progress.animate(from: 0.44, to: 0.61, duration: 1.05)
        progress.update(deltaTime: 0.01, reduceMotion: true)
        #expect(abs(progress.displayed - 0.61) < 0.0001)
    }

    @Test func invalidProgressCannotCreateContent() {
        #expect(PiboBoContainerProgress.normalized(-1) == 0)
        #expect(PiboBoContainerProgress.normalized(.nan) == 0)
        #expect(PiboBoContainerProgress.normalized(2) == 1)
    }

    private func expectVisibleConnection(
        _ character: PiboVectorCharacter,
        context: String
    ) throws {
        let body = try #require(character.bodyDesignPath)
        let bo = try #require(character.boDesignPath)
        let connection = character.boConnectionDesign

        #expect(body.contains(connection.root), "Disconnected semantic root in \(context)")
        #expect(
            segment(
                from: connection.connectorStart,
                to: connection.connectorEnd,
                intersects: body
            ),
            "Connector misses Pibo's body in \(context)"
        )
        #expect(
            segment(
                from: connection.connectorStart,
                to: connection.connectorEnd,
                intersects: bo
            ),
            "Connector misses bo's leaf body in \(context)"
        )
    }

    private func segment(from start: CGPoint, to end: CGPoint, intersects path: CGPath) -> Bool {
        let samples = 160
        return (0 ... samples).contains { index in
            let progress = CGFloat(index) / CGFloat(samples)
            return path.contains(CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            ))
        }
    }
}
