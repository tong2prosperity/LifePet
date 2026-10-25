import PiboCore
import SwiftUI
import UIKit

// The growth sheets (decision 057): 成长, 今日小心愿, 森林装饰, plus the level-up card.
// Everything they show is Core's answer or the ledger's balance — the sheets only word and
// lay it out.
//
// Ported from HarmonyPibo `pixel/ui/GrowthSheets.ets`. The newest print is shown here;
// PolaroidStore keeps each day's print reachable from the footprints.

/// Pibo at a given level, standing on a strip of grass — sheet hero art.
func paintPiboAtLevel(_ frame: PixelFrame, level: Int, happy: Bool) {
    frame.clear(.skyLow)
    frame.fillRect(0, Double(frame.height - 8), Double(frame.width), 8, .groundMid)
    frame.fillRect(0, Double(frame.height - 8), Double(frame.width), 1, .groundLight)
    let appearance = PiboCoreGrowth.appearance(level: level)
    let pose = PiboPixelPose()
    pose.bodyStage = appearance.bodyStage
    pose.leafStage = appearance.leafStage
    pose.accessoryMask = Int(appearance.accessoryMask)
    pose.leafGrowth = 1
    if happy {
        pose.eyes = .happy
        pose.blush = true
        pose.armsUp = true
    }
    drawPiboPixel(frame, (Double(frame.width) / 2).rounded(.down), Double(frame.height - 8), pose)
}

extension View {
    /// A sheet's paper: full width, paper colour, one heavier edge on top.
    func pixelSheetFrame() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(PixelUIColor.paper)
            .overlay(alignment: .top) {
                Rectangle().fill(PixelUIColor.border).frame(height: 3)
            }
            .lpDynamicTypeScaling()
    }
}

// MARK: - 成长

/// The current look, how far to the next level, today's sources and what is next.
struct GrowthSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var growth: GrowthStore
    var polaroids: PolaroidStore? = nil
    var onClose: () -> Void = {}
    var onOpenPolaroid: (PolaroidShot) -> Void = { _ in }
    var onOpenFootprints: (Double) -> Void = { _ in }

    private var next: GrowthPresentation.NextUnlock? {
        GrowthPresentation.nextUnlock(growth.level)
    }

    var body: some View {
        PixelReadingSheet(title: AppLocalization.text("Pibo 的成长"), onClose: onClose) {
            details
        }
    }

    @ViewBuilder
    private var overview: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                portrait
                statistics
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                portrait
                statistics
            }
        }
    }

    private var portrait: some View {
        PixelCanvas(logicalWidth: 56, logicalHeight: 60, revision: growth.level) { frame in
            paintPiboAtLevel(frame, level: growth.level, happy: false)
        }
        .frame(width: 112, height: 120)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lv.\(growth.level)")
                .font(PixelFont.font(24))
                .foregroundStyle(PixelUIColor.leaf)
            PixelBar(fraction: growth.levelProgress(), segments: 12,
                     color: PixelUIColor.gold, barHeight: 10)
            Text(AppLocalization.format("还差 %@ 经验升级",
                                        "\(max(0, growth.xpForNext - growth.xpIntoLevel))"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
            PixelHearts(hearts: growth.hearts, iconSize: 13)
            Text(AppLocalization.format("熟悉度：%@",
                                        GrowthPresentation.toneName(growth.tone)))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            overview

            Text(AppLocalization.text("今天叶子收到的能量"))
                .font(PixelFont.font(18))
                .foregroundStyle(PixelUIColor.ink)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            sourceRow(AppLocalization.text("睡眠"), growth.todaySplit.sleep, PixelUIColor.sleep)
            sourceRow(AppLocalization.text("步数"), growth.todaySplit.steps, PixelUIColor.steps)
            sourceRow(AppLocalization.text("活动"), growth.todaySplit.activity, PixelUIColor.activity)

            Text(AppLocalization.text("能量来自你真实的睡眠、步数和活动；拍拍、心愿、吃饭和聊天也会给一点经验，每天有上限。"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.format("Lv.%@ 会解锁", "\(next.level)"))
                        .font(PixelFont.font(18))
                        .foregroundStyle(PixelUIColor.ink)
                    ForEach(next.changes, id: \.self) { line in
                        HStack(spacing: 6) {
                            PixelIcon(rows: PixelIcons.lock, iconSize: 12)
                            Text(line)
                                .lpText(LP.Typography.b3Regular)
                                .foregroundStyle(PixelUIColor.inkSoft)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(10)
                .background(PixelUIColor.paperDim)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            }

            // Only the newest print lives here; every day's is in the footprints (决定 063).
            if let latest = polaroids?.latest, let image = UIImage(contentsOfFile: latest.fileURL.path) {
                Text(AppLocalization.text("森林拍立得"))
                    .font(PixelFont.font(18))
                    .foregroundStyle(PixelUIColor.ink)
                    .padding(.top, 16)
                    .padding(.bottom, 6)

                HStack(spacing: 10) {
                    Button {
                        onOpenPolaroid(latest)
                    } label: {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 60)
                            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    }
                    .accessibilityLabel(AppLocalization.format("%@ 的拍立得", latest.day))

                    Button {
                        onOpenFootprints(latest.takenAt)
                    } label: {
                        Text(AppLocalization.text("在足迹里翻看每一天 ›"))
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(PixelUIColor.leaf)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                    }
                    .accessibilityIdentifier("growth-open-footprints")
                }
            }
        }
    }

    private func sourceRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(label)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("+\(Int(value.rounded()))")
                .lpText(LP.Typography.b3Medium)
                .monospacedDigit()
                .foregroundStyle(PixelUIColor.ink)
        }
        .frame(minHeight: 36)
    }
}

// MARK: - 今日小心愿

/// Up to three small wishes, stamped when done. No streaks, no penalties.
struct WishSheet: View {
    var wishes: WishStore
    var localHour = 12
    var onClose: () -> Void = {}

    var body: some View {
        PixelReadingSheet(title: AppLocalization.text("今日小心愿"), onClose: onClose) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text("Pibo 每天会想要几件小事。做到了它会很开心，没做到也没关系。"))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)

                VStack(spacing: 10) {
                    ForEach(Array(wishes.visible(localHour: localHour).enumerated()), id: \.offset) { _, slot in
                        row(slot)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func row(_ slot: WishSlot) -> some View {
        if slot.kind == .answerPrompt && !slot.done {
            Button(action: onClose) { rowContent(slot) }.buttonStyle(.plain)
        } else {
            rowContent(slot)
        }
    }

    private func rowContent(_ slot: WishSlot) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(GrowthPresentation.wishTitle(slot))
                    .font(PixelFont.font(16))
                    .foregroundStyle(PixelUIColor.ink)
                PixelBar(fraction: slot.done ? 1 : slot.fraction, segments: 10,
                         color: slot.done ? PixelUIColor.leaf : PixelUIColor.gold, barHeight: 8)
                Text(GrowthPresentation.wishProgressText(slot))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if slot.done {
                Text(AppLocalization.text("已完成"))
                    .font(PixelFont.font(13))
                    .foregroundStyle(Color(pixelHex: 0xC8463A))
                    .padding(5)
                    .overlay(Rectangle().strokeBorder(Color(pixelHex: 0xC8463A), lineWidth: 2))
                    .rotationEffect(.degrees(-12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(slot.done ? Color(pixelHex: 0xEAF6EE) : PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 森林装饰

/// The Core catalog, gated by level and paid with collected `bo`.
struct DecorSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var decor: DecorStore
    var ornamentUnlocks: OrnamentUnlockStore
    var ledger: BoLedgerStore
    var level = 1
    var balance = 0
    var dayCount = 1
    var onClose: () -> Void = {}
    var onPurchase: (PiboCoreDecorID) -> Void = { _ in }

    @State private var hammockBusy = false
    @State private var hammockMessage = ""

    private var hammockCost: Int {
        PiboOrnament.all.first { $0.id == .hammock }?.cost ?? 0
    }

    var body: some View {
        PixelReadingSheet(title: AppLocalization.text("森林装饰"), onClose: onClose) {
            contents
        }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.format("手里有 %@ 枚 bo · 当前 Lv.%@", "\(balance)", "\(level)"))
                .font(PixelFont.font(13))
                .foregroundStyle(PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            if ledger.hasRipeBo || balance == 0 {
                PixelPanel(fill: ledger.hasRipeBo ? PixelUIColor.ripePaper : PixelUIColor.paperDim, inset: 8) {
                    Text(AppLocalization.text(ledger.hasRipeBo
                        ? "头顶有 1 枚已成熟的 bo，去森林往上一拉收取"
                        : "日常睡眠与活动会让头顶凝聚成 bo，成熟后上拉存入库存"))
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(PixelUIColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)
            }

            VStack(spacing: 10) {
                hammock
                // Grouped by the scene each piece stands in (decision 065).
                ForEach([0, 1, 2], id: \.self) { scene in
                    let items = inScene(scene)
                    if !items.isEmpty {
                        Text(AppLocalization.text(GrowthPresentation.decorSceneTitle(scene)))
                            .font(PixelFont.font(13))
                            .foregroundStyle(PixelUIColor.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 148), spacing: 10)],
                                  spacing: 10) {
                            ForEach(items, id: \.id) { item in
                                itemCell(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func inScene(_ scene: Int) -> [PiboCoreDecorDefinition] {
        decor.catalog().filter { PiboCoreDecor.scene($0.id) == scene }
    }

    private func stateLabel(_ item: PiboCoreDecorDefinition, _ state: PiboCoreDecorState) -> String {
        switch state {
        case .owned: return AppLocalization.text("已放置")
        case .levelLocked: return AppLocalization.format("Lv.%@ 解锁", "\(item.minLevel)")
        case .needsBo: return AppLocalization.format("需要 %@ bo", "\(item.cost)")
        case .purchasable: return AppLocalization.format("放置 · %@ bo", "\(item.cost)")
        }
    }

    private var hammock: some View {
        VStack(spacing: 6) {
            PixelCanvas(logicalWidth: 34, logicalHeight: 30,
                        revision: ornamentUnlocks.unlocked.count) { frame in
                frame.clear(.groundLight)
                drawPixelDecorAt(frame, .hammock, 2, 7, PixelDecorScene())
            }
            .frame(width: 82, height: 72)

            Text(AppLocalization.text("吊床"))
                .font(PixelFont.font(14))
                .foregroundStyle(PixelUIColor.ink)
            Text(AppLocalization.text("给 Pibo 一处休息落点，睡眠回顾无需购买"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if ornamentUnlocks.isUnlocked(.hammock) {
                PixelButton(label: hammockBusy
                                ? AppLocalization.text("正在保存…")
                                : AppLocalization.text(ornamentUnlocks.isHammockPlaced() ? "收起吊床" : "放置吊床"),
                            active: !hammockBusy,
                            buttonID: "decor-hammock-placement") {
                    changeHammock()
                }
            } else {
                PixelButton(label: hammockBusy
                                ? AppLocalization.text("正在保存…")
                                : AppLocalization.format("购买并放置 · %@ bo", "\(hammockCost)"),
                            active: !hammockBusy && balance >= hammockCost,
                            buttonID: "decor-buy-hammock") {
                    changeHammock()
                }
                if balance < hammockCost {
                    Text(AppLocalization.format("需要 %@ bo", "\(hammockCost)"))
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
            }
            if !hammockMessage.isEmpty {
                Text(hammockMessage)
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
    }

    private func itemCell(_ item: PiboCoreDecorDefinition) -> some View {
        let state = decor.state(item.id, level: level, balance: balance)
        return VStack(spacing: 6) {
            PixelCanvas(logicalWidth: 30, logicalHeight: 30,
                        revision: decor.revision + Int(item.id.rawValue) * 1000) { frame in
                frame.clear(.groundLight)
                // The catalog speaks Core ids; the art is keyed by the stage's.
                let art = PixelDecorID(rawValue: pixelDecorFromCore(Int(item.id.rawValue)))
                    ?? .mushroomStool
                let size = pixelDecorSize(art)
                var scene = PixelDecorScene()
                scene.flowers = 8
                scene.windmillSpeed = 1
                scene.moonLamp = 2
                scene.stones = 5
                scene.dayCount = dayCount
                scene.owned = [art.rawValue]
                drawPixelDecorAt(frame, art, (30 - size[0]) / 2, (30 - size[1]) / 2, scene)
            }
            .frame(width: 72, height: 72)
            .opacity(state == .levelLocked ? 0.45 : 1)

            Text(GrowthPresentation.decorName(item.id))
                .font(PixelFont.font(14))
                .foregroundStyle(PixelUIColor.ink)
            Text(GrowthPresentation.decorNote(item.id))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if state == .purchasable {
                PixelButton(label: stateLabel(item, .purchasable),
                            buttonID: "decor-buy-\(item.id.rawValue)") {
                    onPurchase(item.id)
                }
            } else {
                Text(stateLabel(item, state))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .frame(minHeight: 44)
            }
        }
        .padding(8)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func changeHammock() {
        guard !hammockBusy else { return }
        hammockBusy = true
        hammockMessage = ""
        defer { hammockBusy = false }
        if ornamentUnlocks.isUnlocked(.hammock) {
            ornamentUnlocks.setHammockPlaced(!ornamentUnlocks.isHammockPlaced())
        } else {
            let result = ornamentUnlocks.purchase(.hammock, using: ledger)
            switch result {
            case .purchased, .alreadyOwned:
                ornamentUnlocks.setHammockPlaced(true)
                hammockMessage = ""
            case .unavailable:
                hammockMessage = AppLocalization.text("暂时没能保存，请重试")
            case .insufficientBalance, .prerequisiteMissing:
                hammockMessage = AppLocalization.text("bo 还不够，等收取后再来看看")
            }
        }
    }
}

// MARK: - 拍立得

/// The evening print of the forest. Saved only on this phone; sharing goes through the
/// system share sheet, which also offers saving to Photos.
struct PolaroidCard: View {
    var shot: PolaroidShot
    var onClose: () -> Void = {}

    private var image: UIImage? {
        UIImage(contentsOfFile: shot.fileURL.path)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(AppLocalization.text("今天的森林"))
                .font(PixelFont.font(20))
                .foregroundStyle(PixelUIColor.leaf)

            if let image {
                // Contain inside a 4:5-ish frame, like the ArkTS `ImageFit.Contain`.
                Color.clear
                    .aspectRatio(0.92, contentMode: .fit)
                    .overlay {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                    }
                    .accessibilityLabel(AppLocalization.format("%@ 的森林拍立得", shot.day))
            } else {
                Rectangle()
                    .fill(PixelUIColor.paperDim)
                    .aspectRatio(0.92, contentMode: .fit)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            }

            Text(shot.day)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(PixelUIColor.inkSoft)
            if !shot.caption.isEmpty {
                Text("「\(shot.caption)」")
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                ShareLink(item: shot.fileURL) {
                    Text(AppLocalization.text("分享 / 保存"))
                        .font(PixelFont.font(14))
                        .foregroundStyle(PixelUIColor.ink)
                        .frame(minWidth: 72, minHeight: 40)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(PixelUIColor.paper)
                        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                }
                .accessibilityIdentifier("polaroid-share")
                PixelButton(label: AppLocalization.text("收好啦"), buttonID: "polaroid-close", onTap: onClose)
            }
        }
        .padding(18)
        .frame(width: 0.84 * UIScreen.main.bounds.width)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 3))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 4, y: 4)
        }
    }
}

// MARK: - Host

/// Which growth sheet is up. HarmonyOS keeps these as flags on `HomeOverlays`; iOS keeps
/// the pixel sheets in one local slot so the old SwiftUI sheet enum stays untouched.
enum PixelSheetKind: Equatable, Identifiable {
    case growth
    case wishes
    case decor
    /// Decision 058: the trail sign's map and the basket's shelf.
    case dayMap
    case shelf

    var id: String {
        switch self {
        case .growth: "pixel-growth"
        case .wishes: "pixel-wishes"
        case .decor: "pixel-decor"
        case .dayMap: "pixel-day-map"
        case .shelf: "pixel-shelf"
        }
    }
}

/// The bottom sheet over a scrim, as `HomePage.GrowthSheetHost` lays it out: a tap above
/// the sheet closes it, and the sheet itself sits on the paper frame.
struct PixelSheetHost: View {
    var kind: PixelSheetKind
    var growth: GrowthStore
    var wishes: WishStore
    var decor: DecorStore
    var ornaments: OrnamentUnlockStore
    var ledger: BoLedgerStore
    var dayCount = 1
    var localHour = 12
    /// Pibo's own day: the shelf, the diary and which scene is open.
    var days: PiboDayStore
    var day: HomeDayController?
    var season = 1
    var polaroids: PolaroidStore? = nil
    var onClose: () -> Void = {}
    var onOpenPolaroid: (PolaroidShot) -> Void = { _ in }
    /// The diary row hands the footprints the day it was written.
    var onOpenFootprints: (Double) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                PixelUIColor.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel(AppLocalization.text("关闭"))
                    .accessibilityAddTraits(.isButton)

                sheet
                    .frame(maxHeight: proxy.size.height * 0.86, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityIdentifier(kind.id)
        .onAppear { Analytics.track(.growthSheetOpen, screen: "home", ["trigger": .string(kind.id)]) }
    }

    @ViewBuilder
    private var sheet: some View {
        switch kind {
        case .growth:
            GrowthSheet(growth: growth, polaroids: polaroids, onClose: onClose,
                        onOpenPolaroid: onOpenPolaroid, onOpenFootprints: onOpenFootprints)
        case .wishes:
            WishSheet(wishes: wishes, localHour: localHour, onClose: onClose)
        case .dayMap:
            DayMapSheet(current: days.scene,
                        level: growth.level,
                        season: season,
                        minLevel: { scene in
                            day?.sceneMinLevel(PiboCoreDayScene(rawValue: Int32(scene)) ?? .clearing) ?? 1
                        },
                        isUnlocked: { scene in
                            day?.sceneUnlocked(PiboCoreDayScene(rawValue: Int32(scene)) ?? .clearing) ?? false
                        },
                        onClose: onClose,
                        onTravel: { scene in
                            // The map steps aside; Pibo walks out of the edge and the scene
                            // changes off-screen (决定 058).
                            onClose()
                            day?.travelTo(PiboCoreDayScene(rawValue: Int32(scene)) ?? .clearing)
                        })
        case .shelf:
            ShelfSheet(days: days,
                       scene: days.scene,
                       onClose: onClose,
                       onOpenFootprints: { milliseconds in onOpenFootprints(milliseconds / 1000) })
        case .decor:
            DecorSheet(decor: decor, ornamentUnlocks: ornaments, ledger: ledger,
                       level: growth.level, balance: ledger.availableBo, dayCount: dayCount,
                       onClose: onClose,
                       onPurchase: { id in
                           // Core gates the price and the level; a successful purchase puts
                           // the piece in the forest, so the sheet steps aside.
                           if decor.purchase(id, level: growth.level, ledger: ledger) {
                               growth.push(GrowthFeedbackEvent(kind: .decor, id: "", decor: Int(id.rawValue)))
                               onClose()
                           }
                       })
        }
    }
}

// MARK: - 升级

/// The level-up reveal: Pibo in its new look, what changed, and one line from Pibo.
struct LevelUpCard: View {
    var level = 1
    var line = ""
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Text(AppLocalization.format("Lv.%@！", "\(level)"))
                .font(PixelFont.font(28))
                .foregroundStyle(PixelUIColor.leaf)
                .accessibilityAddTraits(.isHeader)

            PixelCanvas(logicalWidth: 56, logicalHeight: 60, revision: level) { frame in
                paintPiboAtLevel(frame, level: level, happy: true)
            }
            .frame(width: 168, height: 180)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))

            ForEach(GrowthPresentation.levelUnlocks(level), id: \.self) { change in
                Text("★ \(change)")
                    .font(PixelFont.font(14))
                    .foregroundStyle(PixelUIColor.ink)
            }
            if !line.isEmpty {
                Text("「\(line)」")
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .multilineTextAlignment(.center)
            }
            PixelButton(label: AppLocalization.text("好耶"), buttonID: "level-up-close", onTap: onClose)
        }
        .padding(18)
        .frame(width: 0.84 * UIScreen.main.bounds.width)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 3))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 4, y: 4)
        }
    }
}
