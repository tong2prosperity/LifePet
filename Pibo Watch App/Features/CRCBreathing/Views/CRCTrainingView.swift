import SwiftUI

struct CRCTrainingView: View {
    @StateObject private var viewModel = CRCTrainingViewModel()

    var body: some View {
        ZStack {
            CRCWatchBackground()
            screen
            overlay
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var screen: some View {
        switch viewModel.step {
        case .intro:
            CRCFixedScreen {
                CRCIntroScreen(companionDay: viewModel.companionDay) {
                    Task { await viewModel.startDetection() }
                }
            }
        case .baseline:
            CRCScrollableScreen {
                CRCBaselineScreen(viewModel: viewModel) {
                    Task { await viewModel.discardTraining() }
                }
            }
        case .coreTraining:
            CRCFixedScreen {
                CRCCoreTrainingScreen(viewModel: viewModel) {
                    viewModel.openMenu()
                }
            }
        case .report:
            CRCScrollableScreen {
                CRCReportScreen(viewModel: viewModel) {
                    viewModel.reset()
                }
            }
        case .error:
            CRCFixedScreen {
                CRCErrorScreen(
                    message: viewModel.errorMessage ?? "…再试一次…啵",
                    onRetry: { Task { await viewModel.startDetection() } },
                    onBack: { viewModel.reset() }
                )
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.transient {
        case .none:
            EmptyView()
        case .menu:
            CRCMenuOverlay(
                onResume: { viewModel.resumeTraining() },
                onSave: { Task { await viewModel.stopTraining() } },
                onDiscard: { Task { await viewModel.discardTraining() } }
            )
        case .unstable:
            CRCUnstableOverlay {
                viewModel.dismissUnstable()
            }
        }
    }
}

// MARK: - Palette

private enum CRCPalette {
    /// Pibo's flower — a soft glowing mint-green that reads as a living plant on the dark watch.
    static let flower = Color(red: 0.40, green: 0.92, blue: 0.74)
}

private struct CRCWatchBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.26, blue: 0.24).opacity(0.55),
                    .clear
                ],
                center: .top,
                startRadius: 12,
                endRadius: 170
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Screen containers

private struct CRCFixedScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct CRCScrollableScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Minimal titled container — no step badge, no redundant clock (the watch already shows time).
private struct CRCScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var stopTitle: String?
    var onStop: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
                .frame(maxWidth: .infinity)

            if let onStop, let stopTitle {
                Button(action: onStop) {
                    Text(stopTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .frame(height: 28)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - The flower (shared breathing visual)

/// Procedural blooming flower. `bloom` 0 = closed bud, 1 = fully open.
private struct CRCFlowerView: View {
    var bloom: Double
    var petalCount: Int = 7
    var accent: Color = CRCPalette.flower

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let b = max(0, min(1, bloom))

            ZStack {
                Circle()
                    .fill(accent.opacity(0.08 + 0.12 * b))
                    .frame(width: side * (0.70 + 0.24 * b), height: side * (0.70 + 0.24 * b))
                    .blur(radius: side * 0.04)

                ForEach(0..<petalCount, id: \.self) { index in
                    let angle = Double(index) / Double(petalCount) * 360
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.92), accent.opacity(0.32)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: side * (0.155 - 0.02 * b), height: side * (0.22 + 0.18 * b))
                        // Expand into a full-size box pinned to top so rotation orbits the flower center.
                        .frame(width: side, height: side, alignment: .top)
                        .rotationEffect(.degrees(angle))
                        .opacity(0.45 + 0.45 * b)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.95), accent, accent.opacity(0.3)],
                            center: .center,
                            startRadius: 1,
                            endRadius: side * (0.15 + 0.05 * b)
                        )
                    )
                    .frame(width: side * (0.26 + 0.05 * b), height: side * (0.26 + 0.05 * b))
                    .shadow(color: accent.opacity(0.45 + 0.3 * b), radius: side * 0.06)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(0.9 + 0.1 * b)
        }
    }
}

/// Flower driven by the engine's breathing phase — the core-training hero.
/// Animates continuously off phase flips (the same source the haptics fire on) so it glides
/// across the whole inhale/exhale instead of stepping once per 1 Hz snapshot.
private struct CRCBreathingFlower: View {
    let snapshot: CRCSnapshot?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloom: Double = 0.2

    private var phase: CRCBreathingPhase { snapshot?.phase ?? .inhale }

    private var guidedRate: Double {
        max(snapshot?.guidedBreathingRate ?? CRCConstants.initialGuidedBreathingRate, 0.1)
    }

    private var phaseRatio: Double {
        phase == .inhale ? CRCConstants.inhaleRatio : CRCConstants.exhaleRatio
    }

    private var phaseSeconds: Double {
        60 / guidedRate * phaseRatio
    }

    // Reduce Motion: keep a gentle bloom range so the pacing cue survives without large motion.
    private var openValue: Double { reduceMotion ? 0.68 : 1.0 }
    private var closeValue: Double { reduceMotion ? 0.42 : 0.16 }
    private var targetBloom: Double { phase == .inhale ? openValue : closeValue }

    var body: some View {
        CRCFlowerView(bloom: bloom)
            .onAppear { syncBreath() }
            .onChange(of: phase) { _, _ in syncBreath() }
    }

    private func syncBreath() {
        withAnimation(.easeInOut(duration: phaseSeconds)) {
            bloom = targetBloom
        }
    }
}

/// Gentle self-looping flower for intro / baseline (≈6 breaths per minute preview).
private struct CRCAmbientFlower: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: 10) / 10
            let bloom = reduceMotion ? 0.6 : 0.15 + 0.85 * (0.5 - 0.5 * cos(phase * .pi * 2))
            CRCFlowerView(bloom: bloom)
        }
    }
}

// MARK: - Intro (welcome + preparation, merged)

private struct CRCIntroScreen: View {
    let companionDay: Int
    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let flowerSide = clampValue(min(proxy.size.width * 0.5, proxy.size.height * 0.36), 62, 108)

            VStack(spacing: 9) {
                CRCAmbientFlower()
                    .frame(width: flowerSide, height: flowerSide)

                VStack(spacing: 2) {
                    Text("陪 Pibo 呼吸")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(companionDay > 0 ? "第 \(companionDay) 天 · 让花喝口气" : "让头顶的花，喝口气")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                VStack(spacing: 4) {
                    CRCHintLine(icon: "applewatch", text: "戴稳手表，安静坐好")
                    CRCHintLine(icon: "waveform.path.ecg", text: "跟着震动，慢慢呼吸")
                }

                Button(action: onStart) {
                    Text("开始")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            LinearGradient(
                                colors: [CRCPalette.flower, Color(red: 0.20, green: 0.72, blue: 0.70)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.85))
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct CRCHintLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CRCPalette.flower.opacity(0.85))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Baseline

private struct CRCBaselineScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            title: "Pibo 在感受你",
            subtitle: "先自然呼吸，别刻意调整",
            stopTitle: "取消",
            onStop: onStop
        ) {
            VStack(spacing: 10) {
                CRCAmbientFlower()
                    .frame(width: 66, height: 66)

                VStack(spacing: 5) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.13))
                            Capsule()
                                .fill(CRCPalette.flower)
                                .frame(width: proxy.size.width * viewModel.baselineProgress)
                        }
                    }
                    .frame(height: 6)

                    Text(viewModel.baselineRemaining > 0 ? "还需 \(viewModel.baselineRemaining) 秒" : "…好了…")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 5)
            }
        }
    }
}

// MARK: - Core training (score-free)

private struct CRCCoreTrainingScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onMenu: () -> Void

    @State private var activeHint: String?
    @State private var hintDeadline: Date = .distantPast

    var body: some View {
        GeometryReader { proxy in
            let flowerSide = clampValue(min(proxy.size.width * 0.74, proxy.size.height * 0.5), 104, 152)

            VStack(spacing: 6) {
                ZStack {
                    CRCSessionRing(progress: sessionProgress)
                    CRCBreathingFlower(snapshot: viewModel.snapshot)
                        .frame(width: flowerSide * 0.82, height: flowerSide * 0.82)
                }
                .frame(width: flowerSide, height: flowerSide)

                Text(phaseText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.opacity)

                if let hint = visibleHint {
                    Text(hint)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CRCPalette.flower.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 6) {
                        if !remainingText.isEmpty {
                            Text(remainingText)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        // Live RSA-based estimate — marked "≈" (not clinical RMSSD),
                        // and hidden below ~5ms where averaged BPM yields only noise.
                        if let hrv = viewModel.liveHRV, Int(hrv.rounded()) >= 5 {
                            Label("≈\(Int(hrv.rounded())) ms", systemImage: "waveform.path.ecg")
                                .foregroundStyle(CRCPalette.flower.opacity(0.9))
                                .contentTransition(.numericText())
                                .accessibilityLabel("实时心率变异约 \(Int(hrv.rounded())) 毫秒")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                Button(action: onMenu) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 44, height: 30)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("暂停")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.3), value: visibleHint)
        }
        .onChange(of: viewModel.elapsedSeconds) { _, _ in refreshHint() }
    }

    private var sessionProgress: Double {
        Double(viewModel.elapsedSeconds) / max(1, CRCConstants.recommendedTrainingDuration)
    }

    private var phaseText: String {
        guard let snapshot = viewModel.snapshot else { return "准备中…" }
        let ratio = snapshot.phase == .inhale ? CRCConstants.inhaleRatio : CRCConstants.exhaleRatio
        let seconds = 60 / max(snapshot.guidedBreathingRate, 0.1) * ratio
        return "\(snapshot.phase.label) · \(String(format: "%.1f", seconds)) 秒"
    }

    private var remainingText: String {
        let remaining = viewModel.remainingSeconds
        if remaining >= 60 { return "约剩 \(Int(ceil(Double(remaining) / 60))) 分" }
        if remaining > 0 { return "就快好了…" }
        return ""
    }

    private var visibleHint: String? {
        guard let activeHint, Date() < hintDeadline else { return nil }
        return activeHint
    }

    /// Latch a soft Pibo pace nudge for a few seconds so the 1 Hz guided-rate changes don't
    /// make it flicker. No numbers, no scoring — just a gentle tsundere hint.
    private func refreshHint() {
        guard let snapshot = viewModel.snapshot else { return }
        let delta = snapshot.guidedBreathingRate - snapshot.previousGuidedBreathingRate
        if delta < -0.05 {
            activeHint = "…再慢一点…啵"
            hintDeadline = Date().addingTimeInterval(3.5)
        } else if delta > 0.05 {
            activeHint = "…别太急…笨蛋…"
            hintDeadline = Date().addingTimeInterval(3.5)
        }
    }
}

private struct CRCSessionRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    CRCPalette.flower.opacity(0.8),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
    }
}

// MARK: - Report (Pibo-voice, non-scoring)

private struct CRCReportScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onDone: () -> Void

    var body: some View {
        CRCScaffold(title: "今天，谢谢你") {
            VStack(spacing: 9) {
                if let report = viewModel.report {
                    HStack(spacing: 8) {
                        CRCAmbientFlower()
                            .frame(width: 40, height: 40)
                        Text(report.piboLine)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(CRCPalette.flower.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                    VStack(spacing: 6) {
                        CRCReportRow(icon: "clock.fill", title: "陪你呼吸", value: formatTime(Int(report.duration)), tint: .mint)
                        CRCReportRow(icon: "heart.fill", title: "平均心率", value: "\(report.averageHeartRate) 次/分", tint: .red)
                        if let hrv = hrvValue(report) {
                            CRCReportRow(icon: "waveform.path.ecg", title: "心率变异", value: hrv, tint: CRCPalette.flower)
                        }
                        if viewModel.companionDay > 0 {
                            CRCReportRow(icon: "leaf.fill", title: "一起呼吸", value: "第 \(viewModel.companionDay) 天", tint: CRCPalette.flower)
                        }
                    }
                }

                Button(action: onDone) {
                    Text("完成")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(CRCPalette.flower, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.85))
            }
        }
    }

    /// Prefer the authoritative post-session RMSSD; fall back to the live RSA
    /// average marked with "≈" so it reads as an estimate, not a measurement.
    private func hrvValue(_ report: CRCTrainingReport) -> String? {
        if let ms = report.sessionRMSSD { return "\(Int(ms.rounded())) ms" }
        if let ms = report.liveHRVAverage { return "≈\(Int(ms.rounded())) ms" }
        return nil
    }
}

private struct CRCReportRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .layoutPriority(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Error (retry in place)

private struct CRCErrorScreen: View {
    let message: String
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            CRCOverlayButton(title: "重试", background: CRCPalette.flower, foreground: .black.opacity(0.85), action: onRetry)
            CRCOverlayButton(title: "返回", background: Color.white.opacity(0.16), foreground: .white, action: onBack)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Transient overlays

private struct CRCOverlayScrim<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct CRCOverlayButton: View {
    let title: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }
}

/// Single exit sheet — merges the old pause overlay + end-confirm.
private struct CRCMenuOverlay: View {
    let onResume: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        CRCOverlayScrim {
            Text("歇一会儿？")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            CRCOverlayButton(title: "继续", background: CRCPalette.flower, foreground: .black.opacity(0.85), action: onResume)
            CRCOverlayButton(title: "保存并结束", background: Color.white.opacity(0.16), foreground: .white, action: onSave)
            CRCOverlayButton(title: "丢弃", background: Color(red: 0.62, green: 0.12, blue: 0.12), foreground: .white, action: onDiscard)
        }
    }
}

private struct CRCUnstableOverlay: View {
    let onContinue: () -> Void

    var body: some View {
        CRCOverlayScrim {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.yellow)
            Text("…手抖了…笨蛋…")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("放松手腕，别乱动")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            CRCOverlayButton(title: "继续", background: CRCPalette.flower, foreground: .black.opacity(0.85), action: onContinue)
        }
    }
}

// MARK: - Helpers

private func clampValue(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
    min(max(value, lowerBound), upperBound)
}

private func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

#Preview("CRC Training") {
    CRCTrainingView()
}
