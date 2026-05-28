import SwiftUI

/// 图鉴 — list of every pet you've raised. The grid screen of `原型-02-图鉴.html`.
///
/// Layout (top → bottom):
/// 1. Header: "图鉴." + "陪伴过 N 只 · 累计 X 天"
/// 2. Stats row: 4 chips (养育中 / 圆满 / 短命 / 总天数)
/// 3. 养育中: single LCD-style live card (tap → detail)
/// 4. 已升天: 3-column grid of past pets + locked placeholders
/// 5. Sticky-note footer: "陪伴过 N 只 · 养活 1 · 送走 3"
///
/// Tapping a card pushes `CatalogPetDetailView`. Wrapped in a `NavigationStack`
/// so the tab owns its own back-stack.
struct CatalogView: View {
    @Environment(PetStateStore.self) private var store

    /// Demo dataset overlaid with `PetStateStore` for the alive pet, so BEAN's
    /// name / days / 三状态 stay in lockstep with the home screen. Dead pets
    /// pass through unchanged — their history is frozen.
    private var pets: [CatalogPet] {
        CatalogPet.demo.map { $0.liveOverlay(from: store) }
    }
    private var summary: CatalogSummary { CatalogSummary(pets: pets) }
    /// Locked-slot count: pad the past grid to a multiple of 3 plus a few teasers.
    private var lockedSlots: Int {
        let dead = pets.filter { !$0.isAlive }.count
        let target = max(6, dead + ((3 - dead % 3) % 3) + 3)
        return max(0, target - dead)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LP.Spacing.s4) {
                    header
                    statsRow
                    livingSection
                    pastSection
                    footerNote
                    Spacer(minLength: LP.Spacing.s5)
                }
                .padding(.horizontal, LP.Spacing.s4)
                .padding(.top, LP.Spacing.s3)
            }
            .lpPaper(.app)
            .navigationDestination(for: CatalogPet.self) { pet in
                CatalogPetDetailView(pet: pet)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("图鉴")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(".")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.coral)
            }
            HStack(spacing: 0) {
                Text("陪伴过 ").lpText(LP.Typography.monoTiny).foregroundStyle(LP.Colors.muted)
                Text("\(summary.totalCount)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LP.Colors.coral).tracking(1).textCase(.uppercase)
                Text(" 只 · 累计 ").lpText(LP.Typography.monoTiny).foregroundStyle(LP.Colors.muted)
                Text("\(summary.totalDays)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LP.Colors.coral).tracking(1).textCase(.uppercase)
                Text(" 天").lpText(LP.Typography.monoTiny).foregroundStyle(LP.Colors.muted)
            }
        }
    }

    // MARK: - Stats row (4 chips)

    private var statsRow: some View {
        HStack(spacing: 6) {
            statChip(value: summary.aliveCount, label: "养育中", live: true)
            statChip(value: summary.naturalCount, label: "圆满")
            statChip(value: summary.earlyCount,   label: "短命")
            statChip(value: summary.totalDays,    label: "总天数")
        }
        .padding(.vertical, 10)
        .overlay(LPDashedRule(dash: [4, 3]), alignment: .top)
        .overlay(LPDashedRule(dash: [4, 3]), alignment: .bottom)
    }

    private func statChip(value: Int, label: String, live: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(live ? LP.Colors.coral : LP.Colors.ink)
            Text(label)
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .lpStampedCard(
            radius: 8,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            fill: LP.Colors.paperCool
        )
    }

    // MARK: - Living section

    @ViewBuilder
    private var livingSection: some View {
        if let alive = pets.first(where: \.isAlive) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(tag: "养育中", count: nil)
                NavigationLink(value: alive) {
                    LiveCatalogCard(pet: alive)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Past section

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let dead = pets.filter { !$0.isAlive }
            sectionHeader(tag: "已升天", count: dead.count)

            let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(dead) { pet in
                    NavigationLink(value: pet) {
                        DeadCatalogCard(pet: pet)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(0..<lockedSlots, id: \.self) { _ in
                    LockedCatalogCard()
                }
            }
        }
    }

    // MARK: - Section header (tag + dashed rule + optional count)

    private func sectionHeader(tag: String, count: Int?) -> some View {
        HStack(spacing: 10) {
            Text(tag)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            LPDashedRule(dash: [4, 3])
            if let count = count {
                Text("\(count) 只")
                    .lpText(LP.Typography.monoTiny)
                    .foregroundStyle(LP.Colors.muted)
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Text("陪伴过 ").foregroundStyle(LP.Colors.stickyInk)
                Text("\(summary.totalCount)").foregroundStyle(LP.Colors.coral).fontWeight(.bold)
                Text(" 只 · 养活 ").foregroundStyle(LP.Colors.stickyInk)
                Text("\(summary.aliveCount + summary.naturalCount)").foregroundStyle(LP.Colors.coral).fontWeight(.bold)
                Text(" 只 · 送走 ").foregroundStyle(LP.Colors.stickyInk)
                Text("\(summary.earlyCount)").foregroundStyle(LP.Colors.coral).fontWeight(.bold)
                Text(" 只").foregroundStyle(LP.Colors.stickyInk)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("养死了也别难过，下一只会更好。")
                .font(.system(size: 12, design: .rounded).italic())
                .foregroundStyle(LP.Colors.stickyInk.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.sticky)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

// MARK: - Live card (LCD chrome, breathing sprite)

private struct LiveCatalogCard: View {
    let pet: CatalogPet

    private static let lcd     = Color(hex: 0xEBE3CC)
    private static let lcdDash = Color(hex: 0xBFB89F)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // — LCD frame with offset ink shadow —
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

            HStack(spacing: 14) {
                BreathingSprite {
                    PixelPetSprite(sprite: pet.sprite)
                        .frame(width: 60, height: 60)
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(LP.Colors.ink)
                    Text(pet.dates)
                        .lpText(LP.Typography.monoTiny)
                        .foregroundStyle(LP.Colors.muted)
                    Text("已陪伴 · 第 \(pet.days) 天")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(LP.Colors.coral)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            // LIVE badge — coral pill anchored to top-left.
            Text("LIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(LP.Colors.coral)
                )
                .offset(x: 14, y: -8)
        }
    }
}

// MARK: - Dead pet card (small grid item)

private struct DeadCatalogCard: View {
    let pet: CatalogPet

    var body: some View {
        VStack(spacing: 4) {
            PixelPetSprite(sprite: pet.sprite)
                .frame(width: 44, height: 44)
                .frame(height: 52)
            Text(pet.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
            Text(pet.dates)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            deathBadge
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .lpStampedCard(
            radius: 10,
            padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            fill: LP.Colors.paperCard
        )
        .overlay(rareBadge.padding(-4), alignment: .topTrailing)
    }

    @ViewBuilder
    private var rareBadge: some View {
        if pet.isRare {
            Text("RARE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(LP.Colors.coral)
                )
        }
    }

    private var deathBadge: some View {
        let (bg, fg) = bucketColors(pet.deathBucket)
        return Text(pet.pastGridTag)
            .font(.system(size: 7.5, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(bg)
            )
    }

    private func bucketColors(_ b: CatalogPet.DeathBucket) -> (Color, Color) {
        switch b {
        case .natural: return (Color(hex: 0xF3EBD8), Color(hex: 0x7D6B3A))
        case .chronic: return (Color(hex: 0xD4D4D4), Color(hex: 0x555555))
        case .acute:   return (Color(hex: 0xFADAD6), Color(hex: 0xA13528))
        }
    }
}

// MARK: - Locked card

private struct LockedCatalogCard: View {
    var body: some View {
        VStack(spacing: 4) {
            PixelPetLockedSprite()
                .frame(width: 44, height: 44)
                .frame(height: 52)
            Text("???")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.muted)
            Text("UNLOCK")
                .font(.system(size: 8, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .opacity(0.45)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LP.Colors.paperCool)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LP.Colors.ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
        .accessibilityHidden(true)
    }
}

#Preview {
    CatalogView()
        .environment(PetStateStore())
        .preferredColorScheme(.light)
}
