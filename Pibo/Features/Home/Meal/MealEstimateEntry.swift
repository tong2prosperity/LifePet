import SwiftUI

/// The few seconds after a meal is confirmed: a pixel tag saying which sample it became, with
/// a way into its page. Shown after the forest's specimen card, never on top of it.
/// Ported from HarmonyPibo `components/MealEstimateEntry.ets`.
struct MealEstimateEntry: View {
    let history: HealthHistoryStore
    var mealTypeRaw: String = ""
    var photoId: String = ""
    var onOpen: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var photo: FoodPhoto? {
        if !photoId.isEmpty, let uuid = UUID(uuidString: photoId) {
            return history.foodPhoto(uuid)
        }
        return history.foodPhoto(on: .now, mealType: MealType(rawValue: mealTypeRaw) ?? .lunch)
            ?? history.foodPhotos(on: .now).last
    }

    private func headline(_ photo: FoodPhoto) -> String {
        let sample = history.foodSampleNumber(photo.id)
        return sample > 0 ? AppLocalization.format("No.%@ 收进样本册了", "\(sample)")
            : AppLocalization.text("收进样本册了")
    }

    private func detail(_ photo: FoodPhoto) -> String {
        let dish = photo.analysis?.dishName ?? photo.subjectLabel ?? ""
        let meal = AppLocalization.text(MealType(rawValue: mealTypeRaw)?.title ?? "这一餐")
        return !dish.isEmpty ? "\(meal) · \(dish)" : meal
    }

    var body: some View {
        if let photo {
            HStack(spacing: 10) {
                ZStack {
                    if let uiImage = UIImage(data: photo.pngData) {
                        Image(uiImage: uiImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    } else {
                        Text("🍽️")
                            .font(.system(size: 24))
                    }
                }
                .frame(width: 48, height: 48)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                .rotationEffect(.degrees(-3))

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(photo))
                        .font(PixelFont.font(14))
                        .foregroundStyle(PixelUIColor.ink)
                    Text(detail(photo))
                        .font(.system(size: 12))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(AppLocalization.text("看看 ›"))
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.leaf)

                Button(action: onDismiss) {
                    Text("×")
                        .font(PixelFont.font(18))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(AppLocalization.text("关闭"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(PixelUIColor.paper)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(headline(photo))，\(detail(photo))")
            .accessibilityHint(AppLocalization.text("双击查看这一餐"))
        }
    }
}
