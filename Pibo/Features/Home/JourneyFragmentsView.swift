import SwiftUI

struct JourneyFragmentsView: View {
    let ritual: JourneyRitual
    let fragments: [MemoryFragment]
    let accessories: [JourneyAccessory]
    let nudge: String

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s3) {
            ritualCard
            if !fragments.isEmpty {
                fragmentsSection
            } else {
                lockedFragment
            }
            accessoriesSection
        }
    }

    private var ritualCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            HStack(spacing: LP.Spacing.s2) {
                Text(lp: "契约进度")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text("\(ritual.current)/\(ritual.target)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ritual.isReady ? LP.Colors.coral : LP.Colors.muted)
                LPDashedRule(dash: [4, 3])
            }

            VStack(alignment: .leading, spacing: LP.Spacing.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppLocalization.text(ritual.title))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(LP.Colors.ink)
                    Spacer()
                    Text(lp: ritual.isReady ? "可举行" : "稳定中")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(ritual.isReady ? LP.Colors.coral : LP.Colors.muted)
                }
                Text(AppLocalization.text(ritual.subtitle))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LP.Colors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                RitualProgress(progress: ritual.progress, ready: ritual.isReady)
                    .frame(height: 10)
            }
            .lpStampedCard(fill: ritual.isReady ? LP.Colors.coralSoft : LP.Colors.paperCard)
        }
    }

    private var lockedFragment: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lp: "记忆碎片")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            Text(AppLocalization.text(nudge))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LP.Colors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lpStampedCard(fill: LP.Colors.paperWarm, dashed: true)
    }

    private var fragmentsSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            Text(lp: "记忆碎片")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            ForEach(fragments) { fragment in
                FragmentCard(fragment: fragment)
            }
        }
    }

    private var accessoriesSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            Text(lp: "星光里的物件")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LP.Colors.muted)
            ForEach(accessories) { accessory in
                AccessoryRow(accessory: accessory)
            }
        }
    }
}

private struct FragmentCard: View {
    let fragment: MemoryFragment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppLocalization.text(fragment.title))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Spacer()
                Text(AppLocalization.text(fragment.unlockLabel))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LP.Colors.coral)
            }
            Text(AppLocalization.text(fragment.body))
                .lpText(LP.Typography.serifItalic)
                .foregroundStyle(LP.Colors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lpStampedCard(fill: LP.Colors.paperWarm)
    }
}

private struct AccessoryRow: View {
    let accessory: JourneyAccessory

    var body: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s3) {
            Image(systemName: accessory.isUnlocked ? "sparkles" : "circle.dashed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accessory.isUnlocked ? LP.Colors.coral : LP.Colors.muted)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accessory.isUnlocked ? LP.Colors.coralSoft : LP.Colors.paperCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(LP.Colors.ink, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s2) {
                    Text(AppLocalization.text(accessory.name))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LP.Colors.ink)
                    Text(AppLocalization.text(accessory.unlockLabel))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(accessory.isUnlocked ? LP.Colors.coral : LP.Colors.muted)
                }
                Text(AppLocalization.text(accessory.meaning))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LP.Colors.muted)
            }
            Spacer(minLength: 0)
        }
        .lpStampedCard(
            padding: EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12),
            fill: accessory.isUnlocked ? LP.Colors.coralSoft : LP.Colors.paperCard,
            dashed: !accessory.isUnlocked
        )
    }
}

private struct RitualProgress: View {
    let progress: Double
    let ready: Bool

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                shape.fill(LP.Colors.paperWarm)
                shape
                    .fill(ready ? LP.Colors.coral : LP.Colors.sage)
                    .frame(width: max(0, geo.size.width * clamped))
                    .animation(.easeOut(duration: 0.55), value: clamped)
                shape.strokeBorder(LP.Colors.ink, lineWidth: 1)
            }
        }
    }
}

#Preview {
    JourneyFragmentsView(
        ritual: JourneyRitual(title: "第一次星光仪式", subtitle: "契约已经稳定一周。Pibo 找回了一件来自旧世界的东西。", current: 7, target: 7, isReady: true),
        fragments: [
            MemoryFragment(id: "star-shell", title: "无名星壳", unlockLabel: "Day 3 解锁", body: "很久以前，Pibo 们在没有太阳的地方等待光。")
        ],
        accessories: [
            JourneyAccessory(id: "bell", name: "破损铃铛", unlockLabel: "已显形", meaning: "曾经用于召回迷路的 Pibo。", isUnlocked: true)
        ],
        nudge: "碎片正在稳定。"
    )
    .padding(LP.Spacing.s4)
    .lpPaper(.app)
}
