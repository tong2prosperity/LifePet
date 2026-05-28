import SwiftUI

/// 单只宠物的详情页 — `原型-02-图鉴.html` 中的 detail view.
///
/// Sections (top → bottom):
/// 1. LCD hero: sprite + name + dates + tag chips
/// 2. 4-cell stats: 体力 / 精力 / 心情 / 天数
/// 3. 生命轨迹 line chart with legend
/// 4. 关键时刻 list
/// 5. 它的故事 sticky note
/// 6. 《纪念曲》 (only when `!pet.isAlive`)
/// 7. 📣 分享 button
struct CatalogPetDetailView: View {
    /// The pet as captured at navigation time. For the alive pet we re-overlay
    /// `PetStateStore` on every render via the computed `pet` below, so the
    /// detail view stays in sync if the user runs / sleeps / meditates while
    /// the screen is open.
    private let basePet: CatalogPet
    @Environment(PetStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareCard = false
    @State private var showingIncense = false

    init(pet: CatalogPet) {
        self.basePet = pet
    }

    /// The pet to render — alive pet pulls live values from store; dead pets
    /// are read-only history and pass through unchanged.
    private var pet: CatalogPet { basePet.liveOverlay(from: store) }
    /// "Playback" simulation — drives the waveform cursor while the play
    /// button is on. No real audio yet (V1 work).
    @State private var memorialPlaying = false
    @State private var memorialProgress: Double = 0.18
    /// Single in-flight playback task. We cancel + replace on every toggle so
    /// rapid play/pause/play doesn't spawn parallel timers that double-step
    /// the cursor.
    @State private var memorialTask: Task<Void, Never>?

    // Local LCD literals — mirrors `PetStageView`. See note in CLAUDE.md /
    // PetStageView about why the LCD tone isn't promoted to LP.Colors.
    private static let lcd     = Color(hex: 0xEBE3CC)
    private static let lcdDash = Color(hex: 0xBFB89F)
    private static let lcdInk  = Color(hex: 0x7D7657)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                hero
                statsRow
                trajectoryBlock
                momentsBlock
                bioNote
                if !pet.isAlive { memorial }
                shareButton
            }
            .padding(.horizontal, LP.Spacing.s4)
            .padding(.top, LP.Spacing.s3)
            .padding(.bottom, LP.Spacing.s5)
        }
        .lpPaper(.app)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { LPHaptics.tap(); dismiss() }) {
                    HStack(spacing: 2) {
                        Text("‹")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(LP.Colors.coral)
                        Text("返回图鉴")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(LP.Colors.ink)
                    }
                }
                .accessibilityLabel("返回图鉴")
            }
        }
        .toolbarBackground(LP.Colors.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingShareCard) {
            CatalogShareCard(pet: pet)
                .presentationDetents([.large])
                .presentationBackground(LP.Colors.paper)
        }
        .fullScreenCover(isPresented: $showingIncense) {
            CatalogIncenseOverlayView(pet: pet)
        }
        .onChange(of: memorialPlaying) { _, on in
            memorialTask?.cancel()
            guard on else { return }
            memorialTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { break }
                    memorialProgress = (memorialProgress + 0.008).truncatingRemainder(dividingBy: 1.0)
                }
            }
        }
        .onDisappear { memorialTask?.cancel() }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.lcd)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: 2)
                )
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LP.Colors.ink)
                        .offset(x: 3, y: 3)
                )
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Self.lcdDash, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(5)

            VStack(spacing: 4) {
                BreathingSprite {
                    PixelPetSprite(sprite: pet.sprite)
                        .frame(width: 90, height: 90)
                }
                .frame(height: 100)

                Text(pet.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(LP.Colors.ink)
                Text(heroDates)
                    .lpText(LP.Typography.monoTiny)
                    .foregroundStyle(Self.lcdInk)
                tagsRow.padding(.top, 4)
            }
            .padding(14)
        }
    }

    private var heroDates: String {
        if pet.isAlive {
            return "\(pet.dates) · 已陪伴 \(pet.days) 天"
        } else {
            return "\(pet.dates) · \(pet.totalDays) 天"
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(pet.tags.enumerated()), id: \.offset) { _, tag in
                tagChip(tag)
            }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: CatalogPet.Tag) -> some View {
        let (fg, bg, border) = chipColors(for: tag)
        Text(tag.label)
            .lpText(LP.Typography.monoTiny)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(border, lineWidth: 1.5)
            )
    }

    private func chipColors(for tag: CatalogPet.Tag) -> (Color, Color, Color) {
        switch tag {
        case .rare:        return (.white, LP.Colors.coral, LP.Colors.coral)
        case .dead:        return (.white, LP.Colors.muted, LP.Colors.muted)
        case .plain:       return (LP.Colors.ink, LP.Colors.paperCool, LP.Colors.ink)
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 6) {
            statCell(emoji: "💪", value: pet.stats.vitality, label: "体力")
            statCell(emoji: "⚡", value: pet.stats.energy, label: "精力")
            statCell(emoji: "❤️", value: pet.stats.mood, label: "心情", coral: true)
            statCell(emoji: "📅", value: daysNumber, label: pet.isAlive ? "陪伴中" : "共陪伴")
        }
    }

    private var daysNumber: Int { pet.isAlive ? pet.days : pet.totalDays }

    private func statCell(emoji: String, value: Int, label: String, coral: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(emoji).font(.system(size: 14))
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(coral ? LP.Colors.coral : LP.Colors.ink)
            Text(label)
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .lpStampedCard(
            radius: 8,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            fill: LP.Colors.paperCool
        )
    }

    // MARK: - Trajectory block

    private var trajectoryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trajectoryTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Spacer()
                CatalogTrajectoryLegend()
            }
            CatalogTrajectoryChart(pet: pet)
        }
        .padding(12)
        .lpStampedCard(
            radius: 10,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            fill: LP.Colors.paperCool
        )
    }

    private var trajectoryTitle: String {
        pet.isAlive ? "生命轨迹 · 至今 \(pet.days) 天" : "生命轨迹 · \(pet.totalDays) 天"
    }

    // MARK: - Moments block

    private var momentsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("关键时刻")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
                .padding(.bottom, 6)

            ForEach(Array(pet.moments.enumerated()), id: \.element.id) { idx, m in
                if idx > 0 { LPDashedRule().padding(.vertical, 5) }
                momentRow(m)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .lpStampedCard(
            radius: 10,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            fill: LP.Colors.paperCool
        )
    }

    @ViewBuilder
    private func momentRow(_ m: CatalogPet.Moment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("D\(String(format: "%02d", m.day))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(m.isDeath ? LP.Colors.muted : LP.Colors.coral)
                .frame(width: 34, alignment: .leading)

            (
                Text(m.title)
                + Text(m.isDeath ? " 🕊️" : "")
            )
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(m.isDeath ? LP.Colors.muted : LP.Colors.ink)
            .italic(m.isDeath)
            .lineLimit(2)

            Spacer(minLength: 6)

            if let val = m.value {
                Text(val)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
            }
        }
    }

    // MARK: - Bio sticky

    private var bioNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pet.isAlive ? "它的故事" : "— 它的故事 —")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.stickyInk)
            Text(pet.bio)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(LP.Colors.stickyInk)
                .lineSpacing(2)
            Text("— via Pibo")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.stickyInk.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.sticky)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, lineWidth: 1.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LP.Colors.ink)
                .offset(x: 3, y: 3)
        )
        .rotationEffect(.degrees(-0.3))
    }

    // MARK: - Memorial

    private var memorial: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("♪")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LP.Colors.coral)
                Text(pet.memorialTitle ?? "《纪念曲》")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.stickyInk)
                Spacer()
                Text(pet.memorialDuration ?? "0:00")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(LP.Colors.stickyInk.opacity(0.7))
            }

            CatalogMemorialWaveform(pet: pet, progress: memorialProgress)

            HStack(spacing: 8) {
                Button {
                    LPHaptics.tap()
                    memorialPlaying.toggle()
                } label: {
                    ZStack {
                        Circle().fill(memorialPlaying ? LP.Colors.coral : LP.Colors.stickyInk)
                        Image(systemName: memorialPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LP.Colors.paperWarm)
                            .offset(x: memorialPlaying ? 0 : 1)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(memorialPlaying ? "暂停纪念曲" : "播放纪念曲")

                progressTrack
            }

            Text("由 TA 一生的健康数据生成 · 时长 15 秒")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.stickyInk.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)

            incenseCTA
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xF5EDE0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.stickyInk, lineWidth: 1.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LP.Colors.stickyInk)
                .offset(x: 2, y: 2)
        )
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LP.Colors.stickyInk.opacity(0.25))
                    .frame(height: 2)
                Capsule().fill(LP.Colors.stickyInk)
                    .frame(width: max(0, geo.size.width * memorialProgress), height: 2)
            }
        }
        .frame(height: 12)
    }

    // MARK: - 上香 CTA

    private var incenseCTA: some View {
        VStack(spacing: 5) {
            LPDashedRule(color: Color(hex: 0xC8A860), dash: [4, 3])
                .padding(.bottom, 4)

            Button {
                LPHaptics.confirm()
                memorialPlaying = false
                showingIncense = true
            } label: {
                Text("🕯 上香")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color(hex: 0xF0D8A0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(IncenseButtonStyle())

            Text("点燃一炷香 · 聆听 TA 的 15 秒纪念曲")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.stickyInk.opacity(0.6))
        }
    }

    // MARK: - Share button

    private var shareButton: some View {
        LPButton(variant: .primary, action: { showingShareCard = true }) {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 上香 button style

/// Stamped dark-brown button with press-collapse: on tap, the label slides 2pt
/// down-right and the offset shadow disappears, mirroring the prototype's
/// `:active { transform: translate(2px, 2px); box-shadow: 0 0 0; }`. Kept
/// private — `LPButton` itself doesn't animate press, so this is one-off.
private struct IncenseButtonStyle: ButtonStyle {
    private static let face   = Color(hex: 0x4A3820)
    private static let shadow = Color(hex: 0x3A2810)

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.face)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Self.shadow, lineWidth: 1.5)
            )
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.shadow)
                    .offset(x: pressed ? 0 : 2, y: pressed ? 0 : 2)
            )
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

#Preview("Alive · BEAN") {
    NavigationStack {
        CatalogPetDetailView(pet: .bean)
    }
    .environment(PetStateStore())
    .preferredColorScheme(.light)
}

#Preview("Dead · BLOB") {
    NavigationStack {
        CatalogPetDetailView(pet: .blob)
    }
    .environment(PetStateStore())
    .preferredColorScheme(.light)
}

#Preview("Dead · NOCT") {
    NavigationStack {
        CatalogPetDetailView(pet: .noct)
    }
    .environment(PetStateStore())
    .preferredColorScheme(.light)
}
