import SwiftUI
import os
import AVFoundation
import Observation
import UIKit
import Darwin
import Speech

/// First-launch story and HealthKit authorization flow.
///
/// The sequence mirrors the approved 2026-07-26 onboarding prototype:
/// darkness → forest reveal → first contact → system HealthKit authorization
/// → partnership.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store

    @State private var step: OnboardingStep = .system
    @State private var dialogueIndex = 0
    @State private var lightCount = 0
    @State private var authRequested = false
    @State private var piboMotion = false
    @State private var piboTalkPulse = false
    @State private var sparkle = false

    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                forestLayer
                watchersLayer(size: proxy.size)
                piboLayer(size: proxy.size)

                switch step {
                case .system:
                    systemNarration
                case .void:
                    dialogueOverlay(size: proxy.size, lines: Self.voidLines, finalAction: "继续") {
                        transition(to: .eyes)
                    }
                case .eyes:
                    eyesTransitionOverlay
                case .charge:
                    chargeOverlay
                case .fright:
                    dialogueOverlay(size: proxy.size, lines: Self.frightLines, finalAction: "是的") {
                        transition(to: .link)
                    }
                case .link:
                    dialogueOverlay(size: proxy.size, lines: Self.linkLines, finalAction: "继续") {
                        transition(to: .permission)
                    }
                case .permission:
                    systemAuthorizationBackground
                case .denied:
                    deniedScreen
                case .receiving:
                    Color.clear
                case .repel:
                    dialogueOverlay(size: proxy.size, lines: Self.repelLines, finalAction: "继续") {
                        transition(to: .bonding)
                    }
                case .bonding:
                    dialogueOverlay(size: proxy.size, lines: ["咕噜……契约，亮起来了。"], finalAction: "继续") {
                        transition(to: .partners)
                    }
                case .partners:
                    dialogueOverlay(size: proxy.size, lines: Self.partnerLines, finalAction: "活下去") {
                        finishOnboarding()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
            .clipped()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            restoreOnboardingStepIfNeeded()
            runAutomaticStep()
        }
        .animation(.easeInOut(duration: 0.55), value: step)
        .animation(.easeInOut(duration: 0.65), value: lightCount)
    }

    // MARK: - Scene

    private var forestLayer: some View {
        ZStack {
            Color.black

            Image("onboarding_forest_empty")
                .resizable()
                .scaledToFill()
                .opacity(forestOpacity)
                .brightness(-0.34 + (0.34 * revealProgress))
                .saturation(0.55 + (0.45 * revealProgress))
                .scaleEffect(1.055 - (0.025 * revealProgress))

            Image("onboarding_morning_light")
                .resizable()
                .scaledToFill()
                .blendMode(.screen)
                .opacity(step.isForestVisible ? 0.284 * revealProgress : 0)
        }
        .ignoresSafeArea()
    }

    private func watchersLayer(size: CGSize) -> some View {
        ZStack {
            watcher(scale: 1.16, opacity: 1)
                .position(x: size.width * 0.27, y: size.height * 0.57)
            watcher(scale: 0.66, opacity: 0.62)
                .position(x: size.width * 0.76, y: size.height * 0.44)
            watcher(scale: 0.86, opacity: 0.8)
                .position(x: size.width * 0.56, y: size.height * 0.68)
        }
        .opacity(watchersOpacity)
        .scaleEffect(step == .repel || step.isAfterRepel ? 0.04 : 1, anchor: UnitPoint(x: 0.52, y: 0.48))
        .blur(radius: step == .repel || step.isAfterRepel ? 12 : 0)
        .animation(.easeInOut(duration: step == .repel ? 2.2 : 0.7), value: step)
        .allowsHitTesting(false)
    }

    private func watcher(scale: CGFloat, opacity: Double) -> some View {
        HStack(spacing: 19) {
            Image("onboarding_eye_left")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
            Image("onboarding_eye_right")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
        }
        .frame(width: 70, height: 34)
        .padding(.horizontal, 9)
        .background(
            RadialGradient(colors: [Color.black.opacity(0.48), .clear], center: .center, startRadius: 1, endRadius: 44)
        )
        .shadow(color: Color(hex: 0xCAFF82).opacity(0.8), radius: 9)
        .scaleEffect(scale)
        .opacity(opacity)
    }

    private func piboLayer(size: CGSize) -> some View {
        ZStack {
            Image(step.isPowered ? "onboarding_pibo_powered" : "onboarding_pibo_main")
                .resizable()
                .scaledToFit()
                .frame(width: step.isPowered ? 224 : 188, height: 290)
                .brightness(step == .charge ? -0.72 + (0.72 * revealProgress) : 0)
                .saturation(step == .charge ? 0.4 + (0.6 * revealProgress) : 1)

            if sparkle {
                SparkleView()
                    .offset(x: 31, y: -103)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .position(x: size.width * 0.5, y: size.height * 0.48)
        .opacity(piboOpacity)
        .scaleEffect((piboMotion ? 1.025 : 1) * (piboTalkPulse ? 0.95 : 1))
        .rotationEffect(.degrees(piboMotion ? 0.8 : -0.8))
        .animation(.easeInOut(duration: 0.18).repeatCount(8, autoreverses: true), value: piboMotion)
        .animation(.easeOut(duration: 0.12), value: piboTalkPulse)
        .allowsHitTesting(false)
    }

    // MARK: - Overlays

    private var systemNarration: some View {
        VStack {
            Spacer()
                .frame(height: 230)
            Text("一只未知生命体，坠落在地球。")
                .font(.system(size: 15, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.48))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 28)
        .transition(.opacity)
    }

    private var chargeOverlay: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { addLight() }

            VStack {
                Text("轻点屏幕，给它一点光。")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.56))
                    .padding(.top, 205)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    private var eyesTransitionOverlay: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { transition(to: .charge) }

            Text("……")
                .font(.system(size: 15, weight: .medium))
                .tracking(4)
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.top, 190)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private func dialogueOverlay(
        size: CGSize,
        lines: [String],
        finalAction: String,
        completion: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    LPHaptics.tap()
                    if dialogueIndex < lines.count - 1 {
                        withAnimation(.easeOut(duration: 0.36)) { dialogueIndex += 1 }
                        animatePiboForDialogue()
                    } else {
                        completion()
                    }
                }

            Text(lines[min(dialogueIndex, lines.count - 1)])
                .font(.system(size: 16, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: 278)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 23,
                        bottomLeadingRadius: 7,
                        bottomTrailingRadius: 23,
                        topTrailingRadius: 23,
                        style: .continuous
                    )
                    .fill(Color(red: 3 / 255, green: 15 / 255, blue: 11 / 255).opacity(0.66))
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 23,
                        bottomLeadingRadius: 7,
                        bottomTrailingRadius: 23,
                        topTrailingRadius: 23,
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 25, y: 12)
                .position(x: size.width / 2, y: size.height * 0.23)
                .id(dialogueIndex)
                .transition(.offset(y: 7).combined(with: .opacity))

            if step != .void {
                Text("PIBO（未知生命体）")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .position(x: size.width / 2, y: size.height * 0.71)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(
            "\(lines[min(dialogueIndex, lines.count - 1)])。点击屏幕任意位置继续"
        )
    }

    /// A quiet backing surface while iOS owns the authorization presentation.
    /// There is intentionally no app-authored pre-permission screen here.
    private var systemAuthorizationBackground: some View {
        Color(hex: 0xF7F8EE)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var deniedScreen: some View {
        Color(hex: 0xF7F8EE)
            .ignoresSafeArea()
            .overlay {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 48)

                        Image("onboarding_pibo_tired")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 210, height: 250)

                        Text("LINK INTERRUPTED / 契约中断")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0x7D5B3C))
                            .padding(.top, 22)

                        Text("Pibo 又没电了。")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(hex: 0x122A22))
                            .minimumScaleFactor(0.85)
                            .padding(.top, 12)

                        Text("这次没有连接到健康数据，Pibo 无法从你的睡眠、步数和运动中获得能量。\nMVP 版本暂时不能继续体验。")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0x566C62))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 32)
                            .padding(.top, 12)

                        Spacer(minLength: 36)

                        Button("重新尝试系统授权") {
                            authRequested = false
                            transition(to: .permission)
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .padding(.horizontal, 28)

                        Spacer(minLength: 36)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 720)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func transition(to next: OnboardingStep) {
        dialogueIndex = 0
        withAnimation(.easeInOut(duration: 0.5)) { step = next }
        runAutomaticStep()
    }

    private func runAutomaticStep() {
        switch step {
        case .system:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2600))
                guard step == .system else { return }
                transition(to: .void)
            }
        case .eyes:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1800))
                guard step == .eyes else { return }
                transition(to: .charge)
            }
        case .permission:
            requestHealthAuthorization()
        case .receiving:
            piboMotion = true
            LPHaptics.glitchSurge()
            withAnimation(.easeOut(duration: 0.35)) { sparkle = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1300))
                guard step == .receiving else { return }
                piboMotion = false
                transition(to: .repel)
            }
        default:
            break
        }
    }

    private func addLight() {
        guard step == .charge, lightCount < 5 else { return }
        lightCount += 1
        LPHaptics.tap()
        if lightCount == 5 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard step == .charge else { return }
                transition(to: .fright)
            }
        }
    }

    private func animatePiboForDialogue() {
        piboTalkPulse = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            piboTalkPulse = false
        }
    }

    private func requestHealthAuthorization() {
        guard !authRequested else { return }
        authRequested = true
        LPLog.onboarding.notice("User chose: connect HealthKit")
        Task {
            await health.requestAuthorization()
            let granted = health.authState == .granted
            store.demoMode = false
            Analytics.track(.healthAuth, screen: "onboarding", ["granted": .bool(granted)])
            LPLog.onboarding.notice("Onboarding auth finished (granted=\(granted, privacy: .public))")
            authRequested = false
            transition(to: granted ? .receiving : .denied)
        }
    }

    private func restoreOnboardingStepIfNeeded() {
        guard UserDefaults.standard.bool(forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth) else { return }
        UserDefaults.standard.removeObject(forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth)
        step = .permission
    }

    private func finishOnboarding() {
        LPLog.onboarding.notice("Onboarding finished")
        store.petName = "PIBO"
        store.demoMode = false
        LPHaptics.success()
        onContinue()
    }

    // MARK: - Derived presentation

    private var revealProgress: Double {
        if step == .charge {
            return (Double(lightCount) / 5) * 0.88
        }
        return step.isForestRevealed ? 0.88 : 0
    }

    private var forestOpacity: Double {
        step.isForestVisible ? max(0.05, revealProgress) : 0
    }

    private var piboOpacity: Double {
        if step == .charge {
            return 0.18 + (0.82 * revealProgress)
        }
        return step.showsPibo ? 1 : 0
    }

    private var watchersOpacity: Double {
        switch step {
        case .eyes:
            return 0.95
        case .charge:
            return 0.95 * max(0, 1 - (Double(lightCount) / 5))
        default:
            return 0
        }
    }

    private static let voidLines = [
        "……^&% 这里是哪里？",
        "光……被谁吃掉了。",
        "什么东西在靠近，Pibo好怕"
    ]

    private static let frightLines = [
        "Pibo，闻到了危险的味道",
        "……你是，人吗"
    ]

    private static let linkLines = [
        "人，你好香啊。",
        "靠近你，Pibo好像变强壮了",
        "可以借Pibo一点能量吗"
    ]

    private static let repelLines = [
        "……它们在往后退。",
        "你的能量，把黑暗里的东西赶走了。"
    ]

    private static let partnerLines = [
        "那，现在起我们就是伙伴了",
        "人，我们一起活下去"
    ]
}

private enum OnboardingStep: Equatable {
    case system
    case void
    case eyes
    case charge
    case fright
    case link
    case permission
    case denied
    case receiving
    case repel
    case bonding
    case partners

    var isForestVisible: Bool {
        switch self {
        case .charge, .fright, .link, .receiving, .repel, .bonding, .partners:
            return true
        default:
            return false
        }
    }

    var isForestRevealed: Bool {
        switch self {
        case .fright, .link, .receiving, .repel, .bonding, .partners:
            return true
        default:
            return false
        }
    }

    var showsWatchers: Bool {
        switch self {
        case .eyes, .charge:
            return true
        default:
            return false
        }
    }

    var showsPibo: Bool {
        switch self {
        case .charge, .fright, .link, .receiving, .repel, .bonding, .partners:
            return true
        default:
            return false
        }
    }

    var isPowered: Bool {
        switch self {
        case .receiving, .repel, .bonding, .partners:
            return true
        default:
            return false
        }
    }

    var isAfterRepel: Bool {
        switch self {
        case .bonding, .partners:
            return true
        default:
            return false
        }
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

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(hex: 0x122A22))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().fill(Color(hex: 0xCAFF82)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

private struct SparkleView: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color(hex: 0xF2FFD0)).frame(width: 25, height: 2)
            Capsule().fill(Color(hex: 0xF2FFD0)).frame(width: 2, height: 25)
            Circle().fill(Color.white).frame(width: 6, height: 6)
        }
        .shadow(color: Color(hex: 0xCAFF82), radius: 7)
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
        .environment(HealthDataService())
        .environment(PetStateStore())
}
