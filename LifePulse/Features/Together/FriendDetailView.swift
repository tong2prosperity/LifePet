import SwiftUI

/// One twin-space detail screen — opened by tapping a friend cell on
/// `TogetherView`. Mirrors `viewTwinDetail` in `原型-03-一起.html` v0.9.1.
///
/// Sections (top → bottom):
/// 1. Days header + relation pill (右侧 coral)
/// 2. Twin stage — two breathing pets with health pills floating above and an
///    animated coral light band flowing between them
/// 3. Health-compare card — 5 rows (步数 / 睡眠 / 心率 / 卡路里 / 静息)
/// 4. Message thread — paper bubbles, input row, 4 quick chips
/// 5. Action row — 戳一下 / 加油
///
/// All numbers / pets / messages come from the `Friend` mock. The user's pet
/// name + sprite is overlaid from `PetStateStore` so the "你" side stays in
/// sync with the home screen identity.
struct FriendDetailView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let friend: Friend

    /// Local thread state — seeded once from `friend.messages` in `init` and
    /// mutated by the input row / quick chips. We don't write back to the
    /// static mock. Seeding in `init` (not `onAppear`) means a brief
    /// background trip / scenePhase event won't wipe what the user just
    /// typed; only a fresh navigation push (= new view identity) resets it.
    @State private var messages: [TogetherMessage]
    @State private var draft: String = ""
    @State private var toast: String? = nil
    /// Set when the user taps `戳一下` — drives a one-shot shake animation
    /// on the other pet sprite. Cleared after the shake completes so the
    /// next poke can re-trigger the same animation.
    @State private var pokeNonce: Int = 0
    @State private var cheerNonce: Int = 0

    init(friend: Friend) {
        self.friend = friend
        self._messages = State(initialValue: friend.messages)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                    backRow
                    daysHeader
                    twinStage
                    healthCompare
                    messageThread
                    quickChips
                    actionRow
                    Spacer(minLength: LP.Spacing.s5)
                }
                .padding(.horizontal, LP.Spacing.s4)
                .padding(.top, LP.Spacing.s2)
            }
            if let msg = toast {
                ToastBubble(text: msg)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .lpPaper(.app)
        // Hide the system nav bar that would otherwise appear on push (the
        // root NavigationStack hides it, but that doesn't propagate to
        // pushed destinations — they get a default empty bar unless they
        // hide it themselves). Without this, the user sees both my custom
        // "‹ 返回" header and the system back chevron.
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.25), value: toast)
    }

    // MARK: - Back row

    private var backRow: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Text("‹")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.coral)
                Text("返回")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Days header

    private var daysHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(friend.daysTogether)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text("天 · 一起")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(LP.Colors.muted)
            }
            Spacer()
            Text(friend.relation)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(LP.Colors.paperCard)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LP.Colors.coral)
                )
        }
    }

    // MARK: - Twin stage

    /// Two pets framed inside an LCD card, with a horizontally-flowing coral
    /// particle band between them. The shake / sparkle bubble overlay reacts
    /// to `pokeNonce` and `cheerNonce` — both incremented from the action row.
    private var twinStage: some View {
        ZStack {
            // — LCD chrome —
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LCD.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: 2)
                )
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LP.Colors.ink)
                        .offset(x: 3, y: 3)
                )
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LCD.dash, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(5)

            HStack(alignment: .center, spacing: 6) {
                petColumn(
                    name: store.petName,
                    sprite: .bean,
                    pillItems: [friend.myHealth.stepsShort, friend.myHealth.sleepShort, "\(friend.myHealth.hr)♥"],
                    status: friend.myStatus,
                    nonce: 0
                )
                LightBand()
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                petColumn(
                    name: friend.petName,
                    sprite: friend.sprite,
                    pillItems: [friend.otherHealth.stepsShort, friend.otherHealth.sleepShort, "\(friend.otherHealth.hr)♥"],
                    status: friend.otherStatus,
                    nonce: pokeNonce
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(height: 158)
        // Cheer ✨ floats up over the friend's pet on each `cheerNonce` tick.
        // Always rendered (initial opacity = 0 inside `CheerFloat`) so the
        // `keyframeAnimator(trigger:)` sees a real 0→1, 1→2, … transition
        // and re-runs the keyframes. With `if cheerNonce > 0` + `.id(...)`,
        // each tap created a fresh view whose modifier had no previous
        // trigger to compare against — the keyframes silently skipped.
        .overlay(alignment: .topTrailing) {
            Text("✨")
                .font(.system(size: 22))
                .modifier(CheerFloat(trigger: cheerNonce))
                .padding(.top, 26)
                .padding(.trailing, 36)
                .allowsHitTesting(false)
        }
    }

    private func petColumn(
        name: String,
        sprite: PetSprite,
        pillItems: [String],
        status: String,
        nonce: Int
    ) -> some View {
        VStack(spacing: 4) {
            HealthPill(items: pillItems)
            BreathingSprite {
                PixelPetSprite(sprite: sprite)
                    .frame(width: 64, height: 64)
            }
            .frame(width: 70, height: 70)
            .modifier(PokeShake(trigger: nonce))
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            Text(status)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(LCD.text)
        }
        .frame(width: 96)
    }

    // MARK: - Health compare

    /// 5-row table; "你" column is coral, "TA" is muted. Source values come
    /// straight from the mock — no live HealthKit binding.
    private var healthCompare: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("今日健康").compareHead(width: .leading)
                Text("你").compareHead(color: LP.Colors.coral)
                Text(friend.displayName).compareHead()
            }
            .padding(.vertical, 6)
            .overlay(LPDashedRule(dash: [3, 2]), alignment: .bottom)

            compareRow("步数", me: friend.myHealth.steps, other: friend.otherHealth.steps)
            compareRow("睡眠", me: friend.myHealth.sleep, other: friend.otherHealth.sleep)
            compareRow("心率", me: friend.myHealth.hr,    other: friend.otherHealth.hr)
            compareRow("卡路里", me: friend.myHealth.cal, other: friend.otherHealth.cal)
            compareRow("静息", me: friend.myHealth.rest,  other: friend.otherHealth.rest, last: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 2, y: 2)
        )
    }

    private func compareRow(_ label: String, me: String, other: String, last: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LP.Colors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(me)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(LP.Colors.coral)
                .frame(maxWidth: .infinity)
            Text(other)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(LP.Colors.ink)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7)
        .overlay(
            Group { if !last { LPDashedRule(dash: [3, 2]) } },
            alignment: .bottom
        )
    }

    // MARK: - Message thread

    /// Static thread + input row. New bubbles are appended in-place; SwiftUI's
    /// implicit `.animation(_, value:)` on the VStack handles the pop-in.
    private var messageThread: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("给 \(friend.displayName) 留言")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Spacer()
                Text(messages.last.map { "最近 · \($0.time)" } ?? "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                                .frame(maxWidth: .infinity, alignment: msg.who == .me ? .trailing : .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 154)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("说点什么…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LP.Colors.paperCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
                    )
                    .onSubmit(send)
                Button {
                    send()
                } label: {
                    Text("送出")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LP.Colors.paperCard)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LP.Colors.ink)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 2, y: 2)
        )
    }

    private var quickChips: some View {
        let chips = ["早安~ 今天慢跑加油", "记得喝水 💧", "想你了", "早点休息"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        draft = chip
                        send()
                    } label: {
                        Text(chip)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(LP.Colors.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous).fill(LP.Colors.paperCard)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(LP.Colors.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: poke) {
                Text("戳一下 \(friend.petName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.paperCard)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.ink)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LP.Colors.ink)
                            .offset(x: 2, y: 2)
                    )
            }
            .buttonStyle(.plain)
            Button(action: cheer) {
                Text("给 TA 加油")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.paperCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LP.Colors.ink)
                            .offset(x: 2, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let msg = TogetherMessage(who: .me, text: text, time: "刚刚")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            messages.append(msg)
        }
        draft = ""
        showToast("已送达 \(friend.petName)")
    }

    private func poke() {
        pokeNonce += 1
        showToast("戳了 \(friend.petName) 一下 👋")
    }

    private func cheer() {
        cheerNonce += 1
        showToast("已为 \(friend.petName) 加油 ✨")
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - Compare row helpers

private extension Text {
    func compareHead(width: HorizontalAlignment = .center, color: Color = LP.Colors.muted) -> some View {
        self
            .font(.system(size: 9, design: .monospaced))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: width == .leading ? .leading : .center)
    }
}

// MARK: - Health pill

/// Small dashed pill that floats above each pet on the twin stage. Three
/// short stats (steps / sleep / heart) — kept terse so two pills fit side-by-
/// side without clipping.
private struct HealthPill: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(LCD.text)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(Color(hex: 0xFFF4D6).opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(LCD.text, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        )
    }
}

// MARK: - Light band

/// Animated coral particle band drawn between the two pets. 4 dots loop
/// across the band on a 2.6s period. Drawn with `Canvas` + `TimelineView`
/// (same pattern as `BreathingSprite`) so we don't need a SwiftUI animation
/// driver per particle.
private struct LightBand: View {
    private let period: Double = 2.6
    private let particleCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            Canvas { gc, size in
                // Dashed midline.
                let mid = size.height / 2
                var line = Path()
                line.move(to: CGPoint(x: 8, y: mid))
                line.addLine(to: CGPoint(x: size.width - 8, y: mid))
                gc.stroke(
                    line,
                    with: .color(LP.Colors.coral.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )

                // Flowing dots.
                let now = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<particleCount {
                    let phase = ((now / period) + Double(i) / Double(particleCount))
                        .truncatingRemainder(dividingBy: 1.0)
                    let x = 8 + (size.width - 16) * phase
                    // Fade in/out at the band edges so dots don't pop.
                    let opacity: Double = {
                        if phase < 0.15 { return phase / 0.15 }
                        if phase > 0.85 { return (1.0 - phase) / 0.15 }
                        return 1.0
                    }()
                    let isCoral = i % 2 == 1
                    let color: Color = isCoral
                        ? LP.Colors.coral.opacity(opacity)
                        : Color(hex: 0xFFC847).opacity(opacity)
                    let r: CGFloat = isCoral ? 1.8 : 2.4
                    let yJitter: CGFloat = i == 3 ? -3 : 0   // matches lp4 in the prototype
                    let dot = Path(ellipseIn: CGRect(
                        x: x - r, y: mid - r + yJitter,
                        width: r * 2, height: r * 2
                    ))
                    gc.fill(dot, with: .color(color))
                }
            }
        }
    }
}

// MARK: - Animation modifiers

/// One-shot shake driven by `trigger`. Each integer tick replays the keyframe
/// sequence — uses SwiftUI 6's `.keyframeAnimator` so we don't have to chain
/// `withAnimation` blocks manually.
private struct PokeShake: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(
            initialValue: ShakeFrame(x: 0, y: 0),
            trigger: trigger
        ) { content, value in
            content.offset(x: value.x, y: value.y)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                LinearKeyframe(0, duration: 0.0)
                LinearKeyframe(-3, duration: 0.10)
                LinearKeyframe(3,  duration: 0.10)
                LinearKeyframe(-2, duration: 0.10)
                LinearKeyframe(2,  duration: 0.10)
                LinearKeyframe(0,  duration: 0.10)
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(0,  duration: 0.0)
                LinearKeyframe(-12, duration: 0.10)
                LinearKeyframe(0,  duration: 0.10)
                LinearKeyframe(-7, duration: 0.10)
                LinearKeyframe(0,  duration: 0.10)
                LinearKeyframe(-3, duration: 0.05)
                LinearKeyframe(0,  duration: 0.05)
            }
        }
    }
}

private struct ShakeFrame { var x: CGFloat; var y: CGFloat }

/// Cheer sparkle that floats up + fades out. Same `keyframeAnimator` driver
/// as `PokeShake` so the bubble disappears without lingering state.
private struct CheerFloat: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(
            initialValue: CheerFrame(y: 8, opacity: 0, scale: 0.5),
            trigger: trigger
        ) { content, value in
            content
                .scaleEffect(value.scale)
                .opacity(value.opacity)
                .offset(y: value.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                CubicKeyframe(8,   duration: 0.0)
                CubicKeyframe(-30, duration: 0.4)
                CubicKeyframe(-72, duration: 1.0)
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(0, duration: 0.0)
                CubicKeyframe(1, duration: 0.3)
                CubicKeyframe(1, duration: 0.6)
                CubicKeyframe(0, duration: 0.5)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.5, duration: 0.0)
                CubicKeyframe(1.1, duration: 0.4)
                CubicKeyframe(0.7, duration: 1.0)
            }
        }
    }
}

private struct CheerFrame { var y: CGFloat; var opacity: Double; var scale: CGFloat }

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: TogetherMessage

    private var isMe: Bool { message.who == .me }

    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
            Text(message.text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(isMe ? LP.Colors.paperCard : LP.Colors.ink)
            Text(message.time)
                .font(.system(size: 8, design: .monospaced))
                .opacity(0.65)
                .foregroundStyle(isMe ? LP.Colors.paperCard : LP.Colors.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isMe ? LP.Colors.coral : LCD.fill)
        )
        .frame(maxWidth: 240, alignment: isMe ? .trailing : .leading)
    }
}

#Preview {
    NavigationStack {
        FriendDetailView(friend: TogetherMock.friends[0])
            .environment(PetStateStore())
    }
    .preferredColorScheme(.light)
}
