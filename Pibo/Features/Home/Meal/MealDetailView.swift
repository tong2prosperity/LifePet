import SwiftUI
import UIKit

/// One meal sample's page (决定 063): the sticker pinned on Pibo's specimen card, what Pibo
/// noticed, then your estimate.
/// Ported from HarmonyPibo `components/MealDetailView.ets`.
struct MealDetailView: View {
    var meal: MealType = .lunch
    var photoId: String = ""
    var mealTypeRaw: String = ""
    var onClose: (() -> Void)? = nil
    var onRecapture: (MealType) -> Void = { _ in }

    @Environment(HealthHistoryStore.self) private var history
    @Environment(FoodRecognitionService.self) private var recognizer: FoodRecognitionService?
    @Environment(\.dismiss) private var dismiss
    @State private var retryFailed = false
    @State private var isEditing = false
    @State private var draftAnalysis: FoodAnalysis?
    @State private var metadata: MealMetadataDraft?
    @State private var metadataSaveFailed = false

    private var requestedMeal: MealType {
        if !mealTypeRaw.isEmpty, let matched = MealType(rawValue: mealTypeRaw) {
            return matched
        }
        return meal
    }

    private var effectiveMeal: MealType { photo?.meal ?? requestedMeal }

    private var photo: FoodPhoto? {
        _ = history.revision
        if let id = metadata?.photoID { return history.foodPhoto(id) }
        if !photoId.isEmpty, let uuid = UUID(uuidString: photoId) {
            return history.foodPhoto(uuid)
        }
        return history.foodPhoto(on: .now, mealType: requestedMeal)
    }

    private func sampleNumber(_ photo: FoodPhoto) -> Int {
        photo.analysis?.isFood == false ? 0 : history.foodSampleNumber(photo.id)
    }

    private func titleString(_ photo: FoodPhoto?) -> String {
        guard let photo else { return AppLocalization.text("这一餐") }
        let sample = sampleNumber(photo)
        return sample > 0 ? AppLocalization.format("地球食物样本 No.%@", "\(sample)")
            : AppLocalization.text("这一餐")
    }

    private func handleClose() {
        // The close control discards local drafts. Only the explicit save action commits.
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        if PiboReleaseScope.pixelHome {
            pixelBody
        } else {
            legacyBody
        }
    }

    // MARK: - Pixel Specimen View

    private var pixelBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelSheetTitle(title: titleString(photo), onClose: handleClose)

            if let photo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pixelSpecimenHeader(photo)
                        if let analysis = photo.analysis, analysis.isFood != false { metadataEditor }
                        pixelStates(photo)
                    }
                    .padding(.bottom, 24)
                }
                if let analysis = photo.analysis, analysis.isFood != false {
                    pixelActions(photo: photo, analysis: analysis)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.text("这一餐的照片找不到了"))
                        .font(.system(size: 14))
                        .foregroundStyle(PixelUIColor.inkSoft)
                    PixelButton(label: AppLocalization.text("关闭"), primary: false, onTap: handleClose)
                }
                .padding(.top, 24)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PixelUIColor.paper.ignoresSafeArea())
        .onAppear { loadMetadata() }
        .onChange(of: photo?.updatedAt) { _, _ in
            if !metadataChanged && !isEditing { loadMetadata(refresh: true) }
        }
        .interactiveDismissDisabled(metadataChanged || isEditing)
    }

    private func loadMetadata(refresh: Bool = false) {
        guard (metadata == nil || refresh), let photo else { return }
        metadata = MealMetadataDraft(photo: photo, fallbackMeal: requestedMeal)
    }

    private var metadataChanged: Bool { metadata?.changed ?? false }
    private var metadataName: Binding<String> {
        Binding(get: { metadata?.name ?? "" }, set: { metadata?.name = $0 })
    }
    private var metadataMeal: MealType { metadata?.meal ?? requestedMeal }

    @discardableResult
    private func saveMetadataIfNeeded(portions: FoodAnalysis? = nil) -> Bool {
        guard metadataChanged || portions != nil else { return true }
        guard let metadata else { return false }
        let saved = history.updateMealMetadata(id: metadata.photoID, name: metadata.name,
                                               meal: metadata.meal, portionAnalysis: portions)
        metadataSaveFailed = !saved
        if saved { loadMetadata(refresh: true) }
        return saved
    }

    private func saveAndClose() {
        guard saveMetadataIfNeeded() else { return }
        handleClose()
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.text("食物名称"))
                .font(PixelFont.font(13))
            TextField(AppLocalization.text("给这一餐起个名字"), text: metadataName)
                .font(.system(size: 17))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(PixelUIColor.paper)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
                .submitLabel(.done)
                .accessibilityIdentifier("meal-name-field")
            Text(AppLocalization.text("这张照片属于哪一餐？"))
                .font(PixelFont.font(13))
            HStack(spacing: 8) {
                ForEach(MealType.allCases) { choice in
                    Button {
                        metadata?.meal = choice
                        LPHaptics.tap()
                    } label: {
                        Text(AppLocalization.text(choice.title))
                            .font(PixelFont.font(14))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(metadataMeal == choice ? .white : PixelUIColor.ink)
                            .background(metadataMeal == choice ? PixelUIColor.leaf : PixelUIColor.paper)
                            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(metadataMeal == choice ? .isSelected : [])
                    .accessibilityIdentifier("meal-type-\(choice.rawValue)")
                }
            }
            Text(AppLocalization.text(metadataSaveFailed
                ? "名称不能为空；如果仍无法保存，请重试。"
                : "名称和餐次可修改，点完成保存。"))
                .font(.system(size: 12))
                .foregroundStyle(metadataSaveFailed ? PixelUIColor.warn : PixelUIColor.inkSoft)
        }
        .padding(12)
        .background(PixelUIColor.paperDim)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
    }

    private func pixelSpecimenHeader(_ photo: FoodPhoto) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let uiImage = UIImage(data: photo.pngData) {
                    Image(uiImage: uiImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                } else if let image = displayImage(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipped()
                } else {
                    Text("🍽️")
                        .font(.system(size: 28))
                }
            }
            .frame(width: 58, height: 58)
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
            .background(alignment: .bottomTrailing) {
                Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
            }
            .rotationEffect(.degrees(-2))

            VStack(alignment: .leading, spacing: 4) {
                Text(mealIdentity(photo))
                    .font(PixelFont.font(16))
                    .foregroundStyle(PixelUIColor.ink)
                    .lineLimit(1)
                Text("\(AppLocalization.text(effectiveMeal.title)) · \(captureTime(photo))")
                    .font(PixelFont.font(12))
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(PixelUIColor.paperDim)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
    }

    @ViewBuilder
    private func pixelStates(_ photo: FoodPhoto) -> some View {
        if recognizer?.isAnalyzing(photo.id) == true {
            pixelNotice(
                mood: .sniff,
                headline: AppLocalization.text("Pibo 正在重新看这张照片"),
                body: AppLocalization.text("可以先关上，看完会写在这里。"),
                offerRetry: false,
                photo: photo
            )
        } else if photo.analysis?.isFood == false {
            pixelNotice(
                mood: .puzzled,
                headline: AppLocalization.text("这次没认出是吃的"),
                body: AppLocalization.text("它暂时不算进食物样本。可以再试一次，或者重拍这一餐。"),
                offerRetry: true,
                photo: photo
            )
        } else if let analysis = photo.analysis {
            pixelSuccess(photo: photo, analysis: analysis)
        } else {
            pixelNotice(
                mood: .puzzled,
                headline: AppLocalization.text("这一餐还没看清"),
                body: AppLocalization.text("照片还在。可以再试一次，或者重拍这一餐。"),
                offerRetry: true,
                photo: photo
            )
        }
    }

    private func pixelNotice(mood: PixelPeekMood, headline: String, body: String,
                             offerRetry: Bool, photo: FoodPhoto) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                PixelPeekPibo(mood: mood, peekSize: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(PixelFont.font(15))
                        .foregroundStyle(PixelUIColor.ink)
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(PixelUIColor.paperDim)
            .overlay(
                Rectangle()
                    .strokeBorder(PixelUIColor.border, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            )

            if offerRetry {
                PixelButton(label: AppLocalization.text("用这张照片重试"), onTap: { retry(photo) })
                PixelButton(label: AppLocalization.text("重拍这一餐"), primary: false, onTap: recapture)
            } else {
                PixelButton(label: AppLocalization.text("先关上"), primary: false, onTap: handleClose)
            }
        }
    }

    private func pixelSuccess(photo: FoodPhoto, analysis: FoodAnalysis) -> some View {
        let displayed = isEditing ? (draftAnalysis ?? analysis) : analysis
        return VStack(alignment: .leading, spacing: 14) {
            // Pibo's Observation
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    PixelIcon(rows: PixelIcons.note, iconSize: 12)
                    Text(AppLocalization.text("Pibo 的观察"))
                        .font(PixelFont.font(13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                Text(piboObservation(displayed))
                    .font(.system(size: 13))
                    .foregroundStyle(PixelUIColor.ink)
                    .lineSpacing(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelUIColor.paperDim)
            .overlay(
                Rectangle()
                    .strokeBorder(PixelUIColor.border, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            )

            // Your Estimate
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.text("你的估算"))
                    .font(PixelFont.font(14))
                    .foregroundStyle(PixelUIColor.ink)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(displayed.totalCalories)")
                        .font(PixelFont.font(28))
                        .foregroundStyle(PixelUIColor.ink)
                    Text(AppLocalization.text("千卡"))
                        .font(PixelFont.font(13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }

                HStack(spacing: 8) {
                    pixelMacroBox(label: AppLocalization.text("蛋白质"), grams: displayed.proteinG, color: PixelUIColor.heart)
                    pixelMacroBox(label: AppLocalization.text("碳水"), grams: displayed.carbG, color: PixelUIColor.gold)
                    pixelMacroBox(label: AppLocalization.text("脂肪"), grams: displayed.fatG, color: PixelUIColor.sleep)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelUIColor.paper)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))

            // Food Items
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.text("食物明细"))
                    .font(PixelFont.font(14))
                    .foregroundStyle(PixelUIColor.ink)

                ForEach(displayed.items.indices, id: \.self) { index in
                    if isEditing {
                        pixelEditableItemRow(index: index)
                    } else {
                        pixelItemRow(displayed.items[index])
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelUIColor.paper)
            .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))

            Text(AppLocalization.text("数字是按照片估的，不一定准。改了热量以后，三大营养素会清空，免得留着旧的估算。"))
                .font(.system(size: 12))
                .foregroundStyle(PixelUIColor.inkSoft)
                .lineSpacing(3)
        }
    }

    private func pixelActions(photo: FoodPhoto, analysis: FoodAnalysis) -> some View {
        let displayed = isEditing ? (draftAnalysis ?? analysis) : analysis
        return HStack(spacing: 10) {
            PixelButton(
                label: AppLocalization.text(isEditing ? "取消调整" : "调整份量"),
                primary: false,
                active: !displayed.items.isEmpty,
                onTap: {
                    if isEditing {
                        draftAnalysis = nil
                        isEditing = false
                    } else {
                        draftAnalysis = analysis
                        isEditing = true
                    }
                }
            )
            PixelButton(
                label: AppLocalization.text(isEditing ? "保存调整" : "完成"),
                onTap: {
                    if isEditing {
                        saveDraft(photo: photo)
                    } else {
                        saveAndClose()
                    }
                }
            )
        }
    }

    private func pixelMacroBox(label: String, grams: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(PixelFont.font(11))
                .foregroundStyle(PixelUIColor.inkSoft)
            Text(grams.map { "\(Int($0.rounded()))g" } ?? "—")
                .font(PixelFont.font(13))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(PixelUIColor.paperDim)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
    }

    private func pixelItemRow(_ item: FoodItem) -> some View {
        HStack {
            Text(item.name)
                .font(PixelFont.font(13))
                .foregroundStyle(PixelUIColor.ink)
            if let qty = item.quantity, !qty.isEmpty {
                Text(qty)
                    .font(.system(size: 12))
                    .foregroundStyle(PixelUIColor.inkSoft)
            }
            Spacer()
            Text("\(item.calories) kcal")
                .font(PixelFont.font(12))
                .foregroundStyle(PixelUIColor.inkSoft)
        }
        .padding(.vertical, 4)
    }

    private func pixelEditableItemRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(draftAnalysis?.items[safe: index]?.name ?? "")
                .font(PixelFont.font(13))
                .foregroundStyle(PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(AppLocalization.text("份量"), text: quantityBinding(index))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .padding(.horizontal, 6)
                .frame(height: 32)
                .background(PixelUIColor.paperDim)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))

            TextField(AppLocalization.text("热量"), text: caloriesBinding(index))
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .padding(.horizontal, 6)
                .frame(height: 32)
                .background(PixelUIColor.paperDim)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 1))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Legacy View

    private var legacyBody: some View {
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
                Text("\(AppLocalization.text(effectiveMeal.title)) · \(captureTime(photo))")
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
        if recognizer?.isAnalyzing(photo.id) == true {
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
                    Text(AppLocalization.text("Pibo 正在观察这顿饭…"))
                        .lpText(LP.Typography.uiH5)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    Text(AppLocalization.text("识别完成后会自动保存，稍后可在历史记录中查看。"))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
            }
            .padding(.vertical, LP.Spacing.m)

            PiboMossSecondaryButton(
                title: AppLocalization.text("关闭"),
                action: handleClose
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
                    action: { isEditing ? saveDraft(photo: photo) : saveAndClose() }
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
                    Text("\(AppLocalization.text(effectiveMeal.title)) · \(captureTime(photo))")
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
            Image(systemName: effectiveMeal.symbol)
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
                action: handleClose
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func retry(_ photo: FoodPhoto) {
        retryFailed = false
        Task { @MainActor in
            guard let recognizer else {
                retryFailed = true
                return
            }
            let succeeded = await recognizer.retry(
                photo: photo,
                meal: effectiveMeal,
                history: history
            )
            retryFailed = !succeeded
        }
    }

    private func recapture() {
        LPHaptics.tap()
        handleClose()
        onRecapture(effectiveMeal)
    }

    private func saveDraft(photo: FoodPhoto) {
        guard var draftAnalysis else { return }
        // Merely opening the editor must not alter a valid nutrition estimate.
        if draftAnalysis.items != photo.analysis?.items {
            if !draftAnalysis.items.isEmpty {
                draftAnalysis.totalCalories = draftAnalysis.items.reduce(0) { $0 + $1.calories }
            }
            draftAnalysis.proteinG = nil
            draftAnalysis.carbG = nil
            draftAnalysis.fatG = nil
        }
        guard saveMetadataIfNeeded(portions: draftAnalysis) else { return }
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
        photo.displayName
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
        let subject = names.isEmpty ? (analysis.dishName.isEmpty ? AppLocalization.text("吃的") : analysis.dishName) : names.joined(separator: "、")
        return AppLocalization.format("我看见了%@。", subject)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
