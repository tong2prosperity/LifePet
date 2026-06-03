import SwiftUI

/// 上香 — fullscreen overlay shown when the user taps "🕯 上香" on a dead pet's
/// memorial section (`原型-02-图鉴.html` v0.8). Mirrors the HTML overlay:
/// label → 为 NAME → pixel incense + smoke → 15-sec 纪念曲 progress → 收香.
///
/// The 15-second timer auto-runs on appear; tapping 收香 (or the timer hitting
/// 0:15) closes the sheet. No real audio yet — the bar is a visual playback
/// stand-in until the V1 *纪念曲* generator lands.
struct CatalogIncenseOverlayView: View {
    let pet: CatalogPet

    @Environment(\.dismiss) private var dismiss
    @State private var elapsed: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var audio = MemorialAudioPlayer()

    private static let total = 15

    // Brand-internal palette for the overlay — deliberately *not* promoted to
    // LP.Colors. The dark, ember-toned scene is one-off; if a second screen
    // ever reuses it, lift it then.
    private static let bg        = Color(red: 0.04, green: 0.024, blue: 0.008, opacity: 0.96)
    private static let label     = Color(hex: 0x6A5030)
    private static let accent    = Color(hex: 0xE0C070)
    private static let trackBack = Color(red: 0.59, green: 0.43, blue: 0.20, opacity: 0.30)
    private static let trackFill = Color(hex: 0xC8903C)
    private static let frame     = Color(hex: 0x9A7840)

    var body: some View {
        ZStack {
            Self.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text(lp: "— 上 香 —")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(4)
                    .textCase(.uppercase)
                    .foregroundStyle(Self.label)
                    .padding(.bottom, 6)

                Text(AppLocalization.format("为 %@", pet.name))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Self.accent)
                    .padding(.bottom, 20)

                IncenseSprite()
                    .frame(width: 60, height: 165)
                    .clipped() // confine smoke to the 60×165 box, like HTML SVG's overflow:hidden
                    .padding(.bottom, 20)

                bgmBlock
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)

                Button(action: close) {
                    Text(lp: "收香")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Self.frame)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Self.frame.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            startTimer()
            audio.startRandom()
        }
        .onDisappear {
            stopTimer()
            audio.stop()
        }
    }

    // MARK: - BGM block

    private var bgmBlock: some View {
        VStack(spacing: 8) {
            Text(AppLocalization.text(pet.memorialTitle ?? "《纪念曲》"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Self.frame.opacity(0.95))

            CatalogMemorialWaveform(pet: pet, progress: progress)
                .opacity(0.55)
                .saturation(0.7)
                .brightness(0.18)
                .frame(height: 26)

            ZStack(alignment: .leading) {
                Capsule().fill(Self.trackBack).frame(height: 2)
                GeometryReader { geo in
                    Capsule()
                        .fill(Self.trackFill)
                        .frame(width: max(0, geo.size.width * progress), height: 2)
                }
                .frame(height: 2)
            }
            .frame(height: 2)

            HStack {
                Text(elapsedLabel)
                Spacer()
                Text("0:15")
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Self.label)
        }
    }

    private var progress: Double {
        Double(elapsed) / Double(Self.total)
    }

    private var elapsedLabel: String {
        if elapsed >= Self.total { return AppLocalization.text("✦ 完成") }
        let m = elapsed / 60
        let s = elapsed % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = 0
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled, elapsed < Self.total {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                elapsed = min(elapsed + 1, Self.total)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func close() {
        LPHaptics.tap()
        stopTimer()
        audio.stop()
        dismiss()
    }
}

// MARK: - Incense sprite

/// Pixel incense + holder + animated smoke + glowing tip. 60×165 grid mirroring
/// the SVG in the prototype. Smoke particles loop on a 3-second `TimelineView`,
/// each offset by a fixed delay; tip + ember alternate opacity on a 1.6s
/// `withAnimation` repeatForever loop.
private struct IncenseSprite: View {
    private static let unitW: CGFloat = 60
    private static let unitH: CGFloat = 165

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let ux = size.width / Self.unitW
            let uy = size.height / Self.unitH
            let unit = CGSize(width: ux, height: uy)

            // Stick ash (grey)
            fill(ctx, x: 29, y: 34, w: 2, h: 12, color: Color(hex: 0xB8B090), unit: unit)
            // Stick body (brown)
            fill(ctx, x: 29, y: 46, w: 2, h: 60, color: Color(hex: 0x8B6840), unit: unit)
            // Holder rim
            fill(ctx, x: 17, y: 106, w: 26, h: 2, color: Color(hex: 0x7A6040), unit: unit)
            // Holder upper band
            fill(ctx, x: 18, y: 108, w: 24, h: 2, color: Color(hex: 0x8B7050), unit: unit)
            // Holder body
            fill(ctx, x: 20, y: 110, w: 20, h: 12, color: Color(hex: 0x6B5030), unit: unit)
            // Bottom strip
            fill(ctx, x: 17, y: 122, w: 26, h: 3, color: Color(hex: 0x4A3020), unit: unit)
            // Feet
            fill(ctx, x: 20, y: 125, w: 5, h: 4, color: Color(hex: 0x3A2010), unit: unit)
            fill(ctx, x: 35, y: 125, w: 5, h: 4, color: Color(hex: 0x3A2010), unit: unit)
            // Decorative bands
            fill(ctx, x: 21, y: 114, w: 18, h: 1, color: Color(hex: 0x9A8060).opacity(0.7), unit: unit)
            fill(ctx, x: 21, y: 118, w: 18, h: 1, color: Color(hex: 0x9A8060).opacity(0.7), unit: unit)
            // Sand (where stick sits)
            fill(ctx, x: 27, y: 108, w: 6, h: 4, color: Color(hex: 0xC8B888).opacity(0.6), unit: unit)
        }
        .overlay(GlowingTip())
        .overlay(SmokeStream())
        .accessibilityHidden(true)
    }

    private func fill(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, unit: CGSize) {
        let rect = CGRect(x: x * unit.width, y: y * unit.height, width: w * unit.width, height: h * unit.height)
        ctx.fill(Path(rect), with: .color(color))
    }
}

// MARK: - Glowing tip

private struct GlowingTip: View {
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let ux = geo.size.width / 60
            let uy = geo.size.height / 165
            ZStack {
                // Ember halo (28,26 / 4×5)
                Rectangle()
                    .fill(Color(hex: 0xC83828))
                    .frame(width: 4 * ux, height: 5 * uy)
                    .position(x: (28 + 2) * ux, y: (26 + 2.5) * uy)
                    .opacity(pulse ? 0.3 : 1.0)

                // Hot core (29,23 / 2×4) — phase-shifted by 0.4s
                Rectangle()
                    .fill(Color(hex: 0xFF8028))
                    .frame(width: 2 * ux, height: 4 * uy)
                    .position(x: (29 + 1) * ux, y: (23 + 2) * uy)
                    .opacity(pulse ? 1.0 : 0.3)
            }
            .onAppear {
                // 0.8s half-cycle × autoreverse → 1.6s full cycle, matching the
                // HTML @keyframes tipGlow (0% → 50% → 100% in 1.6s).
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Smoke stream

/// Four staggered smoke particles rising from above the stick tip. Uses a
/// `TimelineView` so all particles share one clock — the offsets fall out of
/// the modulo math instead of needing per-particle state.
private struct SmokeStream: View {
    /// (origin x, origin y, radius, base alpha, delay-seconds).
    /// Base alpha mirrors the SVG's per-particle `rgba(...,a)` literal; the
    /// envelope below applies the keyframe opacity multiplicatively, just like
    /// CSS does (final alpha = base × envelope).
    private static let particles: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        (30, 18, 2.5, 0.7, 0.0),
        (27, 16, 3.5, 0.5, 0.9),
        (33, 20, 2.0, 0.6, 1.8),
        (29, 14, 3.0, 0.4, 2.5),
    ]

    private static let cycle: Double = 3.0
    private static let smokeColor = Color(red: 200/255, green: 175/255, blue: 130/255)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            GeometryReader { geo in
                let ux = geo.size.width / 60
                let uy = geo.size.height / 165
                let now = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<Self.particles.count, id: \.self) { i in
                        let (x, y, r, base, delay) = Self.particles[i]
                        let t = ((now - delay).truncatingRemainder(dividingBy: Self.cycle) + Self.cycle)
                            .truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
                        let dy = -65.0 * t
                        let dx = drift(at: t)
                        Circle()
                            .fill(Self.smokeColor.opacity(base * envelope(at: t)))
                            .frame(width: r * 2 * ux, height: r * 2 * uy)
                            .position(x: x * ux + CGFloat(dx) * ux,
                                      y: y * uy + CGFloat(dy) * uy)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Lateral wobble matching the HTML keyframes: +4px around 30%, then -3px
    /// around 65%, lands near origin.
    private func drift(at t: Double) -> Double {
        switch t {
        case 0..<0.3:    return 4 * (t / 0.3)
        case 0.3..<0.65: return 4 - 7 * ((t - 0.3) / 0.35)
        case 0.65..<1.0: return -3 + 4 * ((t - 0.65) / 0.35)
        default: return 0
        }
    }

    /// Multiplicative opacity envelope from the HTML @keyframes:
    /// 0% → 0.8, 30% → 0.5, 65% → 0.2, 100% → 0.
    private func envelope(at t: Double) -> Double {
        switch t {
        case 0..<0.3:    return lerp(0.8, 0.5, t / 0.3)
        case 0.3..<0.65: return lerp(0.5, 0.2, (t - 0.3) / 0.35)
        case 0.65..<1.0: return lerp(0.2, 0.0, (t - 0.65) / 0.35)
        default: return 0
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

#Preview {
    CatalogIncenseOverlayView(pet: .blob)
        .preferredColorScheme(.light)
}
