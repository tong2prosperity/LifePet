import SwiftUI

/// Bottom-sheet "新运动同步" 提醒。`HealthDataService` 检测到 fresh workout
/// (≤5 min ago) 时 `PetStateStore.pendingWorkout` 被设上，`HomeView` 把这个
/// view 弹起；用户点 "喂养" 触发 `consumePendingWorkout()`、点 backdrop 触
/// 发 `dismissPendingWorkout()`（两路最终都会 applyGain，区别只在动画）。
///
/// 视觉对照 `原型-01-主页.html` 的 `.workout-sheet`：
/// - `paperCool` 背景 + ink 顶边
/// - drag handle（装饰）
/// - source 行 / 标题 / 副标题
/// - 三个 gain cell（vitality 实数；energy/mood 显示 — 因为 PRD §3 workout
///   仅入 vitality）
/// - 「喂养 \(petName)」 主按钮
struct WorkoutAlertSheet: View {
    let workout: PendingWorkout
    let petName: String
    let onFeed: () -> Void
    let onDismiss: () -> Void

    private static let lcd = Color(hex: 0xEBE3CC)
    private static let lcdInk = Color(hex: 0x7D7657)

    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 8)
                .padding(.bottom, LP.Spacing.s3)
            VStack(alignment: .leading, spacing: 2) {
                source
                    .padding(.bottom, 2)
                title
                subtitle
                    .padding(.bottom, LP.Spacing.s4)
                gainCells
                    .padding(.bottom, LP.Spacing.s4 + 2)
                feedButton
            }
            .padding(.horizontal, LP.Spacing.s5)
        }
        .padding(.bottom, LP.Spacing.s7)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(LP.Colors.paperCool)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LP.Colors.ink)
                .frame(height: 2)
        }
        .lpShadow(LP.Shadow.lg)
    }

    // MARK: - Handle

    private var handle: some View {
        Capsule()
            .fill(LP.Colors.hairline)
            .frame(width: 40, height: 4)
    }

    // MARK: - Header text

    private var source: some View {
        Text("APPLE WATCH · 刚刚同步")
            .font(.system(size: 9, design: .monospaced))
            .tracking(1)
            .foregroundStyle(LP.Colors.muted)
    }

    private var title: some View {
        Text(workout.titleLabel)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(LP.Colors.ink)
    }

    private var subtitle: some View {
        Text(subtitleText)
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(LP.Colors.muted)
    }

    private var subtitleText: String {
        var parts: [String] = ["\(workout.durationMin) 分钟"]
        if let kcal = workout.kcal, kcal >= 1 {
            parts.append("\(Int(kcal)) KCAL")
        }
        parts.append(timeLabel(workout.endedAt))
        return parts.joined(separator: " · ")
    }

    private func timeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        let m = cal.component(.minute, from: d)
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Gain cells

    private var gainCells: some View {
        HStack(spacing: LP.Spacing.s2) {
            GainCell(label: "体力", value: "+\(workout.gainVitality)", unit: "PTS", isPositive: true)
            GainCell(label: "精力", value: "+\(workout.gainVitality)", unit: "PTS", isPositive: true)
            GainCell(label: "心情", value: "+\(workout.gainVitality)", unit: "PTS", isPositive: true)
        }
    }

    // MARK: - Feed button

    private var feedButton: some View {
        Button(action: onFeed) {
            Text("喂养 \(petName)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(LP.Colors.paperCool)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LP.Colors.ink)
                )
                .lpShadow(LP.Shadow.md)
        }
        .buttonStyle(LPPressEffectStyle())
        .accessibilityLabel("喂养 \(petName)，应用本次运动的体力增益")
    }
}

// MARK: - Gain cell

private struct GainCell: View {
    let label: String
    let value: String
    let unit: String
    /// `true` 绿、`false` 红、`nil` 中性灰（用于 — 占位）
    let isPositive: Bool?

    private static let lcd = Color(hex: 0xEBE3CC)
    private static let positive = Color(hex: 0x3EB24E)

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LP.Colors.muted)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(unit.isEmpty ? " " : unit)
                .font(.system(size: 8, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.lcd)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: 1.5)
        )
        .lpShadow(LP.Shadow.sm)
    }

    private var valueColor: Color {
        switch isPositive {
        case .some(true):  return Self.positive
        case .some(false): return LP.Colors.coral
        case .none:        return LP.Colors.faint
        }
    }
}

// MARK: - Press effect

/// Tiny (translate(2,2) + shadow shrink) press effect mirroring the prototype's
/// "paper button" feedback. ButtonStyle is the right primitive — `.plain` would
/// disable haptics and have no visual delta.
private struct LPPressEffectStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Workout sheet") {
    ZStack(alignment: .bottom) {
        Color.black.opacity(0.4).ignoresSafeArea()
        WorkoutAlertSheet(
            workout: PendingWorkout(
                id: UUID(),
                kind: .run,
                label: "跑步",
                durationMin: 28,
                kcal: 215,
                endedAt: Date(),
                gainVitality: 32
            ),
            petName: "BEAN",
            onFeed: { print("feed") },
            onDismiss: { print("dismiss") }
        )
    }
}
