import SwiftUI

/// The home affordance through which Pibo "布置" the walk-doodle task (home spec
/// lineage: Pibo 在主界面给用户布置任务). A compact card floating just above the
/// 餐食相机 — accent doodle glyph, the 「Pibo 的任务」 label and a procedural
/// route prompt. Tapping opens `WalkDoodleView` full-screen.
///
/// Styled as a solid white card (`bgContainer` + elevation2), like the 相机 disc,
/// so it stays legible over any themed stage.
struct WalkDoodleTaskCard: View {
    var action: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: LP.Spacing.m) {
                glyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("Pibo 的任务"))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.tertiary)
                    Text(AppLocalization.text("散步涂鸦"))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                    Text(AppLocalization.text("按 Pibo 的任务走出一个形状"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LP.Content.quarternary)
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair))
            .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("Pibo 的任务：散步涂鸦"))
    }

    private var glyph: some View {
        Image(systemName: "scribble.variable")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(LP.Fill.foundationOnAccent)
            .frame(width: 40, height: 40)
            .background(Circle().fill(LP.Fill.foundationAccent))
    }
}

#Preview {
    WalkDoodleTaskCard(action: {})
        .padding()
        .background(LP.Fill.bgSurfaceSecondary)
}
