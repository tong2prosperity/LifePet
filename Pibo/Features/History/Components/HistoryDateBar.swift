import SwiftUI

/// Fixed date bar of 健康记录: `‹  2026年9月16日 周三 ▾  ›`.
///
/// Chevrons are SF Symbols centered in 44pt circles (no text glyphs, so no
/// baseline drift). Tapping the date opens the native calendar limited to
/// today; the forward chevron disables on today. 「今天」 lives in the page
/// header next to share.
struct HistoryDateBar: View {
    let selectedDate: Date
    let onSelect: (Date) -> Void

    @State private var showsPicker = false

    private var canGoForward: Bool { HistoryDateNavigation.canGoForward(selectedDate) }

    var body: some View {
        HStack(spacing: LP.Spacing.s) {
            chevron("chevron.left", label: "前一天", enabled: true) {
                if let day = HistoryDateNavigation.shifted(selectedDate, by: -1) { onSelect(day) }
            }
            Button {
                LPHaptics.tap()
                showsPicker = true
            } label: {
                HStack(spacing: LP.Spacing.xs) {
                    Text("\(Self.dateFormatter.string(from: selectedDate)) \(Self.weekdayFormatter.string(from: selectedDate))")
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LP.Content.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.format(
                "%@，%@，选择日期",
                Self.dateFormatter.string(from: selectedDate),
                Self.weekdayFormatter.string(from: selectedDate)
            ))
            chevron("chevron.right", label: "后一天", enabled: canGoForward) {
                if let day = HistoryDateNavigation.shifted(selectedDate, by: 1) { onSelect(day) }
            }
        }
        .sheet(isPresented: $showsPicker) {
            HistoryDatePickerSheet(selectedDate: selectedDate) { picked in
                showsPicker = false
                onSelect(HistoryDateNavigation.clamped(picked))
            }
        }
    }

    private func chevron(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            LPHaptics.tap()
            action()
        } label: {
            ZStack {
                Circle().fill(LP.Fill.bgContainer)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(enabled ? LP.Content.secondary : LP.Content.quarternary)
            }
            .frame(width: 44, height: 44)
            .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(AppLocalization.text(label))
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

/// Native graphical calendar, bounded to today.
private struct HistoryDatePickerSheet: View {
    let selectedDate: Date
    let onConfirm: (Date) -> Void

    @State private var draft: Date

    init(selectedDate: Date, onConfirm: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onConfirm = onConfirm
        _draft = State(initialValue: selectedDate)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                AppLocalization.text("选择日期"),
                selection: $draft,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .padding(.horizontal, LP.Spacing.l)
            .navigationTitle(AppLocalization.text("选择日期"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.text("完成")) { onConfirm(draft) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
