import SwiftUI

/// Daily-persona first run (decision 049): the production forest with Pibo's
/// everyday expression behind three system pages — welcome, one scrollable
/// product overview, and the health choice. Platform setup only: it never
/// writes story consent, demo data or `bo`, and every health outcome (granted,
/// denied, unavailable, still in flight) may enter the forest.
///
/// `previewMode` renders the same pages over an ephemeral onboarding store for
/// the DEBUG 「Onboarding · 首启预览」 entry: no permission is requested and no
/// completion is recorded.
struct DailyOnboardingView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    @Environment(WeatherDataService.self) private var weather
    @Environment(\.scenePhase) private var scenePhase

    let onboarding: OnboardingStateStore
    var previewMode = false
    var onClosePreview: () -> Void = {}
    /// Performs the platform health request. Only called outside preview mode.
    var onConnectHealth: () async -> HealthDataService.OnboardingReadiness? = { nil }
    var onComplete: () -> Void = {}

    @State private var requesting = false
    @State private var finished = false
    @State private var visible = false
    @State private var animationPresentation = HomeAnimationPresentationController()
    @State private var stageCommands = PiboStageCommandController()
    /// The pixel welcome's own clock: the stone blinks, puffs, and Pibo peeks out.
    @State private var introAgeMs: Double = 0
    @State private var introTask: Task<Void, Never>?

    private var step: DailySetupStep { onboarding.dailySetupStep }

    var body: some View {
        GeometryReader { proxy in
            if PiboReleaseScope.pixelOnboarding {
                pixelBody(in: proxy.size)
            } else {
                legacyBody(in: proxy.size)
            }
        }
        .background(Color(hex: 0x24372E).ignoresSafeArea())
        .onAppear {
            visible = true
            if !previewMode, onboarding.snapshot.firstRunStatus == .notStarted {
                onboarding.begin(at: .encounter)
            }
            refreshStage()
            startIntro()
        }
        .onDisappear {
            visible = false
            introTask?.cancel()
            introTask = nil
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func legacyBody(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            forest
            VStack(spacing: 0) {
                if previewMode { previewBar }
                ScrollView {
                    content
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: cardMaxHeight(in: size))
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.94))
                )
                Spacer(minLength: LP.Spacing.l)
                actions
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: Pixel first run (decision 059)

    /// ArkTS `pixelSetup`: the dusk forest behind a paper card. The forest is drawn at nine
    /// device pixels per logical pixel, the same unit the ArkUI canvas uses.
    private func pixelBody(in size: CGSize) -> some View {
        // The canvas covers the whole screen, so its logical size comes from the screen
        // rather than the safe-area-inset size the layout was handed. It is a background,
        // not a sibling: a full-bleed picture must not decide where the buttons sit.
        let screen = UIScreen.main.bounds.size
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if previewMode { pixelPreviewBar }
                ScrollView {
                    pixelContent
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: pixelCardMaxHeight(in: size))
                .fixedSize(horizontal: false, vertical: true)
                .background(PixelUIColor.paper)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 3))
                .background(alignment: .bottomTrailing) {
                    Rectangle().fill(PixelUIColor.shadow).offset(x: 4, y: 4)
                }
                Spacer(minLength: 12)
                pixelActions
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .background {
            PixelOnboardingForestView(ageMs: introAgeMs,
                                     logicalWidth: max(60, Int(screen.width * UIScreen.main.scale / 9)),
                                     logicalHeight: max(120, Int(screen.height * UIScreen.main.scale / 9)))
                .frame(width: screen.width, height: screen.height)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var pixelContent: some View {
        switch step {
        case .welcome: pixelIntroduction
        case .overview: pixelOverview
        case .health: pixelHealthExplanation
        }
    }

    private var pixelIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelText(text: "Pibo", textSize: 12, color: PixelUIColor.inkSoft)
            PixelText(text: DailyOnboardingCopy.hello, textSize: 17)
                .fixedSize(horizontal: false, vertical: true)
            PixelText(text: DailyOnboardingCopy.valueTitle, textSize: 14)
                .fixedSize(horizontal: false, vertical: true)
            PixelText(text: DailyOnboardingCopy.value, textSize: 13, color: PixelUIColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .accessibilityElement(children: .combine)
    }

    private var pixelOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            PixelText(text: DailyOnboardingCopy.overviewTitle, textSize: 18)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(DailyOnboardingCopy.overviewSections.enumerated()), id: \.element.label) { index, section in
                pixelOverviewRow(PixelOnboardingIcon(rawValue: index) ?? .together, section)
            }
        }
    }

    private func pixelOverviewRow(_ icon: PixelOnboardingIcon,
                                  _ section: DailyOnboardingCopy.OverviewSection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PixelOnboardingIconView(icon: icon)
                .frame(width: 50, height: 60)
                .background(PixelUIColor.paperDim)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                PixelText(text: section.label, textSize: 15, color: PixelUIColor.leaf)
                PixelText(text: section.body, textSize: 13)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var pixelHealthExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelText(text: DailyOnboardingCopy.healthTitle, textSize: 18)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            PixelText(text: DailyOnboardingCopy.healthBody, textSize: 14)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            PixelText(text: DailyOnboardingCopy.healthDetails, textSize: 13, color: PixelUIColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            PixelText(text: DailyOnboardingCopy.healthBoundary, textSize: 12, color: PixelUIColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var pixelPreviewBar: some View {
        HStack(spacing: 8) {
            PixelText(text: DailyOnboardingCopy.previewNotice, textSize: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            PixelButton(label: DailyOnboardingCopy.previewClose, primary: false,
                        buttonID: "pibo.onboarding.preview.close") { onClosePreview() }
        }
        .padding(8)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .padding(.bottom, 8)
    }

    private var pixelActions: some View {
        VStack(spacing: 10) {
            PixelButton(label: primaryLabel, active: !requesting) { advance() }
            if step == .health {
                PixelButton(label: DailyOnboardingCopy.later, primary: false) { finish() }
            }
            if step != .welcome, !requesting {
                PixelButton(label: DailyOnboardingCopy.back, primary: false) {
                    onboarding.moveDailySetup(to: step == .overview ? .welcome : .overview)
                }
            }
        }
    }

    /// The welcome's own timeline: the stone blinks, puffs, and Pibo is peeking behind the
    /// pod. ArkTS caps it at `ONBOARDING_INTRO_MS`; after that the forest is still.
    private func startIntro() {
        guard PiboReleaseScope.pixelOnboarding, introTask == nil else { return }
        let start = Date()
        introTask = Task { @MainActor in
            while !Task.isCancelled {
                let age = Date().timeIntervalSince(start) * 1000
                introAgeMs = min(ONBOARDING_INTRO_MS, age)
                if introAgeMs >= ONBOARDING_INTRO_MS { break }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func pixelCardMaxHeight(in size: CGSize) -> CGFloat {
        let fraction: CGFloat = step == .overview ? 0.5 : 0.36
        return max(160, size.height * fraction - (previewMode ? 52 : 0))
    }

    // MARK: Forest

    private var forest: some View {
        PiboStageView(
            theme: store.currentTheme,
            state: animationPresentation.state,
            animationStateID: animationPresentation.stateID,
            commandController: stageCommands,
            environment: PiboStageEnvironmentResolver.resolve(
                date: .now,
                weather: weather.condition
            ),
            isPaused: scenePhase != .active
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func refreshStage() {
        animationPresentation.refresh(store: store, history: history)
    }

    private func cardMaxHeight(in size: CGSize) -> CGFloat {
        let fraction: CGFloat = step == .overview ? 0.58 : 0.46
        return max(180, size.height * fraction - (previewMode ? 52 : 0))
    }

    // MARK: Pages

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: introduction
        case .overview: productOverview
        case .health: healthExplanation
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            Text("Pibo")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
            Text(DailyOnboardingCopy.hello)
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DailyOnboardingCopy.valueTitle)
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DailyOnboardingCopy.value)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var productOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DailyOnboardingCopy.overviewTitle)
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(DailyOnboardingCopy.overviewSections, id: \.label) { section in
                overviewSection(section)
            }
            HStack(spacing: 16) {
                if PiboReleaseScope.camera {
                    featureIcon(systemImage: "camera.fill", label: DailyOnboardingCopy.cameraLabel)
                }
                featureIcon(systemImage: "list.bullet", label: DailyOnboardingCopy.historyLabel)
            }
        }
    }

    private func overviewSection(_ section: DailyOnboardingCopy.OverviewSection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(section.label)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(Color(hex: 0x237653))
                .frame(width: 40)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xE2EBDD))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(section.body)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func featureIcon(systemImage: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PiboMoss.Color.foundationTeal)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(label)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    private var healthExplanation: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            Text(DailyOnboardingCopy.healthTitle)
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(DailyOnboardingCopy.healthBody)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DailyOnboardingCopy.healthDetails)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DailyOnboardingCopy.healthBoundary)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var previewBar: some View {
        HStack(spacing: 8) {
            Text(DailyOnboardingCopy.previewNotice)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(DailyOnboardingCopy.previewClose) { onClosePreview() }
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.primary)
                .frame(minWidth: 60, minHeight: 44)
                .accessibilityIdentifier("pibo.onboarding.preview.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LP.Fill.bgContainer.opacity(0.94))
        )
        .padding(.bottom, 8)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: advance) {
                Text(primaryLabel)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x237653), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(requesting)
            .opacity(requesting ? 0.7 : 1)

            if step == .health {
                secondaryButton(DailyOnboardingCopy.later) { finish() }
            }
            if step != .welcome, !requesting {
                secondaryButton(DailyOnboardingCopy.back) {
                    onboarding.moveDailySetup(to: step == .overview ? .welcome : .overview)
                }
            }
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(LP.Fill.bgContainer.opacity(0.94), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: DailyOnboardingCopy.meet
        case .overview: DailyOnboardingCopy.overviewContinue
        case .health:
            if previewMode { DailyOnboardingCopy.previewContinue }
            else if requesting { DailyOnboardingCopy.connecting }
            else { DailyOnboardingCopy.connect }
        }
    }

    private func advance() {
        LPHaptics.tap()
        switch step {
        case .welcome: onboarding.moveDailySetup(to: .overview)
        case .overview: onboarding.moveDailySetup(to: .health)
        case .health:
            if previewMode { finish() } else { connect() }
        }
    }

    private func connect() {
        guard !requesting, !finished else { return }
        requesting = true
        Task {
            let readiness = await onConnectHealth()
            // A request that outlives the page (the user already entered the
            // forest) is not recorded as a completed onboarding request.
            guard visible, !finished else { return }
            if let readiness {
                onboarding.markHealthRequestCompleted(readiness: readiness)
            }
            requesting = false
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if previewMode {
            onClosePreview()
        } else {
            PiboSoundEffectService.shared.play(.onboardingComplete)
            onComplete()
        }
    }
}

#if DEBUG
/// DEBUG 「Onboarding · 首启预览」: the real first-run pages over a fresh,
/// never-persisted onboarding store. No permission request, no completion,
/// no eligibility boundary; closing simply dismisses.
struct DailyOnboardingPreviewHost: View {
    @Environment(\.dismiss) private var dismiss
    @State private var previewStore: OnboardingStateStore

    init(startingAt step: DailySetupStep = .welcome) {
        let store = OnboardingStateStore.ephemeralPreview()
        if step != .welcome { store.moveDailySetup(to: step) }
        _previewStore = State(initialValue: store)
    }

    var body: some View {
        DailyOnboardingView(
            onboarding: previewStore,
            previewMode: true,
            onClosePreview: { dismiss() }
        )
    }

    /// `-PiboOnboardingPreview` or `-PiboOnboardingPreview=overview` opens the
    /// preview at launch (simulator screenshots cannot synthesize taps).
    static func launchStep(arguments: [String] = ProcessInfo.processInfo.arguments) -> DailySetupStep? {
        let flag = "-PiboOnboardingPreview"
        if arguments.contains(flag) { return .welcome }
        guard let raw = arguments.first(where: { $0.hasPrefix(flag + "=") })?
            .dropFirst(flag.count + 1) else { return nil }
        return DailySetupStep(rawValue: String(raw)) ?? .welcome
    }
}
#endif

/// Chinese first-release copy, shared with HarmonyOS `dailyOnboarding.*`.
/// Platform nouns (Apple 健康, Home corner placement) are the only deviations.
enum DailyOnboardingCopy {
    struct OverviewSection {
        let label: String
        let title: String
        let body: String
    }

    static let hello = "你好，我是 Pibo。"
    static let valueTitle = "用真实生活，养一只 Pibo。"
    static let value = "你的睡眠和活动，会影响它的状态和成长。来到森林，可以看看它、和它打个招呼。"
    static let meet = "看看这里能做什么"

    static let overviewTitle = "在这里，可以一起……"
    static let overviewSections = [
        OverviewSection(
            label: "相处",
            title: "看看它今天怎么样",
            body: "睡眠和活动影响 Pibo 的状态。双击它的身体，它会回应。"
        ),
        OverviewSection(
            label: "成长",
            title: "让森林慢慢丰富起来",
            body: "头顶能量来自真实生活。成熟后收取，用来唤醒吊床等共同物件，让 Pibo 获得新的能力。"
        ),
        OverviewSection(
            label: "记录",
            title: "留下生活里的小事",
            body: "拍下餐食，得到食物贴纸与营养估算；每天的健康记录，也会留在这里。"
        ),
    ]
    static let cameraLabel = "餐食相机"
    static let historyLabel = "足迹"
    static let overviewContinue = "了解了，继续"
    static let back = "返回上一步"

    static let healthTitle = "让 Pibo 感受到你的日常"
    static let healthBody = "连接 Apple 健康后，Pibo 会根据真实的睡眠和活动呈现不同状态。生活的积累也会慢慢形成 bo。"
    static let healthDetails = "睡眠、步数与运动用于状态和成长。心率、静息心率、HRV 等用于健康趋势及已启用的健康功能。"
    static let healthBoundary = "只读取你在系统中允许的数据，权限可随时调整。这些信息不用于医疗诊断。暂不连接，也可以进入森林。"
    static let connect = "连接健康记录"
    static let connecting = "正在连接…"
    static let later = "暂不连接，先去森林"

    static let patTitle = "双击 Pibo 的身体，和它打个招呼"
    static let patSkip = "稍后，我先看看"
    static let dataReady = "Pibo 正在根据可用的真实记录呈现状态。"
    static let dataUnavailable = "当前健康服务不可用。你仍可以和 Pibo 互动，之后在设置中连接。"
    static let dataRequesting = "健康连接仍在处理中。你可以先和 Pibo 互动。"
    static let dataWaiting = "已获得健康权限，暂时还没有可用记录。Pibo 会等真实数据到来。"
    static let dataNotConnected = "尚未连接健康记录。你仍可以和 Pibo 互动，之后在设置中连接。"

    static let homeTitle = "想试的时候，再打开"
    /// Same words as HarmonyOS `dailyOnboarding.tools`: 足迹 sits bottom-right.
    static var tools: String {
        PiboReleaseScope.camera
            ? "餐食相机在右上角，足迹在右下角。"
            : "足迹在右下角。"
    }
    static let notificationsBody = "通知可选，用于你主动开启的睡眠与健康提醒。"
    static let notificationsEnable = "允许通知"
    static let done = "先这样，慢慢来"

    static let previewEntry = "Onboarding · 首启预览"
    static let previewNotice = "DEBUG · 不申请权限，不写入数据"
    static let previewClose = "关闭"
    static let previewContinue = "结束预览，返回森林"
}
