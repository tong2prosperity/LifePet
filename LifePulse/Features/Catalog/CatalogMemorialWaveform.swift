import SwiftUI

/// 《纪念曲》波形条 — one bar per day of the pet's life, height = average of
/// 三状态 that day, color biased by which stat dominated:
/// - 心情 主导 → coral
/// - 精力 主导 → tan-ish kraft tone
/// - 体力 主导 → ink
///
/// Just a visual; the "playback" track + button are static. Generating actual
/// audio (the PRD §11 *纪念曲* feature) is V1 work and lives in `Generation/`.
struct CatalogMemorialWaveform: View {
    let pet: CatalogPet
    /// Coral-tinted progress (0…1). Only sets the colored cursor — no real
    /// audio playback yet, so the parent decides when this advances.
    var progress: Double = 0.18

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            // Bound the bar count by the *shortest* of the three series so we
            // can safely index all three at any `i`. The dataset should keep
            // them aligned, but a future mismatch shouldn't crash the screen.
            let n = min(pet.series.vitality.count,
                        min(pet.series.energy.count, pet.series.mood.count))
            guard n > 0 else { return }
            let barW = size.width / CGFloat(n)
            let gap = min(1.5, barW * 0.2)
            let h = size.height
            let cursorX = size.width * CGFloat(progress)

            // Baseline.
            var base = Path()
            base.move(to: CGPoint(x: 0, y: h - 1))
            base.addLine(to: CGPoint(x: size.width, y: h - 1))
            ctx.stroke(base, with: .color(LP.Colors.muted.opacity(0.5)), lineWidth: 0.5)

            for i in 0..<n {
                let avg = (pet.series.vitality[i] + pet.series.energy[i] + pet.series.mood[i]) / 3
                let barH = max(3, CGFloat(avg) / 100 * (h - 6))
                let x = CGFloat(i) * barW + gap / 2
                let y = h - barH - 1
                let rect = CGRect(x: x, y: y, width: max(0.5, barW - gap), height: barH)
                let color = barColor(at: i, played: x < cursorX)
                ctx.fill(Path(rect), with: .color(color.opacity(0.9)))
            }

            // Playhead cursor.
            var cursor = Path()
            cursor.move(to: CGPoint(x: cursorX, y: 0))
            cursor.addLine(to: CGPoint(x: cursorX, y: h))
            ctx.stroke(cursor, with: .color(LP.Colors.coral), lineWidth: 1)
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    private func barColor(at i: Int, played: Bool) -> Color {
        let v = pet.series.vitality[i]
        let e = pet.series.energy[i]
        let m = pet.series.mood[i]
        let dominant: Color
        if m >= v && m >= e {
            dominant = LP.Colors.coral
        } else if e >= v {
            dominant = LP.Colors.muted
        } else {
            dominant = LP.Colors.ink
        }
        // Faded after the playhead so the "played" portion reads.
        return played ? dominant : dominant.opacity(0.55)
    }
}

#Preview {
    VStack(spacing: 12) {
        CatalogMemorialWaveform(pet: .blob, progress: 0.45)
        CatalogMemorialWaveform(pet: .noct, progress: 0.18)
        CatalogMemorialWaveform(pet: .hush, progress: 0.85)
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}
