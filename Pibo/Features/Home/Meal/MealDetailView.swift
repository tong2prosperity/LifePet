import SwiftUI
import UIKit

/// Moss Glass meal estimate. The photo is already saved before this opens; the
/// sheet presents processing, success, and retry states without blocking Home.
struct MealDetailView: View {
    let meal: MealType
    var onRecapture: (MealType) -> Void

    @Environment(HealthHistoryStore.self) private var history
    @Environment(FoodRecognitionService.self) private var recognizer
    @Environment(\.dismiss) private var dismiss
    @State private var retryFailed = false
    @State private var isEditing = false
    @State private var draftAnalysis: FoodAnalysis?

    private var photo: FoodPhoto? {
        _ = history.revision
        return history.foodPhoto(on: .now, mealType: meal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                PiboMossSheetHandle()
                    .frame(maxWidth: .infinity)

                if let photo {
                    mealHeader(photo)
                    Divider().overlay(PiboMoss.Color.hairline.opacity(0.52))
                    analysisSection(photo)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.m)
            .padding(.bottom, LP.Spacing.xxl)
        }
        .foregroundStyle(PiboMoss.Color.forestInk)
        .piboMossSheet(detents: [.fraction(0.90), .large])
    }

    private func mealHeader(_ photo: FoodPhoto) -> some View {
        HStack(spacing: LP.Spacing.l) {
            Group {
                if let image = displayImage(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(PiboMoss.Color.tertiaryInk)
                }
            }
            .frame(width: 92, height: 92)
            .background(PiboMoss.Color.raisedNeutral.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: PiboMoss.Radius.media))
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media)
                    .strokeBorder(PiboMoss.Color.hairline.opacity(0.62), lineWidth: 1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text("\(AppLocalization.text(meal.title)) · \(captureTime(photo))")
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)

                Text(mealIdentity(photo))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func analysisSection(_ photo: FoodPhoto) -> some View {
        if recognizer.isAnalyzing(photo.id) {
            processingState
        } else if let analysis = photo.analysis {
            successState(photo: photo, analysis: analysis)
        } else {
            retryState(photo)
        }
    }

    private var processingState: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            HStack(spacing: LP.Spacing.m) {
                ProgressView()
                    .tint(PiboMoss.Color.foundationTeal)
                    .controlSize(.large)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(PiboMoss.Color.foundationTeal.opacity(0.10)))

                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(AppLocalization.text("正在估算"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    Text(AppLocalization.text("正在估算，不用留在这里"))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
            }

            VStack(spacing: LP.Spacing.m) {
                PiboMossSkeletonBar(width: 136, height: 36)
                PiboMossSkeletonBar(width: 190, height: 14)
                HStack {
                    PiboMossSkeletonBar(width: 82)
                    Spacer()
                    PiboMossSkeletonBar(width: 82)
                    Spacer()
                    PiboMossSkeletonBar(width: 82)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LP.Spacing.m)

            Text(AppLocalization.text("识别到的食物"))
                .lpText(LP.Typography.b2Medium)

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack {
                        Circle()
                            .fill(PiboMoss.Color.hairline.opacity(0.52))
                            .frame(width: 36, height: 36)
                        PiboMossSkeletonBar(width: 142)
                        Spacer()
                        PiboMossSkeletonBar(width: 68)
                    }
                    .padding(.vertical, LP.Spacing.m)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(PiboMoss.Color.hairline.opacity(0.38))
                            .frame(height: 1)
                    }
                }
            }

            Text(AppLocalization.text("照片已经保存，稍后可以再来看。"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)

            PiboMossSecondaryButton(
                title: AppLocalization.text("关闭"),
                action: { dismiss() }
            )
        }
    }

    private func successState(photo: FoodPhoto, analysis: FoodAnalysis) -> some View {
        let displayed = isEditing ? (draftAnalysis ?? analysis) : analysis
        return VStack(alignment: .leading, spacing: LP.Spacing.l) {
            VStack(spacing: LP.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s) {
                    Text(AppLocalization.text("约"))
                        .lpText(LP.Typography.b2Regular)
                    Text("\(displayed.totalCalories)")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("kcal")
                        .lpText(LP.Typography.b2Medium)
                }
                .foregroundStyle(PiboMoss.Color.forestInk)

                Text(AppLocalization.text("照片估算值"))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
            }
            .frame(maxWidth: .infinity)

            macroRow(displayed)

            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.text("识别到的食物"))
                    .lpText(LP.Typography.b2Medium)
                    .padding(.bottom, LP.Spacing.s)

                ForEach(displayed.items.indices, id: \.self) { index in
                    if isEditing {
                        editableItemRow(index: index)
                    } else {
                        itemRow(displayed.items[index])
                    }
                }
            }

            Text(AppLocalization.text("结果根据照片估算，份量可以调整。"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)

            HStack(alignment: .top, spacing: LP.Spacing.m) {
                Image(systemName: "leaf")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PiboMoss.Color.foundationTeal)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(PiboMoss.Color.foundationTeal.opacity(0.10)))
                Text(piboObservation(displayed))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LP.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                    .fill(PiboMoss.Color.raisedNeutral.opacity(0.52))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                    .strokeBorder(PiboMoss.Color.hairline.opacity(0.52), lineWidth: 1)
            }

            VStack(spacing: LP.Spacing.s) {
                PiboMossPrimaryButton(
                    title: AppLocalization.text(isEditing ? "保存调整" : "完成"),
                    action: { isEditing ? saveDraft(photo: photo) : dismiss() }
                )
                PiboMossSecondaryButton(
                    title: AppLocalization.text(isEditing ? "取消" : "调整份量"),
                    action: {
                        if isEditing {
                            draftAnalysis = nil
                            isEditing = false
                        } else {
                            draftAnalysis = analysis
                            isEditing = true
                        }
                    }
                )
            }
        }
    }

    private func macroRow(_ analysis: FoodAnalysis) -> some View {
        HStack(spacing: LP.Spacing.s) {
            macroMetric(
                label: AppLocalization.text("蛋白质"),
                grams: analysis.proteinG,
                color: PiboMoss.Color.proteinBerry
            )
            macroMetric(
                label: AppLocalization.text("碳水"),
                grams: analysis.carbG,
                color: PiboMoss.Color.carbsAmber
            )
            macroMetric(
                label: AppLocalization.text("脂肪"),
                grams: analysis.fatG,
                color: PiboMoss.Color.fatBlue
            )
        }
    }

    private func macroMetric(label: String, grams: Double?, color: Color) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                Text(grams.map { "\(Int($0.rounded())) g" } ?? "—")
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: FoodItem) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Circle()
                .fill(PiboMoss.Color.foundationTeal.opacity(0.10))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }

            Text(item.name)
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)

            if let quantity = item.quantity, !quantity.isEmpty {
                Text(quantity)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
            }

            Spacer(minLength: LP.Spacing.s)

            Text(AppLocalization.format("约 %d kcal", item.calories))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
                .monospacedDigit()

            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PiboMoss.Color.foundationTeal)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LP.Spacing.m)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PiboMoss.Color.hairline.opacity(0.42)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func editableItemRow(index: Int) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Text(draftAnalysis?.items[safe: index]?.name ?? "")
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(AppLocalization.text("份量"), text: quantityBinding(index))
                .textFieldStyle(.plain)
                .lpText(LP.Typography.b4Regular)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .padding(.horizontal, LP.Spacing.s)
                .frame(minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                        .fill(PiboMoss.Color.raisedNeutral.opacity(0.64))
                )

            TextField(AppLocalization.text("热量"), text: caloriesBinding(index))
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .lpText(LP.Typography.b4Regular)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .padding(.horizontal, LP.Spacing.s)
                .frame(minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                        .fill(PiboMoss.Color.raisedNeutral.opacity(0.64))
                )
        }
        .padding(.vertical, LP.Spacing.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PiboMoss.Color.hairline.opacity(0.42)).frame(height: 1)
        }
    }

    private func retryState(_ photo: FoodPhoto) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xl) {
            HStack(alignment: .top, spacing: LP.Spacing.l) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(LP.Fill.foundationError.opacity(0.78))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Text(AppLocalization.text("这次没有算出来"))
                        .lpText(LP.Typography.uiH5)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    Text(AppLocalization.text(
                        retryFailed
                            ? "重新估算仍未完成，照片已经保留。"
                            : "照片已经保留，你可以直接用这张照片重试。"
                    ))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(AppLocalization.text("已保存的照片与餐食"))
                .lpText(LP.Typography.b2Medium)

            HStack(spacing: LP.Spacing.m) {
                if let image = displayImage(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: PiboMoss.Radius.control))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(mealIdentity(photo))
                        .lpText(LP.Typography.b3Medium)
                    Text("\(AppLocalization.text(meal.title)) · \(captureTime(photo))")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                    Text(AppLocalization.text("照片已保存，稍后可以继续识别估算。"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
            }

            VStack(spacing: LP.Spacing.s) {
                PiboMossPrimaryButton(
                    title: AppLocalization.text("用这张照片重试"),
                    action: { retry(photo) }
                )
                PiboMossSecondaryButton(
                    title: AppLocalization.text("重新拍摄"),
                    action: recapture
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LP.Spacing.l) {
            PiboMossSheetHandle()
            Image(systemName: meal.symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(PiboMoss.Color.foundationTeal)
            Text(AppLocalization.text("还没有这一餐的照片"))
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(PiboMoss.Color.forestInk)
            PiboMossPrimaryButton(
                title: AppLocalization.text("拍摄这一餐"),
                action: recapture
            )
            PiboMossSecondaryButton(
                title: AppLocalization.text("关闭"),
                action: { dismiss() }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func retry(_ photo: FoodPhoto) {
        retryFailed = false
        Task { @MainActor in
            let succeeded = await recognizer.retry(
                photo: photo,
                meal: meal,
                history: history
            )
            retryFailed = !succeeded
        }
    }

    private func recapture() {
        LPHaptics.tap()
        dismiss()
        onRecapture(meal)
    }

    private func saveDraft(photo: FoodPhoto) {
        guard var draftAnalysis else { return }
        if !draftAnalysis.items.isEmpty {
            draftAnalysis.totalCalories = draftAnalysis.items.reduce(0) { $0 + $1.calories }
        }
        guard let data = try? JSONEncoder().encode(draftAnalysis) else { return }
        history.updateFoodPhoto(id: photo.id) { record in
            record.totalCalories = draftAnalysis.totalCalories
            record.dishName = draftAnalysis.dishName
            record.analysisJSON = data
        }
        self.draftAnalysis = nil
        isEditing = false
        LPHaptics.success()
    }

    private func quantityBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draftAnalysis?.items[safe: index]?.quantity ?? "" },
            set: { value in
                updateDraftItem(index) { $0.quantity = value.isEmpty ? nil : value }
            }
        )
    }

    private func caloriesBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draftAnalysis?.items[safe: index].map { String($0.calories) } ?? "" },
            set: { value in
                guard let calories = Int(value.filter(\.isNumber)) else { return }
                updateDraftItem(index) { $0.calories = calories }
            }
        )
    }

    private func updateDraftItem(_ index: Int, update: (inout FoodItem) -> Void) {
        guard var draftAnalysis, draftAnalysis.items.indices.contains(index) else { return }
        update(&draftAnalysis.items[index])
        self.draftAnalysis = draftAnalysis
    }

    private func displayImage(_ photo: FoodPhoto) -> UIImage? {
        UIImage(data: photo.sourceJPEGData ?? photo.pngData)
    }

    private func mealIdentity(_ photo: FoodPhoto) -> String {
        if let dishName = photo.dishName, !dishName.isEmpty { return dishName }
        if let subjectLabel = photo.subjectLabel, !subjectLabel.isEmpty { return subjectLabel }
        return AppLocalization.text("已保存的餐食")
    }

    private func captureTime(_ photo: FoodPhoto) -> String {
        photo.capturedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(AppLanguage.current.locale)
        )
    }

    private func piboObservation(_ analysis: FoodAnalysis) -> String {
        if let observation = analysis.piboObservation?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !observation.isEmpty {
            return observation
        }
        let names = analysis.items.prefix(3).map(\.name).filter { !$0.isEmpty }
        let subject = names.isEmpty ? analysis.dishName : names.joined(separator: "、")
        return AppLocalization.format("我看见了%@。", subject)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
