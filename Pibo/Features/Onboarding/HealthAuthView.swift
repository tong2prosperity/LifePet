import SwiftUI
import os

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
    @State private var authRequested = false
    @State private var energyProgress: CGFloat = 0
    @State private var pluckOffset: CGFloat = 0
    @State private var piboTapCount = 0

    /// Called by `RootView` when the gate should close.
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            background
            currentScene
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.xl)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .preferredColorScheme(.light)
        .onAppear {
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
        case .call:
            callScene
        case .glitch:
            glitchScene
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
                LinearGradient(
                    colors: [Color(hex: 0x1A1016), Color(hex: 0x07070A)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
            if scene == .glitch {
                GlitchNoiseView()
                    .opacity(0.35)
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
            Button(AppLocalization.text("跳过")) { go(.falling) }
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
                        } else {
                            VStack(spacing: LP.Spacing.s) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 34, weight: .medium))
                                Text("点击屏幕任意位置模拟拍照")
                                    .lpText(LP.Typography.c1Regular)
                            }
                            .foregroundStyle(Color.white.opacity(0.64))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .frame(maxHeight: 520)
            .contentShape(Rectangle())
            .onTapGesture { captureLight() }

            onboardingButton(lightCaptured ? "继续" : "捕捉一点光", kind: .light) {
                lightCaptured ? go(.awaken) : captureLight()
            }
        }
    }

    private var awakenScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(headItem: .mystery, isDark: false, speech: speech ?? "…亮…#@!%")
                .overlay(alignment: .top) {
                    LightBeamView()
                        .offset(y: -46)
                        .allowsHitTesting(false)
                }
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
                Text("前两周它只会喊你「人」。第 15 天起，它会试着喊你的名字。")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.invertTertiary)
            }
            Spacer()
            onboardingButton("确认", kind: .light) {
                commitName()
                go(.call)
            }
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
            Spacer()
            onboardingButton("我叫了", kind: .light) {
                callPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    callPulse = false
                    go(.glitch)
                }
            }
        }
    }

    private var glitchScene: some View {
        VStack(spacing: LP.Spacing.xl) {
            Spacer()
            PiboOnboardingBlob(headItem: .mystery, isDark: true, speech: "…能…量…#@!%…不足…", isGlitching: true)
            VStack(spacing: LP.Spacing.m) {
                warningToast("Pibo 需要你的运动能量才能稳定存在")
                warningToast("你去运动，Pibo 的花才有活力")
            }
            Spacer()
            onboardingButton("签订能量契约", kind: .danger) { go(.auth) }
        }
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
                        onboardingButton("以后再说", kind: .ghost, action: continueWithDemoEnergy)
                    }
                }
            }
            .padding(.vertical, LP.Spacing.l)
        }
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
                PiboOnboardingBlob(headItem: .sprout, isDark: false, speech: nil)
                    .padding(.top, 38)
                PiboHeadItemView(item: .sprout, size: 70)
                    .offset(y: -pluckOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                pluckOffset = max(0, min(110, -value.translation.height))
                            }
                            .onEnded { _ in
                                if pluckOffset >= 76 {
                                    finishPluck()
                                } else {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                                        pluckOffset = 0
                                    }
                                }
                            }
                    )
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
            PiboOnboardingBlob(headItem: .sprout, isDark: false, speech: completeSpeech)
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

    private func startIntro() {
        Task { @MainActor in
            for index in Self.introLines.indices {
                guard scene == .intro else { return }
                withAnimation(.easeInOut(duration: 0.65)) { introIndex = index }
                try? await Task.sleep(for: .milliseconds(Self.introLines[index].pause))
            }
            if scene == .intro { go(.falling, haptics: false) }
        }
    }

    private func captureLight() {
        LPHaptics.tap()
        withAnimation(.easeOut(duration: 0.18)) { lightCaptured = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { go(.awaken, haptics: false) }
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
            go(.energy, haptics: false)
        }
    }

    private func continueWithDemoEnergy() {
        LPLog.onboarding.notice("User chose: onboarding demo/later")
        commitName()
        store.demoMode = true
        go(.energy)
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
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            pluckOffset = 112
        }
        store.growthStage = .sprouted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { go(.complete, haptics: false) }
    }

    private func finishOnboarding() {
        LPLog.onboarding.notice("Onboarding finished")
        commitName()
        onContinue()
    }

    private func commitName() {
        let trimmed = petNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.petName = trimmed.isEmpty ? "PIBO" : String(trimmed.prefix(16))
    }

    // MARK: Pieces

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
        ("一只精灵掉到了地球上", 900, false),
        ("它不会说人话", 650, false),
        ("不认识你", 600, false),
        ("也不认识这个世界", 900, false),
        ("但——", 900, true),
        ("你真的认识自己的身体吗？", 1100, false),
        ("你真的认识周围的世界吗？", 1100, false),
        ("帮它种一朵花", 700, false),
        ("也是帮你自己", 700, false),
        ("重新看一看", 1100, false),
    ]
}

private enum OnboardingScene {
    case intro
    case falling
    case darkness
    case camera
    case awaken
    case name
    case call
    case glitch
    case auth
    case energy
    case pluck
    case complete

    enum Palette { case dark, paper, glitch, home }

    var palette: Palette {
        switch self {
        case .intro, .falling, .darkness, .camera, .awaken, .name, .call:
            return .dark
        case .glitch:
            return .glitch
        case .auth, .energy, .pluck:
            return .paper
        case .complete:
            return .home
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
    var isGlitching: Bool = false

    var body: some View {
        VStack(spacing: LP.Spacing.m) {
            if let speech {
                Text(speech)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(isGlitching ? Color(hex: 0xFF7A7A) : (isDark ? LP.Content.invertSecondary : LP.Content.primary))
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, LP.Spacing.s)
                    .background(Capsule().fill((isDark ? Color.white : Color.black).opacity(0.10)))
                    .overlay(Capsule().strokeBorder((isGlitching ? Color(hex: 0xFF7A7A) : Color.white).opacity(0.25)))
            }

            ZStack(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(isDark ? Color(hex: 0x222222) : .white)
                    .frame(width: 116, height: 132)
                    .overlay(Capsule(style: .continuous).strokeBorder(isDark ? Color.white.opacity(0.12) : Color(hex: 0xDADADA), lineWidth: 2))
                    .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 16, y: 8)
                    .overlay {
                        HStack(spacing: 24) {
                            Ellipse().fill(isDark ? Color.white.opacity(0.22) : Color(hex: 0x1F1F1F)).frame(width: 8, height: 10)
                            Ellipse().fill(isDark ? Color.white.opacity(0.22) : Color(hex: 0x1F1F1F)).frame(width: 8, height: 10)
                        }
                        .offset(y: 10)
                    }
                PiboHeadItemView(item: headItem, size: 42)
                    .offset(y: -26)
            }
            .rotationEffect(.degrees(isGlitching ? -2 : 0))
            .offset(x: isGlitching ? -3 : 0)
        }
        .frame(maxWidth: .infinity)
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
