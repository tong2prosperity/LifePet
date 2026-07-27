import SwiftUI

extension FootprintsMetric {
    var tint: Color {
        switch self {
        case .sleep: LP.Colorful.purple500
        case .steps: LP.Colorful.green500
        case .activeEnergy: LP.Colorful.orange500
        case .hrv: LP.Colorful.red500
        }
    }

    var softTint: Color {
        switch self {
        case .sleep: LP.Colorful.purple100
        case .steps: LP.Colorful.green100
        case .activeEnergy: LP.Colorful.orange100
        case .hrv: LP.Colorful.red100
        }
    }
}

struct FootprintsScopeControl<Scope: Hashable>: View {
    let choices: [(Scope, String)]
    @Binding var selection: Scope

    var body: some View {
        HStack(spacing: LP.Spacing.xs) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button {
                    guard selection != choice.0 else { return }
                    LPHaptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) {
                        selection = choice.0
                    }
                } label: {
                    Text(AppLocalization.text(choice.1))
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(selection == choice.0
                            ? LP.Content.primary
                            : LP.Content.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LP.Spacing.s)
                        .background {
                            if selection == choice.0 {
                                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                                    .fill(LP.Fill.bgPop)
                                    .lpShadow(LP.Shadow.elevation1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(LP.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Neutral.grey250.opacity(0.72))
        )
        .accessibilityElement(children: .contain)
    }
}

struct FootprintsDateStrip: View {
    @Binding var selectedDate: Date
    let minimumDate: Date

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: LP.Spacing.s) {
            HStack {
                Text(monthTitle)
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                HStack(spacing: LP.Spacing.xs) {
                    arrow("chevron.left", enabled: canMoveBackward) { moveWeek(-1) }
                    arrow("chevron.right", enabled: canMoveForward) { moveWeek(1) }
                }
            }

            HStack(spacing: LP.Spacing.xs) {
                ForEach(weekDates, id: \.self) { date in
                    dayButton(date)
                }
            }
        }
    }

    private var weekDates: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private var monthTitle: String {
        let first = weekDates.first ?? selectedDate
        let last = weekDates.last ?? selectedDate
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return Self.month.string(from: selectedDate)
        }
        return "\(Self.shortMonth.string(from: first))–\(Self.month.string(from: last))"
    }

    private var canMoveBackward: Bool {
        guard let first = weekDates.first else { return false }
        return first > calendar.startOfDay(for: minimumDate)
    }

    private var canMoveForward: Bool {
        guard let next = calendar.date(byAdding: .day, value: 7, to: selectedDate) else {
            return false
        }
        return calendar.startOfDay(for: next) <= calendar.startOfDay(for: .now)
    }

    private func dayButton(_ date: Date) -> some View {
        let normalized = calendar.startOfDay(for: date)
        let selected = calendar.isDate(normalized, inSameDayAs: selectedDate)
        let enabled = normalized >= calendar.startOfDay(for: minimumDate)
            && normalized <= calendar.startOfDay(for: .now)
        return Button {
            guard enabled else { return }
            LPHaptics.tap()
            withAnimation(.easeOut(duration: 0.2)) { selectedDate = normalized }
        } label: {
            VStack(spacing: LP.Spacing.xs) {
                Text(Self.weekday.string(from: date))
                    .lpText(LP.Typography.c2Medium)
                Text("\(calendar.component(.day, from: date))")
                    .lpText(LP.Typography.b3Medium)
                Circle()
                    .fill(selected ? LP.Fill.foundationOnAccent : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .foregroundStyle(selected
                ? LP.Fill.foundationOnAccent
                : enabled ? LP.Content.secondary : LP.Content.quarternary.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .fill(selected ? LP.Fill.foundationAccent : LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .strokeBorder(selected ? Color.clear : LP.Border.tertiary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Self.fullDate.string(from: date))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            LPHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? LP.Content.secondary : LP.Content.quarternary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LP.Fill.bgContainer))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func moveWeek(_ direction: Int) {
        guard let shifted = calendar.date(byAdding: .day, value: direction * 7, to: selectedDate) else {
            return
        }
        let today = calendar.startOfDay(for: .now)
        let minimum = calendar.startOfDay(for: minimumDate)
        selectedDate = min(today, max(minimum, calendar.startOfDay(for: shifted)))
    }

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter
    }()

    private static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

struct FootprintsSectionHeader: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(LP.Content.primary)
            if let caption {
                Text(AppLocalization.text(caption))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FootprintsInsightHero: View {
    let insight: FootprintsInsight
    let piboLine: String?
    let appearance: PiboAppearance
    let onOpen: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            onOpen()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [LP.Colorful.green100, LP.Colorful.cyan100],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 154, height: 154)
                    .offset(x: 48, y: 62)

                VStack(alignment: .leading, spacing: LP.Spacing.m) {
                    HStack(spacing: LP.Spacing.s) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("PIBO 注意到了")
                            .lpText(LP.Typography.c1Medium)
                    }
                    .foregroundStyle(LP.Content.accent)

                    Text(AppLocalization.text(insight.fact))
                        .lpText(LP.Typography.uiH4)
                        .foregroundStyle(LP.Content.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppLocalization.text(insight.evidence))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text("看看为什么"))
                            .lpText(LP.Typography.b4Medium)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(LP.Content.accent)
                }
                .frame(maxWidth: 220, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LP.Spacing.xl)
                .padding(.trailing, 104)

                VStack(spacing: -4) {
                    if let piboLine {
                        Text(piboLine)
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, LP.Spacing.s)
                            .padding(.vertical, 6)
                            .background(
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading: LP.Radius.m,
                                        bottomLeading: LP.Radius.m,
                                        bottomTrailing: 2,
                                        topTrailing: LP.Radius.m
                                    ),
                                    style: .continuous
                                )
                                .fill(LP.Fill.bgPop.opacity(0.92))
                            )
                            .frame(width: 126)
                    }

                    PiboPortraitView(appearance: appearance)
                        .frame(width: 126, height: 154)
                }
                .padding(.trailing, LP.Spacing.s)
                .padding(.bottom, -8)
            }
            .frame(minHeight: 226)
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                    .strokeBorder(LP.Border.tertiary, lineWidth: 1)
            )
            .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.text("轻点查看数据依据"))
    }
}

struct FootprintsMetricTile: View {
    let metric: FootprintsMetric
    let value: Double
    let comparison: String
    let onOpen: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack {
                    Image(systemName: metric.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(metric.tint)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(metric.softTint))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LP.Content.quarternary)
                }

                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(AppLocalization.text(metric.title))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                        Text(metric.hasValue(value) ? metric.formatted(value) : "—")
                            .lpText(LP.Typography.uiH4)
                            .foregroundStyle(LP.Content.primary)
                            .monospacedDigit()
                        Text(metric.unit)
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(LP.Content.secondary)
                    }
                    Text(AppLocalization.text(comparison))
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LP.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Border.tertiary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.text("轻点查看趋势与数据来源"))
    }
}
