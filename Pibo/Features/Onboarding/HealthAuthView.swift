import SwiftUI
import os
import UIKit
import Darwin
import AVFoundation
import Speech

/// First-launch onboarding for the 魔丸态 prototype. This ports the 0603 HTML
/// flow into SwiftUI: Pibo falls to Earth, finds light through the camera,
/// remembers its name, glitches from low energy, asks for HealthKit, grows the
/// first sprout, then hands the user into Home.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store

    @State private var scene: OnboardingScene = .intro
    @State private var introIndex = 0
    @State private var petNameDraft: String = ""
    @State private var speech: String?
    @State private var callPulse = false
    @State private var lightCaptured = false
    @State private var lightCaptureAttempts = 0
    @State private var cameraMessage = "点击屏幕任意位置模拟拍照"
    @State private var cameraIsChecking = false
    @State private var authRequested = false
    @State private var energyProgress: CGFloat = 0
    @State private var pluckOffset: CGFloat = 0
    @State private var pluckDragX: CGFloat = 0
    @State private var pluckCompleted = false
    @State private var piboTapCount = 0
    @State private var voiceInput = OnboardingVoiceInputController()
    @State private var voiceStatus: VoiceInputStatus = .idle
    @State private var recognizedCallText = ""
    @State private var isHoldingVoiceInput = false

    /// Called by `RootView` when the gate should close.
    let onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background
            currentScene
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.xl)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            if scene.showsSkip {
                skipButton
                    .padding(.top, LP.Spacing.s)
                    .padding(.trailing, LP.Spacing.l)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            restoreOnboardingSceneIfNeeded()
            if petNameDraft.isEmpty { petNameDraft = store.petName }
            if scene == .intro { startIntro() }
        }
        .animation(.easeInOut(duration: 0.28), value: scene)
    }

    @ViewBuilder
    private var currentScene: some View {
        switch scene {
        case .intro:
            introScene
        case .falling:
            darkLineScene(
                title: "降临",
                line: "…这…是…哪里…",
                detail: "…黑暗…好冷…\n…我的花…呢…",
                button: "靠近一点",
                action: { go(.darkness) }
            )
        case .darkness:
            darkLineScene(
                title: "黑暗里有东西在动",
                line: "…冷…#@!%",
                detail: "…什么东西…在…#@!%…动…\n…花…需要…光…#@!%",
                button: "给它找一点光",
                action: { go(.camera) }
            )
        case .camera:
            cameraScene
        case .awaken:
            awakenScene
        case .name:
            nameScene
        case .nameResponse:
            nameResponseScene
        case .call:
            callScene
        case .glitch:
            glitchScene
        case .contractFailure:
            contractFailureScene
        case .auth:
            authScene
        case .energy:
            energyScene
        case .pluck:
            pluckScene
        case .complete:
            completeScene
        }
    }

    private var background: some View {
        Group {
            switch scene.palette {
            case .dark:
                RadialGradient(
                    colors: [Color(hex: 0x101421), .black],
                    center: .center,
                    startRadius: 40,
                    endRadius: 520
                )
            case .paper:
                LinearGradient(
                    colors: [LP.Fill.bgSurface, LP.Fill.bgContainer],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .glitch:
                RedGlitchIonFlowView()
            case .home:
                LinearGradient(
                    colors: [Color(hex: 0xF5FAF6), Color(hex: 0xE7F2EA)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .overlay {
            if scene.usesIdentityBackground {
                Image("onboarding_identity_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.28))
            }
            if scene == .glitch || scene == .contractFailure {
                GlitchNoiseView()
                    .opacity(0.48)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Scenes

    private var introScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            VStack(spacing: LP.Spacing.m) {
                ForEach(Array(Self.introLines.enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(.system(size: line.highlight ? 17 : 15, weight: .regular))
                        .tracking(line.highlight ? 6 : 2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(index == introIndex ? Color.white.opacity(0.88) : Color.white.opacity(0.24))
                        .blur(radius: index == introIndex ? 0 : 2)
                        .opacity(index <= introIndex ? 1 : 0)
                }
            }
            .frame(maxWidth: 340)
            Spacer()
            Button(AppLocalization.text("跳过开场")) { go(.falling) }
                .font(.system(size: 12, weight: .medium))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.42))
                .buttonStyle(.plain)
        }
    }

    private func darkLineScene(title: String, line: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(headItem: .mystery, isDark: true, speech: line)
            VStack(spacing: LP.Spacing.s) {
                Text(title)
                    .lpText(LP.Typography.c1Medium)
                    .tracking(2)
                    .foregroundStyle(LP.Content.invertTertiary)
                Text(detail)
                    .lpText(LP.Typography.b1Regular)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LP.Content.invertSecondary)
            }
            Spacer()
            onboardingButton(button, kind: .light, action: action)
        }
    }

    private var cameraScene: some View {
        VStack(spacing: LP.Spacing.l) {
            Text("找光源")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
                .foregroundStyle(LP.Content.invertTertiary)
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black)
                    .overlay(cameraGrid.opacity(0.45))
                    .overlay {
                        if lightCaptured {
                            Color.white.opacity(0.78)
                            Text("检测到光")
                                .lpText(LP.Typography.b1Medium)
                                .foregroundStyle(Color.black.opacity(0.72))
                        } else if cameraIsChecking {
                            VStack(spacing: LP.Spacing.s) {
                                ProgressView()
                                    .tint(.white)
                                Text("Pibo 正在看…")
                                    .lpText(LP.Typography.c1Regular)
                            }
                            .foregroundStyle(Color.white.opacity(0.72))
                        } else {
                            VStack(spacing: LP.Spacing.s) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 34, weight: .medium))
                                Text(cameraMessage)
                                    .lpText(LP.Typography.c1Regular)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(Color.white.opacity(0.64))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .frame(maxHeight: 500)
            .contentShape(Rectangle())
            .onTapGesture { captureLight() }

            onboardingButton(lightCaptured ? "继续" : (lightCaptureAttempts == 0 ? "捕捉一点光" : "再拍一次"), kind: .light) {
                lightCaptured ? go(.awaken) : captureLight()
            }
        }
    }

    private var awakenScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(
                headItem: .mystery,
                isDark: false,
                speech: speech ?? "…亮…#@!%",
                showOverhead: false
            )
            Text("…我的花…在地球上…能开吗…")
                .lpText(LP.Typography.b1Regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(LP.Content.invertSecondary)
            Spacer()
            onboardingButton("告诉它你是谁", kind: .light) { go(.name) }
        }
        .onAppear { speech = "…暖…#@!%" }
    }

    private var nameScene: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(headItem: .mystery, isDark: false, speech: "…你…是谁…")
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text("它好像想起了什么…")
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(LP.Content.invertSecondary)
                TextField("告诉它你的名字", text: $petNameDraft)
                    .lpText(LP.Typography.b1Medium)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(LP.Content.primary)
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, LP.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous).strokeBorder(Color.white.opacity(0.28)))
            }
            Spacer()
            onboardingButton("确认", kind: .light) {
                commitName()
                go(.nameResponse)
            }
        }
    }

    private var nameResponseScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(
                headItem: .mystery,
                isDark: false,
                speech: nameResponseSpeech
            )
            Spacer()
            onboardingButton("继续", kind: .light) { go(.call) }
        }
    }

    private var callScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(
                headItem: .mystery,
                isDark: false,
                speech: petNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "…Pibo…#@!%" : "…\(petNameDraft)…？"
            )
            .scaleEffect(callPulse ? 1.05 : 1)
            Text("但它需要你呼唤它的名字，才能完全想起自己")
                .lpText(LP.Typography.b2Regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(LP.Content.invertSecondary)
            Text("呼唤 \"Pibo\" 的名字")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
            VStack(spacing: LP.Spacing.s) {
                holdToSpeakButton
                Text(voiceStatus.message(recognizedText: recognizedCallText))
                    .lpText(LP.Typography.c1Regular)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LP.Content.invertTertiary)
                    .frame(minHeight: 34)
            }
            Spacer()
        }
        .onDisappear { voiceInput.stop() }
    }

    private var glitchScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(
                headItem: .mystery,
                isDark: true,
                speech: "…能…量…#@!%…不足…",
                isGlitching: true,
                isFlickering: true
            )
            VStack(spacing: LP.Spacing.m) {
                warningToast("Pibo 需要你的运动能量才能稳定存在")
                warningToast("你去运动，Pibo 的花才有活力")
            }
            Spacer()
            onboardingButton("签订能量契约", kind: .danger) { go(.auth) }
        }
        .onAppear { LPHaptics.glitchSurge() }
    }

    private var authScene: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Text("签订能量契约")
                        .lpText(LP.Typography.uiH2)
                        .foregroundStyle(LP.Content.primary)
                    Text("…让…我…感受…你的…心跳…#@!%")
                        .lpText(LP.Typography.b2Regular)
                        .foregroundStyle(LP.Content.secondary)
                }

                VStack(spacing: LP.Spacing.m) {
                    authCard(icon: "moon.zzz.fill", title: "睡眠", body: "Pibo 需要知道你休息了多久，花才能安心开")
                    authCard(icon: "figure.run", title: "运动", body: "Pibo 需要感受你的心跳，才知道你有没有动")
                    authCard(icon: "camera", title: "拍照", body: "Pibo 通过你的镜头认识地球")
                }

                VStack(spacing: LP.Spacing.m) {
                    switch health.authState {
                    case .unavailable:
                        Text("当前设备不支持 HealthKit · 仅 Demo 模式可用")
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.tertiary)
                        onboardingButton("用 Demo 数据继续", kind: .primary, action: continueWithDemoEnergy)
                    case .requesting:
                        HStack(spacing: LP.Spacing.m) {
                            ProgressView()
                            Text("等你授权…")
                                .lpText(LP.Typography.c1Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    default:
                        onboardingButton(authRequested ? "正在连接…" : "签订契约，让 Pibo 连上你", kind: .primary, action: connect)
                        onboardingButton("用 Demo 数据继续", kind: .secondary, action: continueWithDemoEnergy)
                        onboardingButton("以后再说", kind: .ghost, action: showContractFailure)
                    }
                }
            }
            .padding(.vertical, LP.Spacing.l)
        }
    }

    private var contractFailureScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            Text("检测到·····能量不足······pibo降临失败")
                .font(.system(size: 26, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0xFF2A35))
                .shadow(color: Color(hex: 0xFF2A35).opacity(0.42), radius: 18)
                .padding(.horizontal, LP.Spacing.l)
            Spacer()
            onboardingButton("退出 App", kind: .danger) { exitAfterContractFailure() }
        }
        .onAppear { LPHaptics.glitchSurge() }
    }

    private var energyScene: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xl) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text("契约已签订")
                    .lpText(LP.Typography.uiH2)
                    .foregroundStyle(LP.Content.primary)
                Text("Pibo 正在获取你的能量数据…")
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(LP.Content.secondary)
            }

            VStack(spacing: LP.Spacing.m) {
                detectionCard(
                    title: "运动能量",
                    status: energyProgress < 0.45 ? "正在检测今天的运动数据…" : "今日步数 4,286\n能量已记录",
                    icon: "figure.walk"
                )
                detectionCard(
                    title: "睡眠能量",
                    status: energyProgress < 0.8 ? "等待运动检测完成…" : "昨晚睡眠 7.2 小时\n能量已记录",
                    icon: "moon.zzz.fill"
                )
            }
            Spacer()
            ProgressView(value: energyProgress)
                .tint(LP.Fill.foundationAccent)
            onboardingButton(energyProgress >= 1 ? "继续" : "读取中…", kind: .primary) {
                if energyProgress >= 1 { go(.pluck) }
            }
        }
        .onAppear { startEnergyRead() }
    }

    private var pluckScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            VStack(spacing: LP.Spacing.s) {
                Text("Pibo 读取了你的能量…")
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text("它在地球上长出了第一株芽")
                    .lpText(LP.Typography.uiH3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LP.Content.primary)
                Text("往上拔，帮它种进花田里")
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(LP.Content.secondary)
            }
            Spacer()
            ZStack(alignment: .top) {
                PiboOnboardingBlob(
                    headItem: .mystery,
                    isDark: false,
                    speech: nil,
                    showHead: false,
                    showOverhead: false
                )
                    .padding(.top, 38)
                if !pluckCompleted {
                    PiboOnboardingHeadSprite(growth: .sprouted, height: 74)
                        .rotationEffect(.radians(Self.hairDragAngle(dx: pluckDragX)))
                        .scaleEffect(x: 1, y: Self.hairDragScale(up: pluckOffset), anchor: .bottom)
                        .offset(x: Self.rubberBand(pluckDragX, limit: 110) * 0.18,
                                y: 78 - pluckOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    pluckDragX = value.translation.width
                                    pluckOffset = max(0, min(110, -value.translation.height))
                                }
                                .onEnded { value in
                                    let pull = hypot(value.translation.width, value.translation.height)
                                    if pluckOffset >= 76 || pull > 82 {
                                        finishPluck()
                                    } else {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                                            pluckOffset = 0
                                            pluckDragX = 0
                                        }
                                    }
                                }
                        )
                }
            }
            Spacer()
            onboardingButton("已经拔下来了", kind: .secondary) { finishPluck() }
        }
    }

    private var completeScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            VStack(spacing: LP.Spacing.s) {
                Text("第 1 天")
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text("和 Pibo 一起的早晨")
                    .lpText(LP.Typography.uiH2)
                    .foregroundStyle(LP.Content.primary)
            }
            Spacer()
            PiboOnboardingBlob(headItem: .mystery, isDark: false, speech: completeSpeech, showHead: false, showOverhead: false)
                .onTapGesture { piboTapCount += 1 }
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text("Pibo 每天会从你这里获取能量，结出一株幼苗")
                Text("它很想要花开，需要你给它注入能量")
                Text("能量不足时，Pibo 会变得暴躁…")
                    .foregroundStyle(LP.Fill.foundationError)
            }
            .lpText(LP.Typography.b2Regular)
            .foregroundStyle(LP.Content.secondary)
            .padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).strokeBorder(LP.Separator.primary))
            Spacer()
            onboardingButton("知道了", kind: .primary) { finishOnboarding() }
        }
    }

    // MARK: Actions

    private func go(_ next: OnboardingScene, haptics: Bool = true) {
        if haptics { LPHaptics.tap() }
        withAnimation(.easeInOut(duration: 0.28)) { scene = next }
    }

    private func restoreOnboardingSceneIfNeeded() {
        guard UserDefaults.standard.bool(forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth) else { return }
        UserDefaults.standard.removeObject(forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth)
        scene = .auth
    }

    private func startIntro() {
        Task { @MainActor in
            for index in Self.introLines.indices {
                guard scene == .intro else { return }
                withAnimation(.easeInOut(duration: 0.95)) { introIndex = index }
                try? await Task.sleep(for: .milliseconds(Self.introLines[index].pause))
            }
            if scene == .intro { go(.falling, haptics: false) }
        }
    }

    private func captureLight() {
        guard !cameraIsChecking else { return }
        LPHaptics.tap()
        lightCaptureAttempts += 1
        cameraIsChecking = true
        let frame = Self.simulatedLightFrame(isBright: lightCaptureAttempts > 1)
        let hasEnoughLight = LightCaptureVerifier.hasEnoughWhite(frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            cameraIsChecking = false
            if hasEnoughLight {
                cameraMessage = "检测到光"
                withAnimation(.easeOut(duration: 0.18)) { lightCaptured = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { go(.awaken, haptics: false) }
            } else {
                cameraMessage = "还是好黑，pibo看不见"
            }
        }
    }

    private func connect() {
        guard !authRequested else { return }
        authRequested = true
        LPLog.onboarding.notice("User chose: connect HealthKit")
        commitName()
        Task {
            await health.requestAuthorization()
            store.demoMode = health.authState != .granted
            LPLog.onboarding.notice("Onboarding auth finished (auth=\(String(describing: health.authState), privacy: .public))")
            Analytics.track(.healthAuth, screen: "onboarding",
                            ["granted": .bool(health.authState == .granted)])
            go(.energy, haptics: false)
        }
    }

    private func continueWithDemoEnergy() {
        LPLog.onboarding.notice("User chose: onboarding demo/later")
        commitName()
        store.demoMode = true
        go(.energy)
    }

    private func showContractFailure() {
        LPLog.onboarding.notice("User chose: onboarding later/failure")
        UserDefaults.standard.set(true, forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth)
        go(.contractFailure)
    }

    private func exitAfterContractFailure() {
        UserDefaults.standard.set(true, forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth)
        LPHaptics.glitchSurge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIApplication.shared.perform(Selector(("suspend")))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            Darwin.exit(0)
        }
    }

    private func startEnergyRead() {
        energyProgress = 0
        Task { @MainActor in
            for value in [0.35, 0.68, 1.0] {
                guard scene == .energy else { return }
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeInOut(duration: 0.35)) { energyProgress = value }
            }
        }
    }

    private func finishPluck() {
        guard !pluckCompleted else { return }
        LPHaptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            pluckOffset = 112
            pluckDragX = 0
            pluckCompleted = true
        }
        store.growthStage = .sprouted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { go(.complete, haptics: false) }
    }

    private func finishOnboarding() {
        LPLog.onboarding.notice("Onboarding finished")
        commitName()
        onContinue()
    }

    /// Bail out of the whole onboarding flow straight to Home. Commits whatever
    /// name was entered (defaults to PIBO) and stops any in-flight voice capture.
    private func skipOnboarding() {
        LPLog.onboarding.notice("User skipped onboarding")
        voiceInput.stop()
        commitName()
        onContinue()
    }

    /// Persistent top-right "跳过" control — skips the entire onboarding stage.
    private var skipButton: some View {
        Button(action: skipOnboarding) {
            HStack(spacing: 3) {
                Text(AppLocalization.text("跳过"))
                    .lpText(LP.Typography.c1Medium)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(skipForeground)
            .padding(.horizontal, LP.Spacing.m)
            .padding(.vertical, LP.Spacing.s)
            .background(Capsule().fill(skipBackground))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Skip-button colors track the scene palette so it stays legible on the
    /// dark / glitch / paper backdrops.
    private var skipForeground: Color {
        switch scene.palette {
        case .dark, .glitch: return Color.white.opacity(0.6)
        case .paper, .home:  return LP.Content.tertiary
        }
    }

    private var skipBackground: Color {
        switch scene.palette {
        case .dark, .glitch: return Color.white.opacity(0.12)
        case .paper, .home:  return Color.black.opacity(0.05)
        }
    }

    private func commitName() {
        let trimmed = petNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.petName = trimmed.isEmpty ? "PIBO" : String(trimmed.prefix(16))
    }

    private var nameResponseSpeech: String {
        let trimmed = petNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? store.petName : String(trimmed.prefix(16))
        return "···\(name)·····嗯，有点复杂·····你好，人"
    }

    // MARK: Pieces

    private var holdToSpeakButton: some View {
        Text(isHoldingVoiceInput ? "松开结束" : "按住呼唤")
            .lpText(LP.Typography.b1Medium)
            .foregroundStyle(isHoldingVoiceInput ? Color.white : Color.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, LP.Spacing.l)
            .background(
                Capsule().fill(isHoldingVoiceInput ? Color(hex: 0xFF2A35) : .white)
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.32), lineWidth: LP.BorderWidth.regular))
            .scaleEffect(isHoldingVoiceInput ? 1.03 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHoldingVoiceInput)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHoldingVoiceInput else { return }
                        beginVoiceCall()
                    }
                    .onEnded { _ in
                        endVoiceCall()
                    }
            )
    }

    private func onboardingButton(_ title: String, kind: OnboardingButtonKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(kind.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LP.Spacing.l)
                .background(Capsule().fill(kind.background))
                .overlay(Capsule().strokeBorder(kind.border, lineWidth: LP.BorderWidth.regular))
        }
        .buttonStyle(.plain)
    }

    private func authCard(icon: String, title: String, body: String) -> some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Fill.foundationAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(body)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(LP.Spacing.l)
        .background(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).fill(LP.Fill.bgContainer))
        .overlay(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).strokeBorder(LP.Separator.primary))
    }

    private func beginVoiceCall() {
        isHoldingVoiceInput = true
        recognizedCallText = ""
        voiceStatus = .requestingPermission
        LPHaptics.confirm()
        voiceInput.start(
            onText: { text in
                recognizedCallText = text
                voiceStatus = .listening
                if Self.isPiboCall(text) {
                    completeVoiceCall()
                }
            },
            onReady: {
                voiceStatus = .listening
            },
            onDenied: {
                isHoldingVoiceInput = false
                voiceStatus = .permissionDenied
            },
            onError: {
                isHoldingVoiceInput = false
                voiceStatus = .failed
            }
        )
    }

    private func endVoiceCall() {
        guard isHoldingVoiceInput else { return }
        isHoldingVoiceInput = false
        voiceInput.stop()
        if Self.isPiboCall(recognizedCallText) {
            completeVoiceCall()
        } else if !recognizedCallText.isEmpty {
            voiceStatus = .notRecognized
        } else if voiceStatus != .permissionDenied {
            voiceStatus = .idle
        }
    }

    private func completeVoiceCall() {
        guard scene == .call else { return }
        isHoldingVoiceInput = false
        voiceInput.stop()
        voiceStatus = .recognized
        callPulse = true
        LPHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            callPulse = false
            go(.glitch)
        }
    }

    private static func isPiboCall(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "，", with: "")
        return normalized.contains("pibo")
            || normalized.contains("皮波")
            || normalized.contains("屁波")
            || normalized.contains("啵啵")
    }

    private func detectionCard(title: String, status: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: LP.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Fill.foundationAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(title)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(status)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(status.contains("已记录") ? LP.Fill.foundationSuccess : LP.Content.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(LP.Spacing.l)
        .background(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).strokeBorder(LP.Separator.primary))
    }

    private func warningToast(_ text: String) -> some View {
        Text(text)
            .lpText(LP.Typography.c1Medium)
            .foregroundStyle(Color(hex: 0xFF7A7A))
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.m)
            .background(Capsule().fill(Color.black.opacity(0.36)))
            .overlay(Capsule().strokeBorder(Color(hex: 0xFF7A7A).opacity(0.35)))
    }

    private var cameraGrid: some View {
        Canvas { ctx, size in
            let color = Color.white.opacity(0.16)
            for x in stride(from: size.width / 3, through: size.width, by: size.width / 3) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
            }
            for y in stride(from: size.height / 3, through: size.height, by: size.height / 3) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
    }

    private var completeSpeech: String {
        let replies = [
            "…第一朵…花在地球…开了…",
            "…别碰…#@!%",
            "…花…会…掉…",
            "…你…是…谁…",
            "…地球…也能…长花…？",
            "…地球人…真奇怪…"
        ]
        return replies[min(piboTapCount, replies.count - 1)]
    }

    private static let introLines: [(text: String, pause: Int, highlight: Bool)] = [
        ("一只精灵掉到了地球上", 1400, false),
        ("它不会说人话", 1100, false),
        ("不认识你", 1050, false),
        ("也不认识这个世界", 1400, false),
        ("但——", 1350, true),
        ("你真的认识自己的身体吗？", 1650, false),
        ("你真的认识周围的世界吗？", 1650, false),
        ("帮它种一朵花", 1150, false),
        ("也是帮你自己", 1150, false),
        ("重新看一看", 1650, false),
    ]

    private static func simulatedLightFrame(isBright: Bool) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let whiteWidth = isBright ? size.width * 0.72 : size.width * 0.32
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: whiteWidth, height: size.height))
        }
    }

    private static func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        limit * value / (abs(value) + limit)
    }

    private static func hairDragAngle(dx: CGFloat) -> CGFloat {
        -0.55 * rubberBand(dx, limit: 110) / 110
    }

    private static func hairDragScale(up: CGFloat) -> CGFloat {
        1 + 0.28 * rubberBand(up, limit: 130) / 130
    }
}

private enum OnboardingScene {
    case intro
    case falling
    case darkness
    case camera
    case awaken
    case name
    case nameResponse
    case call
    case glitch
    case contractFailure
    case auth
    case energy
    case pluck
    case complete

    enum Palette { case dark, paper, glitch, home }

    var palette: Palette {
        switch self {
        case .intro, .falling, .darkness, .camera, .awaken, .name, .nameResponse, .call:
            return .dark
        case .glitch, .contractFailure:
            return .glitch
        case .auth, .energy, .pluck:
            return .paper
        case .complete:
            return .home
        }
    }

    var usesIdentityBackground: Bool {
        switch self {
        case .awaken, .name, .nameResponse:
            return true
        default:
            return false
        }
    }

    /// Whether the global "跳过" control shows. Hidden on the contract-failure
    /// dead-end (its own exit flow) and the final hand-off screen.
    var showsSkip: Bool {
        switch self {
        case .contractFailure, .complete:
            return false
        default:
            return true
        }
    }
}

private enum VoiceInputStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case recognized
    case notRecognized
    case permissionDenied
    case failed

    func message(recognizedText: String) -> String {
        switch self {
        case .idle:
            return "按住按钮，对着它说出 Pibo"
        case .requestingPermission:
            return "正在请求语音权限…"
        case .listening:
            return recognizedText.isEmpty ? "正在听…" : "听到了：\(recognizedText)"
        case .recognized:
            return "…听见了…"
        case .notRecognized:
            return "它没听清，再喊一次 Pibo"
        case .permissionDenied:
            return "需要开启麦克风和语音识别权限"
        case .failed:
            return "语音出了点问题，再试一次"
        }
    }
}

@MainActor
private final class OnboardingVoiceInputController {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var reportsErrors = true

    func start(
        onText: @escaping (String) -> Void,
        onReady: @escaping () -> Void,
        onDenied: @escaping () -> Void,
        onError: @escaping () -> Void
    ) {
        requestPermissions { [weak self] allowed in
            guard allowed else {
                onDenied()
                return
            }
            self?.startRecognition(onText: onText, onReady: onReady, onError: onError)
        }
    }

    func stop() {
        reportsErrors = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            DispatchQueue.main.async {
                guard speechStatus == .authorized else {
                    completion(false)
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async { completion(allowed) }
                }
            }
        }
    }

    private func startRecognition(
        onText: @escaping (String) -> Void,
        onReady: @escaping () -> Void,
        onError: @escaping () -> Void
    ) {
        stop()
        reportsErrors = true
        guard let recognizer, recognizer.isAvailable else {
            onError()
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError()
            return
        }

        let nextRequest = SFSpeechAudioBufferRecognitionRequest()
        nextRequest.shouldReportPartialResults = true
        request = nextRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak nextRequest] buffer, _ in
            nextRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            onReady()
        } catch {
            onError()
            return
        }

        task = recognizer.recognitionTask(with: nextRequest) { [weak self] result, error in
            if let result {
                Task { @MainActor in
                    onText(result.bestTranscription.formattedString)
                }
            }
            if error != nil {
                Task { @MainActor in
                    if self?.reportsErrors == true {
                        onError()
                    }
                }
            }
        }
    }
}

private enum OnboardingButtonKind {
    case primary
    case secondary
    case ghost
    case light
    case danger

    var foreground: Color {
        switch self {
        case .primary, .danger:
            return LP.Fill.foundationOnAccent
        case .secondary, .ghost:
            return LP.Content.primary
        case .light:
            return .black.opacity(0.82)
        }
    }

    var background: Color {
        switch self {
        case .primary:
            return LP.Fill.foundationAccent
        case .secondary:
            return LP.Fill.bgContainer
        case .ghost:
            return .clear
        case .light:
            return .white
        case .danger:
            return LP.Fill.foundationError
        }
    }

    var border: Color {
        switch self {
        case .primary:
            return LP.Fill.foundationAccent
        case .secondary, .ghost:
            return LP.Separator.primary
        case .light:
            return .white.opacity(0.32)
        case .danger:
            return LP.Fill.foundationError
        }
    }
}

private struct PiboOnboardingBlob: View {
    let headItem: PiboHeadItem
    let isDark: Bool
    let speech: String?
    var showHead: Bool = true
    var showOverhead: Bool = true
    var isGlitching: Bool = false
    var isFlickering: Bool = false

    private var growth: PiboGrowthStage {
        headItem == .sprout ? .sprouted : .mystery
    }

    private var usesDarkSpeechStyle: Bool {
        !isGlitching
    }

    var body: some View {
        VStack(spacing: LP.Spacing.m) {
            if let speech {
                Text(speech)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(isGlitching ? Color(hex: 0xFF7A7A) : (usesDarkSpeechStyle ? LP.Content.invertSecondary : LP.Content.primary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, LP.Spacing.s)
                    .frame(maxWidth: 260)
                    .background(Capsule().fill((usesDarkSpeechStyle ? Color.white : Color.black).opacity(0.10)))
                    .overlay(Capsule().strokeBorder((isGlitching ? Color(hex: 0xFF7A7A) : Color.white).opacity(0.25)))
                    .padding(.bottom, LP.Spacing.s)
            }

            figure
                .rotationEffect(.degrees(isGlitching ? -2 : 0))
                .offset(x: isGlitching ? -3 : 0)
        }
        .padding(.vertical, LP.Spacing.s)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var figure: some View {
        if isFlickering {
            TimelineView(.animation) { timeline in
                figureContent
                    .opacity(Self.flickerOpacity(at: timeline.date.timeIntervalSinceReferenceDate))
                    .offset(x: Self.flickerOffset(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            figureContent
        }
    }

    private var figureContent: some View {
        ZStack(alignment: .top) {
                if growth == .mystery, showOverhead {
                    Image("demon_hole")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128)
                        .offset(y: 0)
                }

                if showHead {
                    PiboOnboardingHeadSprite(growth: growth, height: 54)
                        .offset(y: growth == .mystery ? 23 : 14)
                }

                Image("pibo_body")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 154)
                    .offset(y: 58)
                    .shadow(color: .black.opacity(isDark ? 0.32 : 0.14), radius: 16, y: 8)
            }
            .frame(width: 180, height: 220)
            .saturation(isDark ? 0.2 : 1)
            .brightness(isDark ? -0.18 : 0)
            .opacity(isDark ? 0.78 : 1)
    }

    private static func flickerOpacity(at time: TimeInterval) -> Double {
        let pulse = sin(time * 38)
        let snap = sin(time * 91) > 0.86
        return snap ? 0.18 : (pulse > 0.18 ? 0.92 : 0.46)
    }

    private static func flickerOffset(at time: TimeInterval) -> CGFloat {
        sin(time * 73) > 0.72 ? -5 : 3
    }
}

private enum LightCaptureVerifier {
    /// Returns true when at least half the sampled pixels are close to white.
    /// This is intentionally strict: all RGB channels must be bright, so a
    /// saturated colored surface does not masquerade as usable light.
    static func hasEnoughWhite(_ image: UIImage, threshold: CGFloat = 0.5) -> Bool {
        whiteCoverage(in: image) >= threshold
    }

    static func whiteCoverage(in image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }

        let width = 32
        let height = 32
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return 0 }

        var whitePixels = 0
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            if r >= 220, g >= 220, b >= 220 { whitePixels += 1 }
        }

        return CGFloat(whitePixels) / CGFloat(width * height)
    }
}

private struct PiboOnboardingHeadSprite: View {
    let growth: PiboGrowthStage
    var height: CGFloat

    private var imageName: String {
        switch growth {
        case .mystery:
            return "demon_curl"
        case .sprouted:
            return "demon_curl_sprouted"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }
}

private struct LightBeamView: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 180, height: 8)
                .rotationEffect(.degrees(62))
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 2)
                .frame(width: 120, height: 120)
        }
        .blur(radius: 0.4)
    }
}

private struct RedGlitchIonFlowView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * 4
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(
                    Path { $0.addRect(rect) },
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0x210408),
                            Color(hex: 0x070207),
                            Color(hex: 0x31070D)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                for index in 0..<28 {
                    let lane = CGFloat(index) / 28
                    let speed = 0.09 + Double(index % 7) * 0.018
                    let travel = CGFloat((time * speed + Double(index) * 0.137).truncatingRemainder(dividingBy: 1.35))
                    let baseX = (lane * 1.25 - 0.14) * size.width
                    let baseY = (travel - 0.18) * size.height
                    let length = size.height * CGFloat([0.14, 0.22, 0.31, 0.18, 0.26][index % 5])
                    let wobble = sin(time * (1.8 + Double(index % 4)) + Double(index)) * 18
                    var stream = Path()
                    stream.move(to: CGPoint(x: baseX + wobble, y: baseY))
                    stream.addLine(to: CGPoint(x: baseX - length * 0.42 + wobble, y: baseY + length))
                    let hot = index % 4 == 0
                    ctx.stroke(
                        stream,
                        with: .color(Color(hex: hot ? 0xFF2A35 : 0xB10E22).opacity(hot ? 0.72 : 0.38)),
                        style: StrokeStyle(lineWidth: hot ? 3.0 : 1.4, lineCap: .round)
                    )
                }

                for index in 0..<46 {
                    let speed = 0.16 + Double(index % 9) * 0.021
                    let phase = CGFloat((time * speed + Double(index) * 0.071).truncatingRemainder(dividingBy: 1))
                    let x = CGFloat((Double(index * 37 % 100) / 100.0)) * size.width
                    let y = phase * size.height
                    let radius = CGFloat([1.2, 1.8, 2.4, 1.4][index % 4])
                    let glow = CGRect(x: x, y: y, width: radius, height: radius)
                    ctx.fill(
                        Path(ellipseIn: glow),
                        with: .color(Color(hex: 0xFF465A).opacity(0.55))
                    )
                }
            }
            .overlay(
                RadialGradient(
                    colors: [
                        Color(hex: 0xFF1C2E).opacity(0.26),
                        Color.clear,
                        Color.black.opacity(0.52)
                    ],
                    center: .center,
                    startRadius: 24,
                    endRadius: 520
                )
            )
        }
    }
}

private struct GlitchNoiseView: View {
    var body: some View {
        Canvas { ctx, size in
            for row in stride(from: 0, through: size.height, by: 11) {
                let opacity = row.truncatingRemainder(dividingBy: 22) == 0 ? 0.15 : 0.05
                let rect = CGRect(x: 0, y: row, width: size.width, height: 1)
                ctx.fill(Path { $0.addRect(rect) }, with: .color(Color.white.opacity(opacity)))
            }
            for index in 0..<12 {
                let y = CGFloat(index) * size.height / 12
                let width = size.width * CGFloat([0.32, 0.56, 0.22, 0.72][index % 4])
                let x = CGFloat(index % 3) * 18
                let rect = CGRect(x: x, y: y, width: width, height: 3)
                ctx.fill(Path { $0.addRect(rect) }, with: .color(Color(hex: 0xFF4D6D).opacity(0.18)))
            }
        }
    }
}

#Preview("Onboarding") {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
}
