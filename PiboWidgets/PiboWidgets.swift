import SwiftUI
import WidgetKit

struct PiboWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PiboWidgetEntry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PiboWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PiboWidgetEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let rollover = calendar.date(byAdding: .minute, value: 5, to: tomorrow)
            ?? tomorrow.addingTimeInterval(300)
        completion(Timeline(entries: [entry(at: now), entry(at: rollover)], policy: .after(rollover.addingTimeInterval(86_400))))
    }

    private func entry(at date: Date) -> PiboWidgetEntry {
        var snapshot = PiboWidgetSnapshotStore.load()
        snapshot.sceneID = PiboFlatWorldScene.recommended(
            petName: snapshot.petName,
            date: date,
            choices: PiboFlatWorldScene.widgetCycle
        )
        return PiboWidgetEntry(date: date, snapshot: snapshot)
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
        case .systemMedium: PiboMediumWidget(snapshot: entry.snapshot)
        case .accessoryCircular: PiboAccessoryCircularWidget(snapshot: entry.snapshot)
        case .accessoryRectangular: PiboAccessoryRectangularWidget(snapshot: entry.snapshot)
        case .accessoryInline: Text("Pibo · \(entry.snapshot.stateLabel)")
        default: PiboSmallWidget(snapshot: entry.snapshot)
        }
    }
}

struct PiboWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PiboWidgetConstants.homeWidgetKind, provider: PiboWidgetProvider()) { entry in
            PiboWidgetsEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Pibo 运动")
        .description("在 Flat World 中查看 Pibo 和今天的三项活动。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct PiboSmallWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        ZStack {
            PiboFlatWorldBackground(scene: snapshot.sceneID ?? .rainGorge, compact: true)
            VStack(spacing: 4) {
                HStack {
                    Text(snapshot.petName).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(snapshot.stateLabel).font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PiboActivityRing(color: .pink, progress: snapshot.moveProgress, value: value(snapshot.activeEnergy, suffix: "kcal"), label: "活动")
                    PiboActivityRing(color: .mint, progress: snapshot.exerciseProgress, value: value(snapshot.exerciseMinutes.map(Double.init), suffix: "min"), label: "锻炼")
                    PiboActivityRing(color: .cyan, progress: snapshot.standProgress, value: value(snapshot.standHours.map(Double.init), suffix: "h"), label: "站立")
                }
            }
            .padding(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.petName)，\(snapshot.stateLabel)，\(activitySummary)")
    }

    private func value(_ number: Double?, suffix: String) -> String {
        number.map { "\(Int($0.rounded()))\(suffix)" } ?? "--"
    }

    private var activitySummary: String {
        "活动 \(snapshot.activeEnergy.map { "\(Int($0.rounded())) 千卡" } ?? "无数据")，锻炼 \(snapshot.exerciseMinutes.map { "\($0) 分钟" } ?? "无数据")，站立 \(snapshot.standHours.map { "\($0) 小时" } ?? "无数据")"
    }
}

private struct PiboMediumWidget: View {
    let snapshot: PiboWidgetSnapshot

    var body: some View {
        ZStack {
            PiboFlatWorldBackground(scene: snapshot.sceneID ?? .nightClouds, compact: false)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.petName).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(snapshot.stateLabel).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 0)
                }
                .frame(width: 112, alignment: .leading)
                VStack(spacing: 12) {
                    PiboActivityBar(label: "活动", value: snapshot.activeEnergy.map { "\(Int($0.rounded())) kcal" } ?? "--", progress: snapshot.moveProgress, color: .pink)
                    PiboActivityBar(label: "锻炼", value: snapshot.exerciseMinutes.map { "\($0) min" } ?? "--", progress: snapshot.exerciseProgress, color: .mint)
                    PiboActivityBar(label: "站立", value: snapshot.standHours.map { "\($0) h" } ?? "--", progress: snapshot.standProgress, color: .cyan)
                }
            }
            .padding(4)
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.petName)，\(snapshot.stateLabel)，今日活动")
    }
}

private struct PiboActivityRing: View {
    let color: Color
    let progress: Double?
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(.white.opacity(0.20), lineWidth: 3)
                Circle().trim(from: 0, to: min(1, max(0, progress ?? 0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(.system(size: 6.5, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            }
            .frame(width: 31, height: 31)
            Text(label).font(.system(size: 6, weight: .medium))
        }
        .foregroundStyle(.white)
    }
}

private struct PiboActivityBar: View {
    let label: String
    let value: String
    let progress: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Text(value).font(.system(size: 10, weight: .bold, design: .rounded))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, progress ?? 0)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct PiboFlatWorldBackground: View {
    let scene: PiboFlatWorldScene
    let compact: Bool

    var body: some View {
        Image(resourceName)
            .resizable()
            .scaledToFill()
    }

    private var resourceName: String {
        let suffix = compact ? "_compact" : ""
        return switch scene {
        case .rainGorge: "pibo_widget_cobalt_rain\(suffix)"
        case .nightClouds: "pibo_widget_moonlit_river\(suffix)"
        case .riverValley: "pibo_widget_acid_lime_trail\(suffix)"
        case .dawnCreek: "pibo_widget_moonlit_river\(suffix)"
        case .coralDusk: "pibo_widget_cobalt_rain\(suffix)"
        }
    }
}

private struct PiboAccessoryCircularWidget: View {
    let snapshot: PiboWidgetSnapshot
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text("P")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .accessibilityLabel("Pibo，\(snapshot.stateLabel)")
    }
}

private struct PiboAccessoryRectangularWidget: View {
    let snapshot: PiboWidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(snapshot.petName) · \(snapshot.stateLabel)").font(.headline).lineLimit(1)
            Text(snapshot.activeEnergy.map { "活动 \(Int($0.rounded())) kcal" } ?? "活动数据待同步").font(.caption).lineLimit(1)
        }
    }
}

#Preview(as: .systemSmall) { PiboWidgets() } timeline: { PiboWidgetEntry(date: .now, snapshot: .fallback) }
#Preview(as: .systemMedium) { PiboWidgets() } timeline: { PiboWidgetEntry(date: .now, snapshot: .fallback) }
