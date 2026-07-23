import SpriteKit
import SwiftUI
import UIKit
import XCTest
@testable import Pibo

@MainActor
final class StageArchitectureTests: XCTestCase {
    func testEnvironmentNormalizesHourAndPreservesWeatherKind() {
        let snapshot = PiboStageEnvironmentResolver.resolve(
            date: Date(timeIntervalSinceReferenceDate: 0),
            forcedHour: 25.5,
            weather: .snow
        )

        XCTAssertEqual(snapshot.localHour, 1.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.dayPhase, .night)
        XCTAssertEqual(snapshot.weather, .snow)
        XCTAssertEqual(snapshot.rainIntensity, 0)
    }

    func testDayPhaseBoundaries() {
        XCTAssertEqual(environment(at: 4.99).dayPhase, .night)
        XCTAssertEqual(environment(at: 5).dayPhase, .morning)
        XCTAssertEqual(environment(at: 9).dayPhase, .day)
        XCTAssertEqual(environment(at: 16.5).dayPhase, .dusk)
        XCTAssertEqual(environment(at: 20.5).dayPhase, .night)
    }

    func testForestAdapterKeepsAuthoredKeyframes() {
        let morning = ForestEnvironmentAdapter.resolve(environment(at: 6.5))
        XCTAssertEqual(morning.lighting.morningBeam, 0.72, accuracy: 0.0001)
        XCTAssertEqual(morning.wind.strength, 0.45, accuracy: 0.0001)
        XCTAssertEqual(morning.lighting.water.highlightStrength, 0.92, accuracy: 0.0001)

        let dusk = ForestEnvironmentAdapter.resolve(environment(at: 18.5))
        XCTAssertEqual(dusk.lighting.duskBeam, 0.34, accuracy: 0.0001)
        XCTAssertEqual(dusk.wind.strength, 0.55, accuracy: 0.0001)
        XCTAssertEqual(dusk.lighting.water.reflectionStrength, 0.75, accuracy: 0.0001)
    }

    func testCatalogHasUniqueIDsAndCreatesForestRenderer() {
        let ids = PiboThemeCatalog.themes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(PiboThemeCatalog.defaultTheme.id, PiboTheme.forest.id)
        XCTAssertTrue(PiboThemeCatalog.makeRenderer(for: .forest) is ForestThemeRenderer)
    }

    func testCatalogRejectsUnknownPersistedTheme() {
        XCTAssertNil(PiboThemeCatalog.theme(id: "test.unknown"))
        XCTAssertEqual(
            PiboThemeCatalog.resolvedThemeID("test.unknown"),
            PiboThemeCatalog.defaultTheme.id
        )
        XCTAssertEqual(
            PiboThemeCatalog.resolvedThemeID(PiboTheme.forest.id),
            PiboTheme.forest.id
        )
    }

    func testInteractiveLeafReflectionFollowsDownwardDeformation() {
        let restSource = CGPoint(x: 250, y: 600)
        let draggedSource = CGPoint(x: 250, y: 640)
        let contact = CGPoint(x: 250, y: 730)
        let style = ForestReflectionProjection.Style.strong
        let restReflection = ForestReflectionProjection.destination(
            for: restSource,
            contact: contact,
            sourceHeight: 249,
            style: style
        )
        let fixedMirrorReflection = ForestReflectionProjection.destination(
            for: draggedSource,
            contact: contact,
            sourceHeight: 249,
            style: style
        )
        let interactiveReflection = ForestReflectionProjection.destination(
            for: draggedSource,
            restingAt: restSource,
            contact: contact,
            sourceHeight: 249,
            style: style,
            motionResponse: .followSourceDeformation
        )

        XCTAssertLessThan(fixedMirrorReflection.y, restReflection.y)
        XCTAssertGreaterThan(interactiveReflection.y, restReflection.y)
        XCTAssertEqual(
            interactiveReflection.y - restReflection.y,
            (draggedSource.y - restSource.y) * style.verticalCompression,
            accuracy: 0.0001
        )
    }

    func testAllForegroundFoliageUsesIndependentFigmaAssets() throws {
        let expected: [String: (nodeID: String, width: Int, height: Int)] = [
            "forest_main_leaf_1": ("3906:3081", 851, 1104),
            "forest_main_leaf_2": ("3906:3103", 631, 780),
            "forest_front_leaf_1": ("3906:3141", 837, 360),
            "forest_front_leaf_2": ("3906:3151", 744, 386),
            "forest_front_grass_1": ("3906:3156", 212, 274),
            "forest_front_grass_2": ("3906:3177", 381, 512),
            "forest_front_grass_3": ("3906:3213", 209, 363),
        ]

        XCTAssertEqual(Set(ForestSceneManifest.foliage.map(\.image)), Set(expected.keys))
        XCTAssertEqual(Set(ForestSceneManifest.foliage.map(\.sourceNodeID)).count, expected.count)

        for definition in ForestSceneManifest.foliage {
            let source = try XCTUnwrap(expected[definition.image])
            XCTAssertEqual(definition.sourceNodeID, source.nodeID)
            XCTAssertEqual(definition.interaction.role, .direct)
            XCTAssertTrue((0 ... 1).contains(definition.anchor.x))
            XCTAssertTrue((0.9 ... 1).contains(definition.anchor.y))

            let image = try XCTUnwrap(UIImage(named: definition.image)?.cgImage)
            XCTAssertEqual(image.width, source.width, definition.image)
            XCTAssertEqual(image.height, source.height, definition.image)

            let mask = try XCTUnwrap(ForestFoliageAlphaMask(imageNamed: definition.image))
            let samples = (0 ... 20).flatMap { y in
                (0 ... 20).map { x in
                    mask.contains(u: CGFloat(x) / 20, v: CGFloat(y) / 20)
                }
            }
            XCTAssertTrue(samples.contains(true), "\(definition.image) has no interactive pixels")
            XCTAssertTrue(samples.contains(false), "\(definition.image) has no transparent pixels")
        }
    }

    func testMainLeafMaskIncludesBladeStemAndExcludesEmptySpace() throws {
        let mask = try XCTUnwrap(ForestFoliageAlphaMask(imageNamed: "forest_main_leaf_1"))
        // Opaque pixels sampled from Figma node 3906:3081: the broad blade
        // and its long lower stem must both begin the same anchored drag.
        XCTAssertTrue(mask.contains(u: 430.0 / 850.0, v: 1 - 350.0 / 1103.0))
        XCTAssertTrue(mask.contains(u: 730.0 / 850.0, v: 1 - 900.0 / 1103.0))
        // Transparent space inside the sprite bounds must remain available to
        // Pibo and the scene instead of being claimed by this leaf.
        XCTAssertFalse(mask.contains(u: 200.0 / 850.0, v: 1 - 550.0 / 1103.0))
    }

    func testMainTreeUsesCompleteFigmaComposite() throws {
        let image = try XCTUnwrap(UIImage(named: "forest_main_tree")?.cgImage)

        // Figma `3906:3293` exports a 462×219 canvas at @3x. The previously
        // exported `3906:3294` child was only 456.219×206.986 and omitted the
        // moss, bark texture, scratches, and edge shading sibling layers.
        XCTAssertEqual(image.width, 1_386)
        XCTAssertEqual(image.height, 657)
    }

    func testThemeSelectionPersistenceHealsUnknownIDsAndResets() {
        let suiteName = "PiboTests.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("test.unknown", forKey: PiboPersistenceKeys.Defaults.selectedThemeID)
        XCTAssertEqual(
            PiboThemeSelectionPersistence.restore(from: defaults),
            PiboThemeCatalog.defaultTheme.id
        )
        XCTAssertNil(defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID))

        PiboThemeSelectionPersistence.save(PiboTheme.forest.id, to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID),
            PiboTheme.forest.id
        )
        PiboThemeSelectionPersistence.reset(in: defaults)
        XCTAssertNil(defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID))
    }

    func testDirectEnvironmentCannotCarryInconsistentPhase() {
        let snapshot = PiboStageEnvironment(localHour: -1, weather: .clear)
        XCTAssertEqual(snapshot.localHour, 23, accuracy: 0.0001)
        XCTAssertEqual(snapshot.dayPhase, .night)
    }

    #if DEBUG
    func testWaterDebugTuningIsAnOptionalForestCapability() {
        let forest: any PiboThemeRenderer = ForestThemeRenderer()
        let basic: any PiboThemeRenderer = BasicThemeRenderer(theme: .forest)
        XCTAssertNotNil(forest as? WaterDebugTunable)
        XCTAssertNil(basic as? WaterDebugTunable)

        let tuning = WaterDebugTuning(
            speed: 4,
            rippleStrength: -1,
            highlightStrength: 2,
            reflectionIntensity: 3,
            reflectionCompression: 0,
            reflectionTipScale: 2,
            showMask: true
        ).sanitized
        XCTAssertEqual(tuning.speed, 1.4)
        XCTAssertEqual(tuning.rippleStrength, 0)
        XCTAssertEqual(tuning.reflectionCompression, 0.25)
        XCTAssertEqual(tuning.reflectionTipScale, 1)
    }
    #endif

    func testOnlyRainKindsCreateRainNodes() {
        let scene = SKScene(size: CGSize(width: 390, height: 760))
        let back = SKNode()
        let front = SKNode()
        scene.addChild(back)
        scene.addChild(front)
        let controller = PiboWeatherEffectController(backLayer: back, frontLayer: front)
        let wind = StageWind(direction: CGVector(dx: -1, dy: 0), strength: 0.3, gustiness: 0.2)

        controller.apply(
            environment: environment(at: 12, weather: .snow),
            lowPowerMode: false,
            size: scene.size,
            wind: wind,
            themeImpact: { nil },
            characterImpactPoint: { nil }
        )
        XCTAssertTrue(back.children.isEmpty)
        XCTAssertTrue(front.children.isEmpty)

        controller.apply(
            environment: environment(at: 12, weather: .rain),
            lowPowerMode: false,
            size: scene.size,
            wind: wind,
            themeImpact: { nil },
            characterImpactPoint: { nil }
        )
        XCTAssertFalse(back.children.isEmpty)
        XCTAssertFalse(front.children.isEmpty)
    }

    private func environment(
        at hour: Double,
        weather: PiboWeather = .clear
    ) -> PiboStageEnvironment {
        PiboStageEnvironmentResolver.resolve(
            date: Date(timeIntervalSinceReferenceDate: 0),
            forcedHour: hour,
            weather: weather
        )
    }
}
