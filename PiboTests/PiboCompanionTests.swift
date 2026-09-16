import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
struct PiboCompanionTests {
    @Test func bundledCatalogMatchesHarmonyContract() throws {
        let catalog = try #require(PiboCompanionCatalog.bundled())
        #expect(catalog.prompts.count >= 30)
        #expect(!catalog.sceneLines.isEmpty)
        #expect(!catalog.customReactions.isEmpty)
        #expect(!catalog.customEchoes.isEmpty)
        for prompt in catalog.prompts {
            #expect(prompt.options.count == 2)
            #expect(prompt.options.allSatisfy { $0.label.count <= 6 && !$0.echoes.isEmpty })
        }
    }

    @Test func invalidCustomLineIsRejected() {
        let jsonl = """
        {"type":"customReaction","id":"r","status":"approved","conditions":{},"lines":["没有引用"]}
        {"type":"customEcho","id":"e","status":"approved","conditions":{},"lines":["「{custom}」"]}
        """
        #expect(throws: PiboCompanionCatalog.CatalogError.self) { try PiboCompanionCatalog.parse(jsonl) }
    }

    @Test func storeRecordsAnswersAndExpiresThemLocally() throws {
        let suite = "PiboCompanionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = 1_800_000_000.0
        let store = PiboCompanionStore(defaults: defaults, key: "k", clock: { now })
        store.beginEntry(now: now)
        #expect(!store.hasPreviousVisit)
        store.recordAnswer(.init(promptId: "p", optionId: "custom", customText: "你好",
                                 retention: PiboCoreCompanionRetention.today.rawValue,
                                 answeredAt: now, expiresAt: now + 60), askedAt: now, positive: false, tired: false)
        store.recordIgnored(promptId: "q", askedAt: now, now: now)
        #expect(store.recentAnswerRatePercent() == 50)
        store.markVisible(now: now)
        now += 4 * 3600
        let restored = PiboCompanionStore(defaults: defaults, key: "k", clock: { now })
        #expect(restored.answers.isEmpty, "expired memory is pruned on load")
        restored.beginEntry(now: now)
        #expect(restored.hasPreviousVisit)
        #expect(abs(restored.absenceSecondsAtEntry - 4 * 3600) < 1)
        #expect(PiboCoreCompanionPolicy.returnSlot(absenceSeconds: restored.absenceSecondsAtEntry,
                                                  hasPreviousVisit: true) == .returnShort)
    }

    @Test func templatesAndHashesMatchHarmony() {
        #expect(HomeCompanionController.templateAvailable(["走了{steps}步"], values: ["steps": "12"]))
        #expect(!HomeCompanionController.templateAvailable(["走了{steps}步"], values: [:]))
        #expect(HomeCompanionController.render("你说「{custom}」。", values: [:], customText: "嗨") == "你说「嗨」。")
        // Java-style 31 hash over UTF-16, as HarmonyOS `hash()`.
        #expect(HomeCompanionController.hash("ab") == 97 * 31 + 98)
    }
}

#if DEBUG
@MainActor
struct HomeDebugToolCatalogTests {
    @Test func animationCatalogCoversEveryShippedResource() {
        let ids = Set(HomeDebugToolCatalog.tools.filter { $0.group == "动画" }.map(\.id))
        for resource in PiboAnimationStateMap.available {
            #expect(ids.contains("animation:\(resource)"), "missing \(resource)")
            #expect(HomeDebugToolCatalog.animationTitles[resource] != nil, "untitled \(resource)")
        }
        #expect(ids.contains("animation:auto"))
        #expect(Set(HomeDebugToolCatalog.tools.map(\.id)).count == HomeDebugToolCatalog.tools.count)
    }

    @Test func patScenariosCoverAll27CoreContextsWithIsolatedStores() {
        #expect(HomePatDebugScenario.all.count == 27)
        let keys = Set(PiboCorePatContext.allCases.compactMap(\.catalogKey))
        #expect(Set(HomePatDebugScenario.all.map(\.id)) == keys)
    }

    @Test func recentsKeepSixMostRecentUnique() {
        var prefs = HomeDebugDockPreferences()
        for id in ["a", "b", "c", "d", "e", "f", "g", "a"] { prefs.noteUsed(id) }
        #expect(prefs.recents == ["a", "g", "f", "e", "d", "c"])
    }

    @Test func debugBoSessionUsesCoreContainerWithoutTheLedger() {
        let session = HomeDebugBoSession(preset: "reserve")
        #expect(session.hasRipe)
        #expect(session.collect())
        #expect(session.balance == 1)
        #expect(session.hasRipe, "reserve refills the container")
        #expect(!HomeDebugBoSession(preset: "charging").collect())
    }
}
#endif

@MainActor
struct ForestAlphaHitMaskTests {
    @Test func transparentHammockCornersDoNotAnswerTaps() throws {
        let image = try #require(PiboOrnament.ornament(.hammock)?.placement?.image)
        let mask = try #require(ForestAlphaHitMask.mask(named: image))
        #expect(!mask.contains(unitPoint: CGPoint(x: 0.01, y: 0.01), radius: 0))
        #expect(!mask.contains(unitPoint: CGPoint(x: 0.99, y: 0.99), radius: 0))
        #expect(mask.contains(unitPoint: CGPoint(x: 0.5, y: 0.5)))
    }
}
