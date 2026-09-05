import SwiftUI

struct PiboWatchHomeView: View {
    @StateObject private var status = WatchPiboStatusStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var showsDetails = false

    private var animates: Bool { scenePhase == .active && !isLuminanceReduced && !showsDetails }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 180
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: compact ? 2 : 3) {
                        Text(status.petName)
                            .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        WatchPiboCharacter(
                            state: status.vectorState,
                            boProgress: status.growth?.progress ?? 0,
                            actionID: status.snapshot?.patActionID,
                            isInteractive: true,
                            animates: animates,
                            petName: status.petName
                        )
                        .frame(height: compact ? 64 : max(88, min(132, proxy.size.height - 114)))
                        Text(status.stateLabel).font(.callout).fontWeight(.medium)
                        Text("双击 Pibo，打个招呼")
                            .font(.caption2).foregroundStyle(.white.opacity(0.72))
                        if let updated = status.stateUpdatedAt {
                            Text("状态于 \(updated.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(sceneColor.gradient, in: RoundedRectangle(cornerRadius: 20))

                    WatchGrowthSummary(growth: status.growth)

                    Button { showsDetails = true } label: {
                        Label("近况与同步", systemImage: "info.circle")
                            .font(.callout)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)

                    if let connection = status.shadowConnection {
                        WatchShadowCard(connection: connection, animates: animates)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
        .background(.black)
        .task { status.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { status.refresh() } }
        .sheet(isPresented: $showsDetails) { WatchPiboDetailsView(status: status) }
    }

    private var sceneColor: Color {
        switch status.scene {
        case .nightClouds: Color(red: 0.08, green: 0.10, blue: 0.28)
        case .dawnCreek: Color(red: 0.08, green: 0.28, blue: 0.27)
        case .riverValley: Color(red: 0.08, green: 0.30, blue: 0.20)
        case .rainGorge: Color(red: 0.05, green: 0.17, blue: 0.28)
        case .coralDusk: Color(red: 0.25, green: 0.16, blue: 0.34)
        }
    }
}

private struct WatchGrowthSummary: View {
    let growth: PiboCompanionGrowth?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let growth {
                Text(title(growth)).font(.callout).fontWeight(.semibold)
                ProgressView(value: growth.progress).tint(.mint)
                    .accessibilityLabel("这枚 bo 的生长")
                    .accessibilityValue(Text(growth.progress, format: .percent.precision(.fractionLength(0))))
                Text(growth.stage == "ripe" ? "在 iPhone 的森林里，投入共同物件" : "真实睡眠与活动，慢慢长成 bo")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("等你的生活传过来")
                    .font(.callout).fontWeight(.semibold)
                Text("在 iPhone 打开 Pibo，状态和成长会一起来到手腕上。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func title(_ growth: PiboCompanionGrowth) -> String {
        switch growth.stage {
        case "sprouting": "bo 正在发芽"
        case "forming": "bo 正在慢慢成形"
        case "ripe": "\(growth.ripeCount) 枚 bo 已成熟"
        default: "bo 正在等待生长"
        }
    }
}

private struct WatchShadowCard: View {
    let connection: PiboCompanionShadowConnection
    let animates: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text("远方的 Pibo").font(.caption2).foregroundStyle(.secondary)
            Text(connection.displayName).font(.headline).lineLimit(2)
            if let snapshot = connection.snapshot {
                WatchPiboCharacter(
                    state: WatchPiboStatusStore.vectorState(
                        animationID: snapshot.visualVariantKey, publicStateID: snapshot.publicStateID
                    ),
                    animates: animates,
                    petName: connection.displayName
                )
                .frame(height: 84)
                .opacity(0.62)
                .accessibilityHidden(true)
                Text(WatchPiboStatusStore.stateLabel(for: snapshot.publicStateID)).font(.callout)
                Text(connection.status == .paused ? "映照暂停更新" : "最近一次映照")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.syncedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(connection.status == .paused ? "映照暂停更新" : "等待第一次映照")
                    .font(.callout)
                Text("你们的连接还在")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
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
