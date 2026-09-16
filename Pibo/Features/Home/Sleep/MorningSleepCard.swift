import SwiftUI

/// Morning sleep sheet over the home world. A thin host around the shared
/// `SleepDetailContent`, so the morning entry and history's 「展开睡眠详情」
/// show the same night the same way (continuous cloud trail, stage colors,
/// facts and missing semantics). Home keeps owning the once-per-wake-day
/// presentation lifecycle via `HomeSheetModifier`.
struct MorningSleepCard: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: MorningSleepPresentation
    let history: HealthHistoryStore

    static let debugFixtureNotice = "DEBUG · 示例睡眠，非真实健康记录"

    var body: some View {
        SleepDetailContent(
            detail: .from(summary: presentation.summary),
            history: history,
            debugNotice: presentation.isDebugFixture ? Self.debugFixtureNotice : nil,
            onClose: {
                LPHaptics.tap()
                dismiss()
            }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: 0x232B3B))
    }
}
