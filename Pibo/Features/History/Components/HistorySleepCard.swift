import SwiftUI

/// 睡眠 card — total duration over a clouds illustration + a sleep-stage timeline,
/// on a dark grey-850 surface (Figma `activity card` 1193:2161). Cloud size/color
/// map to stage durations (designer note: 云朵大小映射每段时长 · 水平高度区分).
struct HistorySleepCard: View {
    let totalSeconds: TimeInterval
    let deepSeconds: TimeInterval
    let remSeconds: TimeInterval
    let start: Date?
    let end: Date?

    var body: some View {
        HistoryCard(title: "睡眠", dark: true, background: { LP.Neutral.grey850 }) {
            VStack(spacing: LP.Spacing.xs) {
                durationLine
                SleepClouds(total: totalSeconds, deep: deepSeconds, rem: remSeconds)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                timeline
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.s)
        }
    }

    private var hours: Int { Int(totalSeconds) / 3600 }
    private var minutes: Int { (Int(totalSeconds) % 3600) / 60 }
    private var deepMinutes: Int { Int(deepSeconds) / 60 }

    private var durationLine: some View {
        HStack(spacing: LP.Spacing.s) {
            valueUnit("\(hours)", "h")
            valueUnit("\(minutes)", "min")
        }
    }

    private func valueUnit(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
            Text(value).lpText(LP.Typography.uiH4).foregroundStyle(LP.Content.invertPrimary)
            Text(unit).lpText(LP.Typography.b3Medium).foregroundStyle(LP.Content.invertPrimary)
                .padding(.bottom, 2)
        }
    }

    private var timeline: some View {
        HStack {
            Text(timeString(start) ?? "—")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.invertSecondary)
            Spacer(minLength: 0)
            if deepMinutes > 0 {
                Text(AppLocalization.format("深睡 %d 分钟", deepMinutes))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.invertQuarternary)
            }
            Spacer(minLength: 0)
            Text(timeString(end) ?? "—")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.invertSecondary)
        }
    }

    private func timeString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.hm.string(from: date)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "H:mm"
        return f
    }()
}

/// Procedural sleep clouds over a faint ruler with a stage marker line. Clouds
/// vary in size + color (深睡 purple, 浅睡 blue, 眼动/REM lighter) to echo the
/// night's stage mix without shipping art.
private struct SleepClouds: View {
    let total: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                ruler(width: w).frame(height: 8).position(x: w / 2, y: h - 4)

                cloud(color: .white.opacity(0.85), scale: 1.0).position(x: w * 0.17, y: h * 0.4)
                cloud(color: LP.Colorful.blue300, scale: 0.8).position(x: w * 0.4, y: h * 0.52)
                cloud(color: LP.Colorful.purple500, scale: 0.7).position(x: w * 0.52, y: h * 0.62)
                cloud(color: .white.opacity(0.8), scale: 0.95).position(x: w * 0.68, y: h * 0.42)
                cloud(color: LP.Colorful.purple400, scale: 0.6).position(x: w * 0.84, y: h * 0.58)

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1, height: h * 0.78)
                    .position(x: w * 0.33, y: h * 0.44)
            }
        }
    }

    private func cloud(color: Color, scale: CGFloat) -> some View {
        ZStack {
            Circle().frame(width: 24, height: 24).offset(x: -15)
            Circle().frame(width: 34, height: 34)
            Circle().frame(width: 22, height: 22).offset(x: 16, y: 3)
            Capsule().frame(width: 58, height: 16).offset(y: 11)
        }
        .foregroundStyle(color)
        .scaleEffect(scale)
        .frame(width: 64, height: 44)
    }

    private func ruler(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, Int(width / 6)), id: \.self) { _ in
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 6)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}
