import SwiftUI

/// 一起 — third tab. Translates `原型-03-一起.html` v0.9.1 into SwiftUI on top
/// of the LP design system. Two sub-views, switched by a top segmented header:
///
/// 1. **朋友** — 2-column grid of paired friends. Tap a cell to push
///    `FriendDetailView` (twin stage + health compare + message thread).
/// 2. **广场** — community goal banner + 4 community stats + a 4-column pet
///    grid where the user sits as the first cell.
///
/// All data is mocked in `TogetherMock`. Only the user-side pet identity
/// (name + sprite) is read from `PetStateStore` so the demo "you" stays in
/// lockstep with the home screen.
struct TogetherView: View {
    @Environment(PetStateStore.self) private var store
    @State private var section: Section = .friends

    enum Section: Hashable { case friends, plaza }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                subTabBar
                Group {
                    switch section {
                    case .friends: FriendsListView()
                    case .plaza:   PlazaView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .lpPaper(.app)
            .navigationDestination(for: Friend.self) { friend in
                FriendDetailView(friend: friend)
            }
            .navigationDestination(for: InviteRoute.self) { _ in
                InviteView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Sub-tab bar

    /// Custom segmented header — matches the prototype's hand-style font with
    /// a coral underline under the active option. SwiftUI's `Picker(.segmented)`
    /// doesn't let us style the indicator the way the prototype does, so we
    /// roll a small one inline.
    private var subTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "朋友", value: .friends)
            tabButton(title: "广场", value: .plaza)
        }
        .frame(height: 42)
        .overlay(
            Rectangle()
                .fill(LP.Colors.ink)
                .frame(height: LP.BorderWidth.regular),
            alignment: .bottom
        )
    }

    private func tabButton(title: String, value: Section) -> some View {
        let active = section == value
        return Button {
            if !active { LPHaptics.tap() }
            withAnimation(.easeInOut(duration: 0.18)) { section = value }
        } label: {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 17, weight: active ? .bold : .regular, design: .rounded))
                    .foregroundStyle(active ? LP.Colors.ink : LP.Colors.muted)
                Rectangle()
                    .fill(active ? LP.Colors.coral : .clear)
                    .frame(width: 30, height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friends list (sub-tab "朋友")

/// 2-column grid header + cells. Lives inside the same NavigationStack as
/// `TogetherView`, so both the friend cells and the "+ 添加" button push their
/// respective destinations via `NavigationLink(value:)`.
private struct FriendsListView: View {
    private let friends: [Friend] = TogetherMock.friends

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                header
                grid
                Spacer(minLength: LP.Spacing.s5)
            }
            .padding(.horizontal, LP.Spacing.s4)
            .padding(.top, LP.Spacing.s3)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("身边的朋友")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(".")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.coral)
            }
            Spacer()
            NavigationLink(value: InviteRoute()) {
                Text("+ 添加")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.paperCard)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LP.Colors.ink)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LP.Colors.ink)
                            .offset(x: 2, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(friends) { friend in
                NavigationLink(value: friend) {
                    FriendCell(friend: friend)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Friend cell

/// One 2-grid cell. LCD-tinted pet panel on top + 显示名 / 已陪伴天数 /
/// 状态 pill stacked below. New-message dot lights up when the latest message
/// in the friend's thread is from the other side (mirrors the prototype's
/// `fc-new-dot` heuristic).
private struct FriendCell: View {
    let friend: Friend

    private var hasNew: Bool {
        friend.messages.last?.who == .them
    }

    var body: some View {
        VStack(spacing: 6) {
            // — LCD pet panel —
            VStack(spacing: 4) {
                PixelPetSprite(sprite: friend.sprite)
                    .frame(width: 52, height: 52)
                Text(friend.petName)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(LCD.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LCD.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(LCD.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )

            Text(friend.displayName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            Text("已陪伴 \(friend.daysTogether) 天")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(LP.Colors.muted)
            Text(friend.otherStatus)
                .font(.system(size: 8, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(LP.Colors.coral)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous).fill(LP.Colors.coral.opacity(0.08))
                )
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LP.Colors.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 3, y: 3)
        )
        .overlay(alignment: .topTrailing) {
            if hasNew {
                Circle()
                    .fill(LP.Colors.coral)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(LP.Colors.paperCard, lineWidth: 2))
                    .offset(x: -10, y: 10)
            }
        }
    }
}

// MARK: - LCD palette

/// Local LCD-screen colors that match the prototype's `--lcd*` vars. Kept
/// inside this feature folder so we don't pollute the global LP token set —
/// the LCD tone is specific to the pet stage / friend cells.
enum LCD {
    static let fill = Color(hex: 0xEBE3CC)
    static let dash = Color(hex: 0xBFB89F)
    static let text = Color(hex: 0x7D7657)
}

// MARK: - Toast (shared between sub-views)

struct ToastBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(LP.Colors.paperCard)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(LP.Colors.ink))
    }
}

#Preview {
    TogetherView()
        .environment(PetStateStore())
        .preferredColorScheme(.light)
}
