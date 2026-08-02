import SwiftUI

/// 首页左上角的 `bo` 存量与成熟收取入口。
///
/// 成熟判断和余额变更仍由 `BoLedgerStore` 负责；这里仅表达 Figma 的两种视觉状态，
/// 并编排收取时的能量流、计数增长与确认反馈。
struct BoCounterView: View {
    let balance: Int
    let growthProgress: Double
    let hasRipeBo: Bool
    let highlightsExchange: Bool
    let collectAction: () -> Bool
    let exchangeAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripePulse = false
    @State private var progressFlash = false
    @State private var gatherProgress: CGFloat = 0
    @State private var collecting = false
    @State private var streamProgress: CGFloat = 0
    @State private var glyphRotation: Double = 0
    @State private var exchangePulse = false

    private var accessibilityText: String {
        hasRipeBo
            ? AppLocalization.format("已有 %d 枚 bo，有一枚可以收取", balance)
            : AppLocalization.format("已有 %d 枚 bo", balance)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(LP.Neutral.grey850)

            Button(action: handlePrimaryTap) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 102, height: 48)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(AppLocalization.text(hasRipeBo ? "收取成熟的 bo" : "打开 bo 兑换"))

            Text("\(balance) bo")
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: balance)
                .offset(x: 50, y: 12)
                .allowsHitTesting(false)

            Button {
                LPHaptics.tap()
                exchangeAction()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(LP.Content.invertPrimary)
                    .frame(width: 44, height: 44)
                    .background(LP.Colorful.teal500, in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 102, y: 2)
            .scaleEffect(exchangePulse ? 1.06 : 1)
            .shadow(
                color: LP.Colorful.teal500.opacity(highlightsExchange ? 0.75 : 0),
                radius: exchangePulse ? 12 : 7
            )
            .overlay {
                if highlightsExchange {
                    Circle()
                        .stroke(LP.Content.invertPrimary.opacity(0.9), lineWidth: 2)
                        .frame(width: exchangePulse ? 52 : 46, height: exchangePulse ? 52 : 46)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(AppLocalization.text("打开 bo 兑换"))

            Image(hasRipeBo || collecting ? "bo_glyph_ripe" : "bo_glyph_unripe")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 68)
                .scaleEffect(ripePulse ? 1.06 : 1)
                .rotationEffect(.degrees(glyphRotation), anchor: .bottom)
                .shadow(color: Color(hex: 0xFFFDAA).opacity(progressFlash || hasRipeBo ? 0.8 : 0), radius: 8)
                .offset(y: -20)
                .allowsHitTesting(false)

            if collecting && !reduceMotion {
                BoCollectionStream(progress: streamProgress)
                    .frame(width: 72, height: 48)
                    .offset(x: 17, y: -4)
                    .allowsHitTesting(false)
            }

            if progressFlash && !hasRipeBo && !reduceMotion {
                BoGrowthGather(progress: gatherProgress)
                    .frame(width: 148, height: 108)
                    .offset(y: -20)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 148, height: 48)
        .onAppear { syncPulse() }
        .onAppear { syncExchangePulse() }
        .onChange(of: hasRipeBo) { _, _ in syncPulse() }
        .onChange(of: growthProgress) { oldValue, newValue in
            guard newValue > oldValue, !hasRipeBo else { return }
            flashForProgressGain()
        }
        .onChange(of: highlightsExchange) { _, _ in syncExchangePulse() }
    }

    private func handlePrimaryTap() {
        guard hasRipeBo else {
            LPHaptics.tap()
            exchangeAction()
            return
        }
        collectRipeBo()
    }

    private func collectRipeBo() {
        guard !collecting else { return }
        collecting = true
        progressFlash = true

        if reduceMotion {
            let collected = collectAction()
            if collected { LPHaptics.success() }
            collecting = false
            progressFlash = false
            return
        }

        streamProgress = 0
        withAnimation(.easeIn(duration: 0.42)) { streamProgress = 1 }
        withAnimation(.linear(duration: 0.09).repeatCount(4, autoreverses: true)) {
            glyphRotation = 4
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            let collected = collectAction()
            if collected { LPHaptics.success() }
            withAnimation(.easeOut(duration: 0.18)) {
                collecting = false
                progressFlash = false
                glyphRotation = 0
            }
        }
    }

    private func flashForProgressGain() {
        progressFlash = true
        gatherProgress = 0
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.5)) { gatherProgress = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 520))
            withAnimation(.easeOut(duration: 0.18)) { progressFlash = false }
        }
    }

    /// 只有成熟未收时才持续呼吸；Reduce Motion 下保留静态发光状态。
    private func syncPulse() {
        guard hasRipeBo, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { ripePulse = false }
            return
        }
        ripePulse = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            ripePulse = true
        }
    }

    private func syncExchangePulse() {
        guard highlightsExchange, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { exchangePulse = false }
            return
        }
        exchangePulse = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            exchangePulse = true
        }
    }
}

private struct BoGrowthGather: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<8 {
                let delay = CGFloat(index) * 0.055
                let t = min(1, max(0, (progress - delay) / (1 - delay)))
                guard t > 0, t < 1 else { continue }
                let start = CGPoint(x: size.width - CGFloat(index % 3) * 13, y: size.height - CGFloat(index) * 4)
                let control = CGPoint(x: size.width * 0.58, y: size.height * (0.18 + CGFloat(index % 2) * 0.16))
                let end = CGPoint(x: 24, y: 24)
                let inverse = 1 - t
                let point = CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
                let radius: CGFloat = index.isMultiple(of: 3) ? 2.2 : 1.5
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(Color(hex: 0xFFFDAA).opacity(0.9 - t * 0.25))
                )
            }
        }
    }
}

private struct BoCollectionStream: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<7 {
                let delay = CGFloat(index) * 0.07
                let t = min(1, max(0, (progress - delay) / (1 - delay)))
                guard t > 0, t < 1 else { continue }
                let start = CGPoint(x: 4 + CGFloat(index % 3) * 3, y: 4 + CGFloat(index) * 2)
                let control = CGPoint(x: size.width * 0.46, y: size.height * (0.10 + CGFloat(index % 2) * 0.18))
                let end = CGPoint(x: size.width - 3, y: size.height * 0.58)
                let point = quadraticPoint(from: start, control: control, to: end, t: t)
                let radius: CGFloat = index.isMultiple(of: 2) ? 2.4 : 1.6
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0xFFFDAA).opacity(1 - t * 0.35)))
            }
        }
    }

    private func quadraticPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        BoCounterView(balance: 0, growthProgress: 0.12, hasRipeBo: false, highlightsExchange: false, collectAction: { false }) {}
        BoCounterView(balance: 7, growthProgress: 1, hasRipeBo: true, highlightsExchange: true, collectAction: { true }) {}
    }
    .padding(40)
    .background(Color(hex: 0x9FBFA8))
}
