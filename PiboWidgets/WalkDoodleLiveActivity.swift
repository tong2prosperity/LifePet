import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity for an in-progress 地图涂鸦 walk — Lock Screen banner + Dynamic
/// Island, showing 正在行走 with live 距离 / 圈地, a self-counting 用时 timer, and a
/// 结束 button (`StopWalkDoodleIntent`). Driven by `WalkDoodleSession`.
struct WalkDoodleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkDoodleActivityAttributes.self) { context in
            WalkDoodleLockScreenView(context: context)
                .activityBackgroundTint(WalkDoodlePalette.paper)
                .activitySystemActionForegroundColor(WalkDoodlePalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.petName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "figure.walk")
                            .foregroundStyle(WalkDoodlePalette.green)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                        .foregroundStyle(WalkDoodlePalette.ink)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("正在画涂鸦")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        metric("距离", WalkDoodleFormat.distance(context.state.distanceMeters))
                        metric("圈地", WalkDoodleFormat.area(context.state.areaSquareMeters))
                        Spacer(minLength: 0)
                        stopButton
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(WalkDoodlePalette.green)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(WalkDoodlePalette.ink)
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(WalkDoodlePalette.green)
            }
            .keylineTint(WalkDoodlePalette.green)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WalkDoodlePalette.ink)
        }
    }

    private var stopButton: some View {
        Button(intent: StopWalkDoodleIntent()) {
            Text("结束")
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .tint(WalkDoodlePalette.green)
        .buttonStyle(.borderedProminent)
    }
}

private struct WalkDoodleLockScreenView: View {
    let context: ActivityViewContext<WalkDoodleActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(WalkDoodlePalette.green.opacity(0.16))
                Image(systemName: "figure.walk")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WalkDoodlePalette.green)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.attributes.petName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WalkDoodlePalette.ink)
                        .lineLimit(1)
                    Text("正在画涂鸦")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(WalkDoodlePalette.green)
                }
                HStack(spacing: 14) {
                    stat("距离", WalkDoodleFormat.distance(context.state.distanceMeters))
                    stat("圈地", WalkDoodleFormat.area(context.state.areaSquareMeters))
                    stat("用时", nil, timer: context.state.startedAt)
                }
            }

            Spacer(minLength: 4)

            Button(intent: StopWalkDoodleIntent()) {
                Text("结束")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(minWidth: 52)
            }
            .tint(WalkDoodlePalette.green)
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: String?, timer: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(WalkDoodlePalette.muted)
            if let timer {
                Text(timer, style: .timer)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WalkDoodlePalette.ink)
            } else {
                Text(value ?? "—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WalkDoodlePalette.ink)
            }
        }
    }
}

/// Inline number→label formatting for the widget (the app's `DoodleGeometry`
/// lives in the app target only; these mirror its `distanceText` / `areaText`).
enum WalkDoodleFormat {
    static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres.rounded())) m" : String(format: "%.2f km", metres / 1000)
    }
    static func area(_ squareMetres: Double) -> String {
        squareMetres < 10_000 ? "\(Int(squareMetres.rounded())) m²" : String(format: "%.2f 公顷", squareMetres / 10_000)
    }
}

private enum WalkDoodlePalette {
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let muted = Color(red: 0.431, green: 0.400, blue: 0.353)
    static let paper = Color(red: 0.957, green: 0.973, blue: 0.976)
    static let green = Color(red: 0.122, green: 0.659, blue: 0.263)
}

extension WalkDoodleActivityAttributes {
    fileprivate static var preview: WalkDoodleActivityAttributes {
        WalkDoodleActivityAttributes(petName: "Pibo")
    }
}

extension WalkDoodleActivityAttributes.ContentState {
    fileprivate static var walking: WalkDoodleActivityAttributes.ContentState {
        WalkDoodleActivityAttributes.ContentState(
            distanceMeters: 820, areaSquareMeters: 1840,
            startedAt: Date().addingTimeInterval(-372), pointCount: 124)
    }
}

#Preview("WalkDoodle LA", as: .content, using: WalkDoodleActivityAttributes.preview) {
    WalkDoodleLiveActivity()
} contentStates: {
    WalkDoodleActivityAttributes.ContentState.walking
}
