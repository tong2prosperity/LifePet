import SwiftUI

/// Full-screen reader for 隐私协议 / 用户协议. Shared by the login screen (as a
/// full-screen cover, so closing it returns to the non-dismissable login gate)
/// and Settings (pushed, using the navigation back button).
struct LegalDocumentView: View {
    let document: LegalDocument
    /// When set, a leading close control is shown (cover presentation).
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let onClose {
                ZStack {
                    Text(document.title)
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                        .accessibilityAddTraits(.isHeader)
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LP.Content.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.text("返回"))
                        Spacer()
                    }
                }
                .padding(.horizontal, LP.Spacing.s)
                .frame(height: 56)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                    Text("生效日期：\(document.updatedAt)")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                    ForEach(document.sections, id: \.heading) { section in
                        VStack(alignment: .leading, spacing: LP.Spacing.s) {
                            Text(section.heading)
                                .lpText(LP.Typography.b2Medium)
                                .foregroundStyle(LP.Content.primary)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.system(size: 14))
                                    .lineSpacing(6)
                                    .foregroundStyle(LP.Content.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LP.Spacing.l)
                .padding(.top, LP.Spacing.m)
                .padding(.bottom, LP.Spacing.xxl)
            }
        }
        .background(LP.Fill.bgSurfaceSecondary.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
