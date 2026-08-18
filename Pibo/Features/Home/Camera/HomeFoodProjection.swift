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

enum HomeFoodProjectionStatus: Equatable {
    case analyzing
    case ready
    case retry

    var detail: String {
        switch self {
        case .analyzing: "照片已保存，正在后台估算"
        case .ready: "估算已经准备好"
        case .retry: "照片已保留，可以重试估算"
        }
    }
}

struct HomeFoodProjectionOverlay: View {
    let projection: HomeFoodProjection
    let status: HomeFoodProjectionStatus
    let openDetail: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack {
            Spacer()

            Button {
                LPHaptics.tap()
                openDetail()
            } label: {
                HStack(spacing: LP.Spacing.m) {
                    if let image = UIImage(data: projection.pngData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: PiboMoss.Radius.control))
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        Text(AppLocalization.format(
                            "已放进今天的%@",
                            AppLocalization.text(projection.meal.title)
                        ))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)

                        Text(AppLocalization.text(status.detail))
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(PiboMoss.Color.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(AppLocalization.text("查看估算"))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }
                .padding(LP.Spacing.m)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                        .fill(PiboMoss.Color.sheetMoss.opacity(0.96))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                        .strokeBorder(PiboMoss.Color.hairline.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: Color(hex: 0x17342B, alpha: 0.22), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, 108)
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isVisible = true
                }
            }
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
