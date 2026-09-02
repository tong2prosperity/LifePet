import Foundation
import AVFoundation
import HealthKit
import SpriteKit
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PiboAnimationIntegrationTests {
    @Test func shippedCharacterDataCoversAllStatesZonesAndRuntimePrimitives() throws {
        let data = try PiboCharacterData.load()
        let expectedStates: Set<String> = [
            "pibo-state-stable-forest-idle", "pibo-state-waking-hammock-idle", "pibo-state-tired-forest-idle", "boring", "weak", "pibo-event-workout-celebrate",
            "pibo-event-activity-milestone-celebrate", "angry", "dive", "coolhide", "pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-hammock-idle-b",
            "pibo-state-sleeping-ground-idle-a", "pibo-state-waking-ground-behavior-recovering",
        ]
        #expect(Set(data.states.keys) == expectedStates)
        #expect(PiboAnimationStateMap.available == expectedStates)
        #expect(data.designFrame.width == 300)
        #expect(data.designFrame.height == 300)
        #expect(data.transition.durationMs == 600)
        #expect(data.transition.crossZoneDurationMs == 90)

        let expectedZones: [String: Set<String>] = [
            "ground": [
                "pibo-state-stable-forest-idle", "pibo-state-tired-forest-idle",
                "pibo-event-workout-celebrate", "pibo-event-activity-milestone-celebrate", "angry",
            ],
            "groundRest": [
                "pibo-state-sleeping-ground-idle-a",
                "pibo-state-waking-ground-behavior-recovering",
            ],
            "nest": ["pibo-state-waking-hammock-idle", "pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-hammock-idle-b"],
            "treeTraverse": ["boring"],
            "treeRest": ["weak"],
            "water": ["dive"],
            "grassHide": ["coolhide"],
        ]
        #expect(Set(data.transition.zones.keys) == Set(expectedZones.keys))
        for (zone, states) in expectedZones {
            #expect(Set(data.transition.zones[zone] ?? []) == states)
            for stateID in states {
                #expect(data.states[stateID]?.zone == zone)
            }
        }

        let requiredPrimitives: Set<String> = [
            "sigh-sequence", "bring-to-front", "pop-loop", "bubble-breathe",
            "wink-morph", "blink", "path-wiggle", "shake", "bob", "sway",
        ]
        let shippedPrimitives = Set(data.states.values.flatMap { state in
            state.idle?.resolvedParts.map(\.kind) ?? []
        })
        #expect(requiredPrimitives.isSubset(of: shippedPrimitives))

        for sharedPath in data.sharedMorphPaths {
            let morph = try #require(data.morph[sharedPath])
            let counts = try expectedStates.map { stateID in
                try #require(morph.values(for: stateID)).count
            }
            #expect(Set(counts).count == 1)
            #expect(counts.first ?? 0 > 0)
        }

        #expect(data.states["pibo-event-workout-celebrate"]?.idle?.intro?.duration == 0.85)
        #expect(data.states["pibo-event-activity-milestone-celebrate"]?.idle?.intro?.duration == 0.9)
    }

    @Test func groundSleepAndRecoveringWakeUseReviewedRuntimeChoreography() throws {
        let data = try PiboCharacterData.load()

        let groundSleep = try #require(
            data.states[PiboAnimationResourceID.sleepingGroundA]?.idle
        )
        let sleepPart = try #require(groundSleep.resolvedParts.first)
        #expect(groundSleep.resolvedParts.count == 1)
        #expect(sleepPart.kind == "breathe-y")
        #expect(sleepPart.duration == 4.8)
        #expect(sleepPart.amplitude == 0.018)
        #expect(sleepPart.origin == "156px 241px")

        let recovering = try #require(
            data.states[PiboAnimationResourceID.wakingGroundRecovering]?.idle
        )
        #expect(recovering.resolvedParts.map(\.kind) == [
            "sigh-sequence", "blink", "rotate-around-point", "rotate-around-point",
        ])
        let sigh = recovering.resolvedParts[0]
        let duration = (sigh.swellDuration ?? 0)
            + (sigh.flattenDuration ?? 0)
            + (sigh.recoverDuration ?? 0)
            + (sigh.pauseDuration ?? 0)
        #expect(abs(duration - 7.2) < 0.0001)
        #expect(recovering.resolvedParts[1].period == 7.2)
        #expect(recovering.resolvedParts[2].gateCycle == 7.2)
        #expect(recovering.resolvedParts[3].gateCycle == 7.2)
    }

    @Test func everyShippedStateExposesAPresentedSproutRootAnchor() throws {
        let data = try PiboCharacterData.load()
        for stateID in PiboAnimationStateMap.available {
            let character = try #require(PiboVectorCharacter(stateID: stateID, data: data))
            let anchor = try #require(character.presentedSproutRootPoint())
            #expect(anchor.x.isFinite)
            #expect(anchor.y.isFinite)
        }
    }

    @Test func interruptedMorphRetargetsFromTheExactVisibleGeometry() throws {
        let data = try PiboCharacterData.load()
        let character = try #require(PiboVectorCharacter(stateID: "pibo-state-stable-forest-idle", data: data))
        let transition = PiboStateTransition(data: data, stateID: "pibo-state-stable-forest-idle")

        transition.transition(to: "pibo-event-workout-celebrate")
        transition.update(deltaTime: 0.31)
        character.setTransition(
            from: transition.fromStateID,
            to: transition.toStateID,
            progress: transition.progress
        )
        let before = try #require(character.bodyPath())

        transition.transition(to: "pibo-state-tired-forest-idle")
        character.setTransition(
            from: transition.fromStateID,
            to: transition.toStateID,
            progress: transition.progress
        )
        let after = try #require(character.bodyPath())

        #expect(maximumPointDistance(before, after) < 0.001)
    }

    @Test func convergenceDerivativeIsBundledAtAuthoredDuration() async throws {
        let url = try #require(
            Bundle.main.url(
                forResource: "pibo-white-converge-hevc-alpha",
                withExtension: "mov",
                subdirectory: "Character"
            ) ?? Bundle.main.url(
                forResource: "pibo-white-converge-hevc-alpha",
                withExtension: "mov"
            )
        )
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks.first?.load(.naturalSize)
        #expect(abs(duration - 1.35) < 0.02)
        #expect(size == CGSize(width: 1_080, height: 1_080))
    }

    @Test func forestArtboardsMatchPiboContextPlacementAndOcclusion() {
        func placement(_ state: String, _ elapsed: TimeInterval = 0) -> ForestSceneManifest.PiboArtboardPlacement {
            ForestSceneManifest.piboArtboardPlacement(stateID: state, boringElapsed: elapsed)
        }

        #expect(placement("pibo-state-stable-forest-idle").frame == CGRect(x: 61.5, y: 356, width: 270, height: 270))
        #expect(placement("weak").frame == CGRect(x: 61.5, y: 442, width: 270, height: 270))
        #expect(placement("dive").frame == CGRect(x: 61.5, y: 580, width: 270, height: 270))
        #expect(placement("coolhide").frame == CGRect(x: 190, y: 292, width: 195, height: 195))
        #expect(placement("pibo-state-waking-hammock-idle").frame == CGRect(x: 25, y: 146.8, width: 210, height: 210))
        #expect(placement("pibo-state-sleeping-hammock-idle-a") == placement("pibo-state-sleeping-hammock-idle-b"))

        #expect(placement("coolhide").zPosition < 6)       // grass circle
        #expect(placement("boring").zPosition < 11)       // main tree
        #expect(placement("dive").zPosition > 11)         // main tree
        #expect(placement("dive").zPosition < 12)         // left stone

        #expect(placement("boring", 0).frame.minX == -300)
        let authoredEasing = PiboUnitBezier([0.42, 0, 0.58, 1])
        #expect(abs(
            placement("boring", 3).frame.minX
                - (-300 + CGFloat(authoredEasing(0.25)) * 361.5)
        ) < 0.001)
        #expect(abs(placement("boring", 12).frame.minX - 61.5) < 0.001)
        #expect(abs(placement("boring", 16).frame.minX - 61.5) < 0.001)
        #expect(abs(placement("boring", 27.999).frame.minX - 393) < 0.1)

        let groundPlayer = ForestSceneManifest.piboPlayerPlacement(stateID: "pibo-state-stable-forest-idle")
        #expect(groundPlayer.frame == CGRect(x: -10.5, y: 284, width: 414, height: 414))
        #expect(groundPlayer.artboardFrame == placement("pibo-state-stable-forest-idle").frame)
        #expect(abs(groundPlayer.bounceOrigin.x - 196.5) < 0.001)
        #expect(abs(groundPlayer.bounceOrigin.y - 524.12) < 0.001)
    }

    @Test func everyPlayerPlacementMatchesPiboContextOuterViewport() {
        let expected: [String: (CGRect, CGFloat)] = [
            "pibo-state-stable-forest-idle": (CGRect(x: -10.5, y: 284, width: 414, height: 414), 20),
            "pibo-state-tired-forest-idle": (CGRect(x: -10.5, y: 284, width: 414, height: 414), 20),
            "pibo-event-workout-celebrate": (CGRect(x: -10.5, y: 284, width: 414, height: 414), 20),
            "pibo-event-activity-milestone-celebrate": (CGRect(x: -10.5, y: 284, width: 414, height: 414), 20),
            "angry": (CGRect(x: -10.5, y: 284, width: 414, height: 414), 20),
            "weak": (CGRect(x: -10.5, y: 370, width: 414, height: 414), 20),
            "dive": (CGRect(x: -10.5, y: 508, width: 414, height: 414), 11.5),
            "coolhide": (CGRect(x: 138, y: 240, width: 299, height: 299), 5.5),
            "pibo-state-waking-hammock-idle": (CGRect(x: -31, y: 90.8, width: 322, height: 322), 20),
            "pibo-state-sleeping-hammock-idle-a": (CGRect(x: -31, y: 90.8, width: 322, height: 322), 20),
            "pibo-state-sleeping-hammock-idle-b": (CGRect(x: -31, y: 90.8, width: 322, height: 322), 20),
        ]

        for (stateID, value) in expected {
            let placement = ForestSceneManifest.piboPlayerPlacement(stateID: stateID)
            #expect(placement.frame == value.0, Comment(rawValue: stateID))
            #expect(placement.zPosition == value.1, Comment(rawValue: stateID))
            #expect(abs(placement.artboardFrame.width / placement.frame.width - 300 / 460) < 0.0001)
        }

        let boring = ForestSceneManifest.piboPlayerPlacement(stateID: "boring", boringElapsed: 12)
        #expect(boring.frame == CGRect(x: -10.5, y: 292, width: 414, height: 414))
        #expect(boring.zPosition == 10.5)
    }

    @Test func allVisibleStateGeometryMatchesFigmaArtboardPixels() throws {
        let expected: [String: CGRect] = [
            "pibo-state-stable-forest-idle": CGRect(x: 59, y: 31, width: 182, height: 252),
            "weak": CGRect(x: 43, y: 57, width: 214, height: 185),
            "pibo-event-workout-celebrate": CGRect(x: 44, y: 6, width: 212, height: 287),
            "pibo-event-activity-milestone-celebrate": CGRect(x: 37, y: 9, width: 226, height: 277),
            "pibo-state-tired-forest-idle": CGRect(x: 50, y: 39, width: 200, height: 220),
            "angry": CGRect(x: 42, y: 67, width: 217, height: 167),
            "dive": CGRect(x: 48, y: 82, width: 203, height: 136),
            "boring": CGRect(x: 42, y: 42, width: 216, height: 217),
            "coolhide": CGRect(x: 35, y: 15, width: 232, height: 245),
            "pibo-state-sleeping-hammock-idle-a": CGRect(x: 80, y: 96, width: 129, height: 125),
            "pibo-state-sleeping-hammock-idle-b": CGRect(x: 80, y: 93, width: 129, height: 119),
            "pibo-state-waking-hammock-idle": CGRect(x: 52, y: 111, width: 156, height: 164),
        ]

        let data = try PiboCharacterData.load()
        for (stateID, figma) in expected {
            let character = try #require(PiboVectorCharacter(stateID: stateID, data: data))
            let actual = character.renderedContentBounds
            let converted = CGRect(
                x: figma.minX - 150,
                y: 150 - figma.maxY,
                width: figma.width,
                height: figma.height
            )
            #expect(
                rectDistance(actual, converted) < 3,
                Comment(rawValue: "\(stateID): actual=\(actual), expected=\(converted)")
            )
        }
    }

    @Test func angryEntryUsesCoreBounceIntentAndExactPlayerCut() throws {
        #expect(PiboCoreAnimationAdapter.transitionIntent(
            stateID: "pibo-state-stable-forest-idle",
            angryEntered: true
        ) == .bounceCut)
        #expect(PiboCoreAnimationAdapter.transitionIntent(
            stateID: "pibo-state-stable-forest-idle",
            angryEntered: false
        ) == .hardCut)
        #expect(PiboCoreAnimationAdapter.transitionIntent(
            stateID: "pibo-state-sleeping-hammock-idle-a",
            angryEntered: true
        ) == .hardCut)

        let data = try PiboCharacterData.load()
        let transition = PiboStateTransition(data: data, stateID: "pibo-state-stable-forest-idle")
        transition.bounceCut(to: "angry")
        #expect(transition.displayStateID == "pibo-state-stable-forest-idle")
        #expect(transition.suppressesIdle)

        transition.update(deltaTime: 0.08)
        #expect(transition.displayStateID == "pibo-state-stable-forest-idle")
        #expect(transition.presentationScaleX < 1)
        #expect(transition.presentationScaleX == transition.presentationScaleY)

        transition.update(deltaTime: 0.11)
        #expect(transition.displayStateID == "angry")
        #expect(transition.fromStateID == "angry")
        #expect(transition.toStateID == "angry")
        #expect(abs(transition.presentationScaleX - 0.04) < 0.0001)
        #expect(abs(transition.presentationScaleY - 0.04) < 0.0001)
        #expect(transition.visualAlpha == 0)

        transition.update(deltaTime: 0.52)
        #expect(!transition.isRunning)
        #expect(!transition.suppressesIdle)
        #expect(transition.presentationScaleX == 1)
        #expect(transition.presentationScaleY == 1)
        #expect(transition.visualAlpha == 1)
    }

    @Test func interruptedBounceCannotLeavePresentationDirty() throws {
        let transition = PiboStateTransition(data: try PiboCharacterData.load(), stateID: "pibo-state-stable-forest-idle")
        transition.bounceCut(to: "angry")
        transition.update(deltaTime: 0.3)
        transition.hardCut(to: "weak")
        #expect(transition.displayStateID == "weak")
        #expect(transition.presentationScaleX == 1)
        #expect(transition.presentationScaleY == 1)
        #expect(transition.visualAlpha == 1)
    }

    @Test func vectorReflectionInheritsBusinessAndLandingScaleContainers() throws {
        let character = try #require(PiboVectorCharacter(
            stateID: "pibo-state-stable-forest-idle",
            data: try PiboCharacterData.load()
        ))
        #expect(character.reflectionSource.parent !== character.rootNode)
        #expect(character.reflectionSource.inParentHierarchy(character.rootNode))

        func reflectedAxisLengths() -> CGSize {
            let origin = character.rootNode.convert(
                CGPoint.zero,
                from: character.reflectionSource
            )
            let x = character.rootNode.convert(
                CGPoint(x: 10, y: 0),
                from: character.reflectionSource
            )
            let y = character.rootNode.convert(
                CGPoint(x: 0, y: 10),
                from: character.reflectionSource
            )
            return CGSize(width: hypot(x.x - origin.x, x.y - origin.y),
                          height: hypot(y.x - origin.x, y.y - origin.y))
        }

        let resting = reflectedAxisLengths()
        character.setPresentationScale(x: 0.5, y: 0.7)
        character.setSettleScale(0.8)
        let animated = reflectedAxisLengths()
        #expect(abs(animated.width / resting.width - 0.4) < 0.0001)
        #expect(abs(animated.height / resting.height - 0.56) < 0.0001)
    }

    @Test func bounceCutSwapsStatePlacementAndOcclusionAt190Milliseconds() throws {
        let transition = PiboStateTransition(
            data: try PiboCharacterData.load(),
            stateID: "pibo-state-stable-forest-idle"
        )
        transition.bounceCut(to: "coolhide")

        transition.update(deltaTime: 0.189)
        #expect(transition.displayStateID == "pibo-state-stable-forest-idle")
        let before = ForestSceneManifest.piboPlayerPlacement(
            stateID: transition.displayStateID
        )
        #expect(before.frame == CGRect(x: -10.5, y: 284, width: 414, height: 414))
        #expect(before.zPosition == 20)

        transition.update(deltaTime: 0.001)
        #expect(transition.displayStateID == "coolhide")
        let after = ForestSceneManifest.piboPlayerPlacement(
            stateID: transition.displayStateID
        )
        #expect(after.frame == CGRect(x: 138, y: 240, width: 299, height: 299))
        #expect(after.zPosition == 5.5)
        #expect(transition.presentationScaleX == 0.04)
        #expect(transition.presentationScaleY == 0.04)
        #expect(transition.visualAlpha == 0)
    }

    @Test func boringTraversalStartsOnlyWhenBounceDestinationBecomesVisible() throws {
        let transition = PiboStateTransition(
            data: try PiboCharacterData.load(),
            stateID: "pibo-state-stable-forest-idle"
        )
        transition.bounceCut(to: "boring")

        var boringElapsed: TimeInterval = 0
        if transition.displayStateID == "boring" { boringElapsed += 0.189 }
        transition.update(deltaTime: 0.189)
        #expect(boringElapsed == 0)
        #expect(ForestSceneManifest.piboPlayerPlacement(
            stateID: "boring",
            boringElapsed: boringElapsed
        ).frame.minX == -372)

        if transition.displayStateID == "boring" { boringElapsed += 0.001 }
        transition.update(deltaTime: 0.001)
        #expect(boringElapsed == 0)
        #expect(transition.displayStateID == "boring")

        if transition.displayStateID == "boring" { boringElapsed += 0.016 }
        transition.update(deltaTime: 0.016)
        #expect(boringElapsed == 0.016)
    }

    @Test func achievementHardCutUsesOnlyTheAuthoredIntro() throws {
        let data = try PiboCharacterData.load()
        let character = try #require(PiboVectorCharacter(stateID: "pibo-event-workout-celebrate", data: data))
        #expect(abs(character.sproutNode.xScale - 1) < 0.0001)
        #expect(abs(character.sproutNode.yScale - 1) < 0.0001)
        #expect(abs(character.sproutGeometryScale.width - (1 / 3)) < 0.0001)
        #expect(abs(character.sproutGeometryScale.height - (1 / 3)) < 0.0001)
        #expect(character.sproutPath() != nil)

        let transition = PiboStateTransition(data: data, stateID: "pibo-event-workout-celebrate")
        transition.startAuthoredIntro()
        #expect(transition.suppressesIdle)
        #expect(transition.introScale == 1)

        transition.update(deltaTime: 0.85 * 0.25)
        #expect(transition.introScale > 1.06)
        #expect(transition.introGlow > 0)

        transition.update(deltaTime: 0.85)
        #expect(!transition.suppressesIdle)
        #expect(transition.introScale == 1)
        #expect(transition.introGlow == 0)
    }

    @Test func ambientBusinessStateChangesAreTrueHardCuts() throws {
        let data = try PiboCharacterData.load()
        let transition = PiboStateTransition(data: data, stateID: "pibo-state-stable-forest-idle")
        var idleRestartCount = 0
        transition.onIntroFinished = { idleRestartCount += 1 }
        let playbook = PiboCharacterPlaybook(
            transition: transition,
            ambientStateID: "pibo-state-stable-forest-idle"
        )

        playbook.setAmbient("weak")

        #expect(!transition.isRunning)
        #expect(transition.fromStateID == "weak")
        #expect(transition.toStateID == "weak")
        #expect(transition.progress == 1)
        #expect(transition.visualAlpha == 1)
        #expect(idleRestartCount == 1)
    }

    @Test func playbookCanStartAndRestartFromItsTargetStateWithoutStalling() throws {
        let transition = PiboStateTransition(
            data: try PiboCharacterData.load(),
            stateID: "pibo-event-workout-celebrate"
        )
        let playbook = PiboCharacterPlaybook(
            transition: transition,
            ambientStateID: "pibo-event-workout-celebrate"
        )
        let beat = PiboCharacterPlaybook.Beat("pibo-event-workout-celebrate", hold: 0.1)

        playbook.play([beat])
        #expect(playbook.isPlaying)
        #expect(transition.isRunning)

        // A second command while the same intro is active must restart cleanly,
        // not wait forever for a deduplicated transition's settle callback.
        playbook.play([beat])
        transition.update(deltaTime: 0.9)
        playbook.update(deltaTime: 0.1)
        #expect(!playbook.isPlaying)
        #expect(transition.toStateID == "pibo-event-workout-celebrate")
    }

    @Test func legacyActualPatsNeverEnterTheRetiredAngryState() {
        let defaults = testDefaults()
        let experience = PiboAnimationExperienceStore(defaults: defaults)
        let now = Date()
        #expect(!experience.registerActualPat(localHour: 15, now: now))
        #expect(!experience.registerActualPat(localHour: 15, now: now.addingTimeInterval(1)))
        #expect(!experience.registerActualPat(localHour: 15, now: now.addingTimeInterval(2)))
        #expect(!experience.registerActualPat(localHour: 15, now: now.addingTimeInterval(3)))
        #expect(experience.angryUntil == nil)

        let sleeping = PiboAnimationExperienceStore(defaults: testDefaults())
        for offset in 0..<3 {
            #expect(!sleeping.registerActualPat(
                localHour: 23,
                countsTowardAngry: false,
                now: now.addingTimeInterval(Double(offset))
            ))
        }
        #expect(sleeping.angryUntil == nil)

        let deterministic = PiboAnimationExperienceStore(defaults: testDefaults())
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        #expect(!deterministic.registerActualPat(localHour: 15, now: fixed))
        #expect(!deterministic.registerActualPat(localHour: 15, now: fixed.addingTimeInterval(1)))
        #expect(!deterministic.registerActualPat(localHour: 15, now: fixed.addingTimeInterval(2)))
        #expect(!deterministic.registerActualPat(localHour: 15, now: fixed.addingTimeInterval(3)))
        #expect(deterministic.angryUntil == nil)
    }

    @Test func futurePatStateCannotLockAngryAfterClockRollbackOrCorruption() throws {
        let defaults = testDefaults()
        let future = Date.now.addingTimeInterval(
            PiboCorePatAdapter.recentWindowSeconds * 10
        )
        defaults.set(
            future.timeIntervalSince1970,
            forKey: "pibo.animation.angry-until.v1"
        )
        defaults.set(
            try JSONEncoder().encode([future]),
            forKey: "pibo.animation.actual-pats.v1"
        )

        let experience = PiboAnimationExperienceStore(defaults: defaults)

        #expect(experience.angryUntil == nil)
        #expect(experience.actualPatTimes.isEmpty)
    }

    @Test func latestWorkoutReplacesAndSameBatchPiguWins() {
        let experience = PiboAnimationExperienceStore(defaults: testDefaults())
        let first = workout(id: UUID(), endedAt: .now.addingTimeInterval(-60))
        let latest = workout(id: UUID(), endedAt: .now)
        // HealthDataService defines one acquisition batch by querying steps
        // before workouts. The later workout therefore wins the shared Modal.
        #expect(experience.queueStepsAchievement())
        experience.queueWorkout(first)
        experience.queueWorkout(latest)
        #expect(experience.pendingAchievement?.id == latest.id)
        #expect(experience.pendingAchievement?.kind == .pigu)
    }

    @Test func aLaterIndependentStepsAchievementReplacesWorkout() {
        let experience = PiboAnimationExperienceStore(defaults: testDefaults())
        experience.queueWorkout(workout(id: UUID(), endedAt: .now.addingTimeInterval(-60)))
        #expect(experience.pendingAchievement?.kind == .pigu)
        #expect(experience.queueStepsAchievement())
        #expect(experience.pendingAchievement?.kind == .muscle)
    }

    @Test func workoutOrderingAndDailyStepsAreDurable() {
        let defaults = testDefaults()
        let experience = PiboAnimationExperienceStore(defaults: defaults)
        let latest = workout(id: UUID(), endedAt: .now)
        let older = workout(id: UUID(), endedAt: .now.addingTimeInterval(-60))
        experience.queueWorkout(latest)
        experience.queueWorkout(older)
        #expect(experience.pendingAchievement?.id == latest.id)

        #expect(experience.queueStepsAchievement())
        #expect(experience.pendingAchievement?.kind == .muscle)
        _ = experience.confirmPending()
        #expect(!experience.queueStepsAchievement())

        let restored = PiboAnimationExperienceStore(defaults: defaults)
        #expect(!restored.queueStepsAchievement())

        defaults.set(
            Calendar.current.startOfDay(for: .now.addingTimeInterval(-86_400)).timeIntervalSince1970,
            forKey: "pibo.animation.steps-handled-day.v1"
        )
        #expect(restored.queueStepsAchievement())
        #expect(restored.pendingAchievement?.kind == .muscle)
    }

    @Test func crossDayPendingAchievementsExpireAndNeverCreateAHold() {
        let calendar = Calendar.current
        let defaults = testDefaults()
        let experience = PiboAnimationExperienceStore(defaults: defaults, calendar: calendar)
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        experience.queueWorkout(workout(id: UUID(), endedAt: now))
        #expect(experience.pendingAchievement?.kind == .pigu)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        experience.refreshExpiries(now: tomorrow)
        #expect(experience.pendingAchievement == nil)

        experience.queueStepsAchievement(at: now)
        _ = experience.confirmPending(now: now)
        experience.refreshExpiries(now: tomorrow)
    }

    /// 运动完成只在成果卡片里演一次：确认之后首页不保留 `pigu`，直接回到 Core
    /// 判定的健康状态；万步的 `muscle` 同样只是一段事件动画。
    @Test func workoutAchievementNeverHoldsOnTheHome() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let experience = PiboAnimationExperienceStore(defaults: testDefaults(), calendar: calendar)

        experience.queueWorkout(workout(id: UUID(), endedAt: now))
        #expect(experience.pendingAchievement?.kind == .pigu)
        _ = experience.confirmPending(now: now)

        experience.queueStepsAchievement(at: now)
        _ = experience.confirmPending(now: now)
        // 主场景没有 pigu 的保持呼吸，因为它根本不会停在主场景。
        #expect(PiboAnimationStateMap.holdIdle(for: "pibo-event-workout-celebrate") == nil)
    }

    @Test func everyNotificationTapProducesAConsumablePresentationRequest() {
        let experience = PiboAnimationExperienceStore(defaults: testDefaults())
        #expect(experience.notificationPresentationRequestID == nil)

        experience.requestNotificationPresentation()
        let first = experience.notificationPresentationRequestID
        #expect(first != nil)
        experience.requestNotificationPresentation()
        #expect(experience.notificationPresentationRequestID != first)

        experience.queueWorkout(workout(id: UUID(), endedAt: .now))
        _ = experience.confirmPending()
        #expect(experience.notificationPresentationRequestID == nil)
    }

    @Test func contentKeysSleepEligibilityAndPresentationPolicy() {
        #expect(PiboCoreAnimationAdapter.achievementContentID(kind: .pigu, modal: false)
                == "animation.workout.notification")
        #expect(PiboCoreAnimationAdapter.achievementContentID(kind: .pigu, modal: true)
                == "animation.pigu.modal")
        #expect(PiboCoreAnimationAdapter.achievementContentID(kind: .muscle, modal: false)
                == "animation.steps_8000.notification")
        #expect(PiboCoreAnimationAdapter.achievementContentID(kind: .muscle, modal: true)
                == "animation.muscle.modal")

        #expect(HeartbeatSeriesReader.sleepValueMeansAsleep(
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ))
        #expect(HeartbeatSeriesReader.sleepValueMeansAsleep(
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ))
        #expect(!HeartbeatSeriesReader.sleepValueMeansAsleep(
            HKCategoryValueSleepAnalysis.awake.rawValue
        ))
        #expect(!PiboCoreAnimationAdapter.achievementPresentationAllowed(in: "pibo-state-sleeping-hammock-idle-a"))
        #expect(PiboCoreAnimationAdapter.achievementPresentationAllowed(in: "pibo-state-stable-forest-idle"))
    }

    @Test func achievementNotificationPublicationPreservesObservationOrder() async {
        let queue = AchievementNotificationPublicationQueue()
        let gate = AnimationTestGate()
        let recorder = AnimationTestRecorder()

        let olderMuscle = queue.submit {
            await gate.wait()
            await recorder.append("pibo-event-activity-milestone-celebrate")
            return true
        }
        let newerPigu = queue.submit {
            await recorder.append("pibo-event-workout-celebrate")
            return true
        }

        await gate.open()
        #expect(await olderMuscle.value)
        #expect(await newerPigu.value)
        #expect(await recorder.values() == ["pibo-event-activity-milestone-celebrate", "pibo-event-workout-celebrate"])
    }

    private func maximumPointDistance(_ first: CGPath, _ second: CGPath) -> CGFloat {
        let firstPoints = points(in: first)
        let secondPoints = points(in: second)
        guard firstPoints.count == secondPoints.count else { return .infinity }
        return zip(firstPoints, secondPoints).map { lhs, rhs in
            hypot(lhs.x - rhs.x, lhs.y - rhs.y)
        }.max() ?? 0
    }

    private func rectDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        [
            abs(first.minX - second.minX),
            abs(first.minY - second.minY),
            abs(first.maxX - second.maxX),
            abs(first.maxY - second.maxY),
        ].max() ?? .infinity
    }

    // MARK: - Idle fidelity against the design engine

    /// Whole-body idle scales about the authored `transform-origin` — almost
    /// always the character's contact point. Pivoting on the artboard centre
    /// instead slides the feet up and down with every breath.
    @Test func wholeBodyIdlePivotsOnTheAuthoredOrigin() throws {
        let data = try PiboCharacterData.load()
        let part = try #require(data.states["pibo-state-tired-forest-idle"]?.idle?.resolvedParts.first)
        #expect(part.kind == "breathe-y")
        #expect(part.origin == "150px 259px")
        #expect(part.duration == 4.2)

        let character = try #require(PiboVectorCharacter(stateID: "pibo-state-tired-forest-idle", data: data))
        let animator = PiboIdleAnimator(data: data)
        let pivot = presented(CGPoint(x: 150, y: 259), of: character)
        let crown = presented(CGPoint(x: 150, y: 60), of: character)

        func advance(to time: TimeInterval) {
            character.resetIdleTransforms()
            animator.apply(
                idle: data.states["pibo-state-tired-forest-idle"]?.idle,
                stateID: "pibo-state-tired-forest-idle",
                character: character,
                time: time,
                amplitude: 1
            )
        }

        advance(to: 0)
        // A quarter period in is the peak of the breath.
        advance(to: 4.2 / 4)
        let movedPivot = presented(CGPoint(x: 150, y: 259), of: character)
        let movedCrown = presented(CGPoint(x: 150, y: 60), of: character)

        #expect(hypot(movedPivot.x - pivot.x, movedPivot.y - pivot.y) < 0.0001)
        #expect(hypot(movedCrown.x - crown.x, movedCrown.y - crown.y) > 0.5)
    }

    /// `breathe` is a half wave — it only ever swells outward from the rest
    /// shape. A symmetric wave doubles the peak-to-peak travel and dips the
    /// silhouette below its authored size.
    @Test func breatheOnlySwellsOutwardWhileBreatheYIsSymmetric() throws {
        let data = try PiboCharacterData.load()
        let muscle = try #require(data.states["pibo-event-activity-milestone-celebrate"]?.idle?.resolvedParts.first)
        #expect(muscle.kind == "breathe")
        let amplitude = try #require(muscle.amplitude)

        let character = try #require(PiboVectorCharacter(stateID: "pibo-event-activity-milestone-celebrate", data: data))
        let animator = PiboIdleAnimator(data: data)
        character.resetIdleTransforms()
        let restPivot = presented(CGPoint(x: 163, y: 285), of: character)
        let restCrown = presented(CGPoint(x: 163, y: 85), of: character)
        let rest = hypot(restCrown.x - restPivot.x, restCrown.y - restPivot.y)

        var scales: [CGFloat] = []
        for step in 0...48 {
            let time = Double(step) / 48 * (muscle.duration ?? 1.8)
            character.resetIdleTransforms()
            animator.apply(
                idle: data.states["pibo-event-activity-milestone-celebrate"]?.idle,
                stateID: "pibo-event-activity-milestone-celebrate",
                character: character,
                time: time,
                amplitude: 1
            )
            let pivot = presented(CGPoint(x: 163, y: 285), of: character)
            let crown = presented(CGPoint(x: 163, y: 85), of: character)
            scales.append(hypot(crown.x - pivot.x, crown.y - pivot.y))
        }
        let minimum = try #require(scales.min())
        let maximum = try #require(scales.max())
        // Never dips below the authored silhouette, and tops out exactly one
        // amplitude above it.
        #expect(minimum >= rest - 0.001)
        #expect(abs(maximum / rest - (1 + CGFloat(amplitude))) < 0.001)
    }

    /// `unipolar` swings one way only, and the design frame's Y-down degrees
    /// change sign on the way into SpriteKit. Both halves matter here: the wrong
    /// sign sends pigu's inner hand round the outside of the shoulder.
    @Test func unipolarAndHoldRotationsStayOnOneSide() throws {
        let data = try PiboCharacterData.load()
        let character = try #require(PiboVectorCharacter(stateID: "pibo-event-workout-celebrate", data: data))
        let animator = PiboIdleAnimator(data: data)
        let hand = try #require(character.node(forSelector: "#orphan-righthand-pibo-event-workout-celebrate", stateID: "pibo-event-workout-celebrate"))

        var extremes: [CGFloat] = []
        for step in 0...60 {
            // The shared timeline starts at the animator's first frame, so the
            // sweep has to begin at zero for the gate windows to line up.
            let time = Double(step) / 60 * 6
            character.resetIdleTransforms()
            animator.apply(
                idle: data.states["pibo-event-workout-celebrate"]?.idle,
                stateID: "pibo-event-workout-celebrate",
                character: character,
                time: time,
                amplitude: 1
            )
            extremes.append(hand.zRotation)
        }
        #expect(extremes.allSatisfy { $0 >= -0.0001 })
        #expect((extremes.max() ?? 0) > 0.01)

        // `hold` is a pose, not a wag: it parks at full deflection and lets the
        // gate fade do the lifting and lowering.
        let muscleCharacter = try #require(PiboVectorCharacter(stateID: "pibo-event-activity-milestone-celebrate", data: data))
        let leg = try #require(muscleCharacter.node(forSelector: "#orphan-rightleg-pibo-event-activity-milestone-celebrate", stateID: "pibo-event-activity-milestone-celebrate"))
        let muscleAnimator = PiboIdleAnimator(data: data)
        var plateau: [CGFloat] = []
        for time in [0.0, 2.2, 2.6, 2.9] {
            muscleCharacter.resetIdleTransforms()
            muscleAnimator.apply(
                idle: data.states["pibo-event-activity-milestone-celebrate"]?.idle,
                stateID: "pibo-event-activity-milestone-celebrate",
                character: muscleCharacter,
                time: time,
                amplitude: 1
            )
            plateau.append(leg.zRotation)
        }
        let expected = CGFloat(9 * Double.pi / 180)
        #expect(abs(plateau[0]) < 0.0001)
        #expect(plateau.dropFirst().allSatisfy { abs($0 - expected) < 0.0001 })
    }

    /// `path-bulge` runs one damped oscillation across its gate window. Driving
    /// it from a free-running period instead turns pigu's 屁股 duang·duang into a
    /// continuous jiggle at the wrong rate, and leaves it deformed outside the
    /// window.
    @Test func pathBulgeTraversesItsGateWindowAndRestsOutsideIt() throws {
        let data = try PiboCharacterData.load()
        let character = try #require(PiboVectorCharacter(stateID: "pibo-event-workout-celebrate", data: data))
        let animator = PiboIdleAnimator(data: data)
        let body = try #require(character.node(forSelector: "#path-body", stateID: "pibo-event-workout-celebrate"))
        let base = try #require(character.basePath(forSelector: "#path-body", stateID: "pibo-event-workout-celebrate"))

        func deviation(at time: TimeInterval) -> CGFloat {
            character.resetIdleTransforms()
            animator.apply(
                idle: data.states["pibo-event-workout-celebrate"]?.idle,
                stateID: "pibo-event-workout-celebrate",
                character: character,
                time: time,
                amplitude: 1
            )
            guard let path = body.path else { return .infinity }
            return maximumPointDistance(path, base)
        }

        // Window is 0.21…0.56 of the 6 s timeline.
        _ = deviation(at: 0)
        let inside = (0...20).map { deviation(at: 1.3 + Double($0) / 20 * 2.0) }
        #expect((inside.max() ?? 0) > 0.5)
        #expect(deviation(at: 4.2) < 0.0001)
        #expect(deviation(at: 0.6) < 0.0001)
    }

    /// 主场景保持成果姿势时只呼吸，不演连招；参数取自设计侧的 `setIdleOverride`。
    /// 只有 `muscle` 会停在主场景，所以只有它有这条呼吸。
    @Test func achievementHoldUsesTheSourceIdleOverride() throws {
        let muscle = try #require(PiboAnimationStateMap.holdIdle(for: "pibo-event-activity-milestone-celebrate")?.resolvedParts.first)
        #expect(muscle.kind == "breathe-y")
        #expect(muscle.origin == "150px 270px")
        #expect(muscle.duration == 4.2)
        #expect(muscle.amplitude == 0.018)

        #expect(PiboAnimationStateMap.holdIdle(for: "pibo-event-workout-celebrate") == nil)
        #expect(PiboAnimationStateMap.holdIdle(for: "pibo-state-stable-forest-idle") == nil)
        #expect(PiboAnimationStateMap.holdIdle(for: "weak") == nil)
        // 成果卡片里仍然演完整的登场与连招，所以状态数据本身不变。
        let data = try PiboCharacterData.load()
        #expect(data.states["pibo-event-workout-celebrate"]?.idle?.resolvedParts.count == 11)
        #expect(data.states["pibo-event-workout-celebrate"]?.idle?.intro != nil)
    }

    private func presented(_ designPoint: CGPoint, of character: PiboVectorCharacter) -> CGPoint {
        character.rootPoint(forBodyPathPoint: designPoint.applying(character.designToNodeTransform))
    }

    private func points(in path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int = switch element.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            case .closeSubpath: 0
            @unknown default: 0
            }
            for index in 0..<count { result.append(element.points[index]) }
        }
        return result
    }

    private func testDefaults() -> UserDefaults {
        let name = "PiboAnimationIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func workout(id: UUID, endedAt: Date) -> PendingWorkout {
        PendingWorkout(
            id: id,
            kind: .run,
            label: "跑步",
            durationMin: 20,
            kcal: 120,
            endedAt: endedAt,
            gainVitality: 20
        )
    }
}

private actor AnimationTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor AnimationTestRecorder {
    private var entries: [String] = []

    func append(_ value: String) {
        entries.append(value)
    }

    func values() -> [String] {
        entries
    }
}
