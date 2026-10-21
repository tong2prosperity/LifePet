import SwiftUI

// The pixel UI kit for Home and its sheets: square corners, 2 px ink borders and a hard
// offset shadow instead of glass and blur, so the chrome sits in the same world as the
// stage.
//
// Ported from HarmonyPibo `pixel/ui/PixelUI.ets`. Icons are stamped with the stage's own
// palette through `PixelCanvas`, so a moon in a sheet and a moon in the sky are the same
// inks.

enum PixelUIColor {
    static let paper = Color(pixelHex: 0xFFF8EC)
    static let paperDim = Color(pixelHex: 0xF1E6D2)
    static let ink = Color(pixelHex: 0x2E3B45)
    static let inkSoft = Color(pixelHex: 0x5E6B73)
    static let border = Color(pixelHex: 0x2E3B45)
    static let shadow = Color(pixelHex: 0x2E3B45).opacity(0.35)
    static let leaf = Color(pixelHex: 0x20937A)
    static let leafLight = Color(pixelHex: 0x6FDCA8)
    static let gold = Color(pixelHex: 0xF5B94A)
    static let heart = Color(pixelHex: 0xF27A9A)
    static let sleep = Color(pixelHex: 0x6C8FD9)
    static let steps = Color(pixelHex: 0x3FA66B)
    static let activity = Color(pixelHex: 0xF0883E)
    static let scrim = Color(pixelHex: 0x1A2026).opacity(0.55)
    static let warn = Color(pixelHex: 0xD8485F)
    static let off = Color(pixelHex: 0xB9C0C4)
    /// The empty half of a segmented bar.
    static let track = Color(pixelHex: 0x2E3B45).opacity(0.10)
}

extension Color {
    /// The stage's inks are written as `#RRGGBB` in the ArkTS kit; this keeps them
    /// copy-pasteable here. Named to stay out of the design system's own hex initialiser.
    init(pixelHex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((pixelHex >> 16) & 0xFF) / 255,
                  green: Double((pixelHex >> 8) & 0xFF) / 255,
                  blue: Double(pixelHex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum PixelIcons {
    static let moon = ["..KKK.", ".KK...", "KK....", "KK....", ".KK...", "..KKK."]
    static let foot = [".gg.g", "gggg.", "gggg.", ".gg..", ".gg..", "..g.."]
    static let flame = ["..x...", "..xx..", ".xxXx.", "xxXXxx", "xXXXXx", ".xxxx."]
    static let leaf = ["....gg", "..gglg", ".gglgg", "gglgg.", "glgg..", "G....."]
    static let note = ["dddddd", "djjjjd", "dJJJjd", "djjjjd", "dJJjjd", "dddddd"]
    static let heart = [".b.b.", "bbbbb", "bbbbb", ".bbb.", "..b.."]
    static let heartEmpty = [".a.a.", "a.a.a", "a...a", ".a.a.", "..a.."]
    static let drop = ["..W..", ".WzW.", "WzZzW", "WzzzW", ".WWW."]
    static let cycle = [".....ee..", "...eee...", "..e..e...", ".eee.eee.", "e.e.e.e.e", ".e...e..."]
    static let swim = ["......ee.", "......ee.", "..eeeee..", ".........", "z.zz.zz.z", ".z..z..z."]
    static let star = ["..K..", ".KKK.", "KKKKK", ".KKK.", ".K.K."]
    static let lock = [".QQQ.", "Q...Q", "QQQQQ", "QqQqQ", "QQQQQ"]
    static let camera = ["..eee....", "eeeeeeeee", "e.......e", "e..eee..e", "e.e...e.e",
                         "e.e...e.e", "e..eee..e", "e.......e", "eeeeeeeee"]
    static let gear = ["..e.e.e..", ".eeeeeee.", "eee...eee", ".e.....e.", "ee..e..ee",
                       ".e.....e.", "eee...eee", ".eeeeeee.", "..e.e.e.."]
    static let footprints = ["GG.......", "GGG......", "GGG...GG.", ".GG..GGG.", ".....GGG.",
                             "GG...GG..", "GGG......", "GGG......", ".G......."]
    static let walk = ["....ee...", "....ee...", "...eee...", "..e.ee...", "....eee..",
                       "...e..e..", "..e...e..", "..e....e.", "........."]
    static let games = [".........", ".eeeeeee.", "ee.eee.ee", "e...e.e.e", "ee.eeeeee",
                        "eeeeee.ee", ".eeeeeee.", ".........", "........."]
    static let sunrise = [".........", "....u....", ".u.....u.", "...uuu...", "..uuuuu..", ".uuuuuuu.",
                          "eeeeeeeee", ".........", "........."]
    static let sun = ["....u....", ".u.....u.", "...uuu...", "..uuuuu..", "u.uuuuu.u", "..uuuuu..",
                      "...uuu...", ".u.....u.", "....u...."]
    static let night = ["...KKK...", "..KK.....", ".KK....u.", ".KK......", ".KK......", ".KK......",
                        "..KK.....", "...KKK...", "........."]
    static let wrench = [".....QQ..", "....Q..Q.", "....Q..Q.", "...QQQQ..", "..QQQ....", ".QQQ.....",
                         "QQQ......", "QQ.......", "........."]
    static let bell = ["....K....", "...KKK...", "..KKKKK..", "..KKKKK..", "..KKKKK..", ".KKKKKKK.",
                       "KKKKKKKKK", "....e....", "........."]
    static let doc = [".eeeee...", ".e...ee..", ".e.....e.", ".e.ddd.e.", ".e.....e.", ".e.ddd.e.",
                      ".e.....e.", ".eeeeeee.", "........."]
    static let phone = ["..eeeee..", "..e...e..", "..e...e..", "..e...e..", "..e...e..", "..e...e..",
                        "..eeeee..", "..ee.ee..", "..eeeee.."]
    static let speaker = [".........", "....e..x.", "...ee...x", "eeeee.x.x", "eeeee.x.x", "eeeee.x.x",
                          "...ee...x", "....e..x.", "........."]
    static let pulse = [".........", ".bb...bb.", "bbbb.bbbb", "bbbbbbbbb", "bbbbbbbbb", ".bbbbbbb.",
                        "..bbbbb..", "...bbb...", "....b...."]
    static let antenna = ["....x....", "...xXx...", "....e....", "....e....", "...eee...", "..e.e.e..",
                          ".e..e..e.", "....e....", "...eee..."]
}

/// A small stamp icon drawn with the stage palette.
struct PixelIcon: View {
    var rows: [String]
    var iconSize: CGFloat = 18

    var body: some View {
        PixelCanvas(logicalWidth: max(1, rows.first?.count ?? 1),
                    logicalHeight: max(1, rows.count),
                    revision: rows.joined(separator: "|").count) { frame in
            frame.stamp(rows, 0, 0)
        }
        .frame(width: iconSize, height: iconSize)
        .accessibilityHidden(true)
    }
}

/// A paper panel: 2 px border, hard shadow, square corners.
struct PixelPanel<Content: View>: View {
    var fill: Color = PixelUIColor.paper
    var inset: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(inset)
            .background(fill)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(PixelUIColor.shadow)
                    .offset(x: 3, y: 3)
            }
    }
}

/// Body text in the pixel face.
struct PixelText: View {
    var text: String
    var textSize: CGFloat = 13
    var color: Color = PixelUIColor.ink

    var body: some View {
        Text(text)
            .font(PixelFont.font(textSize))
            .foregroundStyle(color)
    }
}

struct PixelButton: View {
    var label: String
    var primary = true
    var active = true
    var buttonID = ""
    var onTap: () -> Void = {}
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(PixelFont.font(14))
            .foregroundStyle(primary && active ? Color.white : PixelUIColor.ink)
            .multilineTextAlignment(.center)
            .frame(minWidth: 72, minHeight: 40)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(!active ? PixelUIColor.paperDim : (primary ? PixelUIColor.leaf : PixelUIColor.paper))
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(PixelUIColor.shadow)
                    .offset(x: pressed ? 0 : 2, y: pressed ? 0 : 2)
            }
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .opacity(active ? 1 : 0.6)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
                if active { onTap() }
            } onPressingChanged: { pressing in
                guard active else { return }
                pressed = pressing
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityIdentifier(buttonID)
    }
}

/// A segmented progress bar: whole blocks only, like a game HUD.
struct PixelBar: View {
    var fraction: Double = 0
    var segments = 10
    var color: Color = PixelUIColor.leaf
    var barHeight: CGFloat = 8

    private var filled: Int {
        Int((max(0, min(1, fraction)) * Double(segments) + 0.0001).rounded(.down))
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<max(1, segments), id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : PixelUIColor.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight - 4)
            }
        }
        .frame(height: barHeight)
        .padding(1)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
        .background(PixelUIColor.paper)
        .accessibilityHidden(true)
    }
}

struct PixelHearts: View {
    var hearts = 0
    var maxHearts = 10
    var iconSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<max(1, maxHearts), id: \.self) { index in
                PixelIcon(rows: index < hearts ? PixelIcons.heart : PixelIcons.heartEmpty,
                          iconSize: iconSize)
            }
        }
    }
}

/// A pixel sheet's title row with a close ×.
struct PixelSheetTitle: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(PixelFont.font(18))
                .foregroundStyle(PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("×")
                .font(PixelFont.font(20))
                .foregroundStyle(PixelUIColor.ink)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel(AppLocalization.text("关闭"))
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// A pixel lever: a lit green lamp when on, grey when off. Reads as a switch.
struct PixelSwitch: View {
    var isOn = false
    var label = ""
    var switchID = ""
    var active = true
    var onChange: (Bool) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            HStack(spacing: 3) {
                Rectangle()
                    .fill(isOn ? PixelUIColor.leafLight : PixelUIColor.off)
                    .frame(width: 6, height: 6)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)

            Rectangle()
                .fill(isOn ? PixelUIColor.paper : PixelUIColor.inkSoft)
                .frame(width: 18, height: 18)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                .padding(2)
        }
        .frame(width: 52, height: 26)
        .background(isOn ? PixelUIColor.leaf : PixelUIColor.paperDim)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 2, y: 2)
        }
        .opacity(active ? 1 : 0.6)
        .contentShape(Rectangle().inset(by: -10))
        .onTapGesture {
            guard active else { return }
            onChange(!isOn)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityLabel(label)
        .accessibilityIdentifier(switchID)
    }
}
