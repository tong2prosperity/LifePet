import Foundation
import SwiftUI

#if DEBUG
struct ForestTuningPanel: View {
    @Binding var tuning: StageRenderTuning
    @Binding var isExpanded: Bool
    @Binding var forcedHour: Double?
    @Binding var forcedAnimationStateID: String?
    let coreAnimationStateID: String
    let presentedAnimationStateID: String
    @Binding var usesBounceCut: Bool
    @Binding var playsAchievementCombo: Bool
    let onSelectAnimationState: (String?) -> Void
    let onReplayAnimation: () -> Void
    @State private var playbackTask: Task<Void, Never>?
    @State private var isPlayingDay = false

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(.scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity))
            } else {
                collapsedButton
                    .transition(.scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { stopPlayback() }
        }
        .onDisappear { stopPlayback() }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(spacing: LP.Spacing.s) {
                Label("森林细节", systemImage: "slider.horizontal.3")
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)

                Spacer(minLength: 0)

                Button {
                    LPHaptics.tap()
                    stopPlayback()
                    tuning = .standard
                    forcedHour = nil
                    usesBounceCut = false
                    playsAchievementCombo = false
                    onSelectAnimationState(nil)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复森林默认参数")

                Button {
                    LPHaptics.tap()
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起森林细节面板")
            }
            .foregroundStyle(LP.Content.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Toggle("隐藏 Pibo", isOn: Binding(
                        get: { !tuning.piboVisible },
                        set: { tuning.piboVisible = !$0 }
                    ))
                    .lpText(LP.Typography.c1Regular)
                    .tint(LP.Fill.foundationAccent)

                    animationStateControl

                    timeLightingControl

                    tuningSlider(
                        title: "树叶晃动",
                        value: $tuning.ambientMotionScale,
                        range: 0...2
                    )

                    tuningSlider(
                        title: "Pibo 草叶柔韧度",
                        value: $tuning.headSproutFlexibility,
                        range: 0...1
                    )
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 470)
        }
        .padding(LP.Spacing.m)
        .frame(width: 264)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
        )
        .lpShadow(LP.Shadow.elevation2)
    }

    /// 动画态走查：切状态、看 Core 判定、看这一态的连招由什么组成、重播登场。
    private var animationStateControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LP.Spacing.s) {
                Text("Pibo 动画态")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(forcedAnimationStateID == nil ? "跟随 Core" : "已强制")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 4
            ) {
                animationStateChip("Core", stateID: nil)
                // 白名单是唯一来源，多一态少一态面板自动跟。
                ForEach(PiboAnimationStateMap.available.sorted(), id: \.self) { stateID in
                    animationStateChip(shortStateLabel(stateID), stateID: stateID)
                }
            }

            Text("Core：\(coreAnimationStateID) · 在演：\(presentedAnimationStateID)")
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .monospacedDigit()

            Text(idleComposition(of: presentedAnimationStateID))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                intentButton("硬切", bounce: false)
                intentButton("Q 弹", bounce: true)
            }

            Button {
                LPHaptics.tap()
                onReplayAnimation()
            } label: {
                Label("重播登场 / 连招", systemImage: "arrow.clockwise")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从头重播当前状态的登场与连招")

            Toggle("成果态演完整连招", isOn: $playsAchievementCombo)
                .lpText(LP.Typography.c1Regular)
                .tint(LP.Fill.foundationAccent)
                .disabled(!isAchievementState(presentedAnimationStateID))
                .accessibilityHint("关闭时首页只跑设计的保持呼吸")
        }
    }

    private func animationStateChip(_ title: String, stateID: String?) -> some View {
        let isSelected = forcedAnimationStateID == stateID
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            onSelectAnimationState(stateID)
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    Capsule().fill(isSelected ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stateID ?? "跟随 Core 判定")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func intentButton(_ title: String, bounce: Bool) -> some View {
        let isSelected = usesBounceCut == bounce
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            usesBounceCut = bounce
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    Capsule().fill(isSelected ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bounce ? "下一次切换走 Q 弹" : "下一次切换走硬切")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 睡眠三态的 ID 太长，四列放不下。
    private func shortStateLabel(_ stateID: String) -> String {
        stateID.replacingOccurrences(of: "sleep-", with: "睡")
    }

    private func isAchievementState(_ stateID: String) -> Bool {
        PiboAnimationStateMap.holdIdle(for: stateID) != nil
    }

    /// 这一态的连招由哪些原语、多长的门控周期组成 —— 直接读运行时数据，
    /// 面板不复述一份。
    private func idleComposition(of stateID: String) -> String {
        guard let idle = PiboCharacterData.shared?.states[stateID]?.idle else {
            return "无待机数据"
        }
        let parts = idle.resolvedParts
        let cycle = parts.compactMap(\.gateCycle).max()
        var summary = "\(parts.count) 段"
        if let cycle { summary += " · 时间轴 \(String(format: "%.1f", cycle))s" }
        if let intro = idle.intro {
            summary += " · 登场 \(String(format: "%.2f", intro.duration))s"
        }
        let kinds = parts.map(\.kind).reduce(into: [String]()) { unique, kind in
            if !unique.contains(kind) { unique.append(kind) }
        }
        return summary + "\n" + kinds.joined(separator: " · ")
    }

    private var timeLightingControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LP.Spacing.s) {
                Text("时间光影")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(forcedHour == nil ? "自动 · \(formattedHour(displayHour))" : formattedHour(displayHour))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }

            Slider(value: hourBinding, in: 0...23.75, step: 0.25)
                .tint(LP.Fill.foundationAccent)
                .accessibilityLabel("森林时间")
                .accessibilityValue(formattedHour(displayHour))

            HStack(spacing: 4) {
                timeButton("自动", hour: nil)
                timeButton("06:30", hour: 6.5)
                timeButton("12:00", hour: 12)
                timeButton("18:30", hour: 18.5)
                timeButton("23:00", hour: 23)
            }

            Button {
                LPHaptics.tap()
                isPlayingDay ? stopPlayback() : startPlayback()
            } label: {
                Label(isPlayingDay ? "停止播放" : "24 秒播放一天",
                      systemImage: isPlayingDay ? "stop.fill" : "play.fill")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayingDay ? "停止时间光影播放" : "用二十四秒播放一天光影")
        }
    }

    private var hourBinding: Binding<Double> {
        Binding(
            get: { displayHour },
            set: { value in
                stopPlayback()
                forcedHour = (value * 4).rounded() / 4
            }
        )
    }

    private var displayHour: Double {
        forcedHour ?? localHour
    }

    private var localHour: Double {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: Date())
        return Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60
    }

    private func timeButton(_ title: String, hour: Double?) -> some View {
        let isSelected: Bool
        if let hour, let forcedHour {
            isSelected = abs(hour - forcedHour) < 0.01
        } else {
            isSelected = hour == nil && forcedHour == nil
        }
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            stopPlayback()
            forcedHour = hour
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    Capsule().fill(isSelected ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hour.map(formattedHour) ?? "自动跟随本地时间")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func formattedHour(_ hour: Double) -> String {
        let normalized = PiboStageEnvironmentResolver.normalizedHour(hour)
        let totalMinutes = Int((normalized * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func startPlayback() {
        stopPlayback()
        isPlayingDay = true
        playbackTask = Task { @MainActor in
            for step in 0..<96 {
                guard !Task.isCancelled else { return }
                forcedHour = Double(step) / 4
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            isPlayingDay = false
            playbackTask = nil
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlayingDay = false
    }

    private var collapsedButton: some View {
        Button {
            LPHaptics.tap()
            isExpanded = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                )
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开森林细节面板")
    }

    private func tuningSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: LP.Spacing.s) {
                Text(title)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05)
                .tint(LP.Fill.foundationAccent)
                .accessibilityLabel(title)
                .accessibilityValue(
                    Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                )
        }
    }
}
#endif
