import SwiftUI

/// "今日步骤" block: heading + sub copy + step card list.
/// Done cards have a green tint; suggest cards a warm orange tint with a
/// dashed border and ✅ / ❌ mini-buttons.
struct StepsSectionView: View {
    let store: PetStateStore

    private static let doneBg    = Color(hex: 0xEEF5E8)
    private static let suggestBg = Color(hex: 0xFEF4E6)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            subline
                .padding(.top, 4)
                .padding(.bottom, 10)
            VStack(spacing: 7) {
                ForEach(store.steps) { step in
                    StepCardView(
                        step: step,
                        doneBg: Self.doneBg,
                        suggestBg: Self.suggestBg,
                        onDone: { store.markDone(step.id) },
                        onQuit: { store.quit(step.id) }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.32), value: store.steps)
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Text("今日步骤")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("\(store.doneCount) 已完成 · \(store.suggestCount) 建议")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            LPDashedRule(dash: [4, 3])
        }
    }

    private var subline: some View {
        // Emojis render as colored glyphs — no `foregroundStyle` here.
        Text("打 ✅ 它开心，打 ❌ 不扣分 —— 但它会记住，下次少推。")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(LP.Colors.muted)
            .padding(.leading, 2)
    }
}

// MARK: - Step card

private struct StepCardView: View {
    let step: StepItem
    let doneBg: Color
    let suggestBg: Color
    let onDone: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            flag
            VStack(alignment: .leading, spacing: 2) {
                title
                result
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .lpStampedCard(
            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
            fill: step.status == .done ? doneBg : suggestBg,
            dashed: step.status == .suggest
        )
        .overlay(autoTagOverlay, alignment: .topTrailing)
    }

    private var flag: some View {
        Text(step.status == .done ? "✅" : "🎯")
            .font(.system(size: 16))
    }

    private var title: some View {
        HStack(spacing: 0) {
            Text(step.displayTitleLead)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            Text(" ")
            Text(step.titleValue)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.coral)
        }
    }

    @ViewBuilder
    private var result: some View {
        let prefix = step.status == .done ? "→ " : "可获得 "
        HStack(spacing: 0) {
            Text(prefix)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            Text("+\(step.gain)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(step.status == .done ? LP.Colors.ink : Color(hex: 0x7A6530))
            Text(" \(step.affects.label)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch step.status {
        case .done:
            Text(step.time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(LP.Colors.faint)
        case .suggest:
            HStack(spacing: 5) {
                MiniButton(symbol: "✅", fill: Color(hex: 0xD3EBD5), action: onDone)
                MiniButton(symbol: "❌", fill: Color(hex: 0xEBEBEB), action: onQuit)
            }
        }
    }

    @ViewBuilder
    private var autoTagOverlay: some View {
        if step.fromAutoSensor && step.status == .done {
            Text("⚡ 手表自动")
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
                .tracking(0.3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LP.Colors.paperCool)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(LP.Colors.hairline, lineWidth: 1)
                )
                .padding(.top, 4)
                .padding(.trailing, 8)
        }
    }

}

// MARK: - Mini square buttons

private struct MiniButton: View {
    let symbol: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LP.Colors.ink)
                    .offset(x: 2, y: 2)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(LP.Colors.ink, lineWidth: 1.5)
                Text(symbol)
                    .font(.system(size: 12))
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}
