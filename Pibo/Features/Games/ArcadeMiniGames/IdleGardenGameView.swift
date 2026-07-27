import Foundation
import SwiftUI

// MARK: - 放置花田

struct IdleGardenGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenLastCollectAt)
    private var lastCollectAt = 0.0
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenSeeds)
    private var storedSeeds = 0
    @AppStorage(PiboPersistenceKeys.Defaults.idleGardenPlantedPlots)
    private var plantedPlots = 1

    @State private var collectionMessage = "...没有惩罚，只有花。"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let snapshot = GardenProductionSnapshot(
                now: timeline.date,
                lastCollectedAt: lastCollectAt,
                plantedPlots: plantedPlots
            )

            MiniGameShell(
                kind: .idleGarden,
                scoreText: "🌱 \(storedSeeds)",
                detailText: "\(plantedPlots)/24 花圃 · \(snapshot.readyFlowers) 可收",
                onClose: { dismiss() }
            ) {
                GeometryReader { proxy in
                    ZStack {
                        ForEach(0..<24, id: \.self) { index in
                            gardenPlot(
                                index: index,
                                isPlanted: index < plantedPlots,
                                isReady: index < snapshot.readyFlowers
                            )
                            .position(
                                x: CGFloat((index % 6) + 1) * proxy.size.width / 7,
                                y: CGFloat((index / 6) + 1) * proxy.size.height / 5
                            )
                        }

                        VStack(spacing: 3) {
                            Text(AppLocalization.text(collectionMessage))
                                .lpText(LP.Typography.handSmall)
                                .foregroundStyle(LP.Content.secondary)
                            Text(AppLocalization.text(snapshot.nextFlowerText))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: proxy.size.width - 32)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 28)
                    }
                }
            } bottomBar: {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: "收 \(snapshot.readyFlowers) 朵",
                        system: "tray.and.arrow.down.fill",
                        variant: .primary,
                        disabled: snapshot.readyFlowers == 0
                    ) {
                        collect(snapshot.readyFlowers, at: timeline.date)
                    }
                    MiniGameActionButton(
                        title: plantedPlots >= 24 ? "已种满" : "扩一块",
                        system: "leaf.fill",
                        disabled: storedSeeds <= 0 || plantedPlots >= 24
                    ) {
                        plantPlot(snapshot: snapshot, at: timeline.date)
                    }
                }
            }
        }
        .onAppear {
            if lastCollectAt == 0 {
                lastCollectAt = Date().timeIntervalSince1970 - GardenProductionSnapshot.growDuration
            }
            plantedPlots = plantedPlots.clamped(to: 1...24)
        }
    }

    @ViewBuilder
    private func gardenPlot(index: Int, isPlanted: Bool, isReady: Bool) -> some View {
        if isReady {
            MiniGameFlowerAsset(level: index % 4)
                .frame(width: 44, height: 44)
        } else if isPlanted {
            MiniGameSproutAsset()
                .frame(width: 30, height: 36)
                .opacity(0.62)
        } else {
            Circle()
                .strokeBorder(LP.Border.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LP.Content.tertiary)
                )
        }
    }

    private func collect(_ collected: Int, at date: Date) {
        guard collected > 0 else { return }
        storedSeeds += collected
        lastCollectAt = date.timeIntervalSince1970
        let newBest = MiniGameBestScoreStore().record(collected, for: .idleGarden)
        let reward = MiniGameRewardStore().grantPetals(for: collected, kind: .idleGarden)
        miniGameTrackResult(kind: .idleGarden, score: collected, reward: reward, newBest: newBest)
        let bestLine = newBest ? "这次最多。" : "慢慢攒。"
        let starLine = MiniGameScoring.starText(score: collected, kind: .idleGarden)
        collectionMessage = reward.petals > 0
            ? "收了 \(collected) 朵，花瓣 +\(reward.petals)。\(starLine)。\(bestLine)"
            : "收了 \(collected) 朵，Pibo 假装不在意。\(starLine)。\(bestLine)"
        LPHaptics.success()
    }

    private func plantPlot(snapshot: GardenProductionSnapshot, at date: Date) {
        guard storedSeeds > 0, plantedPlots < 24 else { return }
        storedSeeds -= 1
        plantedPlots += 1
        lastCollectAt = date.timeIntervalSince1970
            - snapshot.progressFraction * GardenProductionSnapshot.growDuration
        collectionMessage = "多了一块花圃；花会在三分钟内依次长好。"
        LPHaptics.tap()
    }
}

private struct GardenProductionSnapshot {
    static let growDuration = 180.0

    let readyFlowers: Int
    let secondsUntilNext: Int
    let plantedPlots: Int
    let progressFraction: Double

    init(now: Date, lastCollectedAt: Double, plantedPlots: Int) {
        self.plantedPlots = plantedPlots.clamped(to: 1...24)
        let reference = lastCollectedAt == 0
            ? now.timeIntervalSince1970 - Self.growDuration
            : lastCollectedAt
        let elapsed = max(0, now.timeIntervalSince1970 - reference)
        progressFraction = min(1, elapsed / Self.growDuration)
        let exactProgress = progressFraction * Double(self.plantedPlots)
        readyFlowers = Int(floor(exactProgress))

        if readyFlowers >= self.plantedPlots {
            secondsUntilNext = 0
        } else {
            let nextThreshold = Double(readyFlowers + 1) / Double(self.plantedPlots) * Self.growDuration
            secondsUntilNext = max(1, Int(ceil(nextThreshold - elapsed)))
        }
    }

    var nextFlowerText: String {
        guard secondsUntilNext > 0 else { return "这一批已经长好，不收也不会枯" }
        return "下一朵约 \(secondsUntilNext / 60):\(String(format: "%02d", secondsUntilNext % 60)) 后长好"
    }
}
