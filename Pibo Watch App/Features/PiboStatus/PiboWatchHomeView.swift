import SwiftUI

struct PiboWatchHomeView: View {
    @StateObject private var status = WatchPiboStatusStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("pibo.watch.haptics") private var haptics = true
    @AppStorage("pibo.watch.reduceMotion") private var reduceMotion = false
    @State private var showsDetails = false

    private var active: Bool { scenePhase == .active && !isLuminanceReduced && !showsDetails }

    var body: some View {
        GeometryReader { proxy in
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text(status.petName).font(.headline).lineLimit(1)
                    Spacer(minLength: 2)
                    if let pixel = status.pixel {
                        Text("Lv.\(pixel.level) · \(pixel.balance) bo").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                WatchPixelStage(status: status, animates: active, haptics: haptics && !reduceMotion && !systemReduceMotion, reduceMotion: reduceMotion,
                                stageHeight: max(88, min(112, proxy.size.height - 100)))
                Text(status.stateLabel).font(.caption).foregroundStyle(.secondary)
                if let growth = status.growth {
                    ProgressView(value: growth.progress).tint(.green)
                        .accessibilityLabel("这枚 bo 的生长")
                }
                today
                Button("近况与同步") { showsDetails = true }.font(.caption)
                Toggle("轻触觉", isOn: $haptics).font(.caption)
                Toggle("减弱动态", isOn: $reduceMotion).font(.caption)
            }
            .padding(.horizontal, 6).padding(.bottom, 16)
        }
        }
        .background(.black)
        .task { status.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { status.refresh() } }
        .sheet(isPresented: $showsDetails) { WatchPiboDetailsView(status: status) }
    }

    @ViewBuilder private var today: some View {
        if let pixel = status.pixel {
            Divider()
            Text("今日小心愿").font(.headline)
            if status.snapshot?.hasCurrentActivity() == true {
                ForEach(Array(pixel.wishes.enumerated()), id: \.offset) { _, wish in
                    HStack(alignment: .top) {
                        Text(wish.done ? "✓" : "□").foregroundStyle(wish.done ? .green : .secondary)
                        Text(wish.title).font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("今天的小心愿等 iPhone 同步。").font(.caption2).foregroundStyle(.secondary)
            }
            Text("林间散步小收获").font(.headline)
            ForEach(Array(pixel.stations.enumerated()), id: \.offset) { _, station in
                HStack {
                    Text(status.todaySteps.map { $0 >= station.steps } == true ? "✓" : "□")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(station.title).font(.caption)
                        Text("\(station.steps) 步").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                }
            }
            Text(status.todaySteps.map { "今天走了 \($0) 步" } ?? "今日步数待同步")
                .font(.caption2).foregroundStyle(.secondary)
            if !pixel.finds.isEmpty && status.snapshot?.hasCurrentActivity() == true {
                Text("今天带回 \(pixel.finds.count) 件小发现").font(.caption2).foregroundStyle(.green)
            }
        } else {
            Text("在 iPhone 打开 Pibo，成长与小心愿会一起来到手腕上。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct WatchPiboDetailsView: View {
    @ObservedObject var status: WatchPiboStatusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("近况与同步").font(.headline)
                Text(status.syncDescription()).font(.callout).foregroundStyle(.secondary)
                if let message = status.snapshot?.healthMessage {
                    Text(message).font(.callout)
                }
                Button(status.isRefreshing ? "正在刷新…" : "刷新 iPhone 状态") { status.refresh() }
                    .disabled(status.isRefreshing)
                    .frame(maxWidth: .infinity)
                Text("打开 iPhone 的 Pibo 后会继续同步。暂时连不上，不影响已有成长。")
                    .font(.caption2).foregroundStyle(.secondary)

                if !status.capabilities.isEmpty {
                    Divider()
                    Text("一起学会的事").font(.headline)
                    ForEach(status.capabilities) { capability in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capability.title).font(.callout).fontWeight(.semibold)
                            Text(capability.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
                Text("今日活动").font(.headline)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let activity = status.activity(now: context.date) {
                        VStack(spacing: 7) {
                            fact("活动", value: activity.activeEnergy.map { "\(Int($0.rounded())) 千卡" })
                            fact("运动", value: activity.exerciseMinutes.map { "\($0) 分钟" })
                            fact("站立时长", value: activity.standMinutes.map { "\($0) 分钟" })
                        }
                    } else {
                        Text("今天的活动数据还没有同步。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button(status.isReadingActivity ? "正在读取…" : "读取手表今日活动") {
                    Task { await status.readWatchActivity() }
                }
                .disabled(status.isReadingActivity)
                if let message = status.activityMessage {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
    }

    private func fact(_ title: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value ?? "暂无记录")
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}
