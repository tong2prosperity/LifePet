import AVFoundation
import Observation
import SwiftUI

private struct PiboBlobView: View {
    let tint: Color

    var body: some View {
        MiniGamePiboAsset(flowerScale: 0.68)
            .overlay(Circle().fill(tint.opacity(0.12)).blendMode(.multiply))
    }
}

// MARK: - 吹散迷雾

struct MistBreathGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var audioInput = BreathAudioInput()
    @State private var isRunning = false
    @State private var hasStarted = false
    @State private var usesMicrophone = false
    @State private var finalScore = 0
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var gameToken = UUID()

    var body: some View {
        MiniGameShell(
            kind: .mistBreath,
            scoreText: showResult ? miniGameScoreText(for: .mistBreath, score: finalScore) : nil,
            detailText: isRunning ? audioInput.statusText : (hasStarted ? "已暂停" : "选择玩法"),
            onClose: { dismiss() }
        ) {
            MistBreathStage(
                audioInput: audioInput,
                isRunning: isRunning,
                hasStarted: hasStarted,
                onFinished: finish
            )
            .id(gameToken)
        } bottomBar: {
            MiniGameControlBar {
                if hasStarted {
                    MiniGameActionButton(
                        title: isRunning ? "暂停" : "继续",
                        system: isRunning ? "pause.fill" : "play.fill",
                        variant: .primary
                    ) {
                        toggleRunning()
                    }
                    MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
                } else {
                    MiniGameActionButton(
                        title: "用麦克风",
                        system: "waveform",
                        variant: .primary
                    ) {
                        startWithMicrophone()
                    }
                    MiniGameActionButton(
                        title: "按住屏幕",
                        system: "hand.point.up.left.fill"
                    ) {
                        startWithTouch()
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "雾散了",
                message: resultMessage,
                primaryTitle: "再吹一次",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .onDisappear { audioInput.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning {
                pause()
            }
        }
    }

    private func startWithMicrophone() {
        usesMicrophone = true
        hasStarted = true
        isRunning = true
        audioInput.start()
    }

    private func startWithTouch() {
        usesMicrophone = false
        hasStarted = true
        isRunning = true
        audioInput.useTouchFallbackPrompt()
    }

    private func toggleRunning() {
        if isRunning {
            pause()
        } else {
            isRunning = true
            if usesMicrophone {
                audioInput.start()
            }
        }
    }

    private func pause() {
        isRunning = false
        audioInput.stop()
    }

    private func reset() {
        audioInput.stop()
        audioInput.resetPrompt()
        isRunning = false
        hasStarted = false
        usesMicrophone = false
        finalScore = 0
        showResult = false
        resultMessage = ""
        gameToken = UUID()
    }

    private func finish(score: Int) {
        guard !showResult else { return }
        finalScore = score
        isRunning = false
        audioInput.stop()
        resultMessage = miniGameRecordedResult(
            for: .mistBreath,
            score: score,
            fallback: "Pibo 的花看起来没那么卡。"
        )
        showResult = true
        LPHaptics.success()
    }
}

private struct MistBreathStage: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let audioInput: BreathAudioInput
    let isRunning: Bool
    let hasStarted: Bool
    let onFinished: (Int) -> Void

    @State private var mist = 1.0
    @State private var isTouchFallbackActive = false
    @State private var lastTickAt = ProcessInfo.processInfo.systemUptime
    @State private var didFinish = false

    var body: some View {
        ZStack {
            VStack(spacing: verticalSizeClass == .compact ? LP.Spacing.s : LP.Spacing.xl) {
                Spacer(minLength: 0)
                PiboBlobView(tint: LP.Fill.foundationAccent)
                    .frame(
                        width: verticalSizeClass == .compact ? 120 : 210,
                        height: verticalSizeClass == .compact ? 132 : 230
                    )
                    .scaleEffect(1.0 + (1 - mist) * 0.08)

                Text("...雾散一点就好...啵")
                    .lpText(LP.Typography.handMid)
                    .foregroundStyle(LP.Content.secondary)

                VStack(spacing: LP.Spacing.s) {
                    HStack {
                        Text(AppLocalization.text("吹散进度"))
                        Spacer()
                        Text("\(progressScore)%")
                            .monospacedDigit()
                    }
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(width: 220)

                    ProgressView(value: Double(progressScore), total: 100)
                        .tint(MiniGameKind.mistBreath.tint)
                        .frame(width: 220)

                    BreathLevelMeter(level: effectiveInputLevel)
                        .frame(width: 220, height: 18)

                    Text(AppLocalization.text(audioInput.helpText))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 290)

                    if !hasStarted {
                        Label(
                            AppLocalization.text("仅在本机检测音量，结束后删除临时录音"),
                            systemImage: "lock.shield"
                        )
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.quarternary)
                        .multilineTextAlignment(.center)
                    }
                }
                Spacer(minLength: 0)
            }

            MistLayer()
                .drawingGroup(opaque: false, colorMode: .linear)
                .opacity(mist)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isRunning else { return }
                    isTouchFallbackActive = true
                }
                .onEnded { _ in isTouchFallbackActive = false }
        )
        .onChange(of: isRunning) { _, running in
            lastTickAt = ProcessInfo.processInfo.systemUptime
            if !running { isTouchFallbackActive = false }
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled, isRunning, !didFinish {
                updateMist(at: ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("吹散迷雾，当前进度 \(progressScore)%"))
        .accessibilityHint(AppLocalization.text("对着麦克风持续呼气，或使用“吹一口”操作"))
        .accessibilityAction(named: AppLocalization.text("吹一口")) {
            applyAccessibleBreath()
        }
    }

    private var effectiveInputLevel: Double {
        max(audioInput.level, isTouchFallbackActive ? 0.62 : 0)
    }

    private var progressScore: Int {
        min(100, max(0, Int(((1 - mist) * 100).rounded())))
    }

    private func updateMist(at now: TimeInterval) {
        guard isRunning, !didFinish else { return }
        let delta = min(0.25, max(0, now - lastTickAt))
        lastTickAt = now
        guard effectiveInputLevel > 0.18 else { return }

        let reductionPerSecond = 0.05 + effectiveInputLevel * 0.10
        mist = max(0, mist - reductionPerSecond * delta)
        if mist <= 0.005 {
            didFinish = true
            onFinished(100)
        }
    }

    private func applyAccessibleBreath() {
        guard isRunning, !didFinish else { return }
        mist = max(0, mist - 0.08)
        LPHaptics.tap()
        if mist <= 0.005 {
            didFinish = true
            onFinished(100)
        }
    }
}

private struct BreathLevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LP.Fill.bgContainer.opacity(0.78))
                Capsule()
                    .fill(LP.Colorful.cyan500)
                    .frame(width: max(8, proxy.size.width * CGFloat(level.clamped(to: 0...1))))
            }
            .overlay(Capsule().strokeBorder(LP.Border.tertiary, lineWidth: 1))
        }
    }
}

private struct MistLayer: View {
    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                Capsule()
                    .fill(LP.Neutral.grey0.opacity(0.72))
                    .frame(width: CGFloat(120 + (index % 5) * 34), height: CGFloat(32 + (index % 3) * 14))
                    .offset(x: CGFloat((index % 4) * 70 - 110),
                            y: CGFloat((index / 4) * 74 - 120))
            }
        }
        .blur(radius: 9)
    }
}

@Observable
private final class BreathAudioInput {
    var level = 0.0
    var isRunning = false
    var statusText = "准备吹气"
    var helpText = "选择麦克风检测呼气，或选择按住屏幕模式"

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var requestGeneration = 0

    func start() {
        guard !isRunning else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startRecorder()
        case .denied:
            statusText = "触摸吹气"
            helpText = "麦克风未开启，按住屏幕也能继续吹雾"
        case .undetermined:
            statusText = "等待麦克风权限"
            helpText = "仅检测呼气音量；也可以拒绝并按住屏幕继续"
            requestGeneration += 1
            let generation = requestGeneration
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                guard let input = self else { return }
                Task { @MainActor in
                    guard input.requestGeneration == generation else { return }
                    allowed ? input.startRecorder() : input.markDenied()
                }
            }
        @unknown default:
            markDenied()
        }
    }

    func stop() {
        requestGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }
        isRunning = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func resetPrompt() {
        stop()
        statusText = "准备吹气"
        helpText = "选择麦克风检测呼气，或选择按住屏幕模式"
    }

    func useTouchFallbackPrompt() {
        stop()
        statusText = "触摸吹气"
        helpText = "按住屏幕持续吹气，松开就会停下"
    }

    private func startRecorder() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)

            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pibo_breath_meter.caf")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleIMA4),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 16_000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                markDenied()
                return
            }
            self.recorder = recorder
            recordingURL = url
            isRunning = true
            statusText = "正在听呼气"
            helpText = "呼气越稳，雾散得越快"

            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                guard let input = self else { return }
                Task { @MainActor in input.updateMeter() }
            }
        } catch {
            markDenied()
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = ((Double(power) + 48) / 34).clamped(to: 0...1)
        level = level * 0.72 + normalized * 0.28
    }

    private func markDenied() {
        stop()
        statusText = "触摸吹气"
        helpText = "麦克风不可用，按住屏幕也能继续吹雾"
    }
}
