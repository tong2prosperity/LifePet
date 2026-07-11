import SwiftUI
import CoreMotion
import AVFoundation
import Vision

private enum SimpleDifficulty: String, CaseIterable, Identifiable {
    case easy
    case normal
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "轻"
        case .normal: return "稳"
        case .hard: return "狠"
        }
    }
}

private enum NBackLevel: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one: return "一阶"
        case .two: return "二阶"
        case .three: return "三阶"
        }
    }

    var harder: NBackLevel {
        switch self {
        case .one: return .two
        case .two, .three: return .three
        }
    }

    var easier: NBackLevel {
        switch self {
        case .one, .two: return .one
        case .three: return .two
        }
    }
}

// MARK: - 原地踏步点灯
private enum StepInputMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动计步"
        case .manual: return "手动交替"
        }
    }
}

struct StepLightsGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionInput = MotionGameInput()
    @State private var inputMode = StepInputMode.automatic
    @State private var isRunning = false
    @State private var timeLeft = 45
    @State private var steps = 0
    @State private var laneSide = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var countdown = MiniGameCountdownClock(duration: 45)

    var body: some View {
        MiniGameShell(
            kind: .stepLights,
            scoreText: miniGameScoreText(for: .stepLights, score: steps),
            detailText: "\(timeLeft)s · \(inputStatusText)",
            onClose: { dismiss() }
        ) {
            GeometryReader { proxy in
                VStack(spacing: LP.Spacing.m) {
                    VStack(spacing: LP.Spacing.xs) {
                        HStack {
                            Text(AppLocalization.text("第 \(currentLap) 圈"))
                            Spacer()
                            Text(AppLocalization.text("\(lapSteps)/20 步"))
                        }
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(LP.Content.secondary)

                        ProgressView(value: Double(lapSteps), total: 20)
                            .tint(MiniGameKind.stepLights.tint)
                    }
                    .padding(.horizontal, LP.Spacing.m)

                    if proxy.size.width > proxy.size.height {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(visibleTrail, id: \.self) { index in
                                trailLamp(index: index)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visibleTrail.reversed(), id: \.self) { index in
                                HStack {
                                    if index.isMultiple(of: 2) {
                                        trailLamp(index: index)
                                        Spacer(minLength: 58)
                                    } else {
                                        Spacer(minLength: 58)
                                        trailLamp(index: index)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isManualInput {
                        HStack(spacing: LP.Spacing.l) {
                            footButton(title: "左", side: false)
                            footButton(title: "右", side: true)
                        }
                    } else {
                        Label(AppLocalization.text("手机随身携带，原地自然踏步"), systemImage: "figure.walk.motion")
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(LP.Content.secondary)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.m)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                MiniGameSegmentedPicker(selection: $inputMode) { $0.title }
                    .disabled(isRunning)
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: isRunning ? "暂停" : (timeLeft < 45 ? "继续" : "开始"),
                        system: isRunning ? "pause.fill" : "play.fill",
                        variant: .primary,
                        disabled: showResult
                    ) {
                        if timeLeft == 0 { reset() }
                        isRunning.toggle()
                    }
                    MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "踏亮了 \(steps) 步",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning else { return }
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
            if running {
                countdown.resume()
                if inputMode == .automatic {
                    motionInput.startPedometer()
                } else {
                    motionInput.useManualSteps()
                }
            } else {
                countdown.pause()
                motionInput.stopPedometer()
            }
        }
        .onChange(of: motionInput.stepPulse) { oldValue, newValue in
            guard isRunning, inputMode == .automatic, newValue > oldValue else { return }
            let newSteps = newValue - oldValue
            for offset in 0..<newSteps {
                registerStep(haptic: offset == newSteps - 1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning, !showResult {
                isRunning = false
            }
        }
        .onDisappear {
            motionInput.stopPedometer()
        }
    }

    private var isManualInput: Bool {
        inputMode == .manual || motionInput.requiresManualStepInput
    }

    private var inputStatusText: String {
        if isManualInput {
            return motionInput.requiresManualStepInput ? "自动不可用 · 手动左右脚" : "手动左右脚"
        }
        return motionInput.statusText
    }

    private var visibleTrail: [Int] {
        let start = max(0, steps - 5)
        return Array(start..<(start + 12))
    }

    private var currentLap: Int {
        (max(1, steps) - 1) / 20 + 1
    }

    private var lapSteps: Int {
        steps == 0 ? 0 : (steps - 1) % 20 + 1
    }

    private func trailLamp(index: Int) -> some View {
        let isLit = index < steps
        let isNext = index == steps

        return HStack(spacing: LP.Spacing.s) {
            Circle()
                .fill(isLit ? LP.Colorful.yellow400 : LP.Fill.bgContainer.opacity(0.74))
                .frame(width: isNext ? 38 : 30, height: isNext ? 38 : 30)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isNext ? LP.Fill.foundationAccent : (isLit ? LP.Colorful.yellow700.opacity(0.35) : LP.Border.tertiary),
                            lineWidth: isNext ? 3 : 1
                        )
                )
                .shadow(color: isLit ? LP.Colorful.yellow400.opacity(0.5) : .clear, radius: 10)
            Text("\(index + 1)")
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(isNext ? LP.Content.primary : LP.Content.tertiary)
                .monospacedDigit()
        }
        .frame(width: 78, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
    }

    private func footButton(title: String, side: Bool) -> some View {
        return Button {
            guard isRunning else { return }
            if side == laneSide {
                registerStep()
            } else {
                LPHaptics.decline()
            }
        } label: {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(side == laneSide ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(width: 88, height: 88)
                .background(Circle().fill(side == laneSide ? LP.Fill.foundationAccent : LP.Fill.bgContainer))
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isRunning || side != laneSide)
        .accessibilityHint(AppLocalization.text(side == laneSide ? "下一步按这里" : "先按另一只脚"))
    }

    private func registerStep(haptic: Bool = true) {
        if haptic { LPHaptics.success() }
        steps += 1
        laneSide.toggle()
    }

    private func reset() {
        motionInput.stopPedometer()
        countdown.reset()
        isRunning = false
        timeLeft = 45
        steps = 0
        laneSide = false
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        isRunning = false
        motionInput.stopPedometer()
        resultMessage = miniGameRecordedResult(
            for: .stepLights,
            score: steps,
            fallback: steps >= 80 ? "...行吧，Pibo 有点亮了。" : "...还没热起来，再踩一局。"
        )
        showResult = true
        LPHaptics.success()
    }
}

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

// MARK: - 记忆矩阵

struct MemoryMatrixGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(PiboPersistenceKeys.Defaults.memoryMatrixDifficulty)
    private var storedDifficultyRaw = SimpleDifficulty.normal.rawValue

    @State private var difficulty: SimpleDifficulty = .normal
    @State private var level = 1
    @State private var targets = Set<Int>()
    @State private var selected = Set<Int>()
    @State private var hasStarted = false
    @State private var isShowing = false
    @State private var isReviewing = false
    @State private var missedTargets = Set<Int>()
    @State private var wrongSelections = Set<Int>()
    @State private var revealSecondsLeft = 0
    @State private var score = 0
    @State private var roundsCleared = 0
    @State private var showResult = false
    @State private var resultTitle = "完成一组"
    @State private var resultMessage = ""
    @State private var roundToken = 0
    @State private var roundTask: Task<Void, Never>?
    @State private var pendingDifficulty: SimpleDifficulty?
    @State private var showDifficultyConfirmation = false
    @State private var pausedForBackground = false
    private let sessionRounds = 6

    private var gridSize: Int {
        switch difficulty {
        case .easy: return 3
        case .normal: return 4
        case .hard: return 5
        }
    }

    var body: some View {
        MiniGameShell(
            kind: .memoryMatrix,
            scoreText: miniGameScoreText(for: .memoryMatrix, score: score),
            detailText: roundDetailText,
            onClose: { dismiss() }
        ) {
            memoryStage
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                if dynamicTypeSize.isAccessibilitySize {
                    memoryDifficultyMenu
                    HStack(spacing: LP.Spacing.s) {
                        memoryActions
                    }
                } else {
                    MiniGameSegmentedPicker(selection: difficultyBinding) { $0.title }
                    MiniGameControlBar {
                        memoryActions
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: resultTitle,
                message: resultMessage,
                primaryTitle: "再练",
                primarySystem: "arrow.clockwise",
                primaryAction: {
                    resetSession()
                    startSession()
                }
            )
        }
        .onAppear {
            let restored = SimpleDifficulty(rawValue: storedDifficultyRaw) ?? .normal
            difficulty = restored
            resetSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumeAfterBackground()
            } else {
                pauseForBackground()
            }
        }
        .onDisappear { roundTask?.cancel() }
        .confirmationDialog(
            AppLocalization.text("切换难度会重开这一组"),
            isPresented: $showDifficultyConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("切换并重开"), role: .destructive) {
                if let pendingDifficulty { applyDifficulty(pendingDifficulty) }
                pendingDifficulty = nil
            }
            Button(AppLocalization.text("继续当前难度"), role: .cancel) {
                pendingDifficulty = nil
            }
        }
    }

    private var roundDetailText: String {
        if showResult { return "完成" }
        if !hasStarted { return "\(difficulty.title) · 准备" }
        if isReviewing { return "复盘错格" }
        if isShowing { return "\(roundsCleared + 1)/\(sessionRounds) · 记住 · \(revealSecondsLeft)s" }
        return "\(roundsCleared + 1)/\(sessionRounds) · 点回来"
    }

    private var memoryStage: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = gridSize == 5 ? 6 : 8
            let minimumCellSide: CGFloat = 44
            let minimumGridSide = minimumCellSide * CGFloat(gridSize)
                + spacing * CGFloat(gridSize - 1)
            let fittingSide = min(proxy.size.width, max(0, proxy.size.height - 40))
            let gridSide = max(minimumGridSide, min(360, fittingSide))

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                VStack(spacing: LP.Spacing.m) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: spacing),
                            count: gridSize
                        ),
                        spacing: spacing
                    ) {
                        ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                            memoryCell(index)
                        }
                    }
                    .frame(width: gridSide, height: gridSide)

                    Group {
                        if isReviewing {
                            Text(AppLocalization.text("漏了 \(missedTargets.count) 格 · 多点 \(wrongSelections.count) 格"))
                                .foregroundStyle(LP.Fill.foundationError)
                        } else if isShowing {
                            Text(AppLocalization.text("还有 \(revealSecondsLeft) 秒"))
                                .foregroundStyle(LP.Content.secondary)
                                .monospacedDigit()
                        } else {
                            Text(" ")
                                .accessibilityHidden(true)
                        }
                    }
                    .lpText(LP.Typography.c1Medium)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 24)
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .top)
            }
        }
    }

    private var memoryDifficultyMenu: some View {
        Menu {
            ForEach(SimpleDifficulty.allCases) { option in
                Button {
                    difficultyBinding.wrappedValue = option
                } label: {
                    if option == difficulty {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text("难度 · \(difficulty.title)"))
                    .lpText(LP.Typography.c1Medium)
                Spacer(minLength: LP.Spacing.s)
                Image(systemName: "chevron.up.chevron.down")
            }
            .foregroundStyle(LP.Content.secondary)
            .padding(.horizontal, LP.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.72)))
            .overlay(Capsule().strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair))
        }
        .accessibilityLabel(AppLocalization.text("选择难度，当前\(difficulty.title)"))
    }

    @ViewBuilder
    private var memoryActions: some View {
        MiniGameActionButton(
            title: "重开",
            system: "arrow.clockwise",
            disabled: !hasStarted
        ) {
            resetSession()
        }
        MiniGameActionButton(
            title: hasStarted ? "提交" : "开始",
            system: hasStarted ? "checkmark" : "play.fill",
            variant: .primary,
            disabled: hasStarted && (isShowing || isReviewing || showResult)
        ) {
            hasStarted ? submit() : startSession()
        }
    }

    private var difficultyBinding: Binding<SimpleDifficulty> {
        Binding(
            get: { difficulty },
            set: { newDifficulty in
                guard newDifficulty != difficulty else { return }
                if hasStarted, roundsCleared > 0 || score > 0 || !isShowing {
                    pendingDifficulty = newDifficulty
                    showDifficultyConfirmation = true
                } else {
                    applyDifficulty(newDifficulty)
                }
            }
        )
    }

    private func memoryCell(_ index: Int) -> some View {
        Button {
            guard hasStarted, !isShowing, !isReviewing else { return }
            if selected.contains(index) {
                selected.remove(index)
            } else {
                selected.insert(index)
            }
            LPHaptics.tap()
        } label: {
            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                .fill(cellColor(index))
                .overlay(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).strokeBorder(LP.Border.primary, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous))
        }
        .buttonStyle(MemoryMatrixCellButtonStyle())
        .aspectRatio(1, contentMode: .fit)
        .disabled(!hasStarted || isShowing || isReviewing)
        .accessibilityLabel(AppLocalization.text("第 \(index / gridSize + 1) 排第 \(index % gridSize + 1) 格"))
        .accessibilityValue(AppLocalization.text(cellAccessibilityValue(index)))
        .accessibilityIdentifier("memoryMatrix.cell.\(index)")
    }

    private func cellColor(_ index: Int) -> Color {
        if isReviewing, wrongSelections.contains(index) { return LP.Fill.foundationError }
        if isReviewing, missedTargets.contains(index) { return LP.Colorful.yellow400 }
        if isShowing, targets.contains(index) { return LP.Fill.foundationAccent }
        if selected.contains(index) { return LP.Colorful.cyan400 }
        return LP.Fill.bgContainer.opacity(0.86)
    }

    private func newRound() {
        roundTask?.cancel()
        roundToken += 1
        selected = []
        missedTargets = []
        wrongSelections = []
        isReviewing = false
        resultMessage = ""
        isShowing = true
        let count = min(gridSize * gridSize - 1, 2 + level)
        targets = Set((0..<(gridSize * gridSize)).shuffled().prefix(count))
        let duration = Double(count) * 0.28 + 0.9
        scheduleReveal(duration: duration)
    }

    private func startSession() {
        guard !hasStarted, !showResult else { return }
        hasStarted = true
        newRound()
    }

    private func scheduleReveal(duration: TimeInterval) {
        roundTask?.cancel()
        let token = roundToken
        let revealEndsAt = ProcessInfo.processInfo.systemUptime + duration
        revealSecondsLeft = max(1, Int(ceil(duration)))
        roundTask = Task {
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < revealEndsAt {
                let nextSeconds = max(
                    1,
                    Int(ceil(revealEndsAt - ProcessInfo.processInfo.systemUptime))
                )
                if nextSeconds != revealSecondsLeft { revealSecondsLeft = nextSeconds }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, roundToken == token else { return }
            revealSecondsLeft = 0
            isShowing = false
        }
    }

    private func submit() {
        guard !showResult, !isShowing else { return }
        if selected == targets {
            score += targets.count * 10
            LPHaptics.success()
            roundsCleared += 1
            if roundsCleared >= sessionRounds {
                finish(title: "完成一组", fallback: "练这个挑战本身会越来越准。")
            } else {
                level += 1
                newRound()
            }
        } else {
            LPHaptics.decline()
            missedTargets = targets.subtracting(selected)
            wrongSelections = selected.subtracting(targets)
            isReviewing = true
            scheduleReviewFinish()
        }
    }

    private func scheduleReviewFinish() {
        roundTask?.cancel()
        let token = roundToken
        roundTask = Task {
            try? await Task.sleep(for: .milliseconds(1_250))
            guard !Task.isCancelled, roundToken == token else { return }
            finish(
                title: "差一点",
                fallback: "漏了 \(missedTargets.count) 格，多点了 \(wrongSelections.count) 格。"
            )
        }
    }

    private func pauseForBackground() {
        guard hasStarted, !showResult, !pausedForBackground else { return }
        roundTask?.cancel()
        pausedForBackground = true
    }

    private func resumeAfterBackground() {
        guard pausedForBackground, !showResult else { return }
        pausedForBackground = false
        if isShowing {
            scheduleReveal(duration: max(1, TimeInterval(revealSecondsLeft)))
        } else if isReviewing {
            scheduleReviewFinish()
        }
    }

    private func resetSession() {
        roundTask?.cancel()
        roundToken += 1
        level = 1
        score = 0
        roundsCleared = 0
        hasStarted = false
        targets = []
        selected = []
        missedTargets = []
        wrongSelections = []
        isShowing = false
        isReviewing = false
        revealSecondsLeft = 0
        showResult = false
        pausedForBackground = false
        resultTitle = "完成一组"
        resultMessage = ""
    }

    private func applyDifficulty(_ newDifficulty: SimpleDifficulty) {
        difficulty = newDifficulty
        storedDifficultyRaw = newDifficulty.rawValue
        resetSession()
    }

    private func cellAccessibilityValue(_ index: Int) -> String {
        if isReviewing, wrongSelections.contains(index) { return "多点的格" }
        if isReviewing, missedTargets.contains(index) { return "漏掉的目标格" }
        if isShowing, targets.contains(index) { return "亮着" }
        if selected.contains(index) { return "已选择" }
        return "未选择"
    }

    private func finish(title: String, fallback: String) {
        roundTask?.cancel()
        resultTitle = title
        resultMessage = miniGameRecordedResult(
            for: .memoryMatrix,
            score: score,
            fallback: fallback
        )
        showResult = true
    }
}

private struct MemoryMatrixCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
final class BreathAudioInput {
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

// MARK: - Pibo 漂浮

struct BreathFloatGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var elapsedBeforeRun = 0.0
    @State private var runStartedAt = ProcessInfo.processInfo.systemUptime
    @State private var timeLeft = 60
    @State private var score = 0
    @State private var combo = 0
    @State private var ringY = Double.random(in: 0.28...0.72)
    @State private var feedback = "跟着呼吸上下移动，重合时点屏幕"
    @State private var showResult = false
    @State private var resultMessage = ""

    private let cycleLength = 10.0
    private let sessionLength = 60.0

    var body: some View {
        MiniGameShell(
            kind: .breathFloat,
            scoreText: miniGameScoreText(for: .breathFloat, score: score),
            detailText: hasStarted
                ? (isRunning ? "\(timeLeft)s · 连 \(combo)" : "暂停 · \(timeLeft)s · 连 \(combo)")
                : "看准圆环再开始",
            onClose: { dismiss() }
        ) {
            TimelineView(
                .animation(
                    minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                    paused: !isRunning || showResult
                )
            ) { _ in
                GeometryReader { proxy in
                    let phase = breathPhase(at: ProcessInfo.processInfo.systemUptime)
                    let distance = abs(phase.y - ringY)

                    ZStack {
                        ForEach(0..<5, id: \.self) { index in
                            Capsule()
                                .fill(LP.Colorful.cyan200.opacity(0.45))
                                .frame(width: proxy.size.width * CGFloat(0.32 + Double(index) * 0.08), height: 2)
                                .position(x: proxy.size.width * CGFloat(0.5),
                                          y: proxy.size.height * CGFloat(0.2 + Double(index) * 0.13))
                        }

                        Capsule()
                            .fill(MiniGameKind.breathFloat.tint.opacity(distance < 0.09 ? 0.18 : 0.07))
                            .frame(width: 132, height: proxy.size.height * 0.18)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * ringY)

                        Circle()
                            .stroke(MiniGameKind.breathFloat.tint, lineWidth: distance < 0.09 ? 10 : 7)
                            .frame(width: 112, height: 112)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * ringY)
                            .shadow(
                                color: MiniGameKind.breathFloat.tint.opacity(distance < 0.09 ? 0.58 : 0.24),
                                radius: distance < 0.09 ? 22 : 10
                            )

                        MiniGamePiboAsset(flowerScale: 0.72)
                            .frame(width: 96, height: 106)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * phase.y)

                        VStack(spacing: 3) {
                            Text(AppLocalization.text(phase.isInhale ? "吸气 · 上浮" : "呼气 · 下沉"))
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(LP.Content.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                            Text(AppLocalization.text(feedback))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.tertiary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, LP.Spacing.m)
                        .padding(.vertical, LP.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgContainer.opacity(0.9))
                        )
                        .position(
                            x: proxy.size.width / 2,
                            y: dynamicTypeSize.isAccessibilitySize ? 66 : 34
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { passRing() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AppLocalization.text("Pibo 漂浮游戏区"))
                    .accessibilityValue(AppLocalization.text(
                        "\(phase.isInhale ? "吸气上浮" : "呼气下沉")，\(ringProximityText(distance: distance))。\(feedback)"
                    ))
                    .accessibilityHint(AppLocalization.text("重合时双击穿过圆环"))
                    .accessibilityAction { passRing() }
                }
            }
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(title: "穿过", system: "circle.dashed", variant: .primary, disabled: !isRunning) {
                    passRing()
                }
                MiniGameActionButton(
                    title: isRunning ? "暂停" : (hasStarted ? "继续" : "开始"),
                    system: isRunning ? "pause.fill" : "play.fill"
                ) {
                    toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") {
                    reset()
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "穿过 \(score)",
                message: resultMessage,
                primaryTitle: "再漂",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .task(id: isRunning) {
            guard isRunning, !showResult else { return }
            while !Task.isCancelled, isRunning, !showResult {
                let nextTimeLeft = max(
                    0,
                    Int(ceil(sessionLength - elapsed(at: ProcessInfo.processInfo.systemUptime)))
                )
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning, !showResult {
                pause()
            }
        }
    }

    private func elapsed(at now: TimeInterval) -> Double {
        min(
            sessionLength,
            elapsedBeforeRun + (isRunning ? max(0, now - runStartedAt) : 0)
        )
    }

    private func breathPhase(at now: TimeInterval) -> (y: Double, isInhale: Bool) {
        let phaseTime = elapsed(at: now).truncatingRemainder(dividingBy: cycleLength)
        let isInhale = phaseTime < 4
        let progress = isInhale ? phaseTime / 4 : (phaseTime - 4) / 6
        let y = isInhale ? 0.78 - progress * 0.54 : 0.24 + progress * 0.54
        return (y, isInhale)
    }

    private func ringProximityText(distance: Double) -> String {
        if distance < 0.035 { return "正对圆心" }
        if distance < 0.09 { return "接近圆环" }
        return "还没对齐"
    }

    private func passRing(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isRunning, !showResult else { return }
        let phase = breathPhase(at: now)
        let distance = abs(phase.y - ringY)
        if distance < 0.09 {
            combo += 1
            score += 10 + combo
            feedback = distance < 0.035 ? "正中圆环！" : "穿过去了"
            moveRing(awayFrom: phase.y)
            LPHaptics.success()
        } else {
            combo = 0
            feedback = distance < 0.16 ? "差一点，再贴近圆心" : "等 Pibo 靠近圆环"
            LPHaptics.decline()
        }
    }

    private func moveRing(awayFrom y: Double) {
        let candidates = [0.3, 0.42, 0.58, 0.7].filter { abs($0 - y) > 0.16 }
        ringY = candidates.randomElement() ?? 0.5
    }

    private func toggleRunning() {
        if isRunning {
            pause()
        } else {
            resume()
        }
    }

    private func pause() {
        elapsedBeforeRun = elapsed(at: ProcessInfo.processInfo.systemUptime)
        isRunning = false
    }

    private func resume() {
        guard !showResult else { return }
        hasStarted = true
        runStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
    }

    private func reset() {
        hasStarted = false
        isRunning = false
        elapsedBeforeRun = 0
        runStartedAt = ProcessInfo.processInfo.systemUptime
        timeLeft = 60
        score = 0
        combo = 0
        ringY = Double.random(in: 0.28...0.72)
        feedback = "跟着呼吸上下移动，重合时点屏幕"
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        isRunning = false
        resultMessage = miniGameRecordedResult(
            for: .breathFloat,
            score: score,
            fallback: score >= 50 ? "...穿过去了，别太骄傲。" : "...呼吸还在水面下。"
        )
        showResult = true
    }
}

// MARK: - 双 n-back

struct DualNBackGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(PiboPersistenceKeys.Defaults.dualNBackLevel)
    private var storedNLevelRaw = NBackLevel.one.rawValue

    @State private var nLevel: NBackLevel = .two
    @State private var trial = 0
    @State private var score = 0
    @State private var positions: [Int] = []
    @State private var symbols: [String] = []
    @State private var feedback = "准备"
    @State private var phaseText = "准备"
    @State private var phaseSecondsLeft = 0
    @State private var isStimulusVisible = true
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var showResult = false
    @State private var selectedPositionMatch = false
    @State private var selectedSymbolMatch = false
    @State private var hasAnsweredCurrent = false
    @State private var resultMessage = ""
    @State private var pendingNLevel: NBackLevel?
    @State private var trialTask: Task<Void, Never>?
    @State private var positionCorrect = 0
    @State private var positionTotal = 0
    @State private var symbolCorrect = 0
    @State private var symbolTotal = 0

    private let symbolPool = ["P", "I", "B", "O"]
    private var n: Int { nLevel.rawValue }

    var body: some View {
        MiniGameShell(
            kind: .dualNBack,
            scoreText: miniGameScoreText(for: .dualNBack, score: score),
            detailText: "\(nLevel.title) · \(trial)/20 · \(hasStarted ? (isRunning ? phaseText : "已暂停") : "准备")",
            onClose: { dismiss() }
        ) {
            VStack(spacing: LP.Spacing.xxl) {
                Spacer(minLength: 0)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(0..<9, id: \.self) { index in
                        RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                            .fill(isStimulusVisible && index == positions.last ? LP.Fill.foundationAccent : LP.Fill.bgContainer.opacity(0.8))
                            .overlay {
                                if isStimulusVisible, index == positions.last {
                                    Text(symbols.last ?? "")
                                        .lpText(LP.Typography.uiH4)
                                        .foregroundStyle(LP.Fill.foundationOnAccent)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: 320)

                if hasStarted {
                    Text(AppLocalization.text(feedback))
                        .lpText(LP.Typography.handMid)
                        .foregroundStyle(LP.Content.secondary)
                    if phaseSecondsLeft > 0 {
                        Text("\(phaseSecondsLeft)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(LP.Fill.foundationAccent)
                            .monospacedDigit()
                    }
                } else {
                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        Label(AppLocalization.text("先看位置和符号"), systemImage: "1.circle.fill")
                        Label(AppLocalization.text("和 \(n) 题前相同时，点对应按钮"), systemImage: "2.circle.fill")
                        Label(AppLocalization.text("不相同就不点，等待下一题"), systemImage: "3.circle.fill")
                    }
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .padding(LP.Spacing.m)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .fill(LP.Fill.bgContainer.opacity(0.9))
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                if dynamicTypeSize.isAccessibilitySize {
                    nBackLevelMenu
                } else {
                    MiniGameSegmentedPicker(selection: $nLevel) { $0.title }
                        .disabled(hasStarted && !showResult)
                        .opacity(hasStarted && !showResult ? 0.55 : 1)
                }
                HStack(spacing: LP.Spacing.s) {
                    MiniGameActionButton(
                        title: selectedPositionMatch ? "位置已选" : "位置重复",
                        system: "square.grid.3x3.fill",
                        variant: selectedPositionMatch ? .primary : .secondary,
                        disabled: showResult || hasAnsweredCurrent || positions.count <= n || !isRunning
                    ) {
                        selectedPositionMatch.toggle()
                    }
                    MiniGameActionButton(
                        title: selectedSymbolMatch ? "符号已选" : "符号重复",
                        system: "textformat",
                        variant: selectedSymbolMatch ? .primary : .secondary,
                        disabled: showResult || hasAnsweredCurrent || symbols.count <= n || !isRunning
                    ) {
                        selectedSymbolMatch.toggle()
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: LP.Spacing.s) {
                        nBackSessionActions
                    }
                } else {
                    MiniGameControlBar {
                        nBackSessionActions
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "完成一组",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { applyPendingLevelAndReset() }
            )
        }
        .onAppear {
            let restored = NBackLevel(rawValue: storedNLevelRaw) ?? .two
            if restored == nLevel {
                reset()
            } else {
                nLevel = restored
            }
        }
        .onChange(of: nLevel) { _, newLevel in
            storedNLevelRaw = newLevel.rawValue
            reset()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isRunning, !showResult {
                pause()
            }
        }
        .onDisappear { trialTask?.cancel() }
    }

    private var nBackLevelMenu: some View {
        Menu {
            ForEach(NBackLevel.allCases) { option in
                Button {
                    nLevel = option
                } label: {
                    if option == nLevel {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: LP.Spacing.s) {
                Text(AppLocalization.text("难度 · \(nLevel.title)"))
                    .lpText(LP.Typography.c1Medium)
                Spacer(minLength: LP.Spacing.s)
                Image(systemName: "chevron.up.chevron.down")
            }
            .foregroundStyle(LP.Content.secondary)
            .padding(.horizontal, LP.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.72)))
            .overlay(Capsule().strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair))
        }
        .disabled(hasStarted && !showResult)
        .opacity(hasStarted && !showResult ? 0.55 : 1)
        .accessibilityLabel(AppLocalization.text("选择难度，当前\(nLevel.title)"))
    }

    @ViewBuilder
    private var nBackSessionActions: some View {
        MiniGameActionButton(
            title: isRunning ? "暂停" : (hasStarted ? "继续" : "开始"),
            system: isRunning ? "pause.fill" : "play.fill",
            variant: .primary,
            disabled: showResult
        ) {
            if !hasStarted {
                startSession()
            } else {
                isRunning ? pause() : resume()
            }
        }
        MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
    }

    private func submitAnswer() {
        guard !showResult, !hasAnsweredCurrent else { return }
        guard positions.count > n else {
            feedback = "还没有足够早的线索"
            LPHaptics.decline()
            return
        }
        let positionMatch = positions[positions.count - 1] == positions[positions.count - 1 - n]
        let symbolMatch = symbols[symbols.count - 1] == symbols[symbols.count - 1 - n]
        let positionWasCorrect = selectedPositionMatch == positionMatch
        let symbolWasCorrect = selectedSymbolMatch == symbolMatch
        positionTotal += 1
        symbolTotal += 1
        if positionWasCorrect {
            positionCorrect += 1
            score += 5
        }
        if symbolWasCorrect {
            symbolCorrect += 1
            score += 5
        }

        let omissions = [
            positionMatch && !selectedPositionMatch ? "位置" : nil,
            symbolMatch && !selectedSymbolMatch ? "符号" : nil
        ].compactMap { $0 }
        if positionWasCorrect, symbolWasCorrect {
            feedback = "两项都对"
            LPHaptics.success()
        } else if !omissions.isEmpty {
            feedback = "漏答：\(omissions.joined(separator: "、"))相同"
            LPHaptics.decline()
        } else {
            let wrongParts = [
                positionWasCorrect ? nil : "位置",
                symbolWasCorrect ? nil : "符号"
            ].compactMap { $0 }
            feedback = "\(wrongParts.joined(separator: "、"))判断错了"
            LPHaptics.decline()
        }
        hasAnsweredCurrent = true
    }

    private func advanceTrial() {
        guard trial < 20 else {
            let adaptedLevel = adaptiveLevel()
            pendingNLevel = adaptedLevel
            let adaptiveLine = adaptedLevel == nLevel
                ? "下一组继续 \(nLevel.title)。"
                : "下一组调到 \(adaptedLevel.title)。"
            resultMessage = miniGameRecordedResult(
                for: .dualNBack,
                score: score,
                fallback: "位置正确率 \(accuracy(correct: positionCorrect, total: positionTotal))，符号正确率 \(accuracy(correct: symbolCorrect, total: symbolTotal))。\n\(adaptiveLine)"
            )
            showResult = true
            isRunning = false
            return
        }
        selectedPositionMatch = false
        selectedSymbolMatch = false
        hasAnsweredCurrent = false
        trial += 1
        var nextPosition = Int.random(in: 0..<9)
        var nextSymbol = symbolPool.randomElement() ?? "P"
        if trial > n, Bool.random() {
            nextPosition = positions[positions.count - n]
        }
        if trial > n, Bool.random() {
            nextSymbol = symbols[symbols.count - n]
        }
        positions.append(nextPosition)
        symbols.append(nextSymbol)
        feedback = trial <= n ? "只记住，不用作答" : "记住后判断和 \(n) 题前是否相同"
        isStimulusVisible = true
        scheduleCurrentTrial()
    }

    private func scheduleCurrentTrial() {
        trialTask?.cancel()
        guard isRunning, !showResult else { return }
        let tokenTrial = trial
        trialTask = Task {
            guard await waitPhase(seconds: 1.2, title: trial <= n ? "记忆" : "呈现") else { return }
            guard tokenTrial == trial else { return }
            isStimulusVisible = false

            if trial <= n {
                feedback = "建立 \(n)-back 线索"
                guard await waitPhase(seconds: 0.5, title: "准备下一题") else { return }
            } else {
                feedback = "现在作答；不点也算一次回答"
                guard await waitPhase(seconds: 1.8, title: "作答") else { return }
                guard tokenTrial == trial else { return }
                submitAnswer()
                guard await waitPhase(seconds: 0.55, title: "反馈") else { return }
            }

            guard !Task.isCancelled, tokenTrial == trial, isRunning else { return }
            advanceTrial()
        }
    }

    private func waitPhase(seconds: TimeInterval, title: String) async -> Bool {
        phaseText = title
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        phaseSecondsLeft = max(1, Int(ceil(seconds)))
        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            let next = max(
                1,
                Int(ceil(deadline - ProcessInfo.processInfo.systemUptime))
            )
            if next != phaseSecondsLeft { phaseSecondsLeft = next }
            try? await Task.sleep(for: .milliseconds(100))
        }
        phaseSecondsLeft = 0
        return !Task.isCancelled
    }

    private func pause() {
        trialTask?.cancel()
        isRunning = false
        phaseText = "已暂停"
    }

    private func startSession() {
        guard !showResult, !hasStarted else { return }
        hasStarted = true
        isRunning = true
        advanceTrial()
    }

    private func resume() {
        guard !showResult else { return }
        selectedPositionMatch = false
        selectedSymbolMatch = false
        hasAnsweredCurrent = false
        isStimulusVisible = true
        isRunning = true
        feedback = trial <= n ? "重新看这一题，不用抢时间" : "重新呈现这一题"
        scheduleCurrentTrial()
    }

    private func reset() {
        trialTask?.cancel()
        trial = 0
        score = 0
        positions = []
        symbols = []
        feedback = "准备"
        phaseText = "准备"
        phaseSecondsLeft = 0
        isStimulusVisible = true
        hasStarted = false
        isRunning = false
        showResult = false
        pendingNLevel = nil
        selectedPositionMatch = false
        selectedSymbolMatch = false
        hasAnsweredCurrent = false
        resultMessage = ""
        positionCorrect = 0
        positionTotal = 0
        symbolCorrect = 0
        symbolTotal = 0
    }

    private func adaptiveLevel() -> NBackLevel {
        if score >= 160 { return nLevel.harder }
        if score <= 80 { return nLevel.easier }
        return nLevel
    }

    private func applyPendingLevelAndReset() {
        if let pendingNLevel, pendingNLevel != nLevel {
            nLevel = pendingNLevel
        } else {
            reset()
        }
    }

    private func accuracy(correct: Int, total: Int) -> String {
        guard total > 0 else { return "—" }
        return "\(Int((Double(correct) / Double(total) * 100).rounded()))%"
    }
}

// MARK: - 镜前接花瓣

struct MirrorPetalsGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var poseInput = PetalPoseInput()
    @State private var model = MirrorPetalsGameModel()
    @State private var inputMode: MirrorPetalsInputMode?

    var body: some View {
        MiniGameShell(
            kind: .mirrorPetals,
            scoreText: miniGameScoreText(for: .mirrorPetals, score: model.score),
            detailText: detailText,
            onClose: { dismiss() }
        ) {
            MirrorPetalsStage(
                model: model,
                poseInput: poseInput,
                inputMode: inputMode
            )
        } bottomBar: {
            if model.hasStarted {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: model.isRunning ? "暂停" : "继续",
                        system: model.isRunning ? "pause.fill" : "play.fill",
                        variant: .primary,
                        disabled: model.isFinished
                    ) {
                        toggleRunning()
                    }
                    MiniGameActionButton(title: "重来", system: "arrow.clockwise") { reset() }
                }
            } else if inputMode == .camera {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: poseInput.isTracking ? "开始接花" : "举起手腕",
                        system: poseInput.isTracking ? "play.fill" : "figure.arms.open",
                        variant: .primary,
                        disabled: !poseInput.isTracking
                    ) {
                        startCameraGame()
                    }
                    MiniGameActionButton(title: "改用拖动", system: "hand.draw") {
                        startManualGame()
                    }
                }
            } else {
                MiniGameControlBar {
                    MiniGameActionButton(
                        title: "手腕识别",
                        system: "camera.viewfinder",
                        variant: .primary
                    ) {
                        chooseCameraMode()
                    }
                    MiniGameActionButton(title: "拖动接盘", system: "hand.draw") {
                        startManualGame()
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "接住 \(model.caught) 片花瓣",
                message: model.resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .onDisappear {
            poseInput.stop()
            model.stopLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.isRunning {
                pause()
            }
        }
    }

    private var detailText: String {
        if model.hasStarted {
            return model.isRunning
                ? "\(model.timeLeft)s · 连 \(model.combo) · 黑洞 \(model.strikes)/3"
                : "暂停 · 连 \(model.combo)"
        }
        if inputMode == .camera { return poseInput.statusText }
        return "选择玩法"
    }

    private func chooseCameraMode() {
        inputMode = .camera
        poseInput.start()
    }

    private func startCameraGame() {
        guard poseInput.isTracking else { return }
        inputMode = .camera
        model.setPlayerX(poseInput.playerX)
        model.start()
    }

    private func startManualGame() {
        poseInput.stop()
        inputMode = .manual
        model.start()
    }

    private func toggleRunning() {
        if model.isRunning {
            pause()
        } else {
            model.resume()
            if inputMode == .camera { poseInput.start() }
        }
    }

    private func pause() {
        model.pause()
        if inputMode == .camera { poseInput.stop() }
    }

    private func reset() {
        poseInput.stop()
        poseInput.resetPrompt()
        model.reset()
        inputMode = nil
    }
}

private enum MirrorPetalsInputMode: Equatable {
    case camera
    case manual
}

private struct MirrorPetalsStage: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: MirrorPetalsGameModel
    let poseInput: PetalPoseInput
    let inputMode: MirrorPetalsInputMode?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if inputMode == .camera, poseInput.isReady {
                    CameraFramePreview(session: poseInput.session)
                        .opacity(model.hasStarted ? 0.24 : 0.48)
                }

                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(inputMode == .camera ? 0.28 : 0.58))

                if !model.hasStarted {
                    setupContent(in: proxy.size)
                } else {
                    gameContent(in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.hasStarted else { return }
                        model.setPlayerX(Double(value.location.x / max(1, proxy.size.width)))
                    }
            )
            .onAppear { model.updateStageSize(proxy.size) }
            .onChange(of: proxy.size) { _, size in model.updateStageSize(size) }
        }
        .onChange(of: poseInput.playerX) { _, newValue in
            guard inputMode == .camera, model.hasStarted, model.isRunning else { return }
            model.setPlayerX(newValue)
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { poseInput.stop() }
        }
        .accessibilityElement(children: model.hasStarted ? .ignore : .contain)
        .accessibilityLabel(AppLocalization.text(
            model.hasStarted ? "镜前接花瓣，接住 \(model.caught) 片" : "镜前接花瓣准备"
        ))
        .accessibilityHint(AppLocalization.text(
            model.hasStarted
                ? "左右轻扫移动接盘，避开黑洞"
                : "选择手腕识别或拖动接盘"
        ))
        .accessibilityValue(AppLocalization.text(
            model.hasStarted
                ? "接盘在 \(Int((model.playerX * 100).rounded()))%"
                : "尚未开始"
        ))
        .accessibilityAction(named: AppLocalization.text("接盘左移")) {
            guard model.hasStarted, model.isRunning else { return }
            model.movePlayer(by: -0.12)
        }
        .accessibilityAction(named: AppLocalization.text("接盘右移")) {
            guard model.hasStarted, model.isRunning else { return }
            model.movePlayer(by: 0.12)
        }
    }

    @ViewBuilder
    private func setupContent(in size: CGSize) -> some View {
        if inputMode == .camera {
            VStack(spacing: LP.Spacing.l) {
                Image(systemName: poseInput.isTracking ? "checkmark.circle.fill" : "figure.arms.open")
                    .font(.system(size: verticalSizeClass == .compact ? 48 : 72, weight: .medium))
                    .foregroundStyle(poseInput.isTracking ? LP.Fill.foundationAccent : LP.Content.secondary)
                    .frame(
                        width: verticalSizeClass == .compact ? 110 : 150,
                        height: verticalSizeClass == .compact ? 104 : 190
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .stroke(
                                poseInput.isTracking ? LP.Fill.foundationAccent : LP.Border.primary,
                                style: StrokeStyle(lineWidth: 2, dash: [8, 7])
                            )
                    )
                Text(AppLocalization.text(poseInput.isTracking ? "手腕已找到" : "把手机立稳，举起一只手腕"))
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.text(poseInput.helpText))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
            }
            .frame(width: size.width, height: size.height)
        } else {
            VStack(spacing: LP.Spacing.xl) {
                Spacer(minLength: 0)
                MiniGamePetalAsset()
                    .frame(width: 66, height: 92)
                Text(AppLocalization.text("接花瓣，避开黑洞"))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.text("可以用前置镜头追踪手腕，也可以直接拖动接盘。普通花瓣漏掉不会结束游戏。"))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func gameContent(in size: CGSize) -> some View {
        ForEach(model.petals) { petal in
            MiniGamePetalAsset()
                .frame(width: petal.size * 0.78, height: petal.size * 1.28)
                .position(x: petal.x * size.width, y: petal.y * size.height)
        }

        ForEach(model.hazards) { hazard in
            MiniGameBlackHoleAsset()
                .frame(width: hazard.size, height: hazard.size)
                .position(x: hazard.x * size.width, y: hazard.y * size.height)
        }

        Capsule()
            .fill(LP.Fill.foundationAccent)
            .frame(width: 92, height: 28)
            .overlay(Capsule().strokeBorder(.white.opacity(0.58), lineWidth: 1))
            .position(x: model.playerX * size.width, y: size.height - 48)

        MiniGameStageCaption(
            inputMode == .camera ? poseInput.helpText : "拖动屏幕移动接盘",
            textStyle: LP.Typography.c2Medium,
            foreground: LP.Content.tertiary,
            fill: LP.Fill.bgContainer.opacity(0.88)
        )
        .position(
            x: size.width / 2,
            y: dynamicTypeSize.isAccessibilitySize ? 54 : 26
        )
    }
}

@MainActor
@Observable
private final class MirrorPetalsGameModel {
    var playerX = 0.5
    var petals: [FallingPetal] = []
    var hazards: [PetalHazard] = []
    var caught = 0
    var score = 0
    var combo = 0
    var strikes = 0
    var timeLeft = 45
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastUpdateAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var remainingTime = 45.0
    @ObservationIgnored private var nextPetalIn = 0.35
    @ObservationIgnored private var nextHazardIn = 2.8
    @ObservationIgnored private var stageSize = CGSize(width: 360, height: 500)

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isRunning = true
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        startLoop()
    }

    func pause() {
        isRunning = false
        stopLoop()
    }

    func resume() {
        guard hasStarted, !isFinished else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        startLoop()
    }

    func reset() {
        stopLoop()
        playerX = 0.5
        petals = []
        hazards = []
        caught = 0
        score = 0
        combo = 0
        strikes = 0
        timeLeft = 45
        remainingTime = 45
        nextPetalIn = 0.35
        nextHazardIn = 2.8
        hasStarted = false
        isRunning = false
        isFinished = false
        resultMessage = ""
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
    }

    func setPlayerX(_ value: Double) {
        playerX = value.clamped(to: 0.08...0.92)
    }

    func movePlayer(by amount: Double) {
        guard hasStarted, isRunning, !isFinished else { return }
        playerX = (playerX + amount).clamped(to: 0.08...0.92)
        LPHaptics.tap()
    }

    func updateStageSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        stageSize = size
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = min(0.06, max(0, now - self.lastUpdateAt))
                self.lastUpdateAt = now
                self.tick(delta: delta)
            }
        }
    }

    private func tick(delta: TimeInterval) {
        guard isRunning, !isFinished, delta > 0 else { return }

        remainingTime = max(0, remainingTime - delta)
        let nextTimeLeft = max(0, Int(ceil(remainingTime)))
        if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }

        nextPetalIn -= delta
        if nextPetalIn <= 0 {
            petals.append(FallingPetal(
                x: Double.random(in: 0.1...0.9),
                y: 0,
                speed: Double.random(in: 90...145),
                size: CGFloat.random(in: 20...30)
            ))
            nextPetalIn = Double.random(in: 0.42...0.78)
        }

        nextHazardIn -= delta
        if nextHazardIn <= 0 {
            hazards.append(PetalHazard(
                x: Double.random(in: 0.1...0.9),
                y: 0,
                speed: Double.random(in: 80...120),
                size: CGFloat.random(in: 34...48)
            ))
            nextHazardIn = Double.random(in: 2.8...4.4)
        }

        var didCatch = false
        var didMissPetal = false
        var nextPetals: [FallingPetal] = []
        nextPetals.reserveCapacity(petals.count)
        for var petal in petals {
            petal.y += petal.speed / Double(stageSize.height) * delta
            if catcherRect.intersects(petalRect(petal)) {
                caught += 1
                combo += 1
                score += 1 + min(2, combo / 5)
                didCatch = true
            } else if petalRect(petal).minY > stageSize.height + 4 {
                didMissPetal = true
            } else {
                nextPetals.append(petal)
            }
        }
        if nextPetals != petals { petals = nextPetals }
        if didMissPetal { combo = 0 }
        if didCatch { LPHaptics.success() }

        var hitHazard = false
        var nextHazards: [PetalHazard] = []
        nextHazards.reserveCapacity(hazards.count)
        for var hazard in hazards {
            hazard.y += hazard.speed / Double(stageSize.height) * delta
            if catcherRect.intersects(hazardRect(hazard)) {
                strikes += 1
                combo = 0
                hitHazard = true
            } else if hazardRect(hazard).minY <= stageSize.height + 4 {
                nextHazards.append(hazard)
            }
        }
        if nextHazards != hazards { hazards = nextHazards }
        if hitHazard { LPHaptics.decline() }

        if strikes >= 3 {
            finish(message: "...黑洞碰了三次，手腕先休息。")
        } else if remainingTime <= 0 {
            finish(message: caught >= 24 ? "...接得还算稳。" : "...花瓣先落到地上。")
        }
    }

    private var catcherRect: CGRect {
        CGRect(
            x: playerX * Double(stageSize.width) - 46,
            y: Double(stageSize.height) - 62,
            width: 92,
            height: 28
        )
    }

    private func petalRect(_ petal: FallingPetal) -> CGRect {
        let width = Double(petal.size * 0.78)
        let height = Double(petal.size * 1.28)
        return CGRect(
            x: petal.x * Double(stageSize.width) - width / 2,
            y: petal.y * Double(stageSize.height) - height / 2,
            width: width,
            height: height
        )
    }

    private func hazardRect(_ hazard: PetalHazard) -> CGRect {
        CGRect(
            x: hazard.x * Double(stageSize.width) - Double(hazard.size) / 2,
            y: hazard.y * Double(stageSize.height) - Double(hazard.size) / 2,
            width: Double(hazard.size),
            height: Double(hazard.size)
        )
    }

    private func finish(message: String) {
        guard !isFinished else { return }
        isRunning = false
        stopLoop()
        resultMessage = miniGameRecordedResult(for: .mirrorPetals, score: score, fallback: message)
        isFinished = true
    }
}

private struct FallingPetal: Identifiable, Equatable {
    let id = UUID()
    var x: Double
    var y: Double
    var speed: Double
    var size: CGFloat
}

private struct PetalHazard: Identifiable, Equatable {
    let id = UUID()
    var x: Double
    var y: Double
    var speed: Double
    var size: CGFloat
}

private struct CameraFramePreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

@Observable
final class PetalPoseInput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @ObservationIgnored nonisolated(unsafe) let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "fun.tiebao.co.Pibo.games.pose")
    @ObservationIgnored nonisolated(unsafe) private let output = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated(unsafe) private let poseRequest = VNDetectHumanBodyPoseRequest()
    @ObservationIgnored nonisolated(unsafe) private var lastVisionAt = Date.distantPast
    @ObservationIgnored nonisolated(unsafe) private var lastDetectionAt = Date.distantPast
    @ObservationIgnored private var requestGeneration = 0

    var playerX = 0.5
    var isRunning = false
    var isReady = false
    var isTracking = false
    var statusText = "镜头待机"
    var helpText = "镜头只在本机识别手腕，不保存画面"

    @MainActor
    func start() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            statusText = "等待相机权限"
            helpText = "允许后把手机立稳，举起一只手腕"
            requestGeneration += 1
            let generation = requestGeneration
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let input = self else { return }
                Task { @MainActor in
                    guard input.requestGeneration == generation else { return }
                    granted ? input.configureAndStart() : input.markUnavailable()
                }
            }
        default:
            markUnavailable()
        }
    }

    @MainActor
    func stop() {
        requestGeneration += 1
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        isRunning = false
        isReady = false
        isTracking = false
    }

    @MainActor
    func resetPrompt() {
        stop()
        playerX = 0.5
        statusText = "镜头待机"
        helpText = "镜头只在本机识别手腕，不保存画面"
    }

    @MainActor
    private func configureAndStart() {
        statusText = "正在寻找手腕"
        helpText = "把手机立稳，让上半身和手腕进入画面"
        isRunning = true
        isTracking = false
        lastVisionAt = .distantPast
        lastDetectionAt = .distantPast
        let generation = requestGeneration
        queue.async {
            if self.session.inputs.isEmpty {
                self.buildSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let ready = !self.session.inputs.isEmpty
            Task { @MainActor in
                guard self.requestGeneration == generation, self.isRunning else { return }
                if ready {
                    self.isReady = true
                } else {
                    self.markUnavailable()
                }
            }
        }
    }

    private nonisolated func buildSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        output.connection(with: .video)?.videoRotationAngle = 90
        output.connection(with: .video)?.isVideoMirrored = true
    }

    @MainActor
    private func markUnavailable() {
        isRunning = false
        isReady = false
        isTracking = false
        statusText = "拖动接盘"
        helpText = "相机不可用，拖动下方接盘继续玩"
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = Date()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard now.timeIntervalSince(lastVisionAt) > 0.12 else { return }
        lastVisionAt = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        let detectedX: Double?
        do {
            detectedX = try Self.detectWristX(request: poseRequest, handler: handler)
        } catch {
            return
        }

        guard let x = detectedX else {
            if now.timeIntervalSince(lastDetectionAt) > 0.8 {
                Task { @MainActor in
                    guard self.isRunning, self.isTracking else { return }
                    self.isTracking = false
                    self.statusText = "举起一只手腕"
                    self.helpText = "让肩膀和手腕都留在画面里"
                }
            }
            return
        }
        lastDetectionAt = now
        Task { @MainActor in
            guard self.isRunning else { return }
            let smoothedX = self.playerX * 0.62 + x * 0.38
            if abs(self.playerX - smoothedX) > 0.006 {
                self.playerX = smoothedX
            }
            if !self.isTracking {
                self.isTracking = true
                self.statusText = "手腕已找到"
                self.helpText = "移动手腕接花瓣，避开黑洞"
            }
        }
    }

    private nonisolated static func detectWristX(
        request: VNDetectHumanBodyPoseRequest,
        handler: VNImageRequestHandler
    ) throws -> Double? {
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        let points = try observation.recognizedPoints(.all)
        let wrists = [VNHumanBodyPoseObservation.JointName.leftWrist, .rightWrist]
            .compactMap { points[$0] }
            .filter { $0.confidence > 0.28 }
        guard let wrist = wrists.max(by: { $0.confidence < $1.confidence }) else { return nil }
        return min(max(Double(wrist.location.x), 0.08), 0.92)
    }
}

// MARK: - Speed Match

struct SpeedMatchGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var previous: SpeedMatchCard?
    @State private var current = SpeedMatchCard.random()
    @State private var score = 0
    @State private var streak = 0
    @State private var correctAnswers = 0
    @State private var timeLeft = 45
    @State private var running = false
    @State private var isExample = true
    @State private var isRevealing = false
    @State private var feedbackText = "先记住这一张，不计分"
    @State private var questionElapsedBeforeRun = 0.0
    @State private var questionStartedAt = ProcessInfo.processInfo.systemUptime
    @State private var advanceTask: Task<Void, Never>?
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var countdown = MiniGameCountdownClock(duration: 45)

    private let cardColors: [Color] = [
        LP.Colorful.red500,
        LP.Colorful.cyan500,
        LP.Colorful.purple500,
        LP.Colorful.orange500
    ]

    private var pace: SpeedMatchPace {
        if correctAnswers >= 12 { return .flash }
        if correctAnswers >= 5 { return .quick }
        return .steady
    }

    private var questionDuration: TimeInterval { pace.duration }

    var body: some View {
        MiniGameShell(
            kind: .speedMatch,
            scoreText: miniGameScoreText(for: .speedMatch, score: score),
            detailText: isExample
                ? "示例牌 · 准备"
                : (running ? "\(pace.title) · \(timeLeft)s · 连 \(streak)" : "暂停 · 连 \(streak)"),
            onClose: { dismiss() }
        ) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !running || isRevealing || showResult)) { _ in
                let remaining = max(
                    0,
                    1 - questionElapsed(at: ProcessInfo.processInfo.systemUptime) / questionDuration
                )
                VStack(spacing: LP.Spacing.l) {
                    ProgressView(value: isExample ? 1 : remaining)
                        .tint(isRevealing ? LP.Fill.foundationSuccess : MiniGameKind.speedMatch.tint)
                        .frame(maxWidth: 240)
                        .opacity(isExample ? 0.35 : 1)

                    Spacer(minLength: 0)
                    Text(current.symbol)
                        .font(.system(size: 92, weight: .bold, design: .rounded))
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .frame(width: 190, height: 190)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                                .fill(cardColors[current.colorIndex])
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                                .strokeBorder(.white.opacity(0.72), lineWidth: 3)
                        )
                        .shadow(color: cardColors[current.colorIndex].opacity(0.26), radius: 18, y: 8)
                        .rotationEffect(.degrees(streak.isMultiple(of: 2) ? -2 : 2))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppLocalization.text(current.accessibilityLabel))

                    VStack(spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text(isExample ? "示例牌" : "符号和颜色都要比"))
                            .lpText(LP.Typography.handMid)
                            .foregroundStyle(LP.Content.secondary)
                        Text(AppLocalization.text(feedbackText))
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(isRevealing ? LP.Content.primary : LP.Content.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minHeight: 56)
                    Spacer(minLength: 0)
                }
            }
        } bottomBar: {
            VStack(spacing: LP.Spacing.s) {
                if isExample {
                    MiniGameControlBar {
                        MiniGameActionButton(title: "记住，开始", system: "play.fill", variant: .primary) {
                            beginSession()
                        }
                        MiniGameActionButton(title: "换一张", system: "arrow.clockwise") {
                            current = .random()
                        }
                    }
                } else {
                    MiniGameControlBar {
                        MiniGameActionButton(
                            title: "不同",
                            system: "xmark",
                            variant: .secondary,
                            disabled: !running || isRevealing || showResult
                        ) { answer(match: false) }
                        MiniGameActionButton(
                            title: "完全相同",
                            system: "checkmark",
                            variant: .primary,
                            disabled: !running || isRevealing || showResult
                        ) { answer(match: true) }
                    }
                    MiniGameControlBar {
                        MiniGameActionButton(
                            title: running ? "暂停" : "继续",
                            system: running ? "pause.fill" : "play.fill",
                            disabled: showResult
                        ) {
                            running ? pause() : resume()
                        }
                        MiniGameActionButton(title: "重来", system: "arrow.clockwise") {
                            reset()
                        }
                    }
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "反应分 \(score)",
                message: resultMessage,
                primaryTitle: "再来",
                primarySystem: "arrow.clockwise",
                primaryAction: { reset() }
            )
        }
        .onAppear { reset() }
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled, running, !showResult {
                let nextTimeLeft = countdown.secondsLeft()
                if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
                if nextTimeLeft == 0 {
                    finish()
                    return
                }
                if !isExample,
                   !isRevealing,
                   questionElapsed(at: ProcessInfo.processInfo.systemUptime) >= questionDuration {
                    LPHaptics.decline()
                    revealAnswer(wasCorrect: false, prefix: "超时")
                }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, running, !showResult {
                pause()
            }
        }
        .onDisappear { advanceTask?.cancel() }
    }

    private func answer(match: Bool) {
        guard running, !isExample, !isRevealing, let previous else { return }
        let correct = ((previous == current) == match)
        if correct {
            streak += 1
            let responseProgress = max(
                0,
                1 - questionElapsed(at: ProcessInfo.processInfo.systemUptime) / questionDuration
            )
            correctAnswers += 1
            score += 6 + Int((responseProgress * 6).rounded()) + min(8, streak)
            LPHaptics.success()
        } else {
            streak = 0
            LPHaptics.decline()
        }
        revealAnswer(wasCorrect: correct, prefix: correct ? "答对" : "答错")
    }

    private func revealAnswer(wasCorrect: Bool, prefix: String) {
        guard !isRevealing, let previous else { return }
        if !wasCorrect { streak = 0 }
        let correctAnswer = previous == current ? "完全相同" : differenceText(previous, current)
        let milestone = wasCorrect && [5, 12].contains(correctAnswers) ? " · 节奏升级" : ""
        feedbackText = "\(prefix)：\(correctAnswer)\(milestone)"
        isRevealing = true
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, running, !showResult else { return }
            advanceQuestion()
        }
    }

    private func beginSession() {
        previous = current
        isExample = false
        countdown.reset(startsRunning: true)
        running = true
        timeLeft = 45
        advanceQuestion()
    }

    private func advanceQuestion() {
        let last = current
        previous = last
        if Bool.random() {
            current = last
        } else {
            current = SpeedMatchCard.nearMiss(from: last, unlockColorOnly: correctAnswers >= 5)
        }
        isRevealing = false
        feedbackText = "\(pace.title)：判断是否完全相同"
        questionElapsedBeforeRun = 0
        questionStartedAt = ProcessInfo.processInfo.systemUptime
    }

    private func questionElapsed(at now: TimeInterval) -> TimeInterval {
        min(
            questionDuration,
            questionElapsedBeforeRun + (running && !isRevealing ? max(0, now - questionStartedAt) : 0)
        )
    }

    private func differenceText(_ previous: SpeedMatchCard, _ current: SpeedMatchCard) -> String {
        if previous.symbol == current.symbol { return "符号相同，但颜色变了" }
        if previous.colorIndex == current.colorIndex { return "颜色相同，但符号变了" }
        return "符号和颜色都不同"
    }

    private func pause() {
        if isRevealing {
            advanceTask?.cancel()
            advanceQuestion()
        } else {
            questionElapsedBeforeRun = questionElapsed(at: ProcessInfo.processInfo.systemUptime)
        }
        countdown.pause()
        running = false
    }

    private func resume() {
        guard !showResult, !isExample else { return }
        questionStartedAt = ProcessInfo.processInfo.systemUptime
        countdown.resume()
        running = true
    }

    private func reset() {
        advanceTask?.cancel()
        advanceTask = nil
        countdown.reset()
        previous = nil
        current = .random()
        score = 0
        streak = 0
        correctAnswers = 0
        timeLeft = 45
        running = false
        isExample = true
        isRevealing = false
        feedbackText = "先记住这一张，不计分"
        questionElapsedBeforeRun = 0
        questionStartedAt = ProcessInfo.processInfo.systemUptime
        showResult = false
        resultMessage = ""
    }

    private func finish() {
        guard !showResult else { return }
        advanceTask?.cancel()
        countdown.pause()
        running = false
        resultMessage = miniGameRecordedResult(
            for: .speedMatch,
            score: score,
            fallback: "这一题只练这一题，别被 Pibo 骗了。"
        )
        showResult = true
    }
}

private struct SpeedMatchCard: Equatable {
    private static let symbols = ["P", "I", "B", "O", "花", "露"]
    private static let colorNames = ["红色", "青色", "紫色", "橙色"]
    private static let colorCount = 4

    let symbol: String
    let colorIndex: Int

    var accessibilityLabel: String {
        "\(Self.colorNames[colorIndex.clamped(to: 0...(Self.colorNames.count - 1))]) \(symbol)"
    }

    static func random() -> SpeedMatchCard {
        SpeedMatchCard(
            symbol: symbols.randomElement() ?? "P",
            colorIndex: Int.random(in: 0..<colorCount)
        )
    }

    static func nearMiss(from previous: SpeedMatchCard, unlockColorOnly: Bool) -> SpeedMatchCard {
        if unlockColorOnly, Bool.random() {
            let nextColor = (0..<colorCount).filter { $0 != previous.colorIndex }.randomElement() ?? 0
            return SpeedMatchCard(symbol: previous.symbol, colorIndex: nextColor)
        }

        let nextSymbol = symbols.filter { $0 != previous.symbol }.randomElement() ?? "O"
        let keepColor = unlockColorOnly && Bool.random()
        return SpeedMatchCard(
            symbol: nextSymbol,
            colorIndex: keepColor ? previous.colorIndex : Int.random(in: 0..<colorCount)
        )
    }
}

private enum SpeedMatchPace {
    case steady
    case quick
    case flash

    var title: String {
        switch self {
        case .steady: return "稳住"
        case .quick: return "加速"
        case .flash: return "闪回"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .steady: return 3.0
        case .quick: return 2.15
        case .flash: return 1.55
        }
    }
}

// MARK: - Train of Thought

struct TrainThoughtGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrainThoughtGameModel()

    private let colors = [LP.Colorful.green500, LP.Colorful.orange500, LP.Colorful.cyan500]

    var body: some View {
        MiniGameShell(
            kind: .trainThought,
            scoreText: miniGameScoreText(for: .trainThought, score: model.score),
            detailText: model.hasStarted
                ? (model.isRunning
                    ? "\(model.timeLeft)s · 送达 \(model.delivered) · 连 \(model.combo) · 错 \(model.misses)/5"
                    : "暂停 · 送达 \(model.delivered)")
                : "先看道岔，再开始",
            onClose: { dismiss() }
        ) {
            TrainThoughtStage(model: model, colors: colors)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: model.isRunning ? "暂停" : (model.hasStarted ? "继续" : "开始"),
                    system: model.isRunning ? "pause.fill" : "play.fill",
                    variant: .primary,
                    disabled: model.isFinished
                ) {
                    model.toggleRunning()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { model.reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "送达 \(model.delivered) 列",
                message: model.resultMessage,
                primaryTitle: "再送",
                primarySystem: "arrow.clockwise",
                primaryAction: { model.reset() }
            )
        }
        .onDisappear { model.stopLoop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.isRunning, !model.isFinished {
                model.pause()
            }
        }
    }
}

private struct TrainThoughtStage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: TrainThoughtGameModel
    let colors: [Color]

    private let laneX = [0.2, 0.5, 0.8]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.34))

                trackPath(size: proxy.size)
                    .stroke(LP.Border.tertiary, style: StrokeStyle(lineWidth: 5, lineCap: .round))

                selectedTrackPath(size: proxy.size)
                    .stroke(
                        colors[model.selectedLane].opacity(0.78),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [12, 8])
                    )

                Circle()
                    .fill(colors[model.selectedLane])
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * TrainThoughtGameModel.junctionY)

                ForEach(model.trains) { train in
                    MiniGameTrainAsset(tint: colors[train.colorIndex])
                        .frame(width: 58, height: 32)
                        .overlay(alignment: .topTrailing) {
                            Text(AppLocalization.text(["绿", "橙", "蓝"][train.colorIndex]))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.primary)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(LP.Fill.bgContainer.opacity(0.94)))
                                .overlay(Circle().strokeBorder(colors[train.colorIndex], lineWidth: 2))
                        }
                        .position(
                            x: trainX(train) * proxy.size.width,
                            y: train.y * proxy.size.height
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppLocalization.text(
                            "\(["绿", "橙", "蓝"][train.colorIndex])色列车"
                        ))
                }

                ForEach(0..<3, id: \.self) { index in
                    Button {
                        model.selectLane(index)
                    } label: {
                        VStack(spacing: 2) {
                            MiniGameStationAsset(tint: colors[index], active: model.selectedLane == index)
                                .frame(width: proxy.size.width * 0.28, height: 62)
                            Text(AppLocalization.text(["绿站", "橙站", "蓝站"][index]))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(LP.Content.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isRunning || model.isFinished)
                    .accessibilityLabel(AppLocalization.text("切到 \(["绿", "橙", "蓝"][index])站"))
                    .position(x: laneX[index] * proxy.size.width, y: proxy.size.height * 0.89)
                }

                MiniGameStageCaption(
                    "道岔 → \(["绿", "橙", "蓝"][model.selectedLane])站 · \(model.statusText)",
                    fill: LP.Fill.bgContainer.opacity(0.92)
                )
                .position(
                    x: proxy.size.width / 2,
                    y: dynamicTypeSize.isAccessibilitySize ? 54 : 24
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Border.tertiary, lineWidth: LP.BorderWidth.hair)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("三轨列车调度区"))
        .accessibilityValue(AppLocalization.text(accessibilityStatus))
        .accessibilityHint(AppLocalization.text("选择和列车颜色相同的站台，列车经过道岔时会锁定路线"))
        .accessibilityAction(named: Text(AppLocalization.text("切到绿站"))) {
            model.selectLane(0)
        }
        .accessibilityAction(named: Text(AppLocalization.text("切到橙站"))) {
            model.selectLane(1)
        }
        .accessibilityAction(named: Text(AppLocalization.text("切到蓝站"))) {
            model.selectLane(2)
        }
    }

    private var accessibilityStatus: String {
        let names = ["绿", "橙", "蓝"]
        let approaching = model.trains
            .sorted { $0.y > $1.y }
            .prefix(3)
            .map { "\(names[$0.colorIndex])色列车" }
            .joined(separator: "、")
        let queue = approaching.isEmpty ? "暂无线车" : "当前 \(approaching)"
        return "道岔指向 \(names[model.selectedLane])站；\(queue)"
    }

    private func trainX(_ train: ThoughtTrain) -> Double {
        guard train.y > TrainThoughtGameModel.junctionY else { return 0.5 }
        let lane = train.routedLane ?? model.selectedLane
        let branchProgress = min(1, (train.y - TrainThoughtGameModel.junctionY) / 0.3)
        return 0.5 + (laneX[lane] - 0.5) * branchProgress
    }

    private func trackPath(size: CGSize) -> Path {
        Path { path in
            let junction = CGPoint(x: size.width * 0.5, y: size.height * TrainThoughtGameModel.junctionY)
            path.move(to: CGPoint(x: size.width * 0.5, y: 0))
            path.addLine(to: junction)
            for x in laneX {
                path.move(to: junction)
                path.addLine(to: CGPoint(x: size.width * x, y: size.height * 0.84))
            }
        }
    }

    private func selectedTrackPath(size: CGSize) -> Path {
        Path { path in
            let junction = CGPoint(x: size.width * 0.5, y: size.height * TrainThoughtGameModel.junctionY)
            path.move(to: junction)
            path.addLine(to: CGPoint(x: size.width * laneX[model.selectedLane], y: size.height * 0.84))
        }
    }
}

@MainActor
@Observable
private final class TrainThoughtGameModel {
    static let junctionY = 0.4

    var trains: [ThoughtTrain] = []
    var score = 0
    var delivered = 0
    var misses = 0
    var combo = 0
    var bestCombo = 0
    var selectedLane = 1
    var timeLeft = 45
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var statusText = "点站台切换道岔"
    var resultMessage = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var remainingTime = 45.0
    @ObservationIgnored private var nextSpawnIn = 1.2
    @ObservationIgnored private var lastUpdateAt = ProcessInfo.processInfo.systemUptime

    func startLoop() {
        guard loopTask == nil else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = min(0.08, max(0, now - self.lastUpdateAt))
                self.lastUpdateAt = now
                self.tick(delta: delta)
            }
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func selectLane(_ lane: Int) {
        guard isRunning, !isFinished else { return }
        selectedLane = lane.clamped(to: 0...2)
        LPHaptics.tap()
    }

    func toggleRunning() {
        if !hasStarted {
            start()
        } else {
            isRunning ? pause() : resume()
        }
    }

    func start() {
        guard !hasStarted, !isFinished else { return }
        hasStarted = true
        isRunning = true
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        startLoop()
    }

    func pause() {
        isRunning = false
        stopLoop()
    }

    func resume() {
        guard !isFinished else { return }
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        startLoop()
    }

    func reset() {
        stopLoop()
        trains = []
        score = 0
        delivered = 0
        misses = 0
        combo = 0
        bestCombo = 0
        selectedLane = 1
        timeLeft = 45
        hasStarted = false
        isRunning = false
        isFinished = false
        statusText = "点站台切换道岔"
        resultMessage = ""
        remainingTime = 45
        nextSpawnIn = 1.2
        lastUpdateAt = ProcessInfo.processInfo.systemUptime
    }

    private func tick(delta: TimeInterval) {
        guard isRunning, !isFinished, delta > 0 else { return }
        remainingTime = max(0, remainingTime - delta)
        let nextTimeLeft = max(0, Int(ceil(remainingTime)))
        if nextTimeLeft != timeLeft { timeLeft = nextTimeLeft }
        if remainingTime <= 0 {
            finish(message: "小列车先停靠，送达了 \(delivered) 列。")
            return
        }

        nextSpawnIn -= delta
        if nextSpawnIn <= 0 {
            trains.append(ThoughtTrain(colorIndex: Int.random(in: 0..<3), y: 0.08))
            // Teach one train at a time before the board becomes busy. The old
            // 0.35 s opener produced three misses before a newcomer had located
            // the junction control.
            nextSpawnIn += max(1.45, 2.3 - Double(delivered) * 0.025)
        }

        var deliveredLanes: [(target: Int, route: Int)] = []
        let nextTrains = trains.compactMap { train -> ThoughtTrain? in
            var next = train
            next.y += (0.13 + min(Double(delivered) * 0.0018, 0.055)) * delta
            if next.routedLane == nil, next.y >= Self.junctionY {
                next.routedLane = selectedLane
            }
            if next.y >= 0.82 {
                deliveredLanes.append((next.colorIndex, next.routedLane ?? selectedLane))
                return nil
            }
            return next
        }
        if nextTrains != trains { trains = nextTrains }

        for arrival in deliveredLanes {
            if arrival.target == arrival.route {
                delivered += 1
                combo += 1
                bestCombo = max(bestCombo, combo)
                score += 10 + min(12, combo * 2)
                statusText = combo >= 3 ? "连送 \(combo)，加速" : "送达，连 \(combo)"
                LPHaptics.success()
            } else {
                misses += 1
                combo = 0
                statusText = "进错站，重新看颜色"
                LPHaptics.decline()
            }
        }
        if misses >= 5 {
            finish(message: "五列车进错站，先把道岔停下来。")
        }
    }

    private func finish(message: String) {
        guard !isFinished else { return }
        isRunning = false
        stopLoop()
        resultMessage = miniGameRecordedResult(
            for: .trainThought,
            score: score,
            fallback: "\(message)\n最佳连送 \(bestCombo) 列。"
        )
        isFinished = true
    }
}

private struct ThoughtTrain: Identifiable, Equatable {
    let id = UUID()
    var colorIndex: Int
    var y: Double
    var routedLane: Int? = nil
}

// MARK: - Pet Detective

struct PetDetectiveGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = GridPoint(x: 0, y: 0)
    @State private var target = GridPoint(x: 4, y: 4)
    @State private var rocks: Set<GridPoint> = []
    @State private var pathHistory: [GridPoint] = []
    @State private var moves = 0
    @State private var shortestPath = 8
    @State private var showResult = false
    @State private var resultMessage = ""

    private let size = 5

    var body: some View {
        MiniGameShell(
            kind: .petDetective,
            scoreText: showResult
                ? miniGameScoreText(for: .petDetective, score: completedRouteScore)
                : "\(moves) 步",
            detailText: "最短 \(shortestPath) · 已走 \(moves)",
            onClose: { dismiss() }
        ) {
            VStack(spacing: LP.Spacing.l) {
                Spacer(minLength: 0)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: size), spacing: 8) {
                    ForEach(0..<(size * size), id: \.self) { index in
                        let point = GridPoint(x: index % size, y: index / size)
                        detectiveCell(point)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(title: "新地图", system: "map", variant: .primary) { reset() }
                MiniGameActionButton(
                    title: "撤回",
                    system: "arrow.uturn.backward",
                    disabled: pathHistory.isEmpty || showResult
                ) {
                    undoMove()
                }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: showResult,
                title: "找到了",
                message: resultMessage,
                primaryTitle: "下一张",
                primarySystem: "arrow.right",
                primaryAction: { reset() }
            )
        }
        .onAppear { reset() }
    }

    private var completedRouteScore: Int {
        let extra = max(0, moves - shortestPath)
        return max(10, 120 - shortestPath * 4 - extra * 12)
    }

    private func detectiveCell(_ point: GridPoint) -> some View {
        let isAdjacent = abs(point.x - player.x) + abs(point.y - player.y) == 1
        let isBlocked = rocks.contains(point)

        return Button {
            move(to: point)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                    .fill(cellFill(point))
                    .overlay(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).strokeBorder(LP.Border.tertiary, lineWidth: 1))
                if point == player {
                    MiniGamePiboAsset(flowerScale: 0.3, showFlower: false)
                        .padding(4)
                } else if point == target {
                    MiniGameMemoryShardAsset()
                        .padding(14)
                } else if rocks.contains(point) {
                    MiniGameRockAsset()
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .opacity(isBlocked ? 0.58 : (isAdjacent || point == player ? 1 : 0.72))
        .disabled(showResult || isBlocked || !isAdjacent)
        .accessibilityLabel(AppLocalization.text(cellAccessibilityLabel(point)))
        .accessibilityHint(AppLocalization.text(
            isBlocked ? "石块挡住了" : (isAdjacent ? "可以移动到这里" : "不在当前位置旁边")
        ))
    }

    private func cellFill(_ point: GridPoint) -> Color {
        if point == player { return LP.Fill.foundationAccent }
        if point == target { return LP.Colorful.yellow200 }
        if rocks.contains(point) { return LP.Neutral.grey300 }
        if pathHistory.contains(point) { return LP.Fill.foundationAccent.opacity(0.18) }
        return LP.Fill.bgContainer.opacity(0.88)
    }

    private func move(to point: GridPoint) {
        guard !rocks.contains(point),
              abs(point.x - player.x) + abs(point.y - player.y) == 1
        else {
            LPHaptics.decline()
            return
        }
        pathHistory.append(player)
        player = point
        moves += 1
        if point == target {
            let finalScore = completedRouteScore
            resultMessage = miniGameRecordedResult(
                for: .petDetective,
                score: finalScore,
                fallback: moves <= shortestPath ? "...最短路线，行吧。" : "...绕远了，但找到了。"
            )
            showResult = true
            LPHaptics.success()
        } else {
            LPHaptics.tap()
        }
    }

    private func undoMove() {
        guard !showResult, let previous = pathHistory.popLast() else { return }
        player = previous
        LPHaptics.tap()
    }

    private func cellAccessibilityLabel(_ point: GridPoint) -> String {
        if point == player { return "Pibo 当前所在，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        if point == target { return "记忆碎片，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        if rocks.contains(point) { return "石块，第 \(point.x + 1) 列第 \(point.y + 1) 行" }
        return "空地，第 \(point.x + 1) 列第 \(point.y + 1) 行"
    }

    private func reset() {
        player = GridPoint(x: 0, y: 0)
        target = GridPoint(x: 4, y: 4)
        pathHistory = []
        moves = 0
        showResult = false
        resultMessage = ""

        for _ in 0..<40 {
            var nextRocks = Set<GridPoint>()
            while nextRocks.count < 7 {
                let point = GridPoint(x: Int.random(in: 0..<size), y: Int.random(in: 0..<size))
                if point != player, point != target, point.x != point.y {
                    nextRocks.insert(point)
                }
            }
            if let length = shortestPathLength(rocks: nextRocks) {
                rocks = nextRocks
                shortestPath = length
                return
            }
        }

        rocks = []
        shortestPath = 8
    }

    private func shortestPathLength(rocks: Set<GridPoint>) -> Int? {
        var queue: [(point: GridPoint, distance: Int)] = [(player, 0)]
        var visited: Set<GridPoint> = [player]

        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.point == target { return next.distance }

            for neighbor in neighbors(of: next.point) where !rocks.contains(neighbor) && !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append((neighbor, next.distance + 1))
            }
        }

        return nil
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        [
            GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x - 1, y: point.y),
            GridPoint(x: point.x, y: point.y + 1),
            GridPoint(x: point.x, y: point.y - 1)
        ].filter { $0.x >= 0 && $0.x < size && $0.y >= 0 && $0.y < size }
    }
}

private struct GridPoint: Hashable {
    var x: Int
    var y: Int
}

// MARK: - Motion Input

@Observable
final class MotionGameInput {
    var stepPulse = 0
    var bellDownPulse = 0
    var bellUpPulse = 0
    var statusText = "动作感应"
    var requiresManualStepInput = false
    var requiresManualBellInput = false
    var isBellCalibrating = false
    var isBellCalibrated = false

    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    private var baselineSteps: Int?
    private var reportedPedometerSteps = 0
    private var baselineGravity = SIMD3<Double>(0, -1, 0)
    private var calibrationGravitySum = SIMD3<Double>(repeating: 0)
    private var calibrationSampleCount = 0
    private var filteredTiltDegrees = 0.0
    private var stableBellSamples = 0
    private var lastBellTransitionAt = 0.0
    private var bellDetectionPhase = BellDetectionPhase.waitingForDown
    private var isPedometerActive = false
    private var isBellMotionActive = false

    private enum BellDetectionPhase {
        case waitingForDown
        case waitingForUp
    }

    func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else {
            requiresManualStepInput = true
            statusText = "自动不可用"
            return
        }
        baselineSteps = nil
        reportedPedometerSteps = 0
        isPedometerActive = true
        requiresManualStepInput = false
        statusText = "正在计步"
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            guard error == nil, let data else {
                Task { @MainActor in
                    guard self.isPedometerActive else { return }
                    self.requiresManualStepInput = true
                    self.stopPedometer()
                    self.statusText = "自动不可用"
                }
                return
            }
            let total = data.numberOfSteps.intValue
            Task { @MainActor in
                guard self.isPedometerActive else { return }
                if self.baselineSteps == nil {
                    self.baselineSteps = total
                }
                let baseline = self.baselineSteps ?? total
                let delta = max(0, total - baseline)
                if delta > self.reportedPedometerSteps {
                    self.stepPulse += delta - self.reportedPedometerSteps
                    self.reportedPedometerSteps = delta
                }
            }
        }
    }

    func useManualSteps() {
        stopPedometer()
        requiresManualStepInput = false
        statusText = "手动左右脚"
    }

    func stopPedometer() {
        isPedometerActive = false
        pedometer.stopUpdates()
        baselineSteps = nil
        reportedPedometerSteps = 0
        if !requiresManualStepInput { statusText = "动作感应" }
    }

    func prepareBellMotionMode() {
        requiresManualBellInput = false
        statusText = isBellCalibrated ? "已校准 · 可以开始" : "请站直并校准"
    }

    func useManualBell() {
        stopMotion()
        requiresManualBellInput = false
        statusText = "手动下 / 起"
    }

    func beginBellCalibration() {
        stopMotion()
        guard motionManager.isDeviceMotionAvailable else {
            requiresManualBellInput = true
            statusText = "动作感应不可用"
            return
        }

        requiresManualBellInput = false
        isBellCalibrated = false
        isBellCalibrating = true
        calibrationGravitySum = SIMD3<Double>(repeating: 0)
        calibrationSampleCount = 0
        statusText = "站直保持不动…"
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard self.isBellCalibrating else { return }
            guard error == nil, let motion else {
                self.requiresManualBellInput = true
                self.isBellCalibrating = false
                self.statusText = "动作感应不可用"
                self.motionManager.stopDeviceMotionUpdates()
                return
            }

            let gravity = SIMD3(
                motion.gravity.x,
                motion.gravity.y,
                motion.gravity.z
            )
            self.calibrationGravitySum += gravity
            self.calibrationSampleCount += 1
            guard self.calibrationSampleCount >= 30 else { return }

            self.baselineGravity = self.normalized(self.calibrationGravitySum)
            self.isBellCalibrating = false
            self.isBellCalibrated = true
            self.statusText = "校准完成 · 可以开始"
            self.motionManager.stopDeviceMotionUpdates()
            LPHaptics.success()
        }
    }

    func startBellMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            requiresManualBellInput = true
            statusText = "动作感应不可用"
            return
        }
        guard isBellCalibrated else {
            statusText = "请先站直校准"
            return
        }

        motionManager.stopDeviceMotionUpdates()
        bellDetectionPhase = .waitingForDown
        isBellMotionActive = true
        stableBellSamples = 0
        filteredTiltDegrees = 0
        lastBellTransitionAt = ProcessInfo.processInfo.systemUptime
        statusText = "请缓慢下蹲"
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard self.isBellMotionActive else { return }
            guard error == nil, let motion else {
                self.motionManager.stopDeviceMotionUpdates()
                self.isBellMotionActive = false
                self.requiresManualBellInput = true
                self.statusText = "动作感应中断 · 已切到手动"
                return
            }
            self.handleBellMotion(gravity: SIMD3(
                motion.gravity.x,
                motion.gravity.y,
                motion.gravity.z
            ))
        }
    }

    func stopMotion() {
        isBellMotionActive = false
        motionManager.stopDeviceMotionUpdates()
        isBellCalibrating = false
        statusText = isBellCalibrated ? "已校准" : "动作感应"
    }

    private func handleBellMotion(gravity: SIMD3<Double>) {
        let currentGravity = normalized(gravity)
        let dot = (
            currentGravity.x * baselineGravity.x
                + currentGravity.y * baselineGravity.y
                + currentGravity.z * baselineGravity.z
        ).clamped(to: -1...1)
        let tiltDegrees = acos(dot) * 180 / .pi
        filteredTiltDegrees = filteredTiltDegrees * 0.72 + tiltDegrees * 0.28
        let now = ProcessInfo.processInfo.systemUptime

        switch bellDetectionPhase {
        case .waitingForDown:
            stableBellSamples = filteredTiltDegrees >= 11 ? stableBellSamples + 1 : 0
            guard stableBellSamples >= 4, now - lastBellTransitionAt >= 0.55 else { return }
            bellDetectionPhase = .waitingForUp
            stableBellSamples = 0
            lastBellTransitionAt = now
            bellDownPulse += 1
            statusText = "已下蹲 · 请起身"
        case .waitingForUp:
            stableBellSamples = filteredTiltDegrees <= 5 ? stableBellSamples + 1 : 0
            guard stableBellSamples >= 4, now - lastBellTransitionAt >= 0.65 else { return }
            bellDetectionPhase = .waitingForDown
            stableBellSamples = 0
            lastBellTransitionAt = now
            bellUpPulse += 1
            statusText = "已起身 · 请下蹲"
        }
    }

    private func normalized(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0.0001 else { return SIMD3<Double>(0, -1, 0) }
        return vector / length
    }
}

// MARK: - Shared Small Drawing

struct PiboBlobView: View {
    let tint: Color

    var body: some View {
        MiniGamePiboAsset(flowerScale: 0.68)
            .overlay(Circle().fill(tint.opacity(0.12)).blendMode(.multiply))
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
