import SwiftUI
import WidgetKit

struct PiboWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PiboWidgetEntry {
        PiboWidgetEntry(date: Date(), snapshot: .fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (PiboWidgetEntry) -> Void) {
        completion(PiboWidgetEntry(date: Date(), snapshot: PiboWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PiboWidgetEntry>) -> Void) {
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        let entry = PiboWidgetEntry(date: now, snapshot: PiboWidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct PiboWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PiboWidgetSnapshot
}

struct PiboWidgetsEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: PiboWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            PiboMediumWidget(snapshot: entry.snapshot)
        case .accessoryCircular:
            PiboAccessoryCircularWidget(snapshot: entry.snapshot)
        case .accessoryRectangular:
            PiboAccessoryRectangularWidget(snapshot: entry.snapshot)
        case .accessoryInline:
            Text("Pibo \(entry.snapshot.stateLabel) · \(entry.snapshot.vitality)/\(entry.snapshot.energy)/\(entry.snapshot.mood)")
        default:
            PiboSmallWidget(snapshot: entry.snapshot)
        }
    }
}

struct PiboWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: PiboWidgetConstants.homeWidgetKind,
            provider: PiboWidgetProvider()
        ) { entry in
            PiboWidgetsEntryView(entry: entry)
                .containerBackground(PiboWidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("Pibo")
        .description("查看 Pibo 的星光状态。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

private struct PiboSmallWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.petName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PiboWidgetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("DAY \(snapshot.dayCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PiboWidgetPalette.muted)
                }
                Spacer(minLength: 4)
                Text(snapshot.stateLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PiboWidgetPalette.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                PiboPixelPetMark(stateTag: snapshot.stateTag)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    PiboCompactStat(label: "活力", value: snapshot.vitality, tint: PiboWidgetPalette.coral)
                    PiboCompactStat(label: "静息", value: snapshot.energy, tint: PiboWidgetPalette.sage)
                    PiboCompactStat(label: "心绪", value: snapshot.mood, tint: PiboWidgetPalette.stickyInk)
                }
            }

            if let title = snapshot.pendingWorkoutTitle, let gain = snapshot.pendingWorkoutGain {
                Text("\(title) +\(gain)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PiboWidgetPalette.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(2)
    }
}

private struct PiboMediumWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 8) {
                PiboPixelPetMark(stateTag: snapshot.stateTag)
                    .frame(width: 72, height: 72)
                Text(snapshot.stateLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PiboWidgetPalette.coral)
            }
            .frame(width: 86)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.petName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PiboWidgetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 8)
                    Text("DAY \(snapshot.dayCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PiboWidgetPalette.muted)
                }

                PiboWidgetStatBar(title: "活力星光", value: snapshot.vitality, tint: PiboWidgetPalette.coral)
                PiboWidgetStatBar(title: "静息星光", value: snapshot.energy, tint: PiboWidgetPalette.sage)
                PiboWidgetStatBar(title: "心绪回声", value: snapshot.mood, tint: PiboWidgetPalette.stickyInk)

                if let title = snapshot.pendingWorkoutTitle, let gain = snapshot.pendingWorkoutGain {
                    Text("\(title) 等待喂养 · +\(gain) 活力")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PiboWidgetPalette.coral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("最近更新 \(snapshot.updatedAt, style: .time)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(PiboWidgetPalette.muted)
                }
            }
        }
        .padding(2)
    }
}

private struct PiboAccessoryCircularWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        Gauge(value: Double(snapshot.vitality), in: 0...100) {
            Text("P")
        } currentValueLabel: {
            Text("\(snapshot.vitality)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(PiboWidgetPalette.coral)
    }
}

private struct PiboAccessoryRectangularWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(snapshot.petName) · \(snapshot.stateLabel)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("活力 \(snapshot.vitality) · 静息 \(snapshot.energy) · 心绪 \(snapshot.mood)")
                .font(.system(size: 12, design: .rounded))
                .lineLimit(1)
            if let title = snapshot.pendingWorkoutTitle {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
    }
}

private struct PiboCompactStat: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(PiboWidgetPalette.muted)
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PiboWidgetPalette.ink)
        }
    }
}

private struct PiboWidgetStatBar: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PiboWidgetPalette.muted)
                Spacer(minLength: 6)
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PiboWidgetPalette.ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PiboWidgetPalette.hairline)
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(value, 100))) / 100)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct PiboPixelPetMark: View {
    let stateTag: String

    private var accent: Color {
        switch stateTag {
        case "EXCITED", "BLISSFUL": return PiboWidgetPalette.coral
        case "SLEEPING": return PiboWidgetPalette.sage
        case "TIRED", "SICK": return PiboWidgetPalette.muted
        default: return PiboWidgetPalette.ink
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(PiboWidgetPalette.paperCool)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PiboWidgetPalette.ink, lineWidth: 2)
                )
                .shadow(color: PiboWidgetPalette.hairline, radius: 0, x: 3, y: 3)

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
                    .fill(PiboWidgetPalette.ink)
                    .frame(width: stateTag == "SLEEPING" ? 14 : 22, height: 4)
            }

            if stateTag == "EXCITED" || stateTag == "BLISSFUL" {
                Circle()
                    .fill(PiboWidgetPalette.sticky)
                    .frame(width: 8, height: 8)
                    .offset(x: 22, y: -22)
            }
        }
    }
}

private enum PiboWidgetPalette {
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let muted = Color(red: 0.431, green: 0.400, blue: 0.353)
    static let hairline = Color(red: 0.906, green: 0.890, blue: 0.851)
    static let paper = Color(red: 0.980, green: 0.969, blue: 0.937)
    static let paperCool = Color(red: 0.980, green: 0.980, blue: 0.961)
    static let coral = Color(red: 0.820, green: 0.294, blue: 0.239)
    static let sage = Color(red: 0.243, green: 0.478, blue: 0.373)
    static let sticky = Color(red: 0.996, green: 0.957, blue: 0.659)
    static let stickyInk = Color(red: 0.353, green: 0.290, blue: 0.165)
}

#Preview(as: .systemSmall) {
    PiboWidgets()
} timeline: {
    PiboWidgetEntry(date: Date(), snapshot: .fallback)
}

#Preview(as: .systemMedium) {
    PiboWidgets()
} timeline: {
    PiboWidgetEntry(date: Date(), snapshot: .fallback)
}
