import SwiftUI

/// Sprite identity for the 图鉴 — each pet has a distinct 16×16 silhouette
/// matching the SVGs in `原型-02-图鉴.html`. The home-screen `PixelPet` is the
/// 20-grid "live" pet rendered with sparkles; this 16-grid sprite is for the
/// smaller catalog cards / share card / past-pet portraits.
enum PetSprite: String, Hashable {
    case bean, blob, noct, hush
}

/// Renders a 16×16 pixel pet, keyed by `PetSprite`. The art lives as small
/// pixel-rect tables — eyes/accent layers reuse `LP.Colors.paperCool` and
/// `LP.Colors.coral` so a future palette tweak propagates without re-keying.
struct PixelPetSprite: View {
    let sprite: PetSprite
    /// Optional override for the body color — used by `.locked` placeholders
    /// in the catalog grid (rendered as gray silhouettes).
    var bodyColor: Color = LP.Colors.ink

    private static let grid: CGFloat = 16

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let unit = min(size.width, size.height) / Self.grid
            for r in bodyRects { ctx.fill(rect(r, unit: unit), with: .color(bodyColor)) }
            for r in eyes      { ctx.fill(rect(r, unit: unit), with: .color(LP.Colors.paperCool)) }
            for r in accent    { ctx.fill(rect(r, unit: unit), with: .color(LP.Colors.coral)) }
        }
        .accessibilityHidden(true)
    }

    private func rect(_ r: PixelRect, unit: CGFloat) -> Path {
        Path(CGRect(
            x: CGFloat(r.x) * unit,
            y: CGFloat(r.y) * unit,
            width:  CGFloat(r.w) * unit,
            height: CGFloat(r.h) * unit
        ))
    }

    // MARK: - Per-sprite rect tables

    private struct PixelRect { let x, y, w, h: Int }

    private var bodyRects: [PixelRect] {
        switch sprite {
        case .bean: return [
            .init(x: 5, y: 0, w: 6, h: 1),
            .init(x: 4, y: 1, w: 8, h: 12),
            .init(x: 4, y: 13, w: 2, h: 3),
            .init(x: 10, y: 13, w: 2, h: 3),
        ]
        case .blob: return [
            .init(x: 5, y: 1, w: 6, h: 1),
            .init(x: 3, y: 2, w: 10, h: 1),
            .init(x: 2, y: 3, w: 12, h: 9),
            .init(x: 3, y: 12, w: 10, h: 1),
            .init(x: 4, y: 13, w: 2, h: 2),
            .init(x: 10, y: 13, w: 2, h: 2),
        ]
        case .noct: return [
            .init(x: 3, y: 2, w: 2, h: 2),
            .init(x: 11, y: 2, w: 2, h: 2),
            .init(x: 5, y: 1, w: 6, h: 1),
            .init(x: 3, y: 2, w: 10, h: 1),
            .init(x: 2, y: 3, w: 12, h: 10),
            .init(x: 3, y: 13, w: 10, h: 1),
            .init(x: 4, y: 14, w: 2, h: 2),
            .init(x: 10, y: 14, w: 2, h: 2),
        ]
        case .hush: return [
            .init(x: 7, y: 1, w: 2, h: 1),
            .init(x: 6, y: 2, w: 4, h: 1),
            .init(x: 5, y: 3, w: 6, h: 1),
            .init(x: 4, y: 4, w: 8, h: 8),
            .init(x: 5, y: 12, w: 6, h: 1),
            .init(x: 6, y: 13, w: 4, h: 1),
        ]
        }
    }

    private var eyes: [PixelRect] {
        switch sprite {
        case .bean: return [.init(x: 6, y: 5, w: 1, h: 1), .init(x: 9, y: 5, w: 1, h: 1)]
        case .blob: return [.init(x: 5, y: 6, w: 1, h: 1), .init(x: 10, y: 6, w: 1, h: 1)]
        case .noct: return [.init(x: 5, y: 7, w: 1, h: 1), .init(x: 10, y: 7, w: 1, h: 1)]
        case .hush: return [.init(x: 6, y: 7, w: 1, h: 1), .init(x: 9, y: 7, w: 1, h: 1)]
        }
    }

    private var accent: [PixelRect] {
        switch sprite {
        case .bean: return [.init(x: 7, y: 7, w: 2, h: 1)]
        case .blob: return [.init(x: 7, y: 8, w: 2, h: 1)]
        case .noct, .hush: return []   // sleeping / mute pets — no tongue
        }
    }
}

/// Locked-slot placeholder used in the past-grid: a faint rounded square with
/// a "?". Fills its parent frame so it sizes alongside `PixelPetSprite` cards.
struct PixelPetLockedSprite: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                    .fill(LP.Colors.muted)
                Text("?")
                    .font(.system(size: side * 0.45, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LP.Colors.paperCool)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(0.35)
        .accessibilityHidden(true)
    }
}

/// Time-driven breathe animation for the LCD-mounted sprites — ½-period
/// upward drift + tiny vertical squash, matching the prototype's `breathe`
/// keyframe (2.6s loop). Use it on the live card and the detail hero; cards
/// in the past grid should stay still (they're "stopped clocks").
struct BreathingSprite<Content: View>: View {
    let period: Double
    @ViewBuilder let content: () -> Content

    init(period: Double = 2.6, @ViewBuilder content: @escaping () -> Content) {
        self.period = period
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: period)) / period
            let s = sin(phase * .pi * 2)            // -1 … 1
            let yLift  = -3 * 0.5 * (1 - cos(phase * .pi * 2))   // 0 → -3 → 0 over period
            let scaleY = 1.0 - 0.015 * CGFloat(s)   // 1 ± 0.015
            content()
                .scaleEffect(x: 1.0, y: scaleY, anchor: .bottom)
                .offset(y: yLift)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        PixelPetSprite(sprite: .bean).frame(width: 60, height: 60)
        PixelPetSprite(sprite: .blob).frame(width: 60, height: 60)
        PixelPetSprite(sprite: .noct).frame(width: 60, height: 60)
        PixelPetSprite(sprite: .hush).frame(width: 60, height: 60)
        PixelPetLockedSprite()
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}
