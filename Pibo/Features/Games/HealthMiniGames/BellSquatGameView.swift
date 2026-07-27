import SwiftUI

// MARK: - 摇花铃

private enum BellInputMode: String, CaseIterable, Identifiable {
    case motion
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motion: return "动作感应"
        case .manual: return "手动下 / 起"
        }
    }
}

struct BellSquatGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionInput = MotionGameInput()
    @State private var inputMode = BellInputMode.motion
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var timeLeft = 60
    @State private var reps = 0
    @State private var isDown = false
    @State private var bellSwing = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var countdown = MiniGameCountdownClock(duration: 60)

    var body: some View {
        MiniGameShell(
            kind: .bellSquat,
            scoreText: miniGameScoreText(for: .bellSquat, score: reps),
            detailText: hasStarted ? "\(timeLeft)s · \(gameStatusText)" : setupStatusText,
            onClose: { dismiss() }
        ) {
            if hasStarted {
                bellGameStage
            } else {
                bellSetupStage
            }
        } bottomBar: {
            if hasStarted {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: isRunning ? "暂停" : "继续",
                        system: isRunning ? "pause.fill" : "play.fill",
                        variant: .primary,
                        disabled: showResult
                    ) {
                        isRunning.toggle()
                    }
                    MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
                }
            } else {
                VStack(spacing: LP.Spacing.s) {
                    MiniGameSegmentedPicker(selection: $inputMode) { $0.title }
                        .disabled(motionInput.isBellCalibrating)
                    MiniGameControlBar {
                        MiniGameActionButton(
                            title: setupActionTitle,
                            system: inputMode == .motion ? "sensor.tag.radiowaves.forward" : "play.fill",
                            variant: .primary,
                            disabled: motionInput.isBellCalibrating
                        ) {
                            handleSetupAction()
                        }
                        if inputMode == .motion, motionInput.isBellCalibrated {
                            MiniGameActionButton(title: "重新校准", system: "scope") {
                                motionInput.beginBellCalibration()
                            }
                        }
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "花铃响了 \(reps) 次",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning, hasStarted else { return }
            while !Task.isCancelled, isRunning, !showResult {
                let nextTimeLeft = countdown.secondsLeft()
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: isRunning) { _, running in
            guard hasStarted else { return }
            if running {
                countdown.resume()
                if inputMode == .motion {
                    motionInput.startBellMotion()
                }
            } else {
                countdown.pause()
                motionInput.stopMotion()
            }
        }
        .onChange(of: inputMode) { _, mode in
            guard !hasStarted else { return }
            if mode == .manual {
                motionInput.useManualBell()
            } else {
                motionInput.prepareBellMotionMode()
            }
        }
        .onChange(of: motionInput.requiresManualBellInput) { _, requiresManual in
            if requiresManual {
                inputMode = .manual
                if hasStarted {
                    motionInput.useManualBell()
                }
            }
        }
        .onChange(of: motionInput.bellDownPulse) { oldValue, newValue in
            guard isRunning, inputMode == .motion, newValue > oldValue, !isDown else { return }
            isDown = true
            bellSwing.toggle()
            LPHaptics.tap()
        }
        .onChange(of: motionInput.bellUpPulse) { oldValue, newValue in
            guard isRunning, inputMode == .motion, newValue > oldValue, isDown else { return }
            completeRep()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if isRunning { isRunning = false }
                if motionInput.isBellCalibrating { motionInput.stopMotion() }
            }
        }
        .onDisappear {
            motionInput.stopMotion()
        }
    }

    private var bellSetupStage: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: LP.Spacing.l) {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(MiniGameKind.bellSquat.tint.opacity(0.14))
                            .frame(width: 148, height: 148)
                        Image(systemName: inputMode == .motion ? "iphone.gen3" : "hand.tap")
                            .font(.system(size: 62, weight: .medium))
                            .foregroundStyle(MiniGameKind.bellSquat.tint)
                    }

                    VStack(alignment: .leading, spacing: LP.Spacing.m) {
                        setupLine(
                            number: "1",
                            text: inputMode == .motion ? "把手机竖直贴在胸前，双手轻抱" : "用下、起按钮模拟一组动作"
                        )
                        setupLine(
                            number: "2",
                            text: inputMode == .motion ? "站直后校准，动作中保持同一持姿" : "先按下，再按起，完成一次花铃"
                        )
                        setupLine(number: "3", text: "双脚稳踩地面；不舒服就立即暂停")
                    }
                    .padding(LP.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .fill(LP.Fill.bgContainer.opacity(0.86))
                    )

                    Text(AppLocalization.text(setupStatusText))
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LP.Spacing.l)
                .frame(minHeight: proxy.size.height)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.text("花铃深蹲准备"))
    }

    private var bellGameStage: some View {
        VStack(spacing: LP.Spacing.xxl) {
            Spacer(minLength: 0)
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(LP.Colorful.lime300.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .offset(
                            x: cos(Double(index) * .pi / 6) * CGFloat(80 + min(reps, 24)),
                            y: sin(Double(index) * .pi / 6) * CGFloat(80 + min(reps, 24))
                        )
                        .opacity(bellSwing ? 1 : 0.25)
                }
                MiniGameBellAsset(swing: bellSwing)
                    .frame(width: 150, height: 150)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.45),
                        value: bellSwing
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inputMode == .manual {
                HStack(spacing: LP.Spacing.l) {
                    postureButton(title: "下", system: "arrow.down", active: !isDown) {
                        guard isRunning else { return }
                        guard !isDown else {
                            LPHaptics.decline()
                            return
                        }
                        isDown = true
                        bellSwing.toggle()
                        LPHaptics.tap()
                    }
                    postureButton(title: "起", system: "arrow.up", active: isDown) {
                        guard isRunning, isDown else {
                            LPHaptics.decline()
                            return
                        }
                        completeRep()
                    }
                }
            } else {
                Label(
                    AppLocalization.text(isDown ? "缓慢起身，回到站直姿势" : "缓慢下蹲，上身自然前倾"),
                    systemImage: isDown ? "arrow.up" : "arrow.down"
                )
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
                .padding(.horizontal, LP.Spacing.l)
                .frame(minHeight: 56)
                .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.88)))
            }
        }
    }

    private func setupLine(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: LP.Spacing.m) {
            Text(number)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Fill.foundationOnAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(MiniGameKind.bellSquat.tint))
            Text(AppLocalization.text(text))
                .lpText(LP.Typography.b2Regular)
                .foregroundStyle(LP.Content.primary)
        }
    }

    private var setupStatusText: String {
        inputMode == .manual ? "不使用动作传感器" : motionInput.statusText
    }

    private var setupActionTitle: String {
        if inputMode == .manual { return "开始" }
        if motionInput.isBellCalibrating { return "正在校准" }
        return motionInput.isBellCalibrated ? "开始感应" : "站直校准"
    }

    private var gameStatusText: String {
        if !isRunning { return "已暂停" }
        if inputMode == .manual { return isDown ? "请按起" : "请按下" }
        return motionInput.statusText
    }

    private func handleSetupAction() {
        if inputMode == .motion, !motionInput.isBellCalibrated {
            motionInput.beginBellCalibration()
            return
        }
        startGame()
    }

    private func startGame() {
        hasStarted = true
        timeLeft = 60
        reps = 0
        isDown = false
        showResult = false
        resultMessage = ""
        countdown.reset(startsRunning: true)
        isRunning = true
    }

    private func postureButton(title: String, system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(AppLocalization.text(title), systemImage: system)
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(active ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(width: 104, height: 72)
                .background(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).fill(active ? LP.Fill.foundationAccent : LP.Fill.bgContainer))
                .overlay(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).strokeBorder(LP.Border.tertiary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isRunning || !active)
        .accessibilityHint(AppLocalization.text(active ? "当前动作" : "先完成另一段动作"))
    }

    private func completeRep() {
        isDown = false
        reps += 1
        bellSwing.toggle()
        LPHaptics.success()
    }

    private func reset() {
        motionInput.stopMotion()
        countdown.reset()
        hasStarted = false
        isRunning = false
        timeLeft = 60
        reps = 0
        isDown = false
        bellSwing = false
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        isRunning = false
        motionInput.stopMotion()
        resultMessage = miniGameRecordedResult(
            for: .bellSquat,
            score: reps,
            fallback: reps >= 18 ? "...吵醒花了，勉强算好。" : "...花铃还想再响几下。"
        )
        showResult = true
    }
}
