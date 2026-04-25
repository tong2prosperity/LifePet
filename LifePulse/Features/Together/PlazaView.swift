import SwiftUI

/// 广场 — community page rendered as a single scroll view. Mirrors
/// `viewPlazaGrand` in `原型-03-一起.html` v0.9.1.
///
/// Sections (top → bottom):
/// 1. Sticky-note style banner — community goal title, progress bar, and
///    `current / percent` numbers.
/// 2. 2×2 community stats — 在场人数 / 我的步数贡献 / 社区运动次数 / 我的排名.
/// 3. Plaza stage — 4-column LCD-tinted grid where the user's pet sits as the
///    first cell (coral-tinted) and the rest of the community fills out 12
///    mock entries.
///
/// A 2.4s `Timer.publish` ticks the goal counter / online count up by a small
/// random delta — purely cosmetic, so the demo screen feels alive.
struct PlazaView: View {
    @Environment(PetStateStore.self) private var store
    @State private var snapshot: PlazaSnapshot = TogetherMock.plaza

    /// 2.4s drip — increments goal + nudges online count. Driven by `.task`
    /// so SwiftUI auto-cancels when the view disappears (sub-tab switch /
    /// navigation push / leaving the Together tab). Without the auto-cancel,
    /// switching sub-tabs would leak a new ticker every appear and the goal
    /// would race ahead at N× the intended speed.
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                banner
                communityStats
                stage
                Spacer(minLength: LP.Spacing.s5)
            }
            .padding(.horizontal, LP.Spacing.s4)
            .padding(.top, LP.Spacing.s3)
        }
        .task { await runTicker() }
    }

    // MARK: - Banner

    /// Sticky-note style card with progress. The fill animates smoothly when
    /// `snapshot.goalCurrent` changes via the timer.
    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日社区 · 大家一起")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(LP.Colors.stickyInk)
            Text(snapshot.goalTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
                .lineLimit(2)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(LP.Colors.paperCard.opacity(0.6))
                    Capsule(style: .continuous)
                        .fill(LP.Colors.coral)
                        .frame(width: max(8, geo.size.width * snapshot.goalPercent))
                        .animation(.easeOut(duration: 1.4), value: snapshot.goalCurrent)
                }
            }
            .frame(height: 8)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LP.Colors.stickyInk, lineWidth: 1)
            )

            HStack {
                Text(snapshot.goalCurrent.formatted(.number))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LP.Colors.stickyInk)
                Spacer()
                Text("\(Int(snapshot.goalPercent * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LP.Colors.stickyInk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.sticky)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 3, y: 3)
        )
        .rotationEffect(.degrees(-0.3))
    }

    // MARK: - Community stats (2×2)

    private var communityStats: some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
        return LazyVGrid(columns: cols, spacing: 8) {
            statCell(label: "在场人数",        value: "\(snapshot.onlineCount)", sub: "位宠物主人")
            statCell(label: "我的步数贡献",    value: snapshot.myContribSteps,   sub: "步", accent: true)
            statCell(label: "社区运动次数",    value: snapshot.exerciseCount,    sub: "次")
            statCell(label: "我的排名",        value: snapshot.myRank,           sub: "/ \(snapshot.onlineCount) 人", accent: true)
        }
    }

    private func statCell(label: String, value: String, sub: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(LP.Colors.muted)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? LP.Colors.coral : LP.Colors.ink)
            Text(sub)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

    // MARK: - Stage

    /// The "● 248 人在场" ribbon ribbon + 4-column pet grid. Users + me sit on
    /// the same dashed LCD background; the user's cell flips to coral-tinted
    /// "YOU" styling so it's findable at a glance.
    private var stage: some View {
        VStack(spacing: 10) {
            HStack {
                Text("● \(snapshot.onlineCount) 人在场")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(LP.Colors.paperCard)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(LP.Colors.coral)
                    )
                Spacer()
            }

            let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
            LazyVGrid(columns: cols, spacing: 10) {
                meCell
                ForEach(snapshot.members) { member in
                    memberCell(member)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LCD.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LCD.dash, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(5)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 3, y: 3)
        )
    }

    private var meCell: some View {
        VStack(spacing: 3) {
            BreathingSprite { PixelPetSprite(sprite: .bean).frame(width: 42, height: 42) }
                .frame(width: 44, height: 44)
            Text(store.petName)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(LP.Colors.coral)
            Text("YOU")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(LP.Colors.coral)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LP.Colors.coral.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LP.Colors.coral, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
    }

    private func memberCell(_ member: PlazaMember) -> some View {
        VStack(spacing: 3) {
            BreathingSprite { PixelPetSprite(sprite: member.sprite).frame(width: 42, height: 42) }
                .frame(width: 44, height: 44)
            Text(member.name)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(LCD.text)
            // Spacer placeholder to match height with the YOU badge in `meCell`.
            Color.clear.frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.3))
        )
    }

    // MARK: - Ticker

    /// Bumps the goal counter + online count every 2.4s. Mutates `snapshot`
    /// directly; the bar fill animates via the `.animation(_, value:)`
    /// modifier on the banner — no `withAnimation` here, otherwise an
    /// explicit transaction would override the modifier and we'd have two
    /// places declaring the same animation timing.
    ///
    /// `try await Task.sleep` propagates `CancellationError` when SwiftUI
    /// cancels the parent `.task`; the `do/catch` below converts that to a
    /// clean loop exit.
    private func runTicker() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(2.4))
            } catch {
                return  // cancelled — view disappeared
            }
            let goalDelta = Int.random(in: 20...100)
            let onlineDelta = Int.random(in: -2...2)
            snapshot.goalCurrent = min(snapshot.goalTotal, snapshot.goalCurrent + goalDelta)
            snapshot.onlineCount = max(180, min(320, snapshot.onlineCount + onlineDelta))
        }
    }
}

#Preview {
    PlazaView()
        .environment(PetStateStore())
        .lpPaper(.app)
        .preferredColorScheme(.light)
}
