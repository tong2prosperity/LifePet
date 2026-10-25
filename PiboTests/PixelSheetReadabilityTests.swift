import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PixelSheetReadabilityTests {
    @Test func collectedBoRemainsInTheVisibleBalanceAfterTheReceiptEnds() async throws {
        let name = "PixelBoSnapshot.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let ledger = BoLedgerStore(defaults: defaults)
        ledger.debugSet(balance: 0, ripe: 1)
        let now = Date().timeIntervalSince1970
        let memory = PiboCompanionStore(defaults: defaults, clock: { now })
        memory.markVisible(now: now - 4 * 3600)
        let companion = HomeCompanionController(store: memory, clock: { now })
        companion.environment = .init(appActive: { true }, state: { .stable })
        companion.enterHome()
        defer { companion.leaveHome() }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        var renderer: PixelStageRenderer?
        let host = UIHostingController(rootView: CollectionSnapshot(ledger: ledger, companion: companion,
                                                                  growth: GrowthStore(defaults: defaults),
                                                                  decor: DecorStore(defaults: defaults),
                                                                  days: PiboDayStore(defaults: defaults),
                                                                  onReady: { renderer = $0 }))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        let stage = try #require(renderer)
        try save(window: window, filename: "bo-before.png")
        stage.leafPan(-120, ripe: true)
        stage.leafPanEnd()
        companion.tick()
        try await Task.sleep(for: .milliseconds(350))
        #expect(ledger.availableBo == 1)
        #expect(!ledger.hasRipeBo)
        #expect(stage.actorPresent)
        try save(window: window, filename: "bo-received.png")
        try await Task.sleep(for: .milliseconds(2300))
        #expect(stage.currentHint.isEmpty)
        #expect(stage.actorPresent)
        #expect(ledger.availableBo == 1)
        try save(window: window, filename: "bo-after.png")
    }

    private struct CollectionSnapshot: View {
        let ledger: BoLedgerStore
        let companion: HomeCompanionController
        let growth: GrowthStore
        let decor: DecorStore
        let days: PiboDayStore
        var onReady: (PixelStageRenderer) -> Void

        var body: some View {
            let look = HomePixelStageInput(hour: 12, animationStateID: "stable",
                                          growth: growth, cues: nil,
                                          boProgress: ledger.growthProgress, leafRipe: ledger.hasRipeBo,
                                          decor: decor, day: nil, days: days).look
            return ZStack(alignment: .topLeading) {
                PixelStageView(look: look, onStageReady: onReady, onCollectBo: {
                    let collected = ledger.collect()
                    if collected { companion.onBoCollected() }
                    return collected
                })
                GrowthHud(readout: "还没有健康数据权限", boBalance: ledger.availableBo, hasRipeBo: ledger.hasRipeBo)
                    .padding(.leading, 12)
                    .padding(.top, 72)
            }
            .ignoresSafeArea()
        }
    }

    private func save(window: UIWindow, filename: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "PiboReadabilityQA")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: folder.appending(path: filename))
    }

    @Test(arguments: [0, 1, 2])
    func growthExplanationFitsOrScrollsWithLargerText(layout: Int) async throws {
        let accessibility = layout == 2
        let name = "PixelSheetReadabilityTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let growth = GrowthStore(defaults: defaults)
        // An isolated presentation fixture, never real health facts or a real ledger.
        growth.restore(raw: "{\"eventXP\":300,\"eventFamiliarity\":100}")
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let size = CGSize(width: layout == 0 ? 430 : 375, height: layout == 0 ? 932 : 812)
        window.frame = CGRect(origin: .zero, size: size)
        let sheet = PixelSheetHost(kind: .growth, growth: growth, wishes: WishStore(defaults: defaults),
                                  decor: DecorStore(defaults: defaults),
                                  ornaments: OrnamentUnlockStore(defaults: defaults, debugUnlockOverride: false),
                                  ledger: BoLedgerStore(defaults: defaults), days: PiboDayStore(defaults: defaults))
        let host = UIHostingController(rootView: ZStack {
            Color(red: 0.07, green: 0.1, blue: 0.2)
            sheet
        }.environment(\.dynamicTypeSize, accessibility ? .accessibility2 : .large).ignoresSafeArea())
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        if accessibility {
            let scrolls = descendants(host.view).compactMap { $0 as? UIScrollView }
            #expect(scrolls.contains { $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height },
                    "larger explanatory text must remain reachable through a scrollable sheet")
        }
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "PiboReadabilityQA")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = accessibility ? "growth-large-text.png" : (layout == 0 ? "growth-430.png" : "growth-375.png")
        try #require(image.pngData()).write(to: folder.appending(path: filename))
    }

    private func descendants(_ root: UIView) -> [UIView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }
}
