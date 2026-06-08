import SwiftUI

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
    @State private var showDashboard = false
    @State private var showCamera = false
    @State private var energyToken: UUID? = nil
    @State private var pluckToken: PluckToken? = nil
    @State private var showResetConfirm = false

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PiboStageView(
                    theme: store.currentTheme,
                    state: store.activityState,
                    onPat: handlePat,
                    energyGainToken: energyToken,
                    pluckToken: pluckToken
                )
                .ignoresSafeArea()

                // Speech bubble floats just above Pibo's head (~32% down).
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
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.pendingWorkout)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: speech)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in if v.translation.height < -40 { openDashboard() } }
        )
        .task { await idleMutterLoop() }
        .onChange(of: store.pendingWorkout?.id) { _, id in
            if id != nil { energyToken = UUID() }
        }
        .sheet(isPresented: $showDashboard) {
            PiboDashboardView().environment(store)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.mowanGreeting)
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(LP.Content.secondary)
                if !store.currentTheme.displayName.isEmpty {
                    Text(store.currentTheme.displayName)
                        .lpText(LP.Typography.uiH3)
                        .foregroundStyle(LP.Content.primary)
                }
                Text(store.relationshipDayLabel)
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
        showDashboard = true
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
    HomeView()
        .environment(PetStateStore(demoMode: true))
}
