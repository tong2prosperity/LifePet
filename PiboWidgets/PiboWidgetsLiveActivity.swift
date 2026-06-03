import ActivityKit
import SwiftUI
import WidgetKit

struct PiboWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PiboFeedActivityAttributes.self) { context in
            PiboLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(PiboLivePalette.paper)
                .activitySystemActionForegroundColor(PiboLivePalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PiboLivePetGlyph(stateTag: context.state.stateTag)
                        .frame(width: 42, height: 42)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.petName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(context.state.title)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("+\(context.state.vitalityGain)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PiboLivePalette.coral)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text("P")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PiboLivePalette.coral)
            } compactTrailing: {
                Text("+\(context.state.vitalityGain)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } minimal: {
                Text("✦")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PiboLivePalette.coral)
            }
            .keylineTint(PiboLivePalette.coral)
        }
    }
}

private struct PiboLiveActivityLockScreenView: View {
    let context: ActivityViewContext<PiboFeedActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            PiboLivePetGlyph(stateTag: context.state.stateTag)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.attributes.petName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PiboLivePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(context.state.isComplete ? "已记录" : "等待喂养")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(context.state.isComplete ? PiboLivePalette.sage : PiboLivePalette.coral)
                        .lineLimit(1)
                }

                Text(context.state.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PiboLivePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(context.state.message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PiboLivePalette.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            VStack(spacing: 2) {
                Text("+\(context.state.vitalityGain)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(PiboLivePalette.coral)
                Text("活力")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PiboLivePalette.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PiboLivePetGlyph: View {
    let stateTag: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(PiboLivePalette.paperCool)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(PiboLivePalette.ink, lineWidth: 2)
                )

            VStack(spacing: 5) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 7, height: 7)
                }
                Capsule()
                    .fill(PiboLivePalette.ink)
                    .frame(width: stateTag == "SLEEPING" ? 14 : 22, height: 4)
            }

            if stateTag == "EXCITED" || stateTag == "BLISSFUL" {
                Circle()
                    .fill(PiboLivePalette.sticky)
                    .frame(width: 8, height: 8)
                    .offset(x: 22, y: -22)
            }
        }
    }

    private var accent: Color {
        switch stateTag {
        case "EXCITED", "BLISSFUL": return PiboLivePalette.coral
        case "SLEEPING": return PiboLivePalette.sage
        case "TIRED", "SICK": return PiboLivePalette.muted
        default: return PiboLivePalette.ink
        }
    }
}

private enum PiboLivePalette {
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let muted = Color(red: 0.431, green: 0.400, blue: 0.353)
    static let paper = Color(red: 0.980, green: 0.969, blue: 0.937)
    static let paperCool = Color(red: 0.980, green: 0.980, blue: 0.961)
    static let coral = Color(red: 0.820, green: 0.294, blue: 0.239)
    static let sage = Color(red: 0.243, green: 0.478, blue: 0.373)
    static let sticky = Color(red: 0.996, green: 0.957, blue: 0.659)
}

extension PiboFeedActivityAttributes {
    fileprivate static var preview: PiboFeedActivityAttributes {
        PiboFeedActivityAttributes(petName: "Pibo", workoutID: UUID())
    }
}

extension PiboFeedActivityAttributes.ContentState {
    fileprivate static var pending: PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: "跑步完成",
            message: "可喂给 Pibo，活力星光正在落下",
            vitalityGain: 32,
            stateTag: "EXCITED",
            endedAt: Date(),
            isComplete: false
        )
    }

    fileprivate static var complete: PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: "已喂给 Pibo",
            message: "今日运动已记录，Pibo 明亮了一点",
            vitalityGain: 32,
            stateTag: "BLISSFUL",
            endedAt: Date(),
            isComplete: true
        )
    }
}

#Preview("Notification", as: .content, using: PiboFeedActivityAttributes.preview) {
    PiboWidgetsLiveActivity()
} contentStates: {
    PiboFeedActivityAttributes.ContentState.pending
    PiboFeedActivityAttributes.ContentState.complete
}
