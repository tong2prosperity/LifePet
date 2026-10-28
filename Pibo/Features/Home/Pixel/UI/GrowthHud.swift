import SwiftUI

// Home's growth HUD (decision 057): level and experience, familiarity hearts, the badge's
// status bar (decision 062: one line of today's conclusion — the numbers are in the panel
// it opens), the `bo` balance and today's wishes. Every value is already a Core answer or
// a ledger value; the HUD only shows and routes taps.
//
// Ported from HarmonyPibo `pixel/ui/GrowthHud.ets`.

/// The lens colours of the stage's badge, by `PiboPixelActivity` (0 data unknown …
/// 6 celebrate). Taken from the stage's day palette: StoneDark, WaterDeep, Acorn,
/// LeafLight, Fire, EyeBag, Berry.
private let badgeColors: [Color] = [
    Color(pixelHex: 0x858F96), Color(pixelHex: 0x3D82B5), Color(pixelHex: 0xC98A4B),
    Color(pixelHex: 0x6FDCA8), Color(pixelHex: 0xFF9A3C), Color(pixelHex: 0xCDBFDB),
    Color(pixelHex: 0xD8485F),
]

func pixelBadgeColor(_ state: Int) -> Color {
    badgeColors.indices.contains(state) ? badgeColors[state] : badgeColors[0]
}

struct GrowthHud: View {
    var level = 1
    var levelProgress: Double = 0
    var xpIntoLevel = 0
    var xpForNext = 0
    var hearts = 0
    /// The Core state Pibo shows, the colour of the badge.
    var badgeState = 0
    /// Before season one's pod is fixed, the badge here is cracked too.
    var badgeCracked = false
    var readout = ""
    var boBalance = 0
    var hasRipeBo = false
    var wishesDone = 0
    var wishesTotal = 0
    var decorAvailable = false
    var onOpenGrowth: () -> Void = {}
    var onOpenWishes: () -> Void = {}
    var onOpenDecor: () -> Void = {}
    var onOpenReadout: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Lv.\(level)")
                    .font(PixelFont.font(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PixelUIColor.leaf)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    PixelBar(fraction: levelProgress, segments: 12, color: PixelUIColor.gold, barHeight: 9)
                        .frame(width: 96)
                    PixelHearts(hearts: hearts, iconSize: 9)
                }
            }
            .padding(6)
            .frame(minHeight: 48)
            .background(PixelUIColor.paper)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenGrowth)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("等级 \(level)，本级经验 \(xpIntoLevel)/\(xpForNext)，熟悉度 \(hearts) 颗心。打开成长")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("home-growth-entry")

            // Decision 062: the badge's status bar. One conclusion; the readings are a tap away.
            HStack(spacing: 6) {
                badge
                Text(readout)
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 8)
            .padding(.leading, -2)
            .background(PixelUIColor.paper)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle().fill(PixelUIColor.shadow).offset(x: 2, y: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenReadout)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("读数徽章：\(readout)。打开读数")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("home-badge-readout")

            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    chip(hasRipeBo ? PixelIcons.boRipe : PixelIcons.leaf, "bo \(boBalance)",
                         hasRipeBo ? PixelUIColor.gold : PixelUIColor.leaf,
                         hasRipeBo ? "头顶有成熟 bo 待收取；已有 \(boBalance) 枚 bo。打开装饰" : "已收取 \(boBalance) 枚 bo。打开装饰",
                         "home-decor-entry", onOpenDecor,
                         fill: hasRipeBo ? PixelUIColor.ripePaper : PixelUIColor.paper,
                         border: hasRipeBo ? PixelUIColor.ripeBorder : PixelUIColor.border)
                    if hasRipeBo || decorAvailable {
                        Rectangle()
                            .fill(hasRipeBo ? PixelUIColor.gold : PixelUIColor.heart)
                            .frame(width: 7, height: 7)
                            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
                            .offset(x: 3, y: -3)
                    }
                }
                if wishesTotal > 0 {
                    chip(PixelIcons.note, "\(wishesDone)/\(wishesTotal)", PixelUIColor.ink,
                         "今日小心愿完成 \(wishesDone)/\(wishesTotal)。打开心愿", "home-wishes-entry",
                         onOpenWishes)
                }
            }
        }
    }

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(pixelBadgeColor(badgeState))
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(.white)
                .frame(width: 3, height: 3)
            if badgeCracked {
                Rectangle()
                    .fill(PixelUIColor.border)
                    .frame(width: 2, height: 2)
                    .offset(x: 6, y: 2)
                Rectangle()
                    .fill(PixelUIColor.border)
                    .frame(width: 2, height: 2)
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 14, height: 14)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private func chip(_ icon: [String], _ value: String, _ color: Color, _ label: String,
                      _ chipID: String, _ action: @escaping () -> Void,
                      fill: Color = PixelUIColor.paper, border: Color = PixelUIColor.border) -> some View {
        HStack(spacing: 3) {
            PixelIcon(rows: icon, iconSize: 18)
            Text(value)
                .font(PixelFont.font(15))
                .foregroundStyle(color)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 12)
        .frame(minWidth: 72)
        .background(fill)
        .overlay(Rectangle().strokeBorder(border, lineWidth: 2))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 2, y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(chipID)
    }
}
