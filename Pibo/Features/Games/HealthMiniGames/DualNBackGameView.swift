import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import Vision

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
