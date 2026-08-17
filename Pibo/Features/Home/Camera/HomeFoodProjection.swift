import Foundation
import SwiftUI
import UIKit

/// A short-lived forest projection made from the transparent food cut-out.
/// It is presentation-only: calorie recognition and history persistence remain
/// owned by their existing services.
struct HomeFoodProjection: Identifiable, Equatable {
    let id: UUID
    let pngData: Data
    let meal: MealType
    let subjectLabel: String?
}

struct HomeFoodProjectionOverlay: View {
    let projection: HomeFoodProjection
    let openDetail: () -> Void
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: LP.Spacing.s) {
                Spacer()
                    .frame(height: proxy.size.height * 0.51)

                HStack {
                    Spacer(minLength: proxy.size.width * 0.52)

                    ZStack {
                        Circle()
                            .fill(LP.Fill.foundationAccent.opacity(0.10))
                            .frame(width: 116, height: 116)
                        Circle()
                            .strokeBorder(LP.Fill.foundationAccent.opacity(0.30), lineWidth: 1)
                            .frame(width: 102, height: 102)

                        if let image = UIImage(data: projection.pngData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(14)
                                .frame(width: 108, height: 108)
                                .accessibilityHidden(true)
                        }
                    }

                    Spacer(minLength: LP.Spacing.l)
                }

                HStack(spacing: LP.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("已放进今天的足迹"))
                            .lpText(LP.Typography.b3Medium)
                            .foregroundStyle(LP.Content.primary)
                        Text(AppLocalization.text("热量识别会在后台继续"))
                            .lpText(LP.Typography.b4Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }

                    Spacer(minLength: LP.Spacing.s)

                    Button {
                        LPHaptics.tap()
                        openDetail()
                    } label: {
                        Text(AppLocalization.text("查看估算"))
                            .lpText(LP.Typography.b4Medium)
                            .foregroundStyle(LP.Fill.foundationOnAccent)
                            .padding(.horizontal, LP.Spacing.m)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(LP.Fill.foundationAccent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, LP.Spacing.m)
                .padding(.trailing, LP.Spacing.s)
                .padding(.vertical, LP.Spacing.s)
                .frame(maxWidth: 330)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.94))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                }
                .lpShadow(LP.Shadow.elevation2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.92, anchor: .center)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isVisible = true
                }
            }
        }
        .task(id: projection.id) {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            AppLocalization.format(
                "%@记录已保存，热量识别正在后台继续",
                projection.subjectLabel ?? projection.meal.title
            )
        )
    }
}

struct HomeTransientNotice: View {
    let text: String

    var body: some View {
        Text(AppLocalization.text(text))
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(LP.Content.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.m)
            .background(
                Capsule()
                    .fill(LP.Fill.bgContainer.opacity(0.96))
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
            }
            .lpShadow(LP.Shadow.elevation2)
            .accessibilityAddTraits(.isStaticText)
    }
}
