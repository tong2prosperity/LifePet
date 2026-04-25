import SwiftUI

/// Marker for `NavigationStack`'s typed routing — `TogetherView` registers a
/// `navigationDestination(for: InviteRoute.self)` that maps this to
/// `InviteView`. An empty struct is enough; the value carries no payload.
struct InviteRoute: Hashable {}

/// 邀请页 — pushed from the friends list "+ 添加" button. Mirrors
/// `viewInvite` in `原型-03-一起.html` v0.9.1.
///
/// Sections (top → bottom):
/// 1. Custom back row (system nav bar is hidden, same convention as
///    `FriendDetailView`).
/// 2. Hero card — title + subtitle + invite-code box + 复制 / 分享 actions.
/// 3. "—— 或 ——" divider.
/// 4. Scan affordances — 扫码加入对方 / 输入对方邀请码 (placeholder buttons).
/// 5. Relation chips — 6 chips, single-select, purely cosmetic on tap.
///
/// All actions are mock — copy / share / scan / chip-select all surface a
/// short toast; nothing leaves the device. Real invite-code generation +
/// pairing handshake is V1 work.
struct InviteView: View {
    @Environment(\.dismiss) private var dismiss

    /// Static demo code. Hand-picked so it resembles the prototype's
    /// `FISH-7K2` shape: 4-letter handle + dash + 3-char nonce.
    private let inviteCode = "FISH-7K2"

    @State private var selectedRelation: String? = nil
    @State private var toast: String? = nil

    private let relations = ["伴侣", "妈妈", "爸爸", "挚友", "同学", "+ 自定义"]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                    backRow
                    heroCard
                    orDivider
                    scanRow
                    relationSection
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

    // MARK: - Hero card

    /// Stamped paper card — title, subtitle, invite-code box, two action
    /// buttons (复制 = secondary, 分享 = primary). Centered text matches the
    /// prototype's `.invite-card` block.
    private var heroCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("邀请 TA 加入")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text("— 创建你们的双人空间 —")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(LP.Colors.muted)
            }

            // — Invite code box: dashed LCD-tinted box, big monospace —
            Text(inviteCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(LP.Colors.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LCD.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LP.Colors.ink, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                )

            HStack(spacing: 8) {
                inviteAction("复制", primary: false, action: copyCode)
                inviteAction("分享", primary: true,  action: shareCode)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LP.Colors.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 3, y: 3)
        )
    }

    // MARK: - "或" divider

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LP.Colors.muted.opacity(0.5)).frame(height: 1)
            Text("或")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(LP.Colors.muted)
            Rectangle().fill(LP.Colors.muted.opacity(0.5)).frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Scan row

    private var scanRow: some View {
        VStack(spacing: 8) {
            inviteAction("扫码加入对方", primary: false, fullWidth: true) {
                showToast("扫码功能即将上线")
            }
            inviteAction("输入对方邀请码", primary: false, fullWidth: true) {
                showToast("输入对方邀请码 · 即将上线")
            }
        }
    }

    // MARK: - Relation chips

    /// 6 chips, single-select. Tapping toggles `selectedRelation`; the active
    /// chip flips to coral fill. The "+ 自定义" chip behaves like the others
    /// for now — no inline rename UI yet.
    private var relationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关系昵称")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            FlowLayout(spacing: 6) {
                ForEach(relations, id: \.self) { rel in
                    relationChip(rel)
                }
            }
        }
    }

    private func relationChip(_ name: String) -> some View {
        let isActive = selectedRelation == name
        return Button {
            selectedRelation = isActive ? nil : name
        } label: {
            Text(name)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(isActive ? LP.Colors.paperCard : LP.Colors.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous).fill(isActive ? LP.Colors.coral : LP.Colors.paperCard)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isActive ? LP.Colors.coral : LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action button

    /// Shared button used for hero actions + scan placeholders. `primary`
    /// flips to ink-fill; `fullWidth` lets the scan row stretch each option
    /// to fill its line, matching the prototype's stacked layout.
    private func inviteAction(_ title: String, primary: Bool, fullWidth: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(primary ? LP.Colors.paperCard : LP.Colors.ink)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minWidth: fullWidth ? nil : 90)
                .padding(.horizontal, fullWidth ? 0 : 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primary ? LP.Colors.ink : LP.Colors.paperCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LP.Colors.ink)
                        .offset(x: 2, y: 2)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    // MARK: - Actions

    private func copyCode() {
        UIPasteboard.general.string = inviteCode
        showToast("已复制 \(inviteCode)")
    }

    private func shareCode() {
        showToast("已生成分享卡")
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - FlowLayout

/// Minimal flow layout for the relation chips — wraps children into multiple
/// rows when the line fills up. Built on `Layout` so we don't have to fake it
/// with `LazyVGrid` (which forces equal-width columns) or pre-measure widths.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.map(\.height).reduce(0, +) + max(0, CGFloat(rows.count - 1)) * spacing
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, usedWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (idx, size) in row.items {
                subviews[idx].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(idx: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (idx, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let candidateWidth = rows[rows.count - 1].width
                + (rows[rows.count - 1].items.isEmpty ? 0 : spacing)
                + size.width
            if candidateWidth > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var current = rows[rows.count - 1]
            if !current.items.isEmpty { current.width += spacing }
            current.width += size.width
            current.height = max(current.height, size.height)
            current.items.append((idx, size))
            rows[rows.count - 1] = current
        }
        return rows
    }
}

#Preview {
    NavigationStack {
        InviteView()
    }
    .preferredColorScheme(.light)
}
