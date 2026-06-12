import SwiftUI

/// 日期选择 — `‹  6月6日 周六  ›` over the 第 N/总 天 label (Figma `date piker`
/// 1193:2225 + `date label` 1193:2228). Circular chevron buttons on a white
/// container; the forward button disables once the selected day reaches today.
struct HistoryDateBar: View {
    let dateText: String        // "6月6日"
    let weekdayText: String     // "周六"
    let dayLabel: String        // "第 1/213 天"
    var canGoForward: Bool
    var onPrev: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: LP.Spacing.xs) {
            HStack {
                roundButton("chevron.backward", enabled: true, action: onPrev)
                Spacer(minLength: 0)
                HStack(spacing: LP.Spacing.s) {
                    Text(dateText)
                    Text(weekdayText)
                }
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                roundButton("chevron.forward", enabled: canGoForward, action: onNext)
            }
            Text(dayLabel)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            LPHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(enabled ? LP.Content.secondary : LP.Content.quarternary)
                .frame(width: 28, height: 28)
                .padding(LP.Spacing.m)
                .background(Circle().fill(LP.Fill.bgContainer))
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
