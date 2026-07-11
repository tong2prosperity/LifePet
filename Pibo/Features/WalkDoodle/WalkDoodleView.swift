import SwiftUI
import MapKit
import CoreLocation

/// 地图涂鸦 (walk doodle) — Pibo's "用脚画一幅画 / 圈一块花田" task. Presented
/// full-screen from the home (like the 露珠相机). The user walks; their GPS trail
/// draws a thick Pibo-green stroke over the map in real time. On 完成 the camera
/// fits the doodle, Pibo says a line, and 保存 persists it as a `WalkDoodleRecord`
/// (运动能量) that lands on the 历史数据页's 足迹涂鸦 card.
///
/// MVP is freeform. The `WalkDoodleChallenge` scaffold + the stored 面积/完成度
/// fields are where 布置涂鸦 / 比拼面积 plug in later.
struct WalkDoodleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Hands the finished doodle to `HomeView` (persist + Pibo reaction).
    var onSaved: (WalkDoodleResult) -> Void

    @State private var session = WalkDoodleSession()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var result: WalkDoodleResult? = nil
    @State private var piboLine: String = ""
    @State private var hint: String = WalkDoodleCopy.recordingHints[0]
    @State private var showDiscardConfirmation = false

    private let challenge = WalkDoodleChallenge.freeform

    var body: some View {
        ZStack {
            map
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomPanel
            }
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .lpDynamicTypeScaling()
        .accessibilityAddTraits(.isModal)
        .onAppear { session.requestAuthorization() }
        .onDisappear { session.reset() }
        // Live Activity 结束 button → finalize the doodle (preview shows on next
        // foreground). Guarded so we never double-finish.
        .onChange(of: session.stopRequested) { _, requested in
            if requested, result == nil { finishRecording() }
        }
        .alert(
            AppLocalization.text("放弃这次涂鸦？"),
            isPresented: $showDiscardConfirmation
        ) {
            Button(AppLocalization.text("继续画"), role: .cancel) {}
            Button(AppLocalization.text("放弃"), role: .destructive) {
                discardAndDismiss()
            }
        } message: {
            Text(AppLocalization.text("当前路线还没有保存。"))
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if session.coordinates.count >= 2 {
                MapPolyline(coordinates: session.coordinates)
                    .stroke(
                        LP.Fill.foundationAccent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
        }
        // POI labels on (小区 / 地标 as walking reference); flat so the stroke reads clearly.
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if session.phase == .recording {
                Text(hint)
                    .lpText(LP.Typography.handSmall)
                    .foregroundStyle(LP.Content.secondary)
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, LP.Spacing.s)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.top, 120)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LP.Spacing.s) {
                    HStack(spacing: LP.Spacing.s) {
                        closeControl
                        Spacer(minLength: 0)
                        locationControl
                    }
                    titleChip
                }
            } else {
                HStack(spacing: LP.Spacing.s) {
                    closeControl
                    Spacer(minLength: 0)
                    titleChip
                    Spacer(minLength: 0)
                    locationControl
                }
            }
        }
    }

    private var closeControl: some View {
        circleButton(system: "xmark", label: AppLocalization.text("关闭")) {
            if session.phase == .recording || result?.isDrawn == true {
                showDiscardConfirmation = true
            } else {
                discardAndDismiss()
            }
        }
    }

    private var locationControl: some View {
        circleButton(system: "location.fill", label: AppLocalization.text("回到我的位置")) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                camera = .userLocation(fallback: .automatic)
            }
        }
    }

    private var titleChip: some View {
        VStack(spacing: 1) {
            Text(AppLocalization.text("Pibo 的任务"))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.tertiary)
            Text(AppLocalization.text("圈一块花田"))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.vertical, LP.Spacing.s)
        .background(Capsule().fill(.regularMaterial))
        .lpShadow(LP.Shadow.elevation1)
    }

    private func circleButton(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.regularMaterial))
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: LP.Spacing.m) {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(showsIndicators: false) {
                    panelPhaseContent
                }
                .frame(maxHeight: 360)
            } else {
                panelPhaseContent
            }
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.bgPop))
        .lpShadow(LP.Shadow.elevation3)
    }

    @ViewBuilder
    private var panelPhaseContent: some View {
        switch session.phase {
        case .idle:        idlePanel
        case .recording:   recordingPanel
        case .finished:    finishedPanel
        }
    }

    // — idle —

    private var idlePanel: some View {
        VStack(spacing: LP.Spacing.m) {
            if session.isDenied {
                deniedNotice
            } else {
                // Garbled 魔丸 speech stays raw (not localized) — same as the
                // app-wide `speechPool` / `PiboCameraView.genericComments`.
                Text(challenge.promptKey)
                    .lpText(LP.Typography.handMid)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                primaryButton(AppLocalization.text("开始涂鸦"), system: "scribble.variable") {
                    Analytics.track(.walkDoodleStart, screen: "walk_doodle")
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                        session.start()
                    }
                }
            }
        }
    }

    private var deniedNotice: some View {
        VStack(spacing: LP.Spacing.s) {
            Text(AppLocalization.text("需要定位权限才能画地图涂鸦"))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.center)
            Button {
                LPHaptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(AppLocalization.text("去设置打开定位"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // — recording —

    private var recordingPanel: some View {
        VStack(spacing: LP.Spacing.m) {
            statRow
            primaryButton(AppLocalization.text("完成"), system: "checkmark") {
                finishRecording()
            }
        }
    }

    private var statRow: some View {
        doodleStats(
            distance: DoodleGeometry.distanceText(session.distanceMeters),
            area: DoodleGeometry.areaText(session.areaSquareMeters),
            duration: DoodleGeometry.durationText(session.elapsed)
        )
    }

    // — finished —

    private var finishedPanel: some View {
        VStack(spacing: LP.Spacing.m) {
            if let result {
                finishedStats(result)
                piboBubble
                if result.isDrawn {
                    adaptiveActionRow {
                        secondaryButton(AppLocalization.text("重走"), system: "arrow.counterclockwise") {
                            redraw()
                        }
                        primaryButton(AppLocalization.text("保存"), system: "leaf.fill") {
                            onSaved(result)
                            dismiss()
                        }
                    }
                } else {
                    adaptiveActionRow {
                        secondaryButton(AppLocalization.text("放弃"), system: "trash") {
                            session.reset()
                            dismiss()
                        }
                        primaryButton(AppLocalization.text("重走"), system: "arrow.counterclockwise") {
                            redraw()
                        }
                    }
                }
            }
        }
    }

    private func finishedStats(_ result: WalkDoodleResult) -> some View {
        doodleStats(
            distance: DoodleGeometry.distanceText(result.distanceMeters),
            area: DoodleGeometry.areaText(result.areaSquareMeters),
            duration: DoodleGeometry.durationText(result.duration)
        )
    }

    @ViewBuilder
    private func doodleStats(distance: String, area: String, duration: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: LP.Spacing.s) {
                doodleStat(label: AppLocalization.text("距离"), value: distance)
                Divider()
                doodleStat(label: AppLocalization.text("圈地"), value: area)
                Divider()
                doodleStat(label: AppLocalization.text("用时"), value: duration)
            }
        } else {
            HStack(spacing: 0) {
                doodleStat(label: AppLocalization.text("距离"), value: distance)
                divider
                doodleStat(label: AppLocalization.text("圈地"), value: area)
                divider
                doodleStat(label: AppLocalization.text("用时"), value: duration)
            }
        }
    }

    @ViewBuilder
    private func adaptiveActionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: LP.Spacing.s) { content() }
        } else {
            HStack(spacing: LP.Spacing.s) { content() }
        }
    }

    private var piboBubble: some View {
        Text(piboLine)
            .lpText(LP.Typography.handMid)
            .foregroundStyle(LP.Content.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LP.Spacing.m)
            .padding(.vertical, LP.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgSurfaceSecondary))
    }

    // MARK: Pieces

    private func doodleStat(label: String, value: String) -> some View {
        VStack(spacing: LP.Spacing.xs) {
            Text(label)
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.quarternary)
            Text(value)
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(LP.Content.primary)
                .monospacedDigit()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(LP.Separator.primary)
            .frame(width: 1, height: 28)
    }

    private func primaryButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 15, weight: .semibold))
                Text(title).lpText(LP.Typography.b2Medium)
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(LP.Fill.foundationOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LP.Spacing.m)
            .background(Capsule().fill(LP.Fill.foundationAccent))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 15, weight: .medium))
                Text(title).lpText(LP.Typography.b2Medium)
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(LP.Content.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LP.Spacing.m)
            .background(Capsule().fill(LP.Fill.bgContainer))
            .overlay(Capsule().strokeBorder(LP.Border.primary, lineWidth: LP.BorderWidth.hair))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func finishRecording() {
        let finished = session.finish()
        result = finished
        piboLine = (finished.isDrawn ? WalkDoodleCopy.savedLines : WalkDoodleCopy.tooShortLines)
            .randomElement() ?? "..."
        if let region = finished.coordinates.isEmpty
            ? nil
            : DoodleGeometry.boundingRegion(finished.coordinates.map(\.coordinate)) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { camera = .region(region) }
        }
    }

    private func discardAndDismiss() {
        session.reset()
        dismiss()
    }

    /// 重走 — clear the doodle and return to the idle briefing; the user taps
    /// 开始涂鸦 again to record a fresh one (clearer than silently re-recording).
    private func redraw() {
        camera = .userLocation(fallback: .automatic)
        hint = WalkDoodleCopy.recordingHints.randomElement() ?? hint
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            result = nil
            session.reset()
        }
    }
}

#Preview {
    WalkDoodleView(onSaved: { _ in })
}
