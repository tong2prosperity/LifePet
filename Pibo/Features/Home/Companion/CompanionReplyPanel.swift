import SwiftUI

/// Decision 054 "我想说…" card. The text stays on this phone: Core validates
/// the length (Unicode scalars) and the local companion store keeps it.
struct CompanionReplyPanel: View {
    let question: String
    let maxScalars: Int
    let countScalars: (String) -> Int?
    let onCancel: () -> Void
    let onSubmit: (String) -> Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var scalars: Int? { countScalars(draft) }
    private var canSave: Bool {
        guard let scalars else { return false }
        return scalars >= 1 && scalars <= maxScalars
    }

    private var countText: String {
        let used = draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : max(0, scalars ?? draft.unicodeScalars.count)
        return "\(used)/\(maxScalars)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.text("想对 Pibo 说什么？"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LP.Content.primary)
                    if !question.isEmpty {
                        Text(AppLocalization.format("Pibo 问：%@", question))
                            .font(.system(size: 14))
                            .foregroundStyle(LP.Content.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                TextField(AppLocalization.text("写一句就好"), text: $draft)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LP.Fill.bgSurface))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if canSave { _ = onSubmit(draft) } }
                    .onChange(of: draft) { _, value in
                        // Line breaks are never part of a reply; Core rejects them too.
                        let cleaned = value.replacingOccurrences(of: "\n", with: "")
                            .replacingOccurrences(of: "\r", with: "")
                        if cleaned != value { draft = cleaned }
                    }
                    .accessibilityLabel(AppLocalization.text("回复内容"))

                HStack {
                    Text(AppLocalization.text("只保存在这台手机上"))
                        .font(.system(size: 14))
                        .foregroundStyle(LP.Content.tertiary)
                    Spacer()
                    Text(countText)
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(!draft.isEmpty && !canSave ? LP.Fill.foundationError : LP.Content.tertiary)
                        .accessibilityLabel(AppLocalization.format("已输入 %@", countText))
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text(AppLocalization.text("取消"))
                            .font(.system(size: 16))
                            .foregroundStyle(LP.Content.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LP.Fill.bgSurface))
                    }
                    .buttonStyle(.plain)
                    Button {
                        if canSave { _ = onSubmit(draft) }
                    } label: {
                        Text(AppLocalization.text("告诉 Pibo"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(canSave ? LP.Fill.foundationAccent : LP.Separator.primary))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LP.Fill.bgContainer))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .padding(.horizontal, 24)
            .padding(.top, 120)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
    }
}
