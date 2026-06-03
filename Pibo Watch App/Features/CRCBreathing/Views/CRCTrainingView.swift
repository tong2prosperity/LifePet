import SwiftUI

struct CRCTrainingView: View {
    @StateObject private var viewModel = CRCTrainingViewModel()

    var body: some View {
        ZStack {
            CRCWatchBackground()
            screen
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var screen: some View {
        switch viewModel.step {
        case .welcome:
            CRCFixedScreen {
                CRCWelcomeScreen {
                    viewModel.showPreparation()
                }
            }
        case .preparation:
            CRCScrollableScreen {
                CRCPreparationScreen(viewModel: viewModel) {
                    Task { await viewModel.startDetection() }
                }
            }
        case .baseline:
            CRCScrollableScreen {
                CRCBaselineScreen(viewModel: viewModel) {
                    Task { await viewModel.stopTraining() }
                }
            }
        case .breathingGuide:
            CRCFixedScreen {
                CRCBreathingGuideScreen(viewModel: viewModel) {
                    Task { await viewModel.stopTraining() }
                }
            }
        case .realtimeMonitor:
            CRCScrollableScreen {
                CRCRealtimeMonitorScreen(viewModel: viewModel) {
                    Task { await viewModel.stopTraining() }
                }
            }
        case .adaptiveTuning:
            CRCScrollableScreen {
                CRCAdaptiveTuningScreen(viewModel: viewModel) {
                    Task { await viewModel.stopTraining() }
                }
            }
        case .trainingFeedback:
            CRCFixedScreen {
                CRCTrainingFeedbackScreen(viewModel: viewModel) {
                    Task { await viewModel.stopTraining() }
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
                CRCErrorScreen(message: viewModel.errorMessage ?? "请重新开始检测") {
                    viewModel.reset()
                }
            }
        }
    }
}

private struct CRCWatchBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(red: 0.03, green: 0.28, blue: 0.38).opacity(0.55),
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

private struct CRCScaffold<Content: View>: View {
    let step: Int?
    let title: String
    var subtitle: String?
    var onStop: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let step {
                            Text("\(step)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.blue))
                        }
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            content
                .frame(maxWidth: .infinity)

            if let onStop {
                Button {
                    onStop()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(height: 28)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct CRCWelcomeScreen: View {
    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = CRCWelcomeLayout(size: proxy.size)

            VStack(spacing: layout.spacing) {
                CRCHeroAnimationView()
                    .frame(width: layout.heroHeight * 1.08, height: layout.heroHeight)

                VStack(spacing: layout.titleSpacing) {
                    Text("心呼耦合训练")
                        .font(.system(size: layout.titleFontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text("呼吸与心率协同训练")
                        .font(.system(size: layout.subtitleFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Button(action: onStart) {
                    Text("开始训练")
                        .font(.system(size: layout.buttonFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.28, green: 0.32, blue: 1.0),
                                    Color(red: 0.20, green: 0.70, blue: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Text("开启身心协同训练之旅")
                    .font(.system(size: layout.footnoteFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct CRCWelcomeLayout {
    let size: CGSize

    var horizontalPadding: CGFloat {
        clamp(size.width * 0.07, 10, 16)
    }

    var verticalPadding: CGFloat {
        clamp(size.height * 0.045, 7, 14)
    }

    var spacing: CGFloat {
        clamp(size.height * 0.033, 5, 10)
    }

    var titleSpacing: CGFloat {
        clamp(size.height * 0.012, 2, 4)
    }

    var titleFontSize: CGFloat {
        clamp(size.width * 0.118, 18, 23)
    }

    var subtitleFontSize: CGFloat {
        clamp(size.width * 0.064, 10, 12)
    }

    var footnoteFontSize: CGFloat {
        clamp(size.width * 0.056, 9, 11)
    }

    var buttonFontSize: CGFloat {
        clamp(size.width * 0.078, 13, 16)
    }

    var buttonHeight: CGFloat {
        clamp(size.height * 0.18, 34, 44)
    }

    var buttonWidth: CGFloat {
        min(size.width - horizontalPadding * 2, clamp(size.width * 0.86, 124, 210))
    }

    var heroHeight: CGFloat {
        let textHeight = titleFontSize * 1.2 + titleSpacing + subtitleFontSize * 1.2
        let reservedHeight = verticalPadding * 2
            + buttonHeight
            + textHeight
            + footnoteFontSize * 1.3
            + spacing * 3
        let availableHeight = max(58, size.height - reservedHeight)
        let idealHeight = min(size.width * 0.62, size.height * 0.44)
        return clamp(min(idealHeight, availableHeight), 58, 118)
    }

    private func clamp(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}

private struct CRCHeroAnimationView: View {
    var breathingRate: Double = CRCConstants.initialGuidedBreathingRate
    var heartRate: Double = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breathPhase = cyclicProgress(time: time, period: 60 / max(1, breathingRate))
            let heartPhase = cyclicProgress(time: time, period: 60 / max(40, heartRate))
            let breathEase = 0.5 - 0.5 * cos(breathPhase * .pi * 2)
            let heartPulse = pow(max(0, sin(heartPhase * .pi)), 3)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let coreSize = side * (0.46 + 0.08 * breathEase)
                let haloSize = side * (0.70 + 0.14 * breathEase)
                let heartSize = side * (0.19 + 0.03 * heartPulse)

                ZStack {
                    CRCFlowingWave(phase: time * 0.62)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.cyan.opacity(0.45),
                                    Color.blue.opacity(0.35),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: max(2, side * 0.025), lineCap: .round)
                        )
                        .frame(height: side * 0.30)
                        .offset(y: side * 0.23)
                        .opacity(reduceMotion ? 0.28 : 0.70)

                    ForEach(0..<10, id: \.self) { index in
                        let delay = Double(index) / 10
                        let petalPhase = cyclicProgress(time: time + delay * 2.4, period: 4.8)
                        let petalScale = 0.78 + 0.16 * breathEase + 0.06 * sin(petalPhase * .pi * 2)

                        RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.13),
                                        Color.blue.opacity(0.07)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: side * 0.58, height: side * 0.42)
                            .scaleEffect(reduceMotion ? 0.92 : petalScale)
                            .rotationEffect(.degrees(Double(index) * 18 + time * 4))
                            .opacity(0.42)
                    }

                    Circle()
                        .stroke(Color.cyan.opacity(0.22), lineWidth: side * 0.035)
                        .frame(width: haloSize, height: haloSize)
                        .scaleEffect(reduceMotion ? 1 : 0.94 + 0.08 * breathEase)
                        .blur(radius: side * 0.018)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.98),
                                    Color(red: 0.22, green: 0.86, blue: 1.0),
                                    Color(red: 0.18, green: 0.36, blue: 1.0).opacity(0.82),
                                    Color(red: 0.04, green: 0.18, blue: 0.45).opacity(0.16)
                                ],
                                center: .topLeading,
                                startRadius: side * 0.02,
                                endRadius: side * 0.42
                            )
                        )
                        .frame(width: coreSize, height: coreSize)
                        .shadow(color: .cyan.opacity(0.42 + 0.20 * breathEase), radius: side * 0.12)

                    Circle()
                        .stroke(Color.white.opacity(0.26), lineWidth: max(1, side * 0.012))
                        .frame(width: coreSize * 0.74, height: coreSize * 0.74)
                        .scaleEffect(1 + 0.06 * heartPulse)
                        .opacity(0.55 + 0.25 * heartPulse)

                    Image(systemName: "heart.fill")
                        .font(.system(size: heartSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .scaleEffect(1 + 0.10 * heartPulse)
                        .shadow(color: .white.opacity(0.35), radius: side * 0.03)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel("心呼耦合训练动画")
    }

    private func cyclicProgress(time: TimeInterval, period: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        return time.truncatingRemainder(dividingBy: period) / period
    }
}

private struct CRCFlowingWave: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = rect.height * 0.28
        path.move(to: CGPoint(x: rect.minX, y: midY))

        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            let progress = (x - rect.minX) / max(rect.width, 1)
            let wave = sin(progress * .pi * 4.0 + phase * .pi * 2)
            path.addLine(to: CGPoint(x: x, y: midY + wave * amplitude))
        }

        return path
    }
}

private struct CRCPreparationScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStart: () -> Void

    var body: some View {
        CRCScaffold(
            step: 2,
            title: "准备开始训练",
            subtitle: "做好准备，确保数据准确"
        ) {
            VStack(spacing: 7) {
                CRCChecklistRow(
                    icon: "applewatch",
                    tint: .blue,
                    title: "佩戴手表",
                    subtitle: "贴合手腕，避免松动",
                    isReady: true
                )
                CRCChecklistRow(
                    icon: "figure.mind.and.body",
                    tint: .green,
                    title: "保持安静坐姿",
                    subtitle: "放松身体，专注当下",
                    isReady: true
                )
                CRCChecklistRow(
                    icon: "waveform.path.ecg",
                    tint: .purple,
                    title: "开启检测",
                    subtitle: "心率、呼吸与运动",
                    isReady: true
                )

                Button(action: onStart) {
                    Text("开始检测")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            LinearGradient(
                                colors: [.blue.opacity(0.92), .cyan.opacity(0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.top, 2)
            }
        }
    }
}

private struct CRCBaselineScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            step: 3,
            title: "基线检测 30秒",
            subtitle: "采集静息心率与呼吸节律",
            onStop: onStop
        ) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("♥")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.red)
                        .minimumScaleFactor(0.7)
                    Text("\(Int((viewModel.latestHeartRate?.bpm ?? 72).rounded()))")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                    Text("次/分")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity)

                CRCWaveformView(
                    progress: viewModel.baselineProgress,
                    color: .cyan,
                    dotColor: .cyan
                )
                .frame(height: 52)

                VStack(spacing: 5) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.13))
                            Capsule()
                                .fill(Color.cyan)
                                .frame(width: proxy.size.width * viewModel.baselineProgress)
                        }
                    }
                    .frame(height: 6)

                    Text("剩余 \(viewModel.baselineRemaining) 秒")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 5)
            }
        }
    }
}

private struct CRCBreathingGuideScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            step: 4,
            title: "跟随引导，放松呼吸",
            subtitle: "手表通过振动与动画引导呼吸",
            onStop: onStop
        ) {
            VStack(spacing: 8) {
                ZStack {
                    CRCWaveformView(
                        progress: viewModel.snapshot?.phaseProgress ?? 0,
                        color: .cyan.opacity(0.45),
                        dotColor: .clear
                    )
                    .frame(height: 42)
                    .opacity(0.58)

                    CRCBreathingOrb(snapshot: viewModel.snapshot)
                        .frame(width: 128, height: 128)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Image(systemName: "water.waves")
                        .foregroundStyle(.cyan)
                    Text("下次：\(viewModel.snapshot?.phase.nextLabel ?? "呼气")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}

private struct CRCRealtimeMonitorScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            step: 5,
            title: "实时监测中",
            subtitle: "呼吸由陀螺仪融合检测，心率持续监测",
            onStop: onStop
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("呼吸节律")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(String(format: "%.1f 次/分", viewModel.snapshot?.measuredBreathingRate ?? 6.0))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                }

                CRCWaveformView(
                    progress: viewModel.snapshot?.phaseProgress ?? 0,
                    color: .cyan,
                    dotColor: .cyan
                )
                .frame(height: 50)

                Divider()
                    .background(Color.white.opacity(0.18))

                CRCMetricLine(
                    icon: "heart.fill",
                    label: "心率",
                    value: "\(Int(viewModel.snapshot?.heartRate ?? viewModel.latestHeartRate?.bpm ?? 72)) 次/分",
                    tint: .red
                )
                CRCMetricLine(
                    icon: "applewatch.radiowaves.left.and.right",
                    label: "腕部运动",
                    value: viewModel.poseAssessment.isLikelyPlaced ? "稳定" : "调整中",
                    tint: viewModel.poseAssessment.isLikelyPlaced ? .green : .orange
                )
                CRCWristPoseMiniature(assessment: viewModel.poseAssessment)
                    .frame(height: 50)
            }
        }
    }
}

private struct CRCAdaptiveTuningScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            step: 6,
            title: "实时调整引导频率",
            subtitle: "根据心率与呼吸基线自动调节",
            onStop: onStop
        ) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("目标呼吸频率")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", viewModel.snapshot?.previousGuidedBreathingRate ?? 6.0))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text("→")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .minimumScaleFactor(0.7)
                    Text(String(format: "%.1f", viewModel.snapshot?.guidedBreathingRate ?? 5.8))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Spacer()
                    Text("次/分")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                }
                .padding(10)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("调整原因")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text(adaptiveReason)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.cyan)
                    Text("自适应进行中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var adaptiveReason: String {
        guard let snapshot = viewModel.snapshot else {
            return "正在建立心率与呼吸节律的关系。"
        }

        if snapshot.pose.poseConfidence < 0.55 {
            return "姿势信号不稳定，先降低调节幅度，避免误判。"
        }

        if snapshot.heartBreathRatio > CRCConstants.targetHeartBreathRatio + 1 {
            return "检测到心呼比偏高，轻微提高引导频率。"
        }

        return "检测到节律稳定，逐步放慢频率，帮助平稳进入训练。"
    }
}

private struct CRCTrainingFeedbackScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onStop: () -> Void

    var body: some View {
        CRCScaffold(
            step: 7,
            title: "训练中",
            subtitle: "\(formatTime(viewModel.elapsedSeconds))",
            onStop: onStop
        ) {
            VStack(spacing: 12) {
                Text("同步度 / 耦合度")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)

                CRCCircularGauge(value: (viewModel.snapshot?.syncScore ?? 82) / 100) {
                    VStack(spacing: 1) {
                        Text("\(Int((viewModel.snapshot?.syncScore ?? 82).rounded()))%")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text("同步度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        Text(syncLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.18), in: Capsule())
                    }
                }
                .frame(width: 132, height: 132)

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.green)
                    Text(feedbackText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
            }
        }
    }

    private var syncLabel: String {
        let score = viewModel.snapshot?.syncScore ?? 82
        if score >= 78 { return "良好" }
        if score >= 58 { return "稳定" }
        return "调整"
    }

    private var feedbackText: String {
        if viewModel.snapshot?.pose.isLikelyPlaced == false {
            return "手腕信号偏弱，贴近胸腹部"
        }
        return "很好，继续保持节律"
    }
}

private struct CRCReportScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onDone: () -> Void

    var body: some View {
        CRCScaffold(step: 8, title: "训练完成！", subtitle: "本次训练表现") {
            VStack(spacing: 7) {
                if let report = viewModel.report {
                    CRCReportRow(icon: "waveform.path.ecg", title: "耦合指数", value: "\(report.couplingIndex)", tint: .cyan)
                    CRCReportRow(icon: "heart.fill", title: "平均心率", value: "\(report.averageHeartRate) 次/分", tint: .red)
                    CRCReportRow(icon: "swirl.circle.righthalf.filled", title: "平均呼吸频率", value: String(format: "%.1f 次/分", report.averageBreathingRate), tint: .cyan)
                    CRCReportRow(icon: "scope", title: "同步稳定性", value: String(format: "%.2f 良好", report.syncStability), tint: .green)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    Text(report.recommendation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(4)
                        .minimumScaleFactor(0.78)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onDone) {
                Text("完成")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.cyan.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
            }
        }
    }
}

private struct CRCErrorScreen: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("返回", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
        }
        .padding()
    }
}

private struct CRCChecklistRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isReady ? .green : .white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CRCMetricLine: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)
        }
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

private struct CRCBreathingOrb: View {
    let snapshot: CRCSnapshot?

    private var phase: CRCBreathingPhase {
        snapshot?.phase ?? .inhale
    }

    private var progress: Double {
        snapshot?.phaseProgress ?? 0.45
    }

    private var scale: CGFloat {
        let eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2
        switch phase {
        case .inhale:
            return 0.78 + CGFloat(eased) * 0.22
        case .exhale:
            return 1.0 - CGFloat(eased) * 0.22
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .scaleEffect(1.12)
            Circle()
                .stroke(Color.cyan.opacity(0.55), lineWidth: 8)
                .scaleEffect(scale)
                .shadow(color: .cyan.opacity(0.9), radius: 13)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.18), Color.cyan, Color.cyan.opacity(0.25)],
                        center: .top,
                        startRadius: 4,
                        endRadius: 74
                    )
                )
                .scaleEffect(scale * 0.92)

            VStack(spacing: 4) {
                Text(phase.label)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(format: "%.1f 秒", 60 / max(snapshot?.guidedBreathingRate ?? 6, 0.1) * phaseRatio))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: scale)
    }

    private var phaseRatio: Double {
        phase == .inhale ? CRCConstants.inhaleRatio : CRCConstants.exhaleRatio
    }
}

private struct CRCWaveformView: View {
    let progress: Double
    let color: Color
    let dotColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let midY = height / 2
            let amplitude = height * 0.34

            ZStack(alignment: .leading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    for x in stride(from: 0, through: width, by: 2) {
                        let phase = Double(x / max(width, 1)) * .pi * 5.5
                        let y = midY + CGFloat(sin(phase)) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .offset(
                        x: width * progress.crcClampedUnit - 5,
                        y: midY + CGFloat(sin(progress.crcClampedUnit * .pi * 5.5)) * amplitude - 5
                    )
            }
        }
    }
}

private struct CRCCircularGauge<Content: View>: View {
    let value: Double
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 14)
            Circle()
                .trim(from: 0, to: value.crcClampedUnit)
                .stroke(
                    AngularGradient(
                        colors: [.cyan, .green, .cyan],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .green.opacity(0.5), radius: 8)
            content
        }
    }
}

private struct CRCWristPoseMiniature: View {
    let assessment: CRCPoseAssessment

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.28), lineWidth: 2)
                    .frame(width: 42, height: 28)
                RoundedRectangle(cornerRadius: 5)
                    .fill(assessment.isLikelyPlaced ? Color.green : Color.orange)
                    .frame(width: 16, height: 18)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                    .offset(x: -11, y: -8)
            }
            .rotationEffect(.degrees(assessment.isLikelyPlaced ? 0 : -10))

            VStack(alignment: .leading, spacing: 2) {
                Text(assessment.isLikelyPlaced ? "稳定" : "调整姿势")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(assessment.isLikelyPlaced ? .green : .orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(assessment.guidance)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)
            Spacer()
        }
    }
}

private func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

#Preview("CRC Training") {
    CRCTrainingView()
}
