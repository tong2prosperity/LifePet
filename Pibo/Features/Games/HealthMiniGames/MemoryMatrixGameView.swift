import AVFoundation
import CoreMotion
import Observation
import SwiftUI
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
