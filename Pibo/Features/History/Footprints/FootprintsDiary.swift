import SwiftUI

/// 「Pibo 写的」: the upper half of a footprints page (决定 063). Only what really happened
/// that day is listed; Pibo's sentences carry no numbers, facts sit in the small print.
///
/// Ported from HarmonyPibo `pixel/ui/FootprintsDiary.ets`.
struct FootprintsDiary: View {
    var items: [FootprintsDiaryItem] = []
    var onOpenReadout: () -> Void = {}
    var onOpenMeal: (_ photoID: String, _ mealTypeRaw: String) -> Void = { _, _ in }
    var onOpenPolaroid: (_ path: String) -> Void = { _ in }

    private var lines: [FootprintsDiaryItem] {
        items.filter { $0.kind != .meal && $0.kind != .polaroid }
    }

    private var meals: [FootprintsDiaryItem] {
        items.filter { $0.kind == .meal }
    }

    private var polaroid: FootprintsDiaryItem? {
        items.first { $0.kind == .polaroid }
    }

    private func lineText(_ item: FootprintsDiaryItem) -> String {
        if item.kind == .walk {
            return AppLocalization.format("我去了%@，带回了%@。", item.line, item.note)
        }
        return AppLocalization.text(item.line)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PixelIcon(rows: PixelIcons.note, iconSize: 14)
                Text(AppLocalization.text("Pibo 写的"))
                    .font(PixelFont.font(15))
                    .foregroundStyle(PixelUIColor.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)

            if items.isEmpty {
                Text(AppLocalization.text(FOOTPRINTS_EMPTY_LINE))
                    .font(.system(size: 13))
                    .foregroundStyle(PixelUIColor.inkSoft)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(lines) { item in
                    line(item)
                }
                if !meals.isEmpty { samples }
                if let polaroid { polaroidRow(polaroid) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
        }
    }

    // MARK: Rows

    private func label(_ kind: FootprintsDiaryKind) -> some View {
        HStack(spacing: 4) {
            if kind == .first {
                PixelIcon(rows: PixelIcons.star, iconSize: 10)
            }
            Text(AppLocalization.text(footprintsKindTitle(kind)))
                .font(PixelFont.font(12))
                .foregroundStyle(PixelUIColor.leaf)
        }
    }

    private func line(_ item: FootprintsDiaryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if item.kind == .walk {
                PixelCanvas(logicalWidth: PIXEL_FIND_SIZE, logicalHeight: PIXEL_FIND_SIZE,
                            revision: item.item) { frame in
                    frame.clear(.groundLight)
                    drawPixelFind(frame, item.item, 0, 0)
                }
                .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                label(item.kind)
                Text(lineText(item))
                    .font(.system(size: 14))
                    .foregroundStyle(PixelUIColor.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.kind == .walk {
                    Text(AppLocalization.format("你走到 %@ 步时", "\(item.steps)"))
                        .font(.system(size: 11))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.kind == .readout {
                Text("›")
                    .font(PixelFont.font(18))
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            DashedLine()
                .stroke(PixelUIColor.paperDim, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.kind == .readout { onOpenReadout() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(item.kind == .readout ? .isButton : .isStaticText)
        .accessibilityLabel(
            "\(AppLocalization.text(footprintsKindTitle(item.kind)))：\(lineText(item))")
    }

    private var samples: some View {
        VStack(alignment: .leading, spacing: 6) {
            label(.meal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                        VStack(spacing: 4) {
                            ZStack {
                                if let data = meal.pngData, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .padding(4)
                                } else {
                                    Text(meal.glyph)
                                        .font(.system(size: 34))
                                }
                            }
                            .frame(width: 72, height: 72)
                            .background(Color.white)
                            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                            .background(alignment: .bottomTrailing) {
                                Rectangle().fill(PixelUIColor.shadow).offset(x: 2, y: 2)
                            }
                            .rotationEffect(.degrees(index % 2 == 0 ? -2 : 2))
                            Text("No.\(meal.sample)")
                                .font(PixelFont.font(12))
                                .foregroundStyle(PixelUIColor.ink)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenMeal(meal.ref, meal.mealTypeRaw) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(AppLocalization.format(
                            "地球食物样本 No.%@%@", "\(meal.sample)",
                            meal.note.isEmpty ? "" : "，\(meal.note)"))
                        .accessibilityHint(AppLocalization.text("双击查看餐食详情"))
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func polaroidRow(_ shot: FootprintsDiaryItem) -> some View {
        HStack(spacing: 10) {
            if let image = UIImage(contentsOfFile: shot.imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 72, height: 78)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    .rotationEffect(.degrees(2))
            }
            VStack(alignment: .leading, spacing: 3) {
                label(.polaroid)
                if !shot.line.isEmpty {
                    Text("「\(shot.line)」")
                        .font(.system(size: 13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpenPolaroid(shot.ref) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(AppLocalization.text("这一天的森林拍立得"))
    }
}

/// A 1 px rule under a diary line, dashed like a notebook's cut line.
private struct DashedLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
