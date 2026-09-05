import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PiboSampledMotionTests {
    @Test func approvedClipsCloseTheirLoopsAndPatReturnsToStable() throws {
        let clips = try #require(PiboCharacterData.load().authoredClips)
        for id in ["stable", "energetic"] {
            let clip = try #require(clips[id])
            #expect(clip.pose(at: 0) == clip.pose(at: clip.duration))
            #expect(clip.samples.allSatisfy { $0.count == 12 && $0.allSatisfy(\.isFinite) })
        }
        let pat = try #require(clips["pat"])
        #expect(pat.duration == 2.8)
        #expect(pat.pose(at: 2.8) == clips["stable"]?.pose(at: 0))
    }

    @Test func repeatedPatStartsAtVisiblePoseAndFinishesAtStableBaseline() throws {
        let clips = try #require(PiboCharacterData.load().authoredClips)
        let player = PiboSampledMotionPlayer()
        _ = player.pose(id: "stable", time: 0, clips: clips, strength: 1)
        let visible = player.pose(id: "stable", time: 3.7, clips: clips, strength: 1)
        player.restartPat()
        #expect(player.pose(id: "stable", time: 3.7, clips: clips, strength: 1) == visible)
        let middle = player.pose(id: "stable", time: 4.2, clips: clips, strength: 1)
        player.restartPat()
        #expect(player.pose(id: "stable", time: 4.2, clips: clips, strength: 1) == middle)
        #expect(player.pose(id: "stable", time: 7, clips: clips, strength: 1) == clips["stable"]?.pose(at: 0))
    }

    @Test func reduceMotionSuppressesSpaceAndStateChangesCancelPat() throws {
        let clips = try #require(PiboCharacterData.load().authoredClips)
        let player = PiboSampledMotionPlayer()
        _ = player.pose(id: "stable", time: 0, clips: clips, strength: 1)
        player.restartPat()
        _ = player.pose(id: "stable", time: 1, clips: clips, strength: 1)
        #expect(player.pose(id: "energetic", time: 1.5, clips: clips, strength: 1) == clips["energetic"]?.pose(at: 0))
        let reduced = player.pose(id: "energetic", time: 3.96, clips: clips, strength: 0)
        #expect(reduced[1] == 0)
        #expect(reduced[2] == 1 && reduced[3] == 1)
        #expect(reduced[8] == 0 && reduced[10] == 0)
    }
}
