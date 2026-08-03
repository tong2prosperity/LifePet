import os
import SwiftUI
import UIKit

/// First-launch story and HealthKit authorization flow.
///
/// Rebuilt 2026-08-02 against the approved onboarding Figma
/// (`wQtaSAaU2InhraMiu4Mi6r`, page `onboarding`, node `6424:3262`) after the
/// 0801 走查. The beat order is the designer's frame order, left to right:
///
///     降落 → 未知生命体自语 ×2 → 眼睛出现(会眨眼) → 轻点五下给光
///          → Pibo 请求能量 ×5 → 系统授权 → 牠们退开了(眼睛消失)
///          → 能量说明 ×3 → 决定留下
///
/// Three structural rules come out of that review and are easy to regress:
///
/// 1. **Darkness is a black mask, never the forest's own opacity.** Fading the
///    artwork itself washes it toward whatever sits behind (grey), which is why
///    the 走查 screenshot reads milky instead of dark. The forest is always
///    fully opaque; `Color.black.opacity(maskOpacity)` on top does the dimming,
///    and it sits *between* Pibo and the watchers so the eyes stay lit in a
///    pitch-black frame — exactly the Figma layer order.
/// 2. **The watchers persist until authorization**, then retreat on the
///    「牠们退开了」 beat. Previously they faded out during the light taps, which
///    also meant the existing retreat animation was invisible.
/// 3. **The speaker label is part of the bubble**, stacked 4pt above it and
///    left-aligned inside a centered group (Figma `Frame 9417`). It reads
///    「未知生命体」 until Pibo first says its own name, then 「Pibo」.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: OnboardingStep = .system
    @State private var dialogueIndex = 0
    @State private var lightCount = 0
    @State private var authRequested = false
    @State private var watchersRetreated = false
    @State private var piboMotion = false
    @State private var piboTalkPulse = false
    @State private var sparkle = false

    let onContinue: () -> Void

    /// The Figma artboard every ratio below is measured in.
    private enum Design {
        static let frame = CGSize(width: 393, height: 852)

        /// `Frame 9417` — the 说话者标签 + 气泡 group, horizontally centered.
        static let bubbleTop: CGFloat = 272 / frame.height
        /// 「一个未知生命体降落在地球上......」/「轻点屏幕，给Pibo一点光」
        static let narrationCenterY: CGFloat = 328 / frame.height
        /// 「点击屏幕任意位置继续」
        static let hintCenterY: CGFloat = 770 / frame.height
        /// `Button` — 353×60 @ (20, 761)
        static let buttonCenterY: CGFloat = 791 / frame.height
        static let buttonInset: CGFloat = 20 / frame.width
        static let buttonHeight: CGFloat = 60

        /// 天敌的眼睛 — three 44×12 pairs, all low in the frame.
        static let watchers: [CGPoint] = [
            CGPoint(x: 68 / frame.width, y: 653 / frame.height),
            CGPoint(x: 173 / frame.width, y: 740 / frame.height),
            CGPoint(x: 289 / frame.width, y: 709 / frame.height)
        ]

        /// `pibo` — 惊恐 247×305 @ (83,366), 正常 222×303 @ (83,358).
        static let frightPibo = SpriteBox(width: 247, height: 305, x: 83, y: 366)
        static let normalPibo = SpriteBox(width: 222, height: 303, x: 83, y: 358)

        struct SpriteBox {
            let width, height, x, y: CGFloat
            var widthRatio: CGFloat { width / Design.frame.width }
            var centerX: CGFloat { (x + width / 2) / Design.frame.width }
            var centerY: CGFloat { (y + height / 2) / Design.frame.height }
            var aspect: CGFloat { height / width }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Figma layer order: 背景 → Pibo → 黑色蒙层 → 眼睛 → 气泡 → 按钮.
                forestLayer
                piboLayer(size: size)
                darknessMask
                watchersLayer(size: size)
                overlay(size: size)
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .clipped()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            if let forced = OnboardingStep.debugRequestedStep() {
                step = forced
                dialogueIndex = OnboardingStep.debugRequestedLineIndex()
                if forced == .charge { lightCount = OnboardingStep.debugRequestedLightCount() }
                if forced.isPowered { watchersRetreated = true }
                return
            }
            #endif
            restoreOnboardingStepIfNeeded()
            runAutomaticStep()
        }
        .animation(.easeInOut(duration: 0.55), value: step)
        .animation(.easeInOut(duration: 0.65), value: lightCount)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  UserDefaults.standard.bool(
                    forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth
                  )
            else { return }
            UserDefaults.standard.removeObject(
                forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth
            )
            transition(to: .permission)
        }
    }

    // MARK: - Scene

    /// Always fully opaque and always overfilling the screen — the mask above
    /// is what makes it dark. `scaledToFill` on a frame pinned to the *whole*
    /// proxy size is what removes the 走查 黑边: any leftover letterboxing came
    /// from the artwork being allowed to letterbox at its own aspect ratio.
    ///
    /// There is deliberately **no separate light-shaft layer**. Figma's
    /// `light morning` is a child of the `Group 270` scene, so the exported
    /// background already carries the shafts; the old `onboarding_morning_light`
    /// overlay was drawing them a second time.
    private var forestLayer: some View {
        GeometryReader { proxy in
            Image("onboarding_forest_empty")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 五下点击调的是这一层，不是森林本身的透明度。
    private var darknessMask: some View {
        Color.black
            .opacity(maskOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private func watchersLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(Array(Design.watchers.enumerated()), id: \.offset) { index, unit in
                WatcherEyes(phase: Double(index) * 0.9)
                    .position(x: size.width * unit.x, y: size.height * unit.y)
            }
        }
        .opacity(watchersOpacity)
        .scaleEffect(watchersRetreated ? 0.04 : 1, anchor: UnitPoint(x: 0.52, y: 0.8))
        .blur(radius: watchersRetreated ? 12 : 0)
        .animation(.easeInOut(duration: 2.2), value: watchersRetreated)
        .allowsHitTesting(false)
    }

    private func piboLayer(size: CGSize) -> some View {
        let box = step.isPowered ? Design.normalPibo : Design.frightPibo
        let width = size.width * box.widthRatio
        return ZStack {
            Image(step.isPowered ? "onboarding_pibo_normal" : "onboarding_pibo_fright")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: width * box.aspect)

            if sparkle {
                SparkleView()
                    .offset(x: width * 0.13, y: -width * 0.42)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .position(x: size.width * box.centerX, y: size.height * box.centerY)
        .scaleEffect((piboMotion ? 1.025 : 1) * (piboTalkPulse ? 0.95 : 1))
        .rotationEffect(.degrees(piboMotion ? 0.8 : -0.8))
        .animation(.easeInOut(duration: 0.18).repeatCount(8, autoreverses: true), value: piboMotion)
        .animation(.easeOut(duration: 0.12), value: piboTalkPulse)
        .allowsHitTesting(false)
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlay(size: CGSize) -> some View {
        switch step {
        case .system:
            landingNarration(size: size)
        case .charge:
            chargeOverlay(size: size)
        case .permission:
            Color.clear
        case .receiving:
            Color.clear
        default:
            dialogueOverlay(size: size)
        }
    }

    /// The hint lives on this screen only. Figma puts 「下方文字微微呼吸」 on the
    /// landing frame and 「用户有点击行为后 下方提示文字消失」 on the two frames after
    /// it — i.e. the tap advances and the hint is gone because the screen
    /// changed, not because the first tap is spent dismissing it.
    private func landingNarration(size: CGSize) -> some View {
        ZStack {
            tapCatcher { transition(to: .void) }

            narrationText("一个未知生命体降落在地球上......")
                .position(x: size.width / 2, y: size.height * Design.narrationCenterY)

            BreathingHint(text: "点击屏幕任意位置继续")
                .position(x: size.width / 2, y: size.height * Design.hintCenterY)
                .allowsHitTesting(false)
        }
    }

    private func chargeOverlay(size: CGSize) -> some View {
        ZStack {
            tapCatcher { addLight() }

            narrationText("轻点屏幕，给Pibo一点光")
                .position(x: size.width / 2, y: size.height * Design.narrationCenterY)
                .allowsHitTesting(false)
        }
    }

    private func dialogueOverlay(size: CGSize) -> some View {
        let lines = step.lines
        let index = min(dialogueIndex, max(0, lines.count - 1))
        let isLast = index >= lines.count - 1
        let showsButton = step.buttonTitle != nil && isLast

        return ZStack {
            // 有按钮的那一屏，点背景不再推进 —— 必须点按钮。
            if !showsButton {
                tapCatcher { advanceDialogue() }
            }

            SpeechBubble(speaker: step.speakerLabel, text: lines[index])
                .frame(maxWidth: size.width - 80, alignment: .leading)
                // 播报挂在气泡上，不要在外层用 `.combine` —— 那会把「借出能量」
                // 按钮一起并进同一个元素，VoiceOver 就点不到它了。
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.speakerLabel)：\(lines[index])")
                .position(x: size.width / 2, y: size.height * Design.bubbleTop + 39)
                .id(index)
                .transition(.offset(y: 7).combined(with: .opacity))

            if showsButton, let title = step.buttonTitle {
                OnboardingButton(title: title) { completeStep() }
                    .frame(width: size.width * (1 - Design.buttonInset * 2),
                           height: Design.buttonHeight)
                    .position(x: size.width / 2, y: size.height * Design.buttonCenterY)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func narrationText(_ text: String) -> some View {
        Text(text)
            .lpText(LP.Typography.b3Regular)
            .foregroundStyle(Color.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
    }

    private func tapCatcher(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                LPHaptics.tap()
                action()
            }
    }

    // MARK: - Actions

    private func advanceDialogue() {
        let lines = step.lines
        if dialogueIndex < lines.count - 1 {
            withAnimation(.easeOut(duration: 0.36)) { dialogueIndex += 1 }
            animatePiboForDialogue()
        } else {
            completeStep()
        }
    }

    private func completeStep() {
        switch step {
        case .void:      transition(to: .eyes)
        case .eyes:      transition(to: .charge)
        case .plea:      transition(to: .permission)
        case .denied:    retryAuthorization()
        case .repel:     transition(to: .warmth)
        case .warmth:    transition(to: .partners)
        case .partners:  finishOnboarding()
        default:         break
        }
    }

    private func transition(to next: OnboardingStep) {
        dialogueIndex = 0
        withAnimation(.easeInOut(duration: 0.5)) { step = next }
        runAutomaticStep()
    }

    private func runAutomaticStep() {
        switch step {
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
                sparkle = false
                transition(to: .repel)
                // 授权拿到后，这一帧眼睛才退场。
                watchersRetreated = true
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
                transition(to: .plea)
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
            let readiness = await health.onboardingReadiness()
            let granted = readiness.isReady
            store.demoMode = false
            Analytics.track(.healthAuth, screen: "onboarding", ["granted": .bool(granted)])
            LPLog.onboarding.notice("Onboarding auth finished (baselineReady=\(granted, privacy: .public))")
            authRequested = false
            transition(to: granted ? .receiving : .denied)
        }
    }

    /// 「若用户未同意，回到onboarding页面，Pibo继续请求用户授权」.
    ///
    /// iOS only presents decided HealthKit read scopes once. After the first
    /// system sheet, the Figma retry button therefore opens Settings. Returning
    /// to the app re-runs the request (for any still-undecided scopes) and the
    /// real sleep/steps/exercise baseline check above.
    private func retryAuthorization() {
        UserDefaults.standard.set(
            true,
            forKey: PiboPersistenceKeys.Defaults.onboardingResumeAuth
        )
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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

    /// 1 = 全黑, 0 = 全亮. 只有这一个量在控制暗度。
    private var maskOpacity: Double {
        switch step {
        case .system, .void, .eyes:
            return 1
        case .charge:
            return max(0, 1 - (Double(lightCount) / 5))
        default:
            return 0
        }
    }

    private var watchersOpacity: Double {
        step.showsWatchers ? 1 : 0
    }
}

// MARK: - Steps

private enum OnboardingStep: Equatable {
    /// 降落旁白.
    case system
    /// 未知生命体自语（此时还没自称 Pibo）.
    case void
    /// 眼睛出现，开始眨眼.
    case eyes
    /// 轻点五下给光.
    case charge
    /// Pibo 观察你 → 请求借能量（末屏出「借出能量」按钮）.
    case plea
    /// 系统授权页.
    case permission
    /// 用户未同意 —— Pibo 继续请求.
    case denied
    /// 授权成功，能量注入.
    case receiving
    /// 牠们退开了 —— 眼睛消失.
    case repel
    /// 能量从哪来.
    case warmth
    /// 决定留下.
    case partners

    var lines: [String] {
        switch self {
        case .void:
            return ["......^&%*这里是哪里？", "光......被谁吃掉了"]
        case .eyes:
            return ["什么东西在靠近，Pibo好怕......"]
        case .plea:
            return [
                "什么东西在盯着Pibo",
                "你是......",
                "这些东西好像害怕你",
                "是因为你身上的能量吗",
                "可以借一些能量给Pibo吗"
            ]
        case .denied:
            return ["我很需要...这些能量...", "没有这些能量，Pibo不能在这里生存"]
        case .repel:
            return ["果然可以...牠们退开了！"]
        case .warmth:
            return [
                "你的能量好温暖......",
                "你走路、你呼吸、你睡着的时候， 这股能量一直都在",
                "只要Pibo一直和你在一起， 牠们就不会再来了..."
            ]
        case .partners:
            return ["决定了——Pibo 要留在你身边！"]
        case .system, .charge, .permission, .receiving:
            return []
        }
    }

    /// 「Pibo自称Pibo后 未知生命体改为Pibo」— the rename happens on `.eyes`,
    /// the first line where Pibo says its own name.
    var speakerLabel: String {
        self == .void ? "未知生命体" : "Pibo"
    }

    var buttonTitle: String? {
        switch self {
        case .plea, .denied: return "借出能量"
        case .partners:      return "进入Pibo空间"
        default:             return nil
        }
    }

    /// 眼睛一直亮到授权为止（`.repel` 这一帧才退场）。
    var showsWatchers: Bool {
        switch self {
        case .eyes, .charge, .plea, .permission, .denied, .receiving, .repel:
            return true
        default:
            return false
        }
    }

    var isPowered: Bool {
        switch self {
        case .receiving, .repel, .warmth, .partners:
            return true
        default:
            return false
        }
    }
}

#if DEBUG
extension OnboardingStep {
    /// 截图验证用：`-PiboOnboardingStep=plea -PiboOnboardingLine=4`
    /// 直接落在任意一屏，不用一路点过去。
    static func debugRequestedStep() -> OnboardingStep? {
        guard let raw = value(for: "-PiboOnboardingStep=") else { return nil }
        switch raw {
        case "system":     return .system
        case "void":       return .void
        case "eyes":       return .eyes
        case "charge":     return .charge
        case "plea":       return .plea
        case "denied":     return .denied
        case "repel":      return .repel
        case "warmth":     return .warmth
        case "partners":   return .partners
        default:           return nil
        }
    }

    static func debugRequestedLineIndex() -> Int {
        Int(value(for: "-PiboOnboardingLine=") ?? "") ?? 0
    }

    static func debugRequestedLightCount() -> Int {
        Int(value(for: "-PiboOnboardingLight=") ?? "") ?? 0
    }

    private static func value(for prefix: String) -> String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}
#endif

// MARK: - Components

/// 统一的 Pibo 说话气泡（Figma `Frame 9417`）—— 说话者标签和气泡是一组，
/// 4pt 间距、整组左对齐、组本身在屏幕上水平居中。
private struct SpeechBubble: View {
    let speaker: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(speaker)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(Color.white)
                .padding(4)

            Text(text)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, LP.Spacing.xxl)
                .padding(.vertical, LP.Spacing.m)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                    .fill(Color.white)
                )
        }
    }
}

/// Figma `Button` — teal-600 capsule with a solid 8pt darker lip along the
/// bottom (`inset 0 -8px 0 0 #005244`), which is why the label sits 4pt high.
private struct OnboardingButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -4)
        }
        .buttonStyle(LipButtonStyle())
    }

    private struct LipButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    Capsule()
                        .fill(LP.Colorful.teal600)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(hex: 0x005244))
                                .frame(height: 8)
                        }
                        .clipShape(Capsule())
                }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
        }
    }
}

/// 「下方文字微微呼吸 透明度有小变化」.
private struct BreathingHint: View {
    let text: String
    @State private var breathing = false

    var body: some View {
        Text(text)
            .lpText(LP.Typography.b3Regular)
            .foregroundStyle(Color.white.opacity(breathing ? 0.72 : 0.38))
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
    }
}

/// 一对天敌的眼睛 —— 各自独立眨眼（Figma `Group 271`/`Group 272` 的两态，
/// 辉光色取自导出 SVG 的 feColorMatrix: rgb(0.875, 1.0, 0.465)）。
private struct WatcherEyes: View {
    /// Staggers each pair so the three never blink in lockstep.
    let phase: Double

    @State private var closed = false

    private static let glow = Color(hex: 0xDFFF76)
    /// Figma `Group 271`: each pair is 44×12 — two 12pt dots whose centers sit
    /// 32pt apart, so the gap between them is 20.
    private static let dotSize: CGFloat = 12
    private static let centerDistance: CGFloat = 32

    var body: some View {
        HStack(spacing: Self.centerDistance - Self.dotSize) {
            dot
            dot
        }
        .task {
            // Each pair keeps its own rhythm; the offsets are derived from
            // `phase` so this stays deterministic instead of random per frame.
            try? await Task.sleep(for: .milliseconds(Int(phase * 1000)))
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1700 + Int(phase * 900)))
                withAnimation(.easeInOut(duration: 0.09)) { closed = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeInOut(duration: 0.13)) { closed = false }
            }
        }
    }

    private var dot: some View {
        Circle()
            .fill(Color(hex: 0xF6FFDC))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .scaleEffect(y: closed ? 0.08 : 1, anchor: .center)
            .opacity(closed ? 0.25 : 1)
            .shadow(color: Self.glow.opacity(0.9), radius: 4)
            .shadow(color: Self.glow.opacity(0.55), radius: 10)
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

#Preview {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService())
        .environment(PetStateStore())
}
