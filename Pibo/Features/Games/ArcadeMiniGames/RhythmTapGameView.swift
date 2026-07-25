import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 节奏点击

struct RhythmTapGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = RhythmTapGameModel()

    var body: some View {
        MiniGameShell(
            kind: .rhythmTap,
            scoreText: miniGameScoreText(for: .rhythmTap, score: model.score),
            detailText: model.hasStarted
                ? "\(model.timeLeft)s · \(model.audioStatus) · 连 \(model.combo)"
                : "先听四拍",
            onClose: { dismiss() }
        ) {
            RhythmTapStage(model: model)
        } bottomBar: {
            MiniGameControlBar {
                MiniGameActionButton(
                    title: "点",
                    system: "hand.tap.fill",
                    variant: .primary,
                    disabled: !model.isRunning || model.isFinished
                ) {
                    model.tapBeat()
                }
                MiniGameActionButton(
                    title: model.isRunning ? "暂停" : (model.hasStarted ? "继续" : "开始"),
                    system: model.isRunning ? "pause.fill" : "play.fill",
                    disabled: model.isFinished
                ) {
                    model.startOrToggle()
                }
                MiniGameActionButton(title: "重来", system: "arrow.clockwise") { model.reset() }
            }
        } overlay: {
            MiniGameResultOverlay(
                isPresented: model.isFinished,
                title: "节拍亮度 \(model.score)",
                message: model.resultMessage,
                primaryTitle: "再点",
                primarySystem: "arrow.clockwise",
                primaryAction: { model.reset() }
            )
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.isRunning {
                model.pause()
            }
        }
    }
}

private struct RhythmTapStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: RhythmTapGameModel

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1.0 / 30.0 : 1.0 / 60.0,
                paused: !model.isRunning
            )
        ) { _ in
            GeometryReader { proxy in
                let state = model.visualState()
                let targetX = proxy.size.width * 0.22
                let laneY = proxy.size.height * 0.60

                ZStack {
                    RadialGradient(
                        colors: [
                            MiniGameKind.rhythmTap.tint.opacity(min(0.34, Double(model.combo) * 0.018)),
                            .clear
                        ],
                        center: .top,
                        startRadius: 4,
                        endRadius: proxy.size.width * 0.7
                    )

                    MiniGameFlowerAsset(level: min(5, model.combo / 3))
                        .frame(width: 112, height: 112)
                        .scaleEffect(1 + state.targetPulse * 0.06)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.23)

                    Capsule()
                        .fill(LP.Fill.bgContainer.opacity(0.76))
                        .frame(width: proxy.size.width * 0.78, height: 18)
                        .position(x: proxy.size.width * 0.52, y: laneY)

                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .fill(LP.Fill.foundationAccent.opacity(0.20 + state.targetPulse * 0.24))
                        .frame(width: 58, height: 112)
                        .position(x: targetX, y: laneY)

                    ForEach(state.notes) { note in
                        Text(note.syllable)
                            .lpText(LP.Typography.b3Medium)
                            .foregroundStyle(LP.Fill.foundationOnAccent)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle().fill(note.isHigh
                                    ? LP.Colorful.red500
                                    : LP.Colorful.orange500)
                            )
                            .overlay(Circle().strokeBorder(.white.opacity(0.58), lineWidth: 1))
                            .position(x: proxy.size.width * note.x, y: laneY)
                    }

                    VStack(spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text(state.headline))
                            .lpText(LP.Typography.uiH5)
                            .foregroundStyle(LP.Content.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                        Text(AppLocalization.text(model.feedback))
                            .lpText(LP.Typography.handSmall)
                            .foregroundStyle(LP.Content.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.vertical, LP.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(LP.Fill.bgContainer.opacity(0.9))
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.76 : 0.82)
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { model.tapBeat() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.text("节奏点击，连续 \(model.combo) 拍"))
        .accessibilityHint(AppLocalization.text("听到 pi 或 bo 节拍时点按屏幕"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapBeat() }
    }
}

@MainActor
@Observable
private final class RhythmTapGameModel {
    var score = 0
    var combo = 0
    var maxCombo = 0
    var timeLeft = Int(PiboCoreRhythmTapAdapter.config.session)
    var hasStarted = false
    var isRunning = false
    var isFinished = false
    var audioStatus = "声音 + 触觉"
    var feedback = "点开始，先听四拍"
    var resultMessage = ""

    @ObservationIgnored private let audioClock = RhythmAudioClock()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var lastPulseBeat = Int.min
    @ObservationIgnored private var lastJudgedBeat = Int.min
    @ObservationIgnored private var lastResolvedBeat = -1
    @ObservationIgnored private var lastTapUptime = 0.0

    private let config = PiboCoreRhythmTapAdapter.config
    private var beatInterval: TimeInterval { config.beatInterval }
    private var sessionLength: TimeInterval { config.session }
    private var countInLength: TimeInterval { config.countIn }

    func startOrToggle() {
        if !hasStarted {
            startSession()
        } else if isRunning {
            pause()
        } else {
            resume()
        }
    }

    func tapBeat() {
        guard isRunning, !isFinished else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastTapUptime >= config.debounce else { return }
        lastTapUptime = uptime

        let rawElapsed = audioClock.elapsed()
        guard rawElapsed >= countInLength else {
            feedback = "先听完四拍"
            LPHaptics.decline()
            return
        }

        let rhythmElapsed = rawElapsed - countInLength
        resolveExpiredBeats(at: rhythmElapsed)
        let result = PiboCoreRhythmTapAdapter.judge(
            elapsed: rhythmElapsed,
            lastJudgedBeat: lastJudgedBeat,
            combo: combo
        )

        switch result.judgement {
        case .duplicate:
            feedback = "这一拍点过了"
        case .exact:
            lastJudgedBeat = result.beat
            combo = result.newCombo
            maxCombo = max(maxCombo, combo)
            score += result.scoreGain
            feedback = "正拍！\(syllable(for: result.beat))"
            LPHaptics.success()
        case .nearEarly, .nearLate:
            lastJudgedBeat = result.beat
            combo = result.newCombo
            maxCombo = max(maxCombo, combo)
            score += result.scoreGain
            feedback = result.judgement == .nearEarly ? "稍早，接近了" : "稍晚，接近了"
            LPHaptics.tap()
        case .miss:
            combo = result.newCombo
            feedback = "等下一个 pi-bo"
            LPHaptics.decline()
        }
    }

    func pause() {
        guard isRunning else { return }
        audioClock.pause()
        monitorTask?.cancel()
        monitorTask = nil
        isRunning = false
        feedback = "暂停了，节拍不会偷跑"
    }

    func resume() {
        guard hasStarted, !isFinished else { return }
        let audioAvailable = audioClock.resume()
        audioStatus = audioAvailable ? "声音 + 触觉" : "触觉节拍"
        isRunning = true
        feedback = "继续听 pi-bo"
        startMonitor()
    }

    func reset() {
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        score = 0
        combo = 0
        maxCombo = 0
        timeLeft = Int(config.session)
        hasStarted = false
        isRunning = false
        isFinished = false
        audioStatus = "声音 + 触觉"
        feedback = "点开始，先听四拍"
        resultMessage = ""
        lastPulseBeat = .min
        lastJudgedBeat = .min
        lastResolvedBeat = -1
        lastTapUptime = 0
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        isRunning = false
    }

    func visualState() -> RhythmVisualState {
        let rawElapsed = hasStarted ? audioClock.elapsed() : 0
        let rhythmElapsed = rawElapsed - countInLength
        let baseBeat = Int(floor(rhythmElapsed / beatInterval))
        var notes: [RhythmLaneNote] = []

        for beat in (baseBeat - 1)...(baseBeat + 4) {
            let secondsUntilBeat = Double(beat) * beatInterval - rhythmElapsed
            let x = 0.22 + secondsUntilBeat / (beatInterval * 2.5) * 0.72
            guard x > -0.1, x < 1.12 else { continue }
            notes.append(RhythmLaneNote(
                id: beat,
                syllable: syllable(for: beat),
                isHigh: normalizedPatternIndex(for: beat).isMultiple(of: 2),
                x: x
            ))
        }

        let nearestBeat = (rhythmElapsed / beatInterval).rounded()
        let distance = abs(rhythmElapsed - nearestBeat * beatInterval)
        let pulse = max(0, 1 - distance / config.nearWindow)
        let headline: String
        if !hasStarted {
            headline = "听见 pi-bo 时点按"
        } else if rawElapsed < countInLength {
            headline = "准备 \(max(1, Int(ceil((countInLength - rawElapsed) / beatInterval))))"
        } else {
            headline = "pi · bo · pi · bo"
        }
        return RhythmVisualState(notes: notes, targetPulse: pulse, headline: headline)
    }

    private func startSession() {
        let audioAvailable = audioClock.start()
        audioStatus = audioAvailable ? "声音 + 触觉" : "触觉节拍"
        hasStarted = true
        isRunning = true
        feedback = "先听四拍"
        lastPulseBeat = .min
        startMonitor()
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                guard let self, self.isRunning, !self.isFinished else { continue }
                let rawElapsed = self.audioClock.elapsed()
                let beat = Int(floor((rawElapsed + 0.04) / self.beatInterval))
                if beat != self.lastPulseBeat {
                    self.lastPulseBeat = beat
                    LPHaptics.tap()
                }

                guard rawElapsed >= self.countInLength else { continue }
                let gameElapsed = rawElapsed - self.countInLength
                self.resolveExpiredBeats(at: gameElapsed)
                let nextTimeLeft = max(0, Int(ceil(self.sessionLength - gameElapsed)))
                if nextTimeLeft != self.timeLeft { self.timeLeft = nextTimeLeft }
                if gameElapsed >= self.sessionLength { self.finish() }
            }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
        audioClock.stop()
        resultMessage = miniGameRecordedResult(
            for: .rhythmTap,
            score: score,
            fallback: maxCombo >= 8 ? "花亮得有点吵。最高连拍 \(maxCombo)。" : "Pibo 说乱码还没对齐。"
        )
        isFinished = true
    }

    private func resolveExpiredBeats(at rhythmElapsed: TimeInterval) {
        let result = PiboCoreRhythmTapAdapter.resolveExpired(
            elapsed: rhythmElapsed,
            lastResolvedBeat: lastResolvedBeat,
            lastJudgedBeat: lastJudgedBeat
        )
        guard result.advanced else { return }
        lastResolvedBeat = result.latestExpiredBeat
        if result.missed {
            combo = 0
            feedback = "漏了一拍，听下一个 pi-bo"
        }
    }

    private func syllable(for beat: Int) -> String {
        ["pi", "bo", "pi", "bo"][normalizedPatternIndex(for: beat)]
    }

    private func normalizedPatternIndex(for beat: Int) -> Int {
        ((beat % 4) + 4) % 4
    }
}

private struct RhythmVisualState {
    let notes: [RhythmLaneNote]
    let targetPulse: Double
    let headline: String
}

private struct RhythmLaneNote: Identifiable {
    let id: Int
    let syllable: String
    let isHigh: Bool
    let x: Double
}

@MainActor
private final class RhythmAudioClock {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private let beatInterval = PiboCoreRhythmTapAdapter.config.beatInterval
    private var loopBuffer: AVAudioPCMBuffer?
    private var fallbackAccumulated = 0.0
    private var fallbackStartedAt = 0.0
    private var isRunning = false
    private var isAudioAvailable = false
    private var didActivateSession = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            loopBuffer = makeLoopBuffer(format: format)
        }
        player.volume = 0.55
    }

    func start() -> Bool {
        stop()
        fallbackAccumulated = 0
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true

        guard let loopBuffer else {
            isAudioAvailable = false
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            didActivateSession = true
            player.scheduleBuffer(loopBuffer, at: nil, options: [.loops])
            engine.prepare()
            try engine.start()
            player.play()
            isAudioAvailable = true
        } catch {
            player.stop()
            engine.stop()
            isAudioAvailable = false
            if didActivateSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                didActivateSession = false
            }
        }
        return isAudioAvailable
    }

    func pause() {
        guard isRunning else { return }
        fallbackAccumulated = elapsed()
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = false
        if isAudioAvailable { player.pause() }
    }

    @discardableResult
    func resume() -> Bool {
        guard !isRunning else { return isAudioAvailable }
        fallbackStartedAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        if isAudioAvailable {
            do {
                if !engine.isRunning { try engine.start() }
                player.play()
            } catch {
                isAudioAvailable = false
            }
        }
        return isAudioAvailable
    }

    func stop() {
        player.stop()
        engine.stop()
        isRunning = false
        isAudioAvailable = false
        fallbackAccumulated = 0
        fallbackStartedAt = 0
        if didActivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            didActivateSession = false
        }
    }

    func elapsed() -> TimeInterval {
        if isAudioAvailable,
           let renderTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: renderTime) {
            return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        }
        guard isRunning else { return fallbackAccumulated }
        return fallbackAccumulated + max(0, ProcessInfo.processInfo.systemUptime - fallbackStartedAt)
    }

    private func makeLoopBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let barDuration = beatInterval * 4
        let frameCount = AVAudioFrameCount((barDuration * sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        let frequencies = [720.0, 480.0, 660.0, 440.0]
        let toneFrames = Int((0.12 * sampleRate).rounded())
        let attackFrames = max(1, Int((0.008 * sampleRate).rounded()))
        for beat in 0..<4 {
            let startFrame = Int((Double(beat) * beatInterval * sampleRate).rounded())
            for frame in 0..<toneFrames where startFrame + frame < Int(frameCount) {
                let progress = Double(frame) / Double(toneFrames)
                let attack = min(1, Double(frame) / Double(attackFrames))
                let envelope = attack * pow(1 - progress, 1.6)
                let phase = 2 * Double.pi * frequencies[beat] * Double(frame) / sampleRate
                channel[startFrame + frame] += Float(sin(phase) * envelope * 0.24)
            }
        }
        return buffer
    }
}
