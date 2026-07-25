import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import Vision

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
