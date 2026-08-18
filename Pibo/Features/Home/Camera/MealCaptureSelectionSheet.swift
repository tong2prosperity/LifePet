import SwiftUI

/// First step of meal capture. It deliberately lives in a native Half-sheet so
/// the forest remains the spatial context; the full-screen camera opens only
/// after the user has chosen a meal.
struct MealCaptureSelectionSheet: View {
    let onSelect: (MealType) -> Void

    private var suggestedMeal: MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<10: .breakfast
        case 10..<16: .lunch
        default: .dinner
        }
    }

    var body: some View {
        VStack(spacing: LP.Spacing.xl) {
            PiboMossSheetHandle()

            VStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text("这张照片属于哪一餐？"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(AppLocalization.format(
                    "当前时段建议%@",
                    AppLocalization.text(suggestedMeal.title)
                ))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
            }

            VStack(spacing: LP.Spacing.m) {
                ForEach(MealType.allCases) { meal in
                    mealRow(meal)
                }
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.m)
        .padding(.bottom, LP.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .piboMossSheet(detents: [.fraction(0.58)])
    }

    private func mealRow(_ meal: MealType) -> some View {
        let suggested = meal == suggestedMeal
        return Button {
            LPHaptics.tap()
            onSelect(meal)
        } label: {
            HStack(spacing: LP.Spacing.l) {
                Image(systemName: meal.symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(PiboMoss.Color.foundationTeal.opacity(suggested ? 0.16 : 0.08))
                    )

                Text(AppLocalization.text(meal.title))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(PiboMoss.Color.forestInk)

                if suggested {
                    Text(AppLocalization.text("当前建议"))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }

                Spacer(minLength: LP.Spacing.s)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(suggested
                                     ? PiboMoss.Color.foundationTeal
                                     : PiboMoss.Color.tertiaryInk)
            }
            .padding(.horizontal, LP.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .fill(PiboMoss.Color.raisedNeutral.opacity(suggested ? 0.70 : 0.52))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .strokeBorder(
                        suggested
                            ? PiboMoss.Color.foundationTeal.opacity(0.78)
                            : Color.white.opacity(0.46),
                        lineWidth: suggested ? 1.25 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(meal.title))
        .accessibilityHint(suggested ? AppLocalization.text("当前时段建议") : "")
    }
}
