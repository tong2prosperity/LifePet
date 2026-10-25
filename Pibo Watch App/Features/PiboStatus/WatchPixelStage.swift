import SwiftUI
import WatchKit

struct WatchPixelStage: View {
    @ObservedObject var status: WatchPiboStatusStore
    var animates = true
    var haptics = true
    var reduceMotion = false
    var stageHeight: CGFloat = 112
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var patAt: Date?
    @State private var lastLineAt: Date?
    @State private var line = ""
    @State private var leafPull: Double = 0
    @State private var collecting = false
    @State private var rescuedForm: Int?
    @State private var lineTask: Task<Void, Never>?
    @State private var feedbackAllowed = false
    @State private var canHaptic = false

    private var moves: Bool { animates && !reduceMotion && !systemReduceMotion }
    private var look: PiboPixelCompanionArt.Look {
        var look = PiboPixelCompanionArt.Look()
        look.stateID = status.snapshot?.publicStateID ?? "dataUnknown"
        look.bodyStage = status.pixel?.bodyStage ?? 0
        look.leafStage = status.pixel?.leafStage ?? 0
        look.accessoryMask = status.pixel?.accessoryMask ?? 0
        look.progress = status.growth?.progress ?? 0
        look.ripe = status.growth?.stage == "ripe"
        look.form = status.pixel?.form == rescuedForm ? 0 : status.pixel?.form ?? 0
        look.stuck = look.form > 0 && status.pixel?.formStuck == true
        look.thought = status.snapshot?.hasCurrentActivity() == true && status.pixel?.thought == true
        look.leafPull = leafPull
        return look
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let unit = max(1, floor(min(proxy.size.width, proxy.size.height) * displayScale / 88)) / displayScale
                TimelineView(.animation(minimumInterval: 0.1, paused: !moves)) { context in
                    let age = patAt.map { context.date.timeIntervalSince($0) * 1000 } ?? -1
                    if let image = PiboPixelCompanionArt.image(
                        look: look, time: moves ? context.date.timeIntervalSinceReferenceDate * 1000 : 0,
                        patAge: age, mood: mood(context.date), reduceMotion: !moves
                    ) {
                        Image(decorative: image, scale: 1).resizable().interpolation(.none)
                            .frame(width: 88 * unit, height: 88 * unit)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .overlay {
                    Rectangle().fill(.clear).frame(width: 64, height: 64).offset(y: 12)
                        .contentShape(Rectangle())
                        .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                            switch value {
                            case .first: pat()
                            case .second:
                                patAt = .now
                                if haptics && animates { WKInterfaceDevice.current().play(.click) }
                            }
                        })
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(.clear).frame(width: 48, height: 42)
                        .contentShape(Rectangle())
                        .onTapGesture { collect() }
                        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                            if value.translation.height < -12 { collect() }
                        })
                }
            }
            .frame(height: stageHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(status.petName)，\(status.stateLabel)")
            .accessibilityHint("双击打招呼，成熟的叶子可上拉收取")
            .accessibilityAction(named: "拍一拍", pat)
            .accessibilityAction(named: "收取成熟 bo", collect)

            if !line.isEmpty {
                Text(line).font(.caption2).multilineTextAlignment(.center)
                    .padding(6).frame(maxWidth: .infinity)
                    .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.23))
                    .background(Color(red: 0.98, green: 0.96, blue: 0.86))
                    .overlay(Rectangle().stroke(.green.opacity(0.5), lineWidth: 1))
            }
            if look.ripe {
                Button(collecting ? "正在收好…" : "▲ 上拉收取 bo", action: collect)
                    .font(.caption2).tint(.yellow).disabled(collecting)
            } else {
                Text("双击 Pibo，打个招呼").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: status.pixel?.form) { _, _ in rescuedForm = nil }
        .onAppear { feedbackAllowed = animates; canHaptic = animates && haptics }
        .onChange(of: haptics) { _, enabled in canHaptic = animates && enabled }
        .onChange(of: animates) { _, active in
            feedbackAllowed = active
            canHaptic = active && haptics
            if !active { lineTask?.cancel(); line = "" }
        }
        .onDisappear { feedbackAllowed = false; canHaptic = false; lineTask?.cancel() }
    }

    private func mood(_ date: Date) -> PixelMood {
        switch Calendar.current.component(.hour, from: date) {
        case 6..<17: .day
        case 17..<20: .dusk
        default: .night
        }
    }

    private func pat() {
        guard animates else { return }
        patAt = .now
        if haptics { WKInterfaceDevice.current().play(.click) }
        if look.stuck {
            rescuedForm = look.form
            say("呼，变回来了。谢谢你。")
            return
        }
        let now = Date()
        let cooldown = status.pixel?.patCooldownSeconds ?? 3
        guard lastLineAt.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return }
        lastLineAt = now
        if let text = status.pixel?.patLine, !text.isEmpty { say(text) }
    }

    private func collect() {
        guard animates, !collecting else { return }
        guard look.ripe, status.pixel?.collectionToken != nil else {
            patAt = .now
            say("叶子还在慢慢长。")
            return
        }
        collecting = true
        Task { @MainActor in
            if moves { leafPull = 0.45 }
            if canHaptic { WKInterfaceDevice.current().play(.click) }
            try? await Task.sleep(for: .milliseconds(180))
            if moves { leafPull = 1 }
            try? await Task.sleep(for: .milliseconds(160))
            let success = await status.collectBo()
            leafPull = 0
            collecting = false
            if feedbackAllowed {
                if canHaptic { WKInterfaceDevice.current().play(success ? .success : .click) }
                say(success ? "收好啦。叶子还在。" : "连上 iPhone 后再收，成熟的 bo 会留着。")
            }
        }
    }

    private func say(_ text: String) {
        lineTask?.cancel()
        line = text
        lineTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            line = ""
        }
    }
}
