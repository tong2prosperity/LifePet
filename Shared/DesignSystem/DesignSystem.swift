import SwiftUI

/// Pibo Design System v1.0 — shared between iOS and watchOS.
///
/// Call sites read as `LP.Colors.coral`, `LP.Spacing.s4`, `LP.Radius.card`,
/// `LP.Typography.serifH2`, etc. Components live as top-level `LPButton`,
/// `LPPill`, etc. so they can be used directly in SwiftUI bodies.
///
/// Platform split is handled **inside** each token/component — callers never
/// write `#if os(iOS)`:
/// - Token values (Colors, Radius, BorderWidth, Shadow specs) are identical
///   on both platforms.
/// - `LP.Spacing` raw values are identical; its semantic aliases
///   (`cardPadding`, `blockGap`, `sectionGap`, `screenMargin`) return tighter
///   values on watchOS.
/// - `LP.Typography` sizes scale piecewise on watchOS — display/h1/h2 compress
///   hardest, tiny mono labels floor at 9pt.
/// - `lpShadow(_:)` is a no-op on watchOS.
/// - `LPStamp` renders as `EmptyView` on watchOS.
/// - `LPStickyNote` rotates on iOS and stays flat on watchOS.
enum LP {}

// MARK: - Kitchen-sink preview

#Preview("LP · Kitchen sink") {
    ScrollView {
        VStack(alignment: .leading, spacing: LP.Spacing.s5) {
            Text("Pibo").lpText(LP.Typography.display)
            Text("DESIGN · SYSTEM · v1.0")
                .lpText(LP.Typography.monoLabel).foregroundStyle(LP.Colors.muted)

            LPCard(.coral, label: "RIGHT NOW", title: "它有点不舒服") {
                LPSpeechBubble("我有点不舒服……", tone: .urgent)
            }

            LPCard(label: "SLEEP · LAST NIGHT", title: "7h 12m") {
                VStack(alignment: .leading, spacing: LP.Spacing.s3) {
                    LPStatBar(label: "SLEEP",    valueText: "72", progress: 0.72, variant: .sage)
                    LPStatBar(label: "ACTIVITY", valueText: "48", progress: 0.48, variant: .coral)
                    LPStatBar(label: "COMPANY",  valueText: "34", progress: 0.34, variant: .striped)
                }
            }

            HStack(spacing: LP.Spacing.s2) {
                LPPill("P0",   variant: .coral)
                LPPill("V1.0", variant: .sage)
                LPPill("V1.1", variant: .ghost)
            }

            LPStickyNote("它在窗边看了你三次。", tilt: .left)

            HStack(spacing: LP.Spacing.s2) {
                LPButton("PRIMARY",   variant: .primary)   {}
                LPButton("SECONDARY", variant: .secondary) {}
            }
        }
        .padding(LP.Spacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .lpPaper(.app)
}
