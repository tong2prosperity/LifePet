import SwiftUI
import SwiftData
import Observation

/// Drives the 上滑二楼 pull. Owned by `HomeView` for its lifetime but read **only**
/// by `FloorContainer`, so mutating `progress` during a drag re-renders just the
/// thin transform shell — never the stage / chrome / 二楼 subtrees.
@Observable final class FloorModel {
    var progress: CGFloat = 0
}

/// Pibo home (魔丸态) — the SpriteKit stage fills the screen; SwiftUI overlays
/// the chrome: greeting + 与Pibo相识第 N 天, the 露珠相机 button, the 上滑
/// Dashboard handle, 拍一拍 speech, 拔毛, and the 能量收集 card.
///
/// Per the home spec, there are no stat bars / step cards / star-light — Pibo's
/// state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store

    @State private var speech: String? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    /// 上滑二楼 state — 0 = home floor, 1 = data 二楼. Lives in a model HomeView
    /// owns but does not read, so the drag only re-renders `FloorContainer`.
    @State private var floor = FloorModel()
    /// Pause the stage's 60fps loop while parked on the 二楼. Toggled on settle
    /// (not per frame), so the stage is never re-rendered mid-drag.
    @State private var stagePaused = false
    @State private var showCamera = false
    @State private var energyToken: UUID? = nil
    @State private var pluckToken: PluckToken? = nil
    @State private var showResetConfirm = false
    /// Greeting / day-label cached once (they're "drawn once per day"): keeps the
    /// header off the per-frame Calendar path while the 二楼 pull-up drags.
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    var body: some View {
        FloorContainer(
            floor: floor,
            onSettle: { target in stagePaused = target > 0.5 },
            stage: {
                PiboStageView(
                    theme: store.currentTheme,
                    state: store.activityState,
                    onPat: handlePat,
                    energyGainToken: energyToken,
                    pluckToken: pluckToken,
                    isPaused: stagePaused
                )
                .ignoresSafeArea()
            },
            chrome: { chromeContent },
            secondFloor: {
                PiboDashboardView(onClose: closeFloor).environment(store)
            }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.pendingWorkout)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: speech)
        .task { await idleMutterLoop() }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
        }
        .onChange(of: store.pendingWorkout?.id) { _, id in
            if id != nil { energyToken = UUID() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            PiboCameraView(onPhotoSaved: handlePhotoSaved).environment(store)
        }
        .confirmationDialog(
            AppLocalization.text("重置后会回到首启流程"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("重新开始"), role: .destructive, action: performReset)
            Button(AppLocalization.text("取消"), role: .cancel) {}
        }
    }

    // MARK: Chrome (home greeting / speech / controls / energy card)

    /// All the home-floor overlay built as one subtree. `FloorContainer` fades it
    /// out as the 二楼 rises, so it has no per-progress logic of its own.
    private var chromeContent: some View {
        GeometryReader { geo in
            ZStack {
                // Speech bubble floats just above Pibo's head (~30% down).
                if let speech {
                    PiboSpeechCloud(text: speech)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    bottomControls
                }
                .padding(.horizontal, LP.Spacing.l)

                if store.pendingWorkout != nil {
                    EnergyCollectCard(
                        petName: store.petName,
                        gain: store.pendingWorkout?.gainVitality ?? 0,
                        onCollect: { store.consumePendingWorkout() },
                        onDismiss: { store.dismissPendingWorkout() }
                    )
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greetingText.isEmpty ? store.mowanGreeting : greetingText)
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(LP.Content.secondary)
                if !store.currentTheme.displayName.isEmpty {
                    Text(store.currentTheme.displayName)
                        .lpText(LP.Typography.uiH3)
                        .foregroundStyle(LP.Content.primary)
                }
                Text(dayLabelText.isEmpty ? store.relationshipDayLabel : dayLabelText)
                    .lpText(store.currentTheme.displayName.isEmpty ? LP.Typography.uiH4 : LP.Typography.b1Medium)
                    .foregroundStyle(store.currentTheme.displayName.isEmpty ? LP.Content.primary : LP.Content.secondary)
            }
            Spacer()
            Button {
                LPHaptics.tap()
                showResetConfirm = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(LP.Content.tertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("设置"))
        }
        .padding(.top, LP.Spacing.s)
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: LP.Spacing.m) {
            if store.pluckAvailable {
                pluckButton
            }
            cameraButton
            upArrowHandle
        }
        .padding(.bottom, LP.Spacing.s)
    }

    private var cameraButton: some View {
        Button {
            LPHaptics.tap()
            showCamera = true
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 60, height: 60)
                .background(Circle().fill(LP.Fill.bgContainer.opacity(0.92)))
                .overlay(Circle().strokeBorder(LP.Separator.primary, lineWidth: 1))
                .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("拍照"))
    }

    private var pluckButton: some View {
        Button {
            LPHaptics.tap()
            doPluck()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 12))
                Text(AppLocalization.text("收下今天的毛"))
                    .lpText(LP.Typography.b3Medium)
            }
            .foregroundStyle(LP.Fill.foundationOnAccent)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.s)
            .background(Capsule().fill(LP.Fill.foundationAccent))
            .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
    }

    private var upArrowHandle: some View {
        Button(action: openDashboard) {
            VStack(spacing: 3) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                Capsule().fill(LP.Content.quarternary)
                    .frame(width: 36, height: 4)
            }
            .foregroundStyle(LP.Content.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("上滑查看数据"))
    }

    // MARK: Actions

    private func handlePat() {
        LPHaptics.tap()
        if let line = store.pat() { show(line) }
    }

    private func doPluck() {
        let grade = store.pluck()
        pluckToken = PluckToken(id: UUID(), color: grade.seedColor)
        show(grade.piboLines.randomElement() ?? "...给...你...")
    }

    private func handlePhotoSaved() {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        energyToken = UUID()
        if Bool.random() {
            show(PiboCameraView.genericComments.randomElement() ?? "...颜色...记...")
        }
    }

    private func openDashboard() {
        LPHaptics.tap()
        stagePaused = true
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { floor.progress = 1 }
    }

    private func closeFloor() {
        LPHaptics.tap()
        stagePaused = false
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { floor.progress = 0 }
    }

    private func show(_ line: String) {
        speechClear?.cancel()
        withAnimation { speech = line }
        speechClear = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { withAnimation { speech = nil } }
        }
    }

    /// Idle self-mutter loop (spec §3.3) — every 15–30s, ~20% chance Pibo
    /// drifts a line on its own. Cancelled automatically when the view leaves.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil, let line = store.idleMutter() { show(line) }
        }
    }

    private func performReset() {
        store.reset()
        onboardingDone = false
    }
}

// MARK: - Floor container (pull-up coordinator)

/// Owns the 上滑 `progress` + the drag, applying offset/opacity to three subtrees
/// that `HomeView` builds once. Only this view reads `floor.progress`, so a drag
/// re-renders just this thin shell — the stage / chrome / 二楼 bodies are not
/// re-evaluated per frame (they update only when their own inputs change).
private struct FloorContainer<Stage: View, Chrome: View, SecondFloor: View>: View {
    let floor: FloorModel
    /// Called once when a drag settles, with the target floor (0 or 1).
    var onSettle: (CGFloat) -> Void = { _ in }
    @ViewBuilder let stage: Stage
    @ViewBuilder let chrome: Chrome
    @ViewBuilder let secondFloor: SecondFloor

    /// `progress` captured at the start of a drag, so partial drags compose.
    @State private var dragBase: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let p = floor.progress
            ZStack {
                stage
                    .offset(y: -p * h * 0.5)
                    .opacity(1 - Double(p) * 0.85)

                chrome
                    .opacity(1 - Double(min(1, p * 1.6)))
                    .allowsHitTesting(p < 0.08)

                secondFloor
                    .offset(y: (1 - p) * h)
                    .opacity(p > 0.001 ? 1 : 0)
                    .allowsHitTesting(p > 0.9)
            }
            .contentShape(Rectangle())
            .gesture(drag(height: h))
        }
    }

    /// Finger-tracking pull; snaps to the nearer floor (or follows a flick) on
    /// release. `minimumDistance` lets taps reach Pibo (拍一拍) and 二楼 controls.
    private func drag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let base = dragBase ?? floor.progress
                if dragBase == nil { dragBase = floor.progress }
                floor.progress = min(1, max(0, base + (-v.translation.height) / h))
            }
            .onEnded { v in
                let base = dragBase ?? floor.progress
                let p = min(1, max(0, base + (-v.translation.height) / h))
                let flickUp = -v.predictedEndTranslation.height > 150
                let flickDown = v.predictedEndTranslation.height > 150
                let target: CGFloat = flickUp ? 1 : (flickDown ? 0 : (p > 0.5 ? 1 : 0))
                dragBase = nil
                onSettle(target)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { floor.progress = target }
            }
    }
}

// MARK: - Speech cloud

/// Pibo's garbled one-liner, as a soft rounded bubble.
private struct PiboSpeechCloud: View {
    let text: String

    var body: some View {
        Text(text)
            .lpText(LP.Typography.b2Medium)
            .foregroundStyle(LP.Content.primary)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Separator.primary, lineWidth: 1)
            )
            .lpShadow(LP.Shadow.elevation2)
    }
}

// MARK: - 能量收集 card

private struct EnergyCollectCard: View {
    let petName: String
    let gain: Int
    let onCollect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: "figure.run")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Fill.foundationOnAccent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(LP.Fill.foundationAccent))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("收集到你的运动能量！"))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.format("%@ 感觉到了…+%d", petName, gain))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: LP.Spacing.s)
            Button(action: onCollect) {
                Text(AppLocalization.text("收下"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.vertical, LP.Spacing.s)
                    .background(Capsule().fill(LP.Fill.foundationAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgPop)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Separator.primary, lineWidth: 1)
        )
        .lpShadow(LP.Shadow.elevation3)
        .onTapGesture(perform: onDismiss)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: HealthDayRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HealthHistoryStore(context: container.mainContext))
}
