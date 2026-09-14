import CoreGraphics
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PiboExpressionTests {
    @Test func everyExpressionHasAnIdleAndBothFoodDirections() throws {
        let library = try PiboExpressionLibrary.load()
        #expect(library.clips.count == 37)
        #expect(Set(library.bindings.keys) == Set(PiboCoreExpression.allCases.map(\.contentID)))
        for profile in library.bindings.keys {
            let idle = try #require(library.clips[profile])
            let first = idle.sample(0), last = idle.sample(idle.duration)
            #expect(first.weights == last.weights)
            for (a, b) in zip(first.transforms.flatMap({ $0 }), last.transforms.flatMap({ $0 })) {
                #expect(abs(a - b) < 0.001)
            }
            for side in ["left", "right"] {
                #expect(library.clips["\(profile).food.\(side)"]?.duration == 6.08)
            }
        }
    }

    @Test func restPersistsAndFoodDoesNotInterruptSettlingOrChangeItsState() throws {
        let library = try PiboExpressionLibrary.load()
        let observing = PiboExpressionPlayer(), ambient = PiboExpressionPlayer()
        for player in [observing, ambient] {
            player.select("tired", time: 0)
            _ = player.sample(library, time: 0.5, reduced: false)
            player.select("tiredResting", time: 1)
        }
        observing.observe(onRight: true, time: 1.2)
        for time in [1.3, 2.1, 4.3, 7.5, 1200] {
            let a = try #require(observing.sample(library, time: time, reduced: false))
            let b = try #require(ambient.sample(library, time: time, reduced: false))
            #expect(a.weights == b.weights)
            #expect(observing.profile == "tiredResting")
            let finite = a.transforms.flatMap { $0 }.allSatisfy { $0.isFinite }
            #expect(finite)
            if time > 8 { #expect(a.transforms == b.transforms) }
        }
        let reduced = try #require(observing.sample(library, time: 1201, reduced: true))
        #expect(reduced.weights == library.clips["tiredResting"]?.rest.weights)
        #expect(reduced.eyes[0] < 1)
    }

    @Test func sleepingIgnoresFoodAndChangingStateCancelsStaleObservation() throws {
        let library = try PiboExpressionLibrary.load()
        let player = PiboExpressionPlayer(), control = PiboExpressionPlayer()
        for p in [player, control] { p.select("sleeping", time: 0) }
        player.observe(onRight: true, time: 0)
        let closed = try #require(player.sample(library, time: 2, reduced: false))
        let rest = try #require(control.sample(library, time: 2, reduced: false))
        #expect(closed.eyes == rest.eyes)
        #expect(closed.weights == rest.weights)
        player.select("tired", time: 2)
        control.select("tired", time: 2)
        #expect(player.sample(library, time: 3, reduced: false)?.transforms == control.sample(library, time: 3, reduced: false)?.transforms)
    }

    @Test func repeatedPatBeginsAtVisiblePoseAndReturnsToAmbient() throws {
        let library = try PiboExpressionLibrary.load()
        let player = PiboExpressionPlayer()
        player.select("stable", time: 0)
        let before = player.sample(library, time: 3.7, reduced: false)
        player.restartPat()
        #expect(player.sample(library, time: 3.7, reduced: false)?.transforms == before?.transforms)
        let middle = player.sample(library, time: 4.2, reduced: false)
        player.restartPat()
        #expect(player.sample(library, time: 4.2, reduced: false)?.transforms == middle?.transforms)
        #expect(player.sample(library, time: 7.1, reduced: false)?.transforms == library.clips["stable"]?.sample(7.1).transforms)
    }

    @Test func fatigueEyesAndMovingGeometryRemainFiniteInNativeRenderer() throws {
        let data = try PiboCharacterData.load()
        let library = try PiboExpressionLibrary.load()
        for profile in ["tired", "tiredResting", "wakingRecovering", "wakingRecoveringGreeted"] {
            let resource = try #require(library.bindings[profile])
            let character = try #require(PiboVectorCharacter(stateID: resource, data: data))
            for step in 0...24 {
                character.resetIdleTransforms()
                #expect(character.updateExpression(stateID: resource, deltaTime: 1.0/60, reduceMotion: false,
                    captureClip: profile, captureTime: Double(step)/2))
                let bounds = character.renderedContentBounds
                #expect(bounds.minX.isFinite && bounds.minY.isFinite && bounds.width > 0 && bounds.width < 310)
                let body = try #require(character.bodyPath())
                #expect(body.boundingBoxOfPath.width > 100)
            }
        }
    }
}
