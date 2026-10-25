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
        let stored = PiboWidgetSnapshotStore.load()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let rollover = calendar.date(byAdding: .minute, value: 5, to: tomorrow)
            ?? tomorrow.addingTimeInterval(300)
        let entries = PiboWidgetTimeline.dates(from: now, calendar: calendar).map { entry(at: $0, stored: stored) }
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(rollover)))
    }

    private func entry(at date: Date, stored: PiboWidgetSnapshot = PiboWidgetSnapshotStore.load()) -> PiboWidgetEntry {
        var snapshot = stored
        snapshot.sceneID = PiboFlatWorldScene.recommended(
            petName: snapshot.petName,
            date: date,
            choices: PiboFlatWorldScene.widgetCycle
        )
        snapshot.stateLabel = snapshot.displayStateLabel(at: date)
        snapshot = snapshot.activitySnapshotForDisplay(at: date)
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
        case .systemMedium: PiboMediumWidget(snapshot: entry.snapshot, date: entry.date)
        case .accessoryCircular: PiboAccessoryCircularWidget(snapshot: entry.snapshot)
        case .accessoryRectangular: PiboAccessoryRectangularWidget(snapshot: entry.snapshot)
        case .accessoryInline: Text("Pibo · \(entry.snapshot.stateLabel)")
        default: PiboSmallWidget(snapshot: entry.snapshot, date: entry.date)
        }
    }
}

struct PiboWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PiboWidgetConstants.homeWidgetKind, provider: PiboWidgetProvider()) { entry in
            PiboWidgetsEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Pibo")
        .description("一小片像素森林，陪你看看今天的生活。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private let widgetPaper = Color(red: 0.98, green: 0.96, blue: 0.87)
private let widgetInk = Color(red: 0.18, green: 0.25, blue: 0.23)

private struct PiboSmallWidget: View {
    let snapshot: PiboWidgetSnapshot
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PiboPixelWidgetForest(snapshot: snapshot, date: date, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.petName).font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text(snapshot.stateLabel).font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 0, x: 1, y: 1)
                .padding(8)
            }
            HStack(spacing: 6) {
                fact("活动", snapshot.activeEnergyText, "kcal")
                fact("锻炼", snapshot.exerciseMinutesText, "min")
                fact("站立", snapshot.standHoursText, "h")
            }
            .padding(6).frame(maxWidth: .infinity).background(widgetPaper)
            Text(snapshot.activityStatus(at: date))
                .font(.system(size: 8)).foregroundStyle(widgetInk.opacity(0.7))
                .lineLimit(1).frame(maxWidth: .infinity).padding(.bottom, 4).background(widgetPaper)
        }
        .overlay(Rectangle().strokeBorder(widgetInk, lineWidth: 2))
        .widgetURL(URL(string: "pibo://home"))
        .accessibilityElement(children: .combine)
    }

    private func fact(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 8))
            Text("\(value)\(unit)").font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity).foregroundStyle(widgetInk)
    }
}

private struct PiboMediumWidget: View {
    let snapshot: PiboWidgetSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PiboPixelWidgetForest(snapshot: snapshot, date: date, compact: true)
                Text(snapshot.petName).font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 0, x: 1, y: 1).padding(8)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.stateLabel).font(.system(size: 11, weight: .bold, design: .monospaced)).lineLimit(1)
                PiboPixelActivityBar(label: "活动", value: "\(snapshot.activeEnergyText) kcal", progress: snapshot.moveProgress)
                PiboPixelActivityBar(label: "锻炼", value: "\(snapshot.exerciseMinutesText) min", progress: snapshot.exerciseProgress)
                PiboPixelActivityBar(label: "站立", value: "\(snapshot.standHoursText) h", progress: snapshot.standProgress)
                Text(snapshot.activityStatus(at: date)).font(.system(size: 8)).lineLimit(1)
            }
            .foregroundStyle(widgetInk).padding(10).frame(maxWidth: .infinity).background(widgetPaper)
        }
        .background(widgetPaper)
        .overlay(Rectangle().strokeBorder(widgetInk, lineWidth: 2))
        .widgetURL(URL(string: "pibo://home"))
        .accessibilityElement(children: .combine)
    }
}

private struct PiboPixelActivityBar: View {
    var label: String
    var value: String
    var progress: Double?

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer(minLength: 2)
                Text(value).monospacedDigit()
            }.font(.system(size: 9))
            HStack(spacing: 2) {
                ForEach(0..<10) { i in
                    Rectangle().fill(Double(i) < (progress ?? 0) * 10 ? Color.green.opacity(0.8) : widgetInk.opacity(0.12))
                }
            }.frame(height: 5)
        }
    }
}

private struct PiboPixelWidgetForest: View {
    let snapshot: PiboWidgetSnapshot
    let date: Date
    let compact: Bool

    var body: some View {
        let hour = Calendar.current.component(.hour, from: date)
        let mood: PixelMood = hour < 6 || hour >= 20 ? .night : (hour >= 17 ? .dusk : .day)
        let look = snapshot.pixelLook
        GeometryReader { proxy in
            if let image = PiboPixelCompanionArt.forestImage(look: look, mood: mood, width: 88, height: 88) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    .scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }
    }
}

struct PiboPixelWidgetGlyph: View {
    var stateTag: String
    var pixel: PiboCompanionPixelState? = nil

    private var look: PiboPixelCompanionArt.Look {
        var snapshot = PiboWidgetSnapshot.fallback
        snapshot.stateTag = stateTag
        snapshot.pixel = pixel
        return snapshot.pixelLook
    }

    var body: some View {
        if let image = PiboPixelCompanionArt.image(look: look, reduceMotion: true) {
            Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
        }
    }
}

private struct PiboAccessoryCircularWidget: View {
    let snapshot: PiboWidgetSnapshot
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            PiboPixelWidgetGlyph(stateTag: snapshot.stateTag, pixel: snapshot.pixel)
        }
        .accessibilityLabel("Pibo，\(snapshot.stateLabel)")
    }
}

private struct PiboAccessoryRectangularWidget: View {
    let snapshot: PiboWidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(snapshot.petName) · \(snapshot.stateLabel)").font(.headline).lineLimit(1)
            Text(snapshot.activeEnergy.map { _ in "活动 \(snapshot.activeEnergyText) kcal" } ?? "活动数据待同步").font(.caption).lineLimit(1)
        }
    }
}

#Preview(as: .systemSmall) { PiboWidgets() } timeline: { PiboWidgetEntry(date: .now, snapshot: .fallback) }
#Preview(as: .systemMedium) { PiboWidgets() } timeline: { PiboWidgetEntry(date: .now, snapshot: .fallback) }
