import SwiftUI

/// Pibo home — translates `原型-01-主页.html` into SwiftUI on top of the
/// `LP` design system. State lives in `PetStateStore`, fed by HealthKit
/// events; this view is mostly presentation + the "incoming sample"
/// animation glue.
///
/// Sections, top to bottom:
/// 1. Top meta (greeting + date)
/// 2. Pet identity (large hand-style name + 已陪伴第 N 天 + state pill)
/// 3. LCD stage with pixel pet
/// 4. Three stat cards (体力 / 精力 / 心情)
/// 5. 今日步骤 — done + suggest cards
struct HomeView: View {
    @Environment(PetStateStore.self) private var store

    /// Time-bounded sparkle burst on the pet stage, fired when a HealthKit
    /// event nudges any stat. Held for 1.6s, then cleared.
    @State private var burstUntil: Date? = nil
    /// Toggles a one-shot 0.45s shake on the pet sprite. Driven by
    /// `store.feedToken` changes (i.e. the user just tapped 「喂养」). Held
    /// only long enough for the animation to finish.
    @State private var vibrateToken: UUID? = nil
    /// `false` until the user watches the egg hatch once. Persists across
    /// launches via `UserDefaults`. Demo mode also goes through the hatch —
    /// the gate is purely "have they seen it once," not "is this real data."
    /// `PetStageView` itself splits hatch into two stages (waiting-for-tap →
    /// playing) so the 1.25s animation isn't missed during the auth-dialog
    /// dismissal.
    @AppStorage(PiboPersistenceKeys.Defaults.hatched) private var hatched: Bool = false
    /// Mirrored from `RootView` so the reset button can flip it back to
    /// `false` and bounce the app to `HealthAuthView`. SwiftUI's @AppStorage
    /// shares UserDefaults, so this stays in sync with the source of truth.
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false
    @State private var showResetConfirm = false

    /// Index into `Self.demoCycleStates`. Only used when `store.demoMode` is
    /// true — taps on the "换一换" pill advance it modulo the cycle length.
    @State private var demoStateIndex: Int = 0
    /// Demo cycle covers all 6 PRD states. Two pairs share sprites
    /// (`.sick`/`.normal` → blobLying; `.blissful`/`.excited` → blobRun) but
    /// their corner tags + sparkle flags differ, so cycling through all six
    /// still feels visually distinct.
    private static let demoCycleStates: [PetState] = [
        .normal, .excited, .tired, .sleeping, .sick, .blissful,
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topMeta
                        .padding(.bottom, 8)
                        .overlay(LPDashedRule(dash: [4, 3]), alignment: .bottom)
                    petIdentity
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .overlay(LPDashedRule(dash: [4, 3]), alignment: .bottom)
                    PetStageView(
                        petName: store.petName,
                        dayCount: store.dayCount,
                        state: store.state,
                        lastWorkoutAt: store.lastWorkoutEndedAt,
                        bursting: isBursting,
                        vibrateToken: vibrateToken,
                        isHatching: !hatched,
                        onHatchCompleted: { hatched = true },
                        onPetTapped: {
                            LPHaptics.tap()
                            store.nudgePibo()
                        }
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    LPSpeechBubble(store.piboSpeech.text, tone: store.piboSpeech.tone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, store.demoMode ? 8 : 14)

                    if store.demoMode {
                        demoCycleButton
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 14)
                    }

                    StarlightStatusView(summaries: store.starlightSummaries)
                        .padding(.bottom, 14)

                    JourneyFragmentsView(
                        ritual: store.journeyRitual,
                        fragments: store.memoryFragments,
                        accessories: store.journeyAccessories,
                        nudge: store.journeyNudge
                    )
                    .padding(.bottom, 14)

                    StepsSectionView(store: store)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .lpPaper(.app)

            // Workout sheet 三层（backdrop / sheet / toast）—— 故意拆成
            // 三个**顶层**条件而不是嵌套 ZStack 子元素，是因为 `.transition`
            // 在 if-let 内嵌 ZStack 的子元素上 SwiftUI 不一定播完整退出动画；
            // 顶层 if 才是稳定写法。
            //
            // 层序（背 → 前）= ScrollView → backdrop → sheet → toast。
            // 把 toast 放最前是为了让喂养完成的 toast 不被退出中的 backdrop
            // 压暗（B1 修复）。`hatched` 守卫防止蛋未孵化时 sheet 盖在蛋上面
            // —— pendingWorkout 留着，孵化完 SwiftUI 重评 if 后再弹（W2）。
            if hatched, store.pendingWorkout != nil {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { store.dismissPendingWorkout() }
                    .transition(.opacity)
            }
            if hatched, let pw = store.pendingWorkout {
                WorkoutAlertSheet(
                    workout: pw,
                    petName: store.petName,
                    onFeed: { store.consumePendingWorkout() },
                    onDismiss: { store.dismissPendingWorkout() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 能量粒子层 — 用 overlayPreferenceValue 拿宠物中心 + GeometryReader
        // 拿容器尺寸，再交给 EnergyParticleField 自己监听 feedToken 触发。
        // 放在 ZStack 之后是为了让粒子盖在 sheet 上面（喂养瞬间 sheet 还在
        // 滑下，粒子从按钮位置往上飞穿过去更顺）。
        .overlayPreferenceValue(PetCenterAnchorKey.self) { anchor in
            GeometryReader { geo in
                let center = anchor.map { geo[$0] }
                EnergyParticleField(
                    token: store.feedToken,
                    petCenter: center,
                    size: geo.size
                )
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: store.toast)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.pendingWorkout)
        .onChange(of: store.lastDelta) { _, new in
            // Any new delta = run the sparkle burst for ~1.6s.
            guard new != nil else { return }
            burstUntil = Date().addingTimeInterval(1.6)
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if let until = burstUntil, until <= Date() {
                    burstUntil = nil
                }
            }
        }
        .onChange(of: store.feedToken) { _, new in
            // 用户点了「喂养」 — 触发宠物震动 + 强制开 burst（即使 lastDelta
            // 因为 clamp/同值未触发也至少要有动画反馈）。
            guard let new else { return }
            vibrateToken = new
            burstUntil = Date().addingTimeInterval(1.6)
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                if vibrateToken == new { vibrateToken = nil }
            }
        }
    }

    private var isBursting: Bool {
        guard let until = burstUntil else { return false }
        return Date() < until
    }

    // MARK: - Subviews

    private var topMeta: some View {
        HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s2) {
            HStack(spacing: 0) {
                Text(AppLocalization.text(store.greeting) + ", ")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(store.ownerName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.coral)
            }
            Spacer(minLength: LP.Spacing.s2)
            Text(store.dateLabel)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(LP.Colors.muted)
            resetButton
        }
        .confirmationDialog(
            AppLocalization.text("重置后会回到首启流程"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("重新开始"), role: .destructive, action: performReset)
            Button(AppLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(lp: "当前所有 stats、卡片和孵化记录都会清掉。")
        }
    }

    /// Subtle "↻" pill in topMeta. Low visual weight on purpose — it's a
    /// dev/recovery affordance, not a primary action.
    private var resetButton: some View {
        Button {
            LPHaptics.tap()
            showResetConfirm = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LP.Colors.muted)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(LP.Colors.muted.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("重置 Pibo 流程"))
    }

    private func performReset() {
        store.reset()
        hatched = false
        onboardingDone = false
    }

    /// Demo-only "换一换" pill below the LCD. Cycling mutates `store.state`
    /// directly — that single field flows into the sprite (via
    /// `SpriteCatalog.idle(for:)`), the LCD corner tag, and the sparkle flag,
    /// so one tap updates all three at once.
    ///
    /// Skipped while the egg is still waiting (`!hatched`) — letting the
    /// user shuffle states before hatch finishes is a layering bug, not a
    /// feature.
    private var demoCycleButton: some View {
        Button(action: { LPHaptics.tap(); cycleDemoState() }) {
            HStack(spacing: 6) {
                Image(systemName: "shuffle")
                    .font(.system(size: 11, weight: .semibold))
                Text(lp: "换一换")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(LP.Colors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(LP.Colors.paperCard))
            .overlay(Capsule(style: .continuous).strokeBorder(LP.Colors.ink, lineWidth: 1))
            .lpShadow(LP.Shadow.sm)
        }
        .buttonStyle(.plain)
        .opacity(hatched ? 1 : 0.3)
        .disabled(!hatched)
        .accessibilityLabel(AppLocalization.text("换一种宠物状态"))
    }

    private func cycleDemoState() {
        let next = (demoStateIndex + 1) % Self.demoCycleStates.count
        demoStateIndex = next
        withAnimation(.easeInOut(duration: 0.2)) {
            store.state = Self.demoCycleStates[next]
        }
    }

    private var petIdentity: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                Text(store.petName)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(LP.Colors.ink)
                Text(".")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.coral)
            }
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text(lp: "已陪伴 ")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(LP.Colors.muted)
                        .tracking(1)
                        .textCase(.uppercase)
                    Text(AppLocalization.format("第 %d 天", store.dayCount))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(LP.Colors.coral)
                        .tracking(1)
                        .textCase(.uppercase)
                }
                statePill
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statePill: some View {
        Text(AppLocalization.text(store.state.journeyLabel))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white)
            .tracking(0.5)
            .padding(.horizontal, LP.Spacing.s2)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LP.Colors.coral)
            )
    }
}

// MARK: - Toast

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(AppLocalization.text(text))
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(LP.Colors.paperCard)
            .padding(.horizontal, LP.Spacing.s4)
            .padding(.vertical, LP.Spacing.s2)
            .background(
                Capsule(style: .continuous)
                    .fill(LP.Colors.ink)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LP.Colors.ink, lineWidth: 1.5)
            )
            .lpShadow(LP.Shadow.sm)
    }
}

#Preview {
    HomeView()
        .environment(PetStateStore())
}
