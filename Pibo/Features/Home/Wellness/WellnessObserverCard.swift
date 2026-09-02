import SwiftUI

/// A compact, persistent Home overlay. It explains today's Core readiness
/// without turning the forest into a dashboard or exposing raw health values.
struct WellnessObserverCard: View {
    let presentation: WellnessObserverPresentation
    let expanded: Bool
    let onToggleExpanded: () -> Void
    let onOpenHealthStatus: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            header
            content
            if expanded {
                explanation
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.top, LP.Spacing.s)
        .padding(.bottom, LP.Spacing.l)
        .frame(maxWidth: 340, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .lpShadow(LP.Shadow.elevation1)
        .lpDynamicTypeScaling()
    }

    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                onToggleExpanded()
            }
        } label: {
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PiboMoss.Color.foundationTeal)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(PiboMoss.Color.foundationTeal.opacity(0.12)))
                    .accessibilityHidden(true)

                Text(AppLocalization.text("状态观测仪"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(AppLocalization.text(expanded ? "收起" : "展开"))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: PiboMoss.Control.minimumHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(
            expanded ? "收起状态观测仪详情" : "展开状态观测仪详情"
        ))
        .accessibilityValue(AppLocalization.text(expanded ? "已展开" : "已折叠"))
    }

    @ViewBuilder
    private var content: some View {
        switch presentation.content {
        case .available(let available):
            availableContent(available)
        case .unavailable(let unavailable):
            unavailableContent(unavailable)
        }
    }

    private func availableContent(
        _ available: WellnessObserverPresentation.Available
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: LP.Spacing.l) {
                    scoreBlock(available)
                    metrics(available)
                }
                VStack(alignment: .leading, spacing: LP.Spacing.m) {
                    scoreBlock(available)
                    metrics(available)
                }
            }

            Text(available.band.conclusion)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scoreBlock(
        _ available: WellnessObserverPresentation.Available
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: LP.Spacing.xs) {
                Text(Int(available.score.rounded()).formatted())
                    .lpText(LP.Typography.uiH2)
                    .monospacedDigit()
                    .foregroundStyle(PiboMoss.Color.sleepIndigo)
                    .contentTransition(.numericText())
                Text("/100")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.tertiaryInk)
            }

            Text(available.band.label)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)
                .padding(.horizontal, LP.Spacing.s)
                .padding(.vertical, LP.Spacing.xs)
                .background(Capsule().fill(available.band.fill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.format(
            "今日准备度 %d 分，%@",
            Int(available.score.rounded()),
            available.band.label
        ))
    }

    private func metrics(
        _ available: WellnessObserverPresentation.Available
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            metric(
                label: AppLocalization.text("睡眠充足度"),
                value: available.sleepSufficiency.map {
                    "\(Int($0.rounded()))%"
                } ?? AppLocalization.text("数据不足"),
                accent: PiboMoss.Color.sleepIndigo
            )
            metric(
                label: AppLocalization.text("近期身体负荷"),
                value: available.load.label,
                accent: PiboMoss.Color.foundationTeal
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LP.Spacing.xs) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(label)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
            }
            Text(value)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(PiboMoss.Color.forestInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value)")
    }

    private func unavailableContent(
        _ unavailable: WellnessObserverPresentation.UnavailableKind
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(alignment: .center, spacing: LP.Spacing.m) {
                Text("—")
                    .lpText(LP.Typography.uiH2)
                    .monospacedDigit()
                    .foregroundStyle(PiboMoss.Color.tertiaryInk)

                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(unavailable.title)
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(unavailable.detail)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(unavailable.title)，\(unavailable.detail)")

            if unavailable.offersHealthDetails {
                Button {
                    onOpenHealthStatus()
                } label: {
                    Text(AppLocalization.text("查看"))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                        .padding(.horizontal, LP.Spacing.l)
                        .frame(minHeight: PiboMoss.Control.minimumHit)
                        .background(
                            Capsule().fill(PiboMoss.Color.foundationTeal.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.text("查看健康数据状态"))
            }
        }
    }

    @ViewBuilder
    private var explanation: some View {
        if case .available(let available) = presentation.content {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Divider().overlay(PiboMoss.Color.hairline.opacity(0.72))

                Text(AppLocalization.text("主要依据"))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)

                if let reason = available.primaryReason {
                    reasonRow(reason.text, tint: PiboMoss.Color.sleepIndigo)
                }
                if let reason = available.secondaryReason {
                    reasonRow(reason.text, tint: PiboMoss.Color.foundationTeal)
                }

                Text(AppLocalization.format(
                    "基于 %d 晚 · %@ 更新 · 只比较你的个人记录",
                    available.calibrationDays,
                    timeText(available.generatedAt)
                ))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reasonRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(PiboMoss.Color.forestInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
                    .fill(PiboMoss.Color.sheetMoss.opacity(0.88))
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
            .strokeBorder(PiboMoss.Color.hairline.opacity(0.72), lineWidth: 1)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension WellnessObserverPresentation.Band {
    var label: String {
        switch self {
        case .significantlyBelow: AppLocalization.text("明显偏低")
        case .belowPersonalNormal: AppLocalization.text("低于个人常态")
        case .personalNormal: AppLocalization.text("个人常态")
        case .ample: AppLocalization.text("状态充足")
        }
    }

    var conclusion: String {
        switch self {
        case .significantlyBelow: AppLocalization.text("今天先放轻一点。")
        case .belowPersonalNormal: AppLocalization.text("今天适合轻量活动。")
        case .personalNormal: AppLocalization.text("今天按平常节奏就好。")
        case .ample: AppLocalization.text("今天的状态很充足。")
        }
    }

    var fill: Color {
        switch self {
        case .significantlyBelow: PiboMoss.Color.proteinBerry.opacity(0.16)
        case .belowPersonalNormal: PiboMoss.Color.carbsAmber.opacity(0.18)
        case .personalNormal: PiboMoss.Color.sleepIndigo.opacity(0.13)
        case .ample: PiboMoss.Color.foundationTeal.opacity(0.13)
        }
    }
}

private extension WellnessObserverPresentation.Load {
    var label: String {
        switch self {
        case .buildingBaseline: AppLocalization.text("正在校准")
        case .belowUsual: AppLocalization.text("低于平时")
        case .usual: AppLocalization.text("与平时相当")
        case .aboveUsual: AppLocalization.text("高于平时")
        case .unavailable: AppLocalization.text("数据不足")
        }
    }
}

private extension WellnessObserverPresentation.Reason {
    var text: String {
        switch self {
        case .missingCurrentSleep: AppLocalization.text("今天还没有完整的睡眠记录。")
        case .buildingPersonalBaseline: AppLocalization.text("个人基线还在建立。")
        case .sleepInsufficient: AppLocalization.text("昨晚睡得比需要的少。")
        case .sleepSufficient: AppLocalization.text("昨晚睡眠基本够。")
        case .hrvBelowUsual: AppLocalization.text("夜间 HRV 低于个人常态。")
        case .hrvUsual: AppLocalization.text("夜间 HRV 接近个人常态。")
        case .hrvAboveUsual: AppLocalization.text("夜间 HRV 高于个人常态。")
        case .heartRateElevated: AppLocalization.text("夜间心率高于个人常态。")
        case .heartRateUsual: AppLocalization.text("夜间心率接近个人常态。")
        case .heartRateLowerThanUsual: AppLocalization.text("夜间心率低于个人常态。")
        case .temperatureDeviation: AppLocalization.text("腕温和个人常态有偏差。")
        case .recentLoadAboveUsual: AppLocalization.text("近期身体负荷高于平时。")
        case .recentLoadUsual: AppLocalization.text("近期身体负荷与平时相当。")
        }
    }
}

private extension WellnessObserverPresentation.UnavailableKind {
    var title: String {
        switch self {
        case .healthKitUnavailable: AppLocalization.text("当前无法读取健康数据")
        case .needsAuthorization: AppLocalization.text("还没有健康数据权限")
        case .checking: AppLocalization.text("正在检查健康数据")
        case .noReadableData: AppLocalization.text("还没有可读取的健康记录")
        case .temporarilyInterrupted: AppLocalization.text("健康数据暂时中断")
        case .missingCurrentSleep: AppLocalization.text("今天的睡眠记录还没到")
        case .buildingPersonalBaseline: AppLocalization.text("个人基线正在建立")
        case .updating: AppLocalization.text("正在更新今天的数据")
        case .insufficientData: AppLocalization.text("今天还不能计算准备度")
        }
    }

    var detail: String {
        switch self {
        case .healthKitUnavailable:
            AppLocalization.text("这台设备暂时不能读取健康记录。")
        case .needsAuthorization:
            AppLocalization.text("连接后才能计算准备度。")
        case .checking:
            AppLocalization.text("完成后会自动更新。")
        case .noReadableData:
            AppLocalization.text("有新的睡眠记录后会自动计算。")
        case .temporarilyInterrupted:
            AppLocalization.text("恢复后会自动更新。")
        case .missingCurrentSleep:
            AppLocalization.text("收到完整记录后会自动计算。")
        case .buildingPersonalBaseline(let observed, let required):
            AppLocalization.format("已记录 %d / %d 晚", observed, required)
        case .updating:
            AppLocalization.text("完成后会自动显示。")
        case .insufficientData:
            AppLocalization.text("数据不足不会按 0 分处理。")
        }
    }
}

#if DEBUG
#Preview("状态观测仪 · 收起") {
    WellnessObserverCard(
        presentation: .init(content: .available(.init(
            score: 78,
            band: .personalNormal,
            sleepSufficiency: 86,
            load: .usual,
            primaryReason: .sleepSufficient,
            secondaryReason: .hrvUsual,
            calibrationDays: 18,
            generatedAt: .now
        ))),
        expanded: false,
        onToggleExpanded: {},
        onOpenHealthStatus: {}
    )
    .padding()
    .background(PiboMoss.Color.canvasMist)
    .preferredColorScheme(.light)
}

#Preview("状态观测仪 · 校准") {
    WellnessObserverCard(
        presentation: .init(content: .unavailable(.buildingPersonalBaseline(
            observed: 5,
            required: 7
        ))),
        expanded: true,
        onToggleExpanded: {},
        onOpenHealthStatus: {}
    )
    .padding()
    .background(PiboMoss.Color.canvasMist)
    .preferredColorScheme(.light)
}
#endif
