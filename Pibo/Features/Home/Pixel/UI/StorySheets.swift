import SwiftUI

// Season one's paper (decision 059): the report Pibo sent home and the letters that came
// back, on ruled pixel paper. The words come from the story copy; this only lays them out.
//
// Ported from HarmonyPibo `pixel/ui/StorySheets.ets`.

private let storyRuleColor = Color(pixelHex: 0xD9CBB2)

/// The report, a letter, or the old notebook's crossed-out guesses about Earth.
struct StoryPaperSheet: View {
    var title = ""
    var lines: [String] = []
    var signature = ""
    /// The letter's seal or the rolled report, drawn at the top.
    var letter = true
    /// A find drawn at the top instead (the old notebook); −1 uses `letter`.
    var icon = -1
    /// Lines drawn crossed out.
    var struck: [Int] = []
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                PixelCanvas(logicalWidth: PIXEL_FIND_SIZE + 2,
                            logicalHeight: PIXEL_FIND_SIZE + 2,
                            revision: icon >= 0 ? 10 + icon : (letter ? 1 : 2)) { frame in
                    frame.clear(.clear)
                    drawPixelFind(frame,
                                  icon >= 0 ? icon : (letter ? PIXEL_STORY_LETTER : PIXEL_STORY_REPORT),
                                  1, 1)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

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
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(PixelFont.font(14))
                        .foregroundStyle(struck.contains(index) ? PixelUIColor.inkSoft : PixelUIColor.ink)
                        .strikethrough(struck.contains(index))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(storyRuleColor).frame(height: 2)
                        }
                }
                Text(signature)
                    .font(PixelFont.font(14))
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .background(PixelUIColor.paperDim)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .accessibilityElement(children: .combine)
        }
        .pixelSheetFrame()
    }
}

/// The scrim and bottom sheet, laid out like `PixelSheetHost`.
struct StoryPaperHost: View {
    var page: PiboStoryPaper
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            PixelUIColor.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel(AppLocalization.text("关闭"))
                .accessibilityAddTraits(.isButton)

            StoryPaperSheet(title: page.title,
                            lines: page.lines,
                            signature: page.signature,
                            letter: page.letter,
                            icon: page.icon,
                            struck: page.struck,
                            onClose: onClose)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .accessibilityIdentifier("pixel-story-paper")
    }
}
