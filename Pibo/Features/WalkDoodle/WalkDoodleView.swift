import SwiftUI
import MapKit
import CoreLocation
import PiboCore

/// 地图涂鸦 (walk doodle) — a walking route and creation tool. Presented
/// full-screen from the home (like the 餐食相机). The user walks; their GPS trail
/// draws a thick Pibo-green stroke over the map in real time. On 完成 the camera
/// fits the doodle, Pibo says a line, and 保存 persists it as a `WalkDoodleRecord`
/// that lands on the 历史数据页. Core assigns 圆/三角形/五角星, grades the
/// completed route, and authorizes a capped improvement bonus for `bo` growth.
struct WalkDoodleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(WalkDoodleProgressStore.self) private var progress

    var routeEchoEnabled = false
    /// Hands the committed task to `HomeView` (reward + persist + reaction).
    var onSaved: (WalkDoodleCompletionResult) -> Void

    @State private var session = WalkDoodleSession()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var result: WalkDoodleResult? = nil
    @State private var piboLine: String = ""
    @State private var hint: String = WalkDoodleCopy.recordingHints[0]
    @State private var showDiscardConfirmation = false
    @State private var dayTask: WalkDoodleDayProgress?
    @State private var evaluation: PiboCoreDoodleAdapter.Evaluation?
    @State private var attemptOrdinal = 0

    private var taskShape: PiboCoreWalkDoodleShape { dayTask?.shape ?? .circle }

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
        .background(PiboMoss.Color.canvasMist.ignoresSafeArea())
        .lpDynamicTypeScaling()
        .accessibilityAddTraits(.isModal)
        .onAppear {
            session.requestAuthorization()
            dayTask = progress.task()
            hint = copyLine(
                kind: .recordingHint,
                lines: WalkDoodleCopy.recordingHints,
                result: nil
            )
        }
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
            Text(AppLocalization.text("散步涂鸦"))
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
                .fill(PiboMoss.Color.sheetMoss.opacity(0.96)))
        .overlay {
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(PiboMoss.Color.hairline.opacity(0.68), lineWidth: 1)
        }
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
            if session.isDenied || session.needsPreciseLocation {
                deniedNotice
            } else {
                taskCard
                primaryButton(AppLocalization.text("开始散步涂鸦"), system: "figure.walk") {
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
            Text(AppLocalization.text(
                session.needsPreciseLocation
                    ? "当前只有大概位置权限，记录轨迹需要精确位置"
                    : "需要定位权限才能进行散步涂鸦"
            ))
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

    private var taskCard: some View {
        HStack(spacing: LP.Spacing.m) {
            WalkDoodleRouteEchoView(shape: taskShape)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.format(
                    "今天画一个%@",
                    WalkDoodleCopy.shapeName(taskShape)
                ))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                Text(WalkDoodleCopy.taskInstruction(taskShape))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let best = dayTask?.bestScore, best > 0 {
                    Text(AppLocalization.format("今日最好 %d 分", best))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LP.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
                .fill(PiboMoss.Color.raisedNeutral.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
                .strokeBorder(PiboMoss.Color.hairline.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // — finished —

    private var finishedPanel: some View {
        VStack(spacing: LP.Spacing.m) {
            if let result {
                finishedStats(result)
                resultCard(result)
                if result.isDrawn {
                    adaptiveActionRow {
                        secondaryButton(AppLocalization.text("重走"), system: "arrow.counterclockwise") {
                            redraw()
                        }
                        primaryButton(
                            AppLocalization.text(evaluation?.score.isCompleted == true
                                ? "保存这次涂鸦"
                                : "保存路线"),
                            system: "leaf.fill"
                        ) {
                            save(result)
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
    private func resultCard(_ result: WalkDoodleResult) -> some View {
        if let evaluation {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack(spacing: LP.Spacing.m) {
                    WalkDoodleRouteEchoView(
                        shape: taskShape,
                        coordinates: result.coordinates
                    )
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(WalkDoodleCopy.resultTitle(evaluation))
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(PiboMoss.Color.forestInk)
                            Spacer(minLength: LP.Spacing.s)
                            Text("\(evaluation.score.score)")
                                .lpText(LP.Typography.uiH3)
                                .foregroundStyle(evaluation.score.isCompleted
                                    ? PiboMoss.Color.foundationTeal
                                    : PiboMoss.Color.secondaryInk)
                                .monospacedDigit()
                        }
                        Text(piboLine)
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(PiboMoss.Color.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if evaluation.reward.grantedEnergy > 0 {
                            Text(AppLocalization.format(
                                "本次为 Pibo 补充 +%d 能量",
                                Int(evaluation.reward.grantedEnergy.rounded())
                            ))
                                .lpText(LP.Typography.c2Medium)
                                .foregroundStyle(PiboMoss.Color.stepsGreen)
                        } else if evaluation.score.isCompleted,
                                  (dayTask?.rewardedEnergy ?? 0) > 0 {
                            Text(AppLocalization.text("今天的奖励已按最好成绩结算"))
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(PiboMoss.Color.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if routeEchoEnabled {
                    HStack(spacing: LP.Spacing.s) {
                        scorePart("闭合", value: evaluation.score.closureScore,
                                  tint: PiboMoss.Color.activityCyan)
                        scorePart("轮廓", value: evaluation.score.contourScore,
                                  tint: PiboMoss.Color.foundationTeal)
                        scorePart("转向", value: evaluation.score.structureScore,
                                  tint: PiboMoss.Color.sleepIndigo)
                    }
                } else {
                    Text(AppLocalization.text("唤醒补梦风铃后，可以看见闭合、轮廓和转向评分。"))
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(PiboMoss.Color.tertiaryInk)
                }
            }
            .padding(LP.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: PiboMoss.Radius.card, style: .continuous)
                    .fill(PiboMoss.Color.raisedNeutral.opacity(0.62))
            )
        }
    }

    private func scorePart(_ label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            HStack {
                Text(AppLocalization.text(label))
                Spacer(minLength: 2)
                Text("\(value)").monospacedDigit()
            }
            .lpText(LP.Typography.c2Medium)
            .foregroundStyle(PiboMoss.Color.secondaryInk)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(PiboMoss.Color.hairline.opacity(0.48))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, value))) / 100)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func doodleStats(distance: String, area: String, duration: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: LP.Spacing.s) {
                doodleStat(label: AppLocalization.text("距离"), value: distance)
                Divider()
                doodleStat(label: AppLocalization.text("路线面积"), value: area)
                Divider()
                doodleStat(label: AppLocalization.text("用时"), value: duration)
            }
        } else {
            HStack(spacing: 0) {
                doodleStat(label: AppLocalization.text("距离"), value: distance)
                divider
                doodleStat(label: AppLocalization.text("路线面积"), value: area)
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
        evaluation = PiboCoreDoodleAdapter.evaluate(
            shape: taskShape,
            coordinates: finished.coordinates.map(\.coordinate),
            previousBestScore: dayTask?.bestScore ?? 0,
            dailyRewardedEnergy: dayTask?.rewardedEnergy ?? 0
        )
        if let evaluation {
            piboLine = WalkDoodleCopy.resultMessage(
                shape: taskShape,
                evaluation: evaluation
            )
        } else {
            piboLine = copyLine(
                kind: finished.isDrawn ? .saved : .tooShort,
                lines: finished.isDrawn
                    ? WalkDoodleCopy.savedLines
                    : WalkDoodleCopy.tooShortLines,
                result: finished
            )
        }
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
        attemptOrdinal += 1
        hint = copyLine(
            kind: .recordingHint,
            lines: WalkDoodleCopy.recordingHints,
            result: nil
        )
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            result = nil
            evaluation = nil
            piboLine = ""
            session.reset()
        }
    }

    private func save(_ result: WalkDoodleResult) {
        let resolvedEvaluation = evaluation ?? PiboCoreDoodleAdapter.evaluate(
            shape: taskShape,
            coordinates: result.coordinates.map(\.coordinate),
            previousBestScore: dayTask?.bestScore ?? 0,
            dailyRewardedEnergy: dayTask?.rewardedEnergy ?? 0
        )
        let committed = progress.commit(
            shape: taskShape,
            evaluation: resolvedEvaluation
        )
        onSaved(WalkDoodleCompletionResult(
            route: result,
            taskDayKey: committed.day.dayKey,
            shape: taskShape,
            evaluation: resolvedEvaluation,
            rewardEventID: committed.eventID,
            scoringVersion: PiboCoreDoodleAdapter.scoringVersion,
            rewardVersion: PiboCoreDoodleAdapter.rewardVersion
        ))
        dismiss()
    }

    private func copyLine(
        kind: PiboCoreWalkDoodleCopyKind,
        lines: [String],
        result: WalkDoodleResult?
    ) -> String {
        guard let index = PiboCoreDoodleAdapter.copyIndex(
            kind: kind,
            coordinateCount: result?.coordinates.count ?? 0,
            distanceMeters: result?.distanceMeters ?? 0,
            durationSeconds: result?.duration ?? 0,
            attempt: attemptOrdinal,
            lineCount: lines.count
        ), lines.indices.contains(index) else { return "" }
        return AppLocalization.text(lines[index])
    }
}

#Preview {
    WalkDoodleView(onSaved: { _ in })
        .environment(WalkDoodleProgressStore())
}
