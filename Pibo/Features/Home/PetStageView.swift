import SwiftUI

/// LCD-style stage hosting the active pet sprite. Custom (non-LP) tan tone —
/// the LCD surface in the prototype is unique to this screen, so the literal
/// lives here rather than polluting `LP.Colors` with a one-use token.
///
/// The sprite layer has three modes:
/// - **Hatch · waiting** (`isHatching && !hatchPlaying`): renders a static
///   `egg_hatch/frame_00` with a breathing pulse + "戳一下" hint. Tapping the
///   stage flips `hatchPlaying` and starts the animation. Without this gate
///   the 1.25 s hatch animation flies by during the auth-dialog dismissal
///   and the user never sees it.
/// - **Hatch · playing** (`isHatching && hatchPlaying`): runs the
///   `egg_hatch` one-shot and fires `onHatchCompleted` at the end. Caller
///   flips `isHatching` to false on the callback so the next render shows
///   the live pet.
/// - **Idle** (`!isHatching`): maps `state` → a looped `SpriteSequence` via
///   `SpriteCatalog`. Sparkles overlay when state warrants
///   (excited/blissful) or `bursting`.
struct PetStageView: View {
    let petName: String
    let dayCount: Int
    let state: PetState
    /// EndDate of the latest workout, forwarded to `SpriteCatalog.idle`.
    /// Drives the "刚刚运动 → run animation" override on `.normal` state.
    /// `nil` → no recent workout known; the catalog falls back to
    /// time-of-day mapping.
    var lastWorkoutAt: Date? = nil
    /// One-shot "data just landed" overlay — drives the sparkle layer for
    /// ~1.6s after a HealthKit push, even when the pet's base state isn't
    /// `.excited`. Independent of `state.showsSparkles`.
    var bursting: Bool = false
    /// Bumped each time the user taps 「喂养」 (i.e. `feedToken` flipped on
    /// `PetStateStore`). A change runs a 0.45s shake on the sprite — translates
    /// the prototype's `tap-vibrate` keyframe. `nil` → no shake.
    var vibrateToken: UUID? = nil
    /// `true` → render the egg (waiting or playing) instead of the idle
    /// sprite. Caller is responsible for flipping it false on
    /// `onHatchCompleted`.
    var isHatching: Bool = false
    var onHatchCompleted: (() -> Void)? = nil
    var onPetTapped: (() -> Void)? = nil

    /// Local two-stage gate inside the hatch path. `false` = static egg +
    /// tap hint; `true` = `egg_hatch` animation playing. Defaults to `false`
    /// on every fresh mount, so a user who killed the app mid-animation
    /// (before `hatched = true` got persisted) gets another chance to tap.
    @State private var hatchPlaying: Bool = false
    /// Drives the shake animation off `vibrateToken`. Each token bump steps
    /// `shakePhase` 0 → 1 across 0.45s; the modifier maps that to translate +
    /// rotation keyframes. Held in @State so the spring animation lives on
    /// this view's identity, not the parent's.
    @State private var shakePhase: CGFloat = 0

    private static let lcd        = Color(hex: 0xEBE3CC)
    private static let lcdDash    = Color(hex: 0xBFB89F)
    private static let lcdInk     = Color(hex: 0x7D7657)

    var body: some View {
        ZStack {
            // — LCD surface —
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Self.lcd)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: 2)
                )
            // — Inset dashed border —
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Self.lcdDash,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .padding(5)

            // — Corner labels —
            corners

            // — Pet sprite + (state-or-burst-driven) sparkles —
            ZStack {
                if isHatching {
                    if hatchPlaying {
                        AnimatedSprite(sequence: .eggHatch, onCompleted: onHatchCompleted)
                    } else {
                        eggWaiting
                    }
                } else {
                    AnimatedSprite(sequence: SpriteCatalog.idle(for: state, lastWorkoutAt: lastWorkoutAt))
                    if state.showsSparkles || bursting {
                        SparkleField()
                    }
                }
            }
            .frame(width: 160, height: 160)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHatching else { return }
                onPetTapped?()
            }
            .modifier(ShakeOnFeed(phase: shakePhase))
            // Publish the sprite's center as a preference so HomeView can aim
            // energy particles at it. `.center` resolves to the midpoint of the
            // 160×160 frame in this view's coord space; HomeView converts to
            // global via `.overlayPreferenceValue + GeometryProxy`.
            .anchorPreference(key: PetCenterAnchorKey.self, value: .center) { $0 }
        }
        .frame(height: 208)
        .onChange(of: vibrateToken) { _, new in
            // 不论 token 来自哪一次喂养，都从 0 跳到 1，由动画自己回到 0。
            // 用 .interactiveSpring + 二段动画拼出 "弹跳一下又回正" 的效果，
            // 让最终值仍然停在 0，下次喂养再次从 0 → 1。
            guard new != nil else { return }
            shakePhase = 0
            withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
                shakePhase = 1
            }
            Task {
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(.easeOut(duration: 0.12)) {
                    shakePhase = 0
                }
            }
        }
    }

    /// Closed egg sitting on the LCD, breathing slowly + a pulsing
    /// "戳一下 →" hint underneath. The whole 160 × 160 frame is tappable
    /// (`contentShape(Rectangle())`), so users don't have to land precisely
    /// on the egg pixels.
    private var eggWaiting: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 1.0 + sin(t * 2.4) * 0.04             // 0.96 ~ 1.04 scale
            let tilt  = sin(t * 1.6) * 3.0                    // -3° ~ +3° wobble
            let alpha = 0.55 + 0.45 * (sin(t * 2.0) + 1) / 2  // 0.55 ~ 1.00

            VStack(spacing: 8) {
                Image(SpriteSequence.eggHatch.assetName(at: 0))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse)
                    .rotationEffect(.degrees(tilt))
                Text("戳一下 →")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Self.lcdInk)
                    .opacity(alpha)
            }
        }
        .frame(width: 160, height: 160)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { hatchPlaying = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("点击让蛋孵化")
    }

    private var corners: some View {
        ZStack {
            cornerLabel("\(petName) ○",        alignment: .topLeading)
            cornerLabel(String(format: "D%02d", dayCount), alignment: .topTrailing)
            cornerLabel(isHatching ? "EGG" : state.tag, alignment: .bottomLeading)
            cornerLabel("♪ ♫ ♪",               alignment: .bottomTrailing)
        }
        .padding(10)
    }

    private func cornerLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Self.lcdInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Pet-center anchor preference

/// Carries the resolved sprite-center anchor up to `HomeView` so the energy
/// particle layer can target the pet. `nil` until the pet renders (e.g. during
/// the egg waiting state — particles wouldn't fire then anyway, since the
/// hatch flow runs before any HK ingest could land).
///
/// Single-emit semantics: the reduce just keeps the latest, since at most one
/// `PetStageView` is on screen at a time.
struct PetCenterAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - Shake-on-feed

/// Translates the prototype's `tap-vibrate` keyframe into a SwiftUI modifier:
/// scale up ~6%, wobble x±3, rotate ±4°. `phase` ∈ [0, 1] is animated by the
/// caller so we can ride a spring instead of CSS keyframes.
private struct ShakeOnFeed: AnimatableModifier {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        // Map [0, 1] → small oscillation. Two cycles, decaying amplitude.
        let damp = 1.0 - phase                          // 1 → 0 over the throw
        let xWobble = sin(phase * .pi * 4) * 3 * damp   // ±3pt, ~2 cycles
        let rotate = cos(phase * .pi * 4) * 4 * damp    // ±4°, ~2 cycles
        let lift = 1.0 + 0.06 * phase * (1 - phase) * 4 // peaks ~1.06 mid-throw
        return content
            .scaleEffect(lift)
            .rotationEffect(.degrees(rotate))
            .offset(x: xWobble)
    }
}

// MARK: - Sparkle particles

/// Three drifting coral glyphs around the pet — same offsets / lift / fade
/// curve as the prototype's CSS keyframe. Driven by a small TimelineView so
/// we don't bother the AnimatedSprite's own clock.
private struct SparkleField: View {
    private let sparklePeriod: Double = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                sparkle("★", phase: t / sparklePeriod, offset: 0.00, pos: .init(x: -48, y: -48))
                sparkle("✦", phase: t / sparklePeriod, offset: 0.30, pos: .init(x:  44, y: -35))
                sparkle("✧", phase: t / sparklePeriod, offset: 0.60, pos: .init(x:   8, y: -64))
            }
        }
    }

    private func sparkle(_ glyph: String, phase: Double, offset: Double, pos: CGPoint) -> some View {
        let local = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        // Float up by 30pt, rotate -10° → 20°, fade in/out.
        let yLift  = -30.0 * local
        let angle  = -10.0 + 30.0 * local
        let opacity: Double = {
            if local < 0.25 { return local / 0.25 }
            else            { return max(0, 1 - (local - 0.25) / 0.75) }
        }()
        return Text(glyph)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(LP.Colors.coral)
            .opacity(opacity)
            .rotationEffect(.degrees(angle))
            .offset(x: pos.x, y: pos.y + yLift)
    }
}

#Preview("Idle · excited") {
    PetStageView(petName: "BEAN", dayCount: 7, state: .excited)
        .padding(LP.Spacing.s4)
        .lpPaper(.app)
}

#Preview("Hatching") {
    PetStageView(
        petName: "BEAN", dayCount: 0, state: .normal,
        isHatching: true, onHatchCompleted: { print("hatched") }
    )
    .padding(LP.Spacing.s4)
    .lpPaper(.app)
}
