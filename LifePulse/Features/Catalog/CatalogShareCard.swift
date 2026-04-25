import SwiftUI

/// "📣 分享" sheet content. Renders a screenshot-style card with the pet's
/// likeness + headline stats + 2 key moments + a faux QR for getting new users
/// to install the app. Save / 小红书 buttons live below the card.
///
/// The faux QR is a deterministic dot pattern — good enough for the hackathon
/// demo. Wiring a real `lifepet.app/p/<petId>` URL through CoreImage's
/// `CIQRCodeGenerator` is V1 work.
struct CatalogShareCard: View {
    let pet: CatalogPet

    var body: some View {
        ScrollView {
            VStack(spacing: LP.Spacing.s4) {
                shareCard
                actions
            }
            .padding(.horizontal, LP.Spacing.s4)
            .padding(.top, LP.Spacing.s3)
            .padding(.bottom, LP.Spacing.s5)
        }
        // No close button — per Apple HIG, sheets are dismissed by the drag
        // indicator (swipe down) or by tapping outside in non-modal style.
        .presentationDragIndicator(.visible)
    }

    // MARK: - Card

    private var shareCard: some View {
        VStack(spacing: 6) {
            Text("· LIFEPET ·")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(LP.Colors.coral)

            spriteHero
                .padding(.top, 4)
                .padding(.bottom, 2)

            Text(pet.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(LP.Colors.ink)

            Text(daysCopy)
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
                .padding(.top, 2)

            statsStrip
                .padding(.top, 10)

            momentsBlock
                .padding(.top, 6)

            qrBlock
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
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
                .offset(x: 4, y: 4)
        )
    }

    private var spriteHero: some View {
        BreathingSprite {
            PixelPetSprite(sprite: pet.sprite)
                .frame(width: 70, height: 70)
        }
    }

    private var daysCopy: String {
        pet.isAlive ? "已陪伴 · 第 \(pet.days) 天" : "陪伴了 \(pet.totalDays) 天 · 已升天"
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack {
            Spacer(minLength: 0)
            shareStatCell("💪", value: pet.stats.vitality, label: "体力")
            Spacer(minLength: 0)
            shareStatCell("⚡", value: pet.stats.energy, label: "精力")
            Spacer(minLength: 0)
            shareStatCell("❤️", value: pet.stats.mood, label: "心情", coral: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(LPDashedRule(dash: [4, 3]), alignment: .top)
        .overlay(LPDashedRule(dash: [4, 3]), alignment: .bottom)
    }

    private func shareStatCell(_ emoji: String, value: Int, label: String, coral: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(emoji).font(.system(size: 13))
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(coral ? LP.Colors.coral : LP.Colors.ink)
            Text(label)
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
        }
        .frame(minWidth: 56)
    }

    // MARK: - Moments

    private var momentsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(pet.moments.prefix(2))) { m in
                HStack(spacing: 6) {
                    Text("D\(String(format: "%02d", m.day))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(LP.Colors.coral)
                        .frame(minWidth: 26, alignment: .leading)
                    Text(m.title)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(LP.Colors.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: - QR block

    private var qrBlock: some View {
        VStack(spacing: 6) {
            FauxQRCode(seed: "lifepet-\(pet.id)")
                .frame(width: 86, height: 86)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(LP.Colors.paperCool)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
                )
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text("扫码注册")
                    Text("LifePet").foregroundStyle(LP.Colors.coral).fontWeight(.bold)
                }
                Text("养一只属于你自己的")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(LP.Colors.ink)

            Text("lifepet.app · via FISH")
                .font(.system(size: 8, design: .monospaced))
                .tracking(1)
                .foregroundStyle(LP.Colors.faint)
        }
        .padding(.top, 8)
        .overlay(LPDashedRule(dash: [4, 3]), alignment: .top)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            LPButton("📥 保存到相册", variant: .secondary) {
                // Hooks: render share-card as UIImage + write to PHPhotoLibrary.
            }
            LPButton("🌹 分享到小红书", variant: .coral) {
                // Hooks: launch UIActivityViewController with the rendered image.
            }
        }
    }
}

// MARK: - Faux QR

/// Deterministic 21×21 black-square pattern with three positioning markers,
/// shaped to read as a QR at thumbnail size. Same seeded-LCG approach as the
/// prototype JS — just enough randomness that two seeds produce different
/// patterns without anyone mistaking it for a real QR.
private struct FauxQRCode: View {
    let seed: String
    private static let size = 21

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let cells = generate(seed: seed)
            let unit = min(canvasSize.width, canvasSize.height) / CGFloat(Self.size)
            for y in 0..<Self.size {
                for x in 0..<Self.size where cells[y][x] {
                    let r = CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)
                    ctx.fill(Path(r), with: .color(LP.Colors.ink))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func generate(seed: String) -> [[Bool]] {
        var s: UInt32 = 0
        for c in seed.unicodeScalars {
            s = (s &* 31) &+ c.value
        }
        var grid = Array(repeating: Array(repeating: false, count: Self.size), count: Self.size)
        let rand: () -> Double = {
            s = (s &* 1664525) &+ 1013904223
            return Double(s) / Double(UInt32.max)
        }
        for y in 0..<Self.size {
            for x in 0..<Self.size {
                grid[y][x] = rand() < 0.48
            }
        }
        // Three positioning squares (top-left, top-right, bottom-left).
        let placeMarker: (Int, Int) -> Void = { sx, sy in
            for y in 0..<7 {
                for x in 0..<7 {
                    grid[sy + y][sx + x] = (x == 0 || x == 6 || y == 0 || y == 6)
                }
            }
            for y in 2..<5 {
                for x in 2..<5 {
                    grid[sy + y][sx + x] = true
                }
            }
        }
        placeMarker(0, 0)
        placeMarker(Self.size - 7, 0)
        placeMarker(0, Self.size - 7)
        return grid
    }
}

#Preview {
    Color.black.opacity(0.7)
        .ignoresSafeArea()
        .overlay(
            CatalogShareCard(pet: .blob)
                .frame(maxWidth: 320)
                .padding()
        )
}
