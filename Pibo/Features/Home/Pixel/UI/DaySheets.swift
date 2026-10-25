import PiboCore
import SwiftUI

// Decision 058's day sheets: the trail sign opens the map of scenes, the basket opens the
// shelf of finds and the away diary. Which scene is open and what was found come from Core.
//
// Ported from HarmonyPibo `pixel/ui/DaySheets.ets`. The thumbnails are cut from a real
// phone-sized stage, so every scene keeps the proportions it has on Home.

private let dayThumbWidth = 112
private let dayThumbHeight = 84
/// The full phone stage the thumbnail is cut from.
private let dayStageWidth = 143
private let dayStageHeight = 315

/// A small daytime view of a scene, drawn with the stage's own generators.
func paintSceneThumb(_ frame: PixelFrame, scene: Int, season: Int) {
    let layout = pixelForestLayout(dayStageWidth, dayStageHeight)
    let stage = PixelFrame(dayStageWidth, dayStageHeight)
    let coreScene = PiboCoreDayScene(rawValue: Int32(scene)) ?? .clearing
    let coreSeason = PiboCoreDaySeason(rawValue: Int32(season)) ?? .summer
    drawPixelForestStatic(stage, layout, 20250817, .day,
                          PixelWorldLook(scene: coreScene, season: coreSeason))
    drawPixelPlaces(stage, layout, coreScene,
                    PixelPlaceLook(season: coreSeason, snow: false, timeMs: 0,
                                   poked: nil, pokeAge: -1, basketFull: false),
                    dayStageHeight, false)
    // The middle band: the wood's edge, the open ground and whatever lies across it.
    let x0 = Int((Double(dayStageWidth - frame.width) / 2).rounded(.down))
    // The creek keeps its water in frame; the others show their tree tops.
    let y0 = layout.groundY - (scene == Int(PiboCoreDayScene.creek.rawValue) ? 58 : 74)
    for y in 0..<frame.height {
        for x in 0..<frame.width { frame.set(x, y, stage.get(x0 + x, y0 + y)) }
    }
}

// MARK: - 森林地图

/// 地图: the three scenes, each opening at a level. Pibo walks out of the edge to go.
struct DayMapSheet: View {
    var current = 0
    var level = 1
    var season = 1
    /// Core's `scene_min_level`: which level opens a scene.
    var minLevel: (Int) -> Int = { _ in 1 }
    var isUnlocked: ((Int) -> Bool)? = nil
    var onClose: () -> Void = {}
    var onTravel: (Int) -> Void = { _ in }

    private var scenes: [Int] { PiboCoreDayScene.allCases.map { Int($0.rawValue) } }

    var body: some View {
        PixelReadingSheet(title: AppLocalization.text("森林地图"), onClose: onClose) {
            VStack(spacing: 12) {
                ForEach(scenes, id: \.self) { scene in row(scene) }
            }
        }
    }

    private func row(_ scene: Int) -> some View {
        let unlocked = isUnlocked?(scene) ?? (level >= minLevel(scene))
        return HStack(spacing: 12) {
            ZStack {
                PixelCanvas(logicalWidth: dayThumbWidth, logicalHeight: dayThumbHeight,
                            revision: scene * 10 + season) { frame in
                    paintSceneThumb(frame, scene: scene, season: season)
                }
                .frame(width: 120, height: 90)
                .opacity(unlocked ? 1 : 0.4)
                if !unlocked { PixelIcon(rows: PixelIcons.lock, iconSize: 22) }
            }
            .frame(width: 120, height: 90)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(piboSceneName(scene))
                    .font(PixelFont.font(15))
                    .foregroundStyle(PixelUIColor.ink)
                Text(piboSceneNote(scene))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if scene == current {
                    Text(AppLocalization.text("Pibo 在这里"))
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(PixelUIColor.leaf)
                } else if !unlocked {
                    Text(AppLocalization.format("Lv.%@ 开放", "\(minLevel(scene))"))
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(PixelUIColor.inkSoft)
                } else {
                    PixelButton(label: AppLocalization.text("一起去"),
                                buttonID: "day-travel-\(scene)",
                                onTap: { onTravel(scene) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(scene == current ? PixelUIColor.paperDim : PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if unlocked && scene != current {
                onTravel(scene)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 收藏架

/// 收藏架: everything Pibo carried home, silhouettes for what is still out there, and the
/// diary of where it walked while you walked. A find can be put out in the scene Pibo is
/// in (decision 065: one spot per scene), swapped or taken back in.
struct ShelfSheet: View {
    var days: PiboDayStore
    /// The scene Pibo is in now: where 摆出来 puts a find.
    var scene = 0
    var onClose: () -> Void = {}
    /// The walk diary lives in the footprints now (决定 063); opens them on the latest walk.
    var onOpenFootprints: (Double) -> Void = { _ in }

    @State private var picked = -1
    #if DEBUG
    /// Screenshot scaffolding: `-PiboPixelShelfPick=1` starts with a find selected, since
    /// the simulator cannot tap a shelf slot.
    private var debugPick: Int? {
        guard let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-PiboPixelShelfPick=") })?
            .dropFirst("-PiboPixelShelfPick=".count) else { return nil }
        return Int(raw)
    }
    #endif

    private var items: [Int] { Array(0..<pixelFindCount()) }

    private func record(_ item: Int) -> PiboFindRecord? {
        days.finds.first { $0.item == item }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelSheetTitle(title: AppLocalization.text("收藏架"), onClose: onClose)
            Text(AppLocalization.format("找到 %@ / %@ 样", "\(days.finds.count)", "\(pixelFindCount())"))
                .font(PixelFont.font(13))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6),
                              spacing: 8) {
                        ForEach(items, id: \.self) { item in slot(item) }
                    }
                    .frame(height: 300)

                    if !days.finds.isEmpty { displayRow }

                    Text(AppLocalization.text("散步日记"))
                        .font(PixelFont.font(15))
                        .foregroundStyle(PixelUIColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let entry = days.diary.first {
                        diaryRow(entry)
                        Text(AppLocalization.text("日记写在足迹里 ›"))
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(PixelUIColor.leaf)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenFootprints(entry.at) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("shelf-open-footprints")
                    } else {
                        Text(AppLocalization.text("你走路的时候，我也会出去走走。"))
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(PixelUIColor.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 440)
        }
        .pixelSheetFrame()
        .onAppear {
            #if DEBUG
            if let debugPick { picked = debugPick }
            #endif
        }
    }

    private func slot(_ item: Int) -> some View {
        let record = record(item)
        return VStack(spacing: 2) {
            PixelCanvas(logicalWidth: PIXEL_FIND_SIZE + 2, logicalHeight: PIXEL_FIND_SIZE + 2,
                        revision: days.revision * 32 + item) { frame in
                frame.clear(.groundLight)
                if record != nil {
                    drawPixelFind(frame, item, 1, 1)
                } else {
                    drawPixelFindSilhouette(frame, item, 1, 1, .groundMid)
                }
            }
            .frame(width: 44, height: 44)
            Text(record != nil ? piboFindName(item) : "？")
                .font(.system(size: 10))
                .foregroundStyle(PixelUIColor.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)
            if let count = record?.count, count > 1 {
                Text("×\(count)")
                    .font(PixelFont.font(10))
                    .foregroundStyle(PixelUIColor.leaf)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(2)
        .overlay(Rectangle().strokeBorder(PixelUIColor.leaf,
                                          lineWidth: picked == item ? 2 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            guard record != nil else { return }
            picked = picked == item ? -1 : item
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record != nil
            ? AppLocalization.format("%@，第 %@ 天带回来", piboFindName(item),
                                     "\(record?.firstDay ?? 1)")
            : AppLocalization.text("还没找到"))
    }

    /// Where a find is out on display, as a scene name, or "".
    private func shownIn(_ item: Int) -> String {
        for scene in 0..<PiboCoreDayScene.allCases.count where days.displayedIn(scene) == item {
            return piboSceneName(scene)
        }
        return ""
    }

    private var displayRow: some View {
        HStack(spacing: 8) {
            if picked >= 0 {
                let shown = shownIn(picked)
                Text(shown.isEmpty
                    ? piboFindName(picked)
                    : AppLocalization.format("%@ · 摆在%@", piboFindName(picked), shown))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let out = days.displayedIn(scene) == picked
                PixelButton(label: AppLocalization.text(out ? "收回来" : "摆出来"),
                            primary: !out,
                            buttonID: "shelf-display",
                            onTap: {
                                days.setDisplayed(scene, out ? -1 : picked)
                                Analytics.track(.findDisplayToggle, screen: "home", [
                                    "item": .string("find_\(picked)"), "action": .string(out ? "recall" : "display"),
                                    "scene": .string(PiboAnalyticsKeys.scene(scene))
                                ])
                            })
            } else if days.displayedIn(scene) >= 0 {
                Text(AppLocalization.format("%@摆着%@。点一样东西可以换。",
                                            piboSceneName(scene),
                                            piboFindName(days.displayedIn(scene))))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(AppLocalization.format("点一样找到的东西，可以摆到%@。", piboSceneName(scene)))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func diaryRow(_ entry: PiboDiaryEntry) -> some View {
        HStack(spacing: 8) {
            PixelCanvas(logicalWidth: PIXEL_FIND_SIZE, logicalHeight: PIXEL_FIND_SIZE,
                        revision: entry.item) { frame in
                frame.clear(.groundLight)
                drawPixelFind(frame, entry.item, 0, 0)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.format("第 %@ 天 · %@", "\(entry.dayCount)",
                                            piboDestinationName(entry.destination)))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.ink)
                Text(AppLocalization.format("你走到 %@ 步时，我带回了%@", "\(entry.steps)",
                                            piboFindName(entry.item)))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
