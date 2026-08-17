import SwiftUI
import UIKit

/// 早/中/晚 餐次详情弹窗 — shows the captured meal photo big plus the backend
/// Kimi VLM 卡路里/营养 result. Presented from the home meal icons: after a fresh
/// capture (recognition in flight → spinner) or by tapping an already-filled
/// icon (cached result). Recognition is slow, so the modal is dismissible and
/// re-renders when the result lands (via `HealthHistoryStore.revision`).
struct MealDetailView: View {
    let meal: MealType
    /// User wants a new photo for this meal — dismiss + reopen the camera.
    var onRecapture: (MealType) -> Void

    @Environment(HealthHistoryStore.self) private var history
    @Environment(FoodRecognitionService.self) private var recognizer
    @Environment(\.dismiss) private var dismiss
    @State private var retryFailed = false

    /// Latest photo for this meal today (re-queried on every history write).
    private var photo: FoodPhoto? {
        _ = history.revision
        return history.foodPhoto(on: Date(), mealType: meal)
    }

    var body: some View {
        ZStack {
            LP.Fill.bgSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                ScrollView {
                    VStack(spacing: LP.Spacing.l) {
                        if let photo {
                            photoCard(photo)
                            analysisSection(photo)
                        } else {
                            emptyState
                        }
                    }
                    .padding(LP.Spacing.l)
                }
            }
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: meal.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LP.Fill.foundationAccent)
                Text(AppLocalization.text(meal.title))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LP.Content.quarternary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.vertical, LP.Spacing.m)
    }

    // MARK: Photo

    private func photoCard(_ photo: FoodPhoto) -> some View {
        VStack(spacing: LP.Spacing.s) {
            Group {
                if let ui = UIImage(data: photo.pngData) {
                    Image(uiImage: ui).resizable().scaledToFit().padding(LP.Spacing.l)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).fill(.white))
            .lpShadow(LP.Shadow.elevation2)

            Text(photo.timeLabel)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
        }
    }

    // MARK: Analysis

    @ViewBuilder
    private func analysisSection(_ photo: FoodPhoto) -> some View {
        if recognizer.isAnalyzing(photo.id) {
            loadingState
        } else if let a = photo.analysis {
            resultView(a)
        } else {
            // Failed, or interrupted by a relaunch (no analysis, nothing in
            // flight) — either way, offer a recapture rather than a blank.
            failedState(photo)
        }
        recaptureButton
    }

    private var loadingState: some View {
        VStack(spacing: LP.Spacing.m) {
            ProgressView().controlSize(.large)
            Text(AppLocalization.text("Pibo 正在认真数卡路里…可能要等一会儿"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.xl)
    }

    private func failedState(_ photo: FoodPhoto) -> some View {
        VStack(spacing: LP.Spacing.s) {
            Text(AppLocalization.text("这张照片还没有估算结果"))
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.text(retryFailed ? "重新估算仍未完成，可以稍后再试。" : "可以使用保存的原图重新估算，不必重拍。"))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
                .multilineTextAlignment(.center)

            Button {
                retryFailed = false
                Task { @MainActor in
                    let succeeded = await recognizer.retry(
                        photo: photo,
                        meal: meal,
                        history: history
                    )
                    retryFailed = !succeeded
                }
            } label: {
                Label(AppLocalization.text("重新估算这张照片"), systemImage: "arrow.clockwise")
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .padding(.horizontal, LP.Spacing.l)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(LP.Fill.foundationAccent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.l)
    }

    private func resultView(_ a: FoodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            // Dish name + total calories headline.
            VStack(alignment: .leading, spacing: 4) {
                Text(a.dishName)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(a.totalCalories)")
                        .lpText(LP.Typography.uiH1)
                        .foregroundStyle(LP.Fill.foundationAccent)
                    Text("kcal")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }

            macros(a)

            if !a.items.isEmpty {
                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Text(AppLocalization.text("食物明细"))
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Content.tertiary)
                    ForEach(a.items) { item in itemRow(item) }
                }
            }

            if let note = a.note, !note.isEmpty {
                Text(note)
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .padding(LP.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .fill(LP.Fill.bgContainer))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macros(_ a: FoodAnalysis) -> some View {
        HStack(spacing: LP.Spacing.s) {
            macroPill(AppLocalization.text("蛋白质"), a.proteinG)
            macroPill(AppLocalization.text("碳水"), a.carbG)
            macroPill(AppLocalization.text("脂肪"), a.fatG)
        }
    }

    private func macroPill(_ label: String, _ grams: Double?) -> some View {
        VStack(spacing: 2) {
            Text(grams.map { "\(Int($0.rounded()))g" } ?? "—")
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
            Text(label)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.m)
        .background(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous).fill(LP.Fill.bgContainer))
    }

    private func itemRow(_ item: FoodItem) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Text(item.name)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
            if let q = item.quantity, !q.isEmpty {
                Text(q)
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: LP.Spacing.s)
            Text("\(item.calories) kcal")
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.secondary)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LP.Separator.primary).frame(height: 0.5)
        }
    }

    /// 重拍 is a door back into the camera, so it disappears with it. Both call
    /// sites (the populated view and `emptyState`) then render nothing here.
    @ViewBuilder
    private var recaptureButton: some View {
        if PiboReleaseScope.camera {
            Button {
                LPHaptics.tap()
                dismiss()
                onRecapture(meal)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill").font(.system(size: 13))
                    Text(AppLocalization.text("重拍这一餐"))
                        .lpText(LP.Typography.b3Medium)
                }
                .foregroundStyle(LP.Content.secondary)
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.s)
                .background(Capsule().fill(LP.Fill.bgContainer))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, LP.Spacing.s)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LP.Spacing.m) {
            Image(systemName: meal.symbol)
                .font(.system(size: 40))
                .foregroundStyle(LP.Content.quarternary)
            Text(AppLocalization.text("还没有拍这一餐"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
            recaptureButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.xxl)
    }
}
