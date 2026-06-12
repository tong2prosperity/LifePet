import SwiftUI
import UIKit

/// 今日记录 card — the day's food photos (camera captures, background-removed via
/// `SubjectCutout`) pinned to a ruled paper texture (Figma `food list` 1374:2255 +
/// `paper texture` 1397:3929). Each photo floats on a white polaroid with a slight
/// tilt and its capture time above it.
struct HistoryFoodCard: View {
    let foods: [FoodPhoto]

    var body: some View {
        HistoryCard(title: "今日记录", background: { PaperTexture() }) {
            Group {
                if foods.isEmpty {
                    emptyState
                } else {
                    foodScroll
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.top, LP.Spacing.m)
            .padding(.bottom, LP.Spacing.l)
        }
    }

    private var foodScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(foods.enumerated()), id: \.element.id) { idx, food in
                    foodCard(food, tilt: idx.isMultiple(of: 2) ? -2 : 2)
                }
            }
        }
    }

    private func foodCard(_ food: FoodPhoto, tilt: Double) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(food.timeLabel)
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.tertiary)
                .padding(.leading, LP.Spacing.s)
            photo(food)
                .rotationEffect(.degrees(tilt))
        }
        .frame(width: 120)
    }

    private func photo(_ food: FoodPhoto) -> some View {
        Group {
            if let ui = UIImage(data: food.pngData) {
                Image(uiImage: ui).resizable().scaledToFit().padding(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(LP.Content.quarternary)
            }
        }
        .frame(width: 120, height: 120)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
        .lpShadow(LP.Shadow.elevation1)
    }

    private var emptyState: some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: "camera")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(LP.Content.tertiary)
            Text(AppLocalization.text("还没有记录，用露珠相机拍一张吧"))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.45)))
    }
}

/// Ruled-paper backdrop for the 今日记录 card — grey-200 with faint horizontal
/// rules (Figma `paper texture` 1397:3929).
private struct PaperTexture: View {
    var body: some View {
        LP.Neutral.grey200.overlay {
            GeometryReader { geo in
                let count = max(1, Int(geo.size.height / 40))
                VStack(spacing: 40) {
                    ForEach(0..<count, id: \.self) { _ in
                        Rectangle().fill(LP.Colorful.blue200.opacity(0.5)).frame(height: 1)
                    }
                }
                .padding(.top, 40)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }
}
