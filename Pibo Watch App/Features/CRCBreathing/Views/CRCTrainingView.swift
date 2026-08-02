import SwiftUI

struct CRCTrainingView: View {
    private enum Route { case home, duration, session }

    @StateObject private var viewModel = CRCTrainingViewModel()
    @StateObject private var status = WatchPiboStatusStore()
    @State private var route: Route = .home

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PiboWatchVisualTraining") {
            _route = State(initialValue: .session)
        }
#endif
    }

    var body: some View {
        ZStack {
            CRCWatchBackground()
            switch route {
            case .home:
                PiboStatusHome(status: status) { route = .duration }
            case .duration:
                CRCDurationScreen(
                    selectedSeconds: $viewModel.selectedDurationSeconds,
                    onStart: {
                        route = .session
                        Task { await viewModel.startDetection() }
                    },
                    onBack: { route = .home }
                )
            case .session:
                sessionScreen
            }
            transientOverlay
        }
        .task {
            await status.refresh()
#if DEBUG
            viewModel.startVisualValidationIfRequested()
#endif
        }
    }

    @ViewBuilder
    private var sessionScreen: some View {
        switch viewModel.step {
        case .intro:
            ProgressView().tint(.mint)
        case .coreTraining:
            CRCCoreTrainingScreen(viewModel: viewModel) { viewModel.openMenu() }
        case .report:
            CRCReportScreen(viewModel: viewModel) {
                viewModel.reset()
                route = .home
                Task { await status.refresh() }
            }
        case .error:
            CRCErrorScreen(
                message: viewModel.errorMessage ?? "暂时无法开始训练",
                onRetry: { Task { await viewModel.startDetection() } },
                onBack: { Task { await leaveSession(discard: true) } }
            )
        }
    }

    @ViewBuilder
    private var transientOverlay: some View {
        switch viewModel.transient {
        case .none: EmptyView()
        case .menu:
            CRCMenuOverlay(
                onResume: { viewModel.resumeTraining() },
                onSave: { Task { await viewModel.stopTraining() } },
                onDiscard: { Task { await leaveSession(discard: true) } }
            )
        case .unstable:
            CRCUnstableOverlay { viewModel.dismissUnstable() }
        }
    }

    private func leaveSession(discard: Bool) async {
        if discard { await viewModel.discardTraining() }
        route = .home
        await status.refresh()
    }
}

private enum CRCPalette {
    static let mint = Color(red: 0.48, green: 0.94, blue: 0.73)
    static let moss = Color(red: 0.29, green: 0.37, blue: 0.22)
    static let glow = Color(red: 0.20, green: 0.78, blue: 0.63)
    static let dim = Color.white.opacity(0.58)
}

private struct CRCWatchBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.03, green: 0.18, blue: 0.14).opacity(0.34), .clear],
                center: .top,
                startRadius: 4,
                endRadius: 190
            )
            .ignoresSafeArea()
            Circle()
                .fill(CRCPalette.mint.opacity(0.09))
                .frame(width: 4, height: 4)
                .blur(radius: 1)
                .offset(x: 72, y: -94)
        }
    }
}

private struct PiboStatusHome: View {
    @ObservedObject var status: WatchPiboStatusStore
    let onBreathe: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 1) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    Circle()
                        .fill(CRCPalette.glow.opacity(0.16))
                        .frame(width: 112, height: 112)
                        .blur(radius: 18)
                        .offset(y: -7)
                    CRCGroundLight()
                        .frame(width: 102, height: 18)
                    PiboStatusPose(state: status.vectorState)
                        .padding(.bottom, 5)
                        .offset(y: -17)
                }
                .frame(height: min(139, proxy.size.height * 0.54))
                .accessibilityLabel(status.title)

                Text(status.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(status.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CRCPalette.dim)
                    .lineLimit(1)

                Button(action: onBreathe) {
                    Label("一起呼吸", systemImage: "wind")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(CRCPalette.moss, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.top, 8)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct PiboStatusPose: View {
    let state: PiboVectorState

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            PiboStateAnimator(state: .constant(state))
                .id(state)
                .frame(width: 300, height: 300)
                .scaleEffect(side / 260)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct CRCGroundLight: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<4 {
                let inset = CGFloat(index) * 9
                let rect = CGRect(
                    x: inset,
                    y: CGFloat(index) * 3,
                    width: size.width - inset * 2,
                    height: 7
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(CRCPalette.glow.opacity(0.42 - Double(index) * 0.07)),
                    lineWidth: 0.7
                )
            }
        }
        .blur(radius: 0.4)
    }
}

private struct CRCDurationScreen: View {
    @Binding var selectedSeconds: Int
    let onStart: () -> Void
    let onBack: () -> Void
    private let choices = [60, 180, 300]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.75))
                Text("呼吸多久？")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(choices, id: \.self) { seconds in
                    Button {
                        selectedSeconds = seconds
                    } label: {
                        HStack {
                            Text("\(seconds / 60) 分钟")
                            Spacer()
                            if selectedSeconds == seconds {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            selectedSeconds == seconds ? CRCPalette.mint.opacity(0.2) : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedSeconds == seconds ? CRCPalette.mint : .white)
                }
            }

            Button(action: onStart) {
                Text("开始")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(CRCPalette.mint, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.84))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}

private struct CRCCoreTrainingScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onMenu: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Text(viewModel.snapshot?.phase.label ?? "准备")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text(formatTime(viewModel.remainingSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CRCPalette.dim)
                    .contentTransition(.numericText())

                PiboBreathingGuideView(snapshot: viewModel.snapshot)
                    .frame(height: min(138, proxy.size.height * 0.56))

                HStack(spacing: 0) {
                    CRCMetric(title: "心率", value: heartRateText, unit: "")
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 31)
                    CRCMetric(title: "≈HRV", value: hrvText, unit: "ms", emphasized: true)
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 31)
                    CRCMetric(title: "节奏", value: breathRateText, unit: "次/分", emphasized: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .topLeading) {
                Button(action: onMenu) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private var heartRateText: String {
        viewModel.latestHeartRate.map { "\(Int($0.bpm.rounded()))" } ?? "--"
    }
    private var hrvText: String {
        guard let value = viewModel.liveHRV, value >= 5 else { return "--" }
        return "\(Int(value.rounded()))"
    }
    private var breathRateText: String {
        guard let rate = viewModel.snapshot?.guidedBreathingRate else { return "--" }
        return String(format: "%.1f", rate)
    }
}

private struct CRCMetric: View {
    let title: String
    let value: String
    let unit: String
    var emphasized = false

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(CRCPalette.dim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                }
            }
            .foregroundStyle(emphasized ? Color(red: 0.57, green: 0.68, blue: 0.30) : .white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }
}

private struct CRCReportScreen: View {
    @ObservedObject var viewModel: CRCTrainingViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(CRCPalette.mint)
                Text("呼吸完成")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Pibo 的呼吸慢慢安静下来")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CRCPalette.dim)

                if let report = viewModel.report {
                    CRCReportRow(title: "时长", value: formatTime(Int(report.duration)))
                    CRCReportRow(title: "平均心率", value: "\(report.averageHeartRate) 次/分")
                    if let hrv = report.sessionRMSSD ?? report.liveHRVAverage {
                        CRCReportRow(
                            title: report.sessionRMSSD == nil ? "HRV 估算" : "HRV",
                            value: "\(report.sessionRMSSD == nil ? "≈" : "")\(Int(hrv.rounded())) ms"
                        )
                    }
                }
                Button("完成", action: onDone)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 35)
                    .background(CRCPalette.mint, in: Capsule())
                    .buttonStyle(.plain)
                    .foregroundStyle(.black.opacity(0.84))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CRCReportRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(CRCPalette.dim)
            Spacer()
            Text(value).foregroundStyle(.white)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CRCErrorScreen: View {
    let message: String
    let onRetry: () -> Void
    let onBack: () -> Void
    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            CRCOverlayButton(title: "重试", background: CRCPalette.mint, foreground: .black, action: onRetry)
            CRCOverlayButton(title: "返回", background: .white.opacity(0.13), foreground: .white, action: onBack)
        }
        .padding(.horizontal, 15)
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 33)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }
}

private struct CRCMenuOverlay: View {
    let onResume: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void
    var body: some View {
        CRCOverlayScrim {
            Text("暂停呼吸")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            CRCOverlayButton(title: "继续", background: CRCPalette.mint, foreground: .black, action: onResume)
            CRCOverlayButton(title: "保存并结束", background: .white.opacity(0.14), foreground: .white, action: onSave)
            CRCOverlayButton(title: "放弃本次", background: .red.opacity(0.55), foreground: .white, action: onDiscard)
        }
    }
}

private struct CRCUnstableOverlay: View {
    let onContinue: () -> Void
    var body: some View {
        CRCOverlayScrim {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 27)).foregroundStyle(.yellow)
            Text("信号不太稳定")
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("放松手腕，再继续")
                .font(.system(size: 11)).foregroundStyle(CRCPalette.dim)
            CRCOverlayButton(title: "继续", background: CRCPalette.mint, foreground: .black, action: onContinue)
        }
    }
}

private struct CRCOverlayScrim<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 10) { content }
                .padding(.horizontal, 15)
        }
    }
}

private func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

#Preview("Pibo Watch 46mm") {
    CRCTrainingView()
        .frame(width: 208, height: 248)
}
