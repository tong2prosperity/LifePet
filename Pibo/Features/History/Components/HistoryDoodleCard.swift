import SwiftUI

/// 足迹涂鸦 card — the day's walk doodles (GPS strokes the user traced on the map).
/// Each doodle re-renders offline from its stored points via `WalkDoodleShape` (no
/// map tile persisted), shown on a cool-grey tile with its 距离 · 路线面积 caption — the
/// surface that grows into the future 完成度 / 比拼面积 view. Hides on no-data days
/// like 运动记录 / 体征.
struct HistoryDoodleCard: View {
    let doodles: [WalkDoodleRecord]

    var body: some View {
        HistoryCard(title: "足迹涂鸦", background: { LP.Fill.bgContainer }) {
            Group {
                if doodles.isEmpty {
                    emptyState
                } else {
                    doodleScroll
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.top, LP.Spacing.s)
            .padding(.bottom, LP.Spacing.l)
        }
    }

    private var doodleScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LP.Spacing.m) {
                ForEach(doodles) { doodle in
                    doodleTile(doodle)
                }
            }
        }
    }

    private func doodleTile(_ doodle: WalkDoodleRecord) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(doodle.timeLabel)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
            WalkDoodleShape(coordinates: doodle.coordinates)
                .stroke(LP.Fill.foundationAccent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(LP.Spacing.s)
                .frame(width: 128, height: 128)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgSurfaceSecondary))
            Text("\(DoodleGeometry.distanceText(doodle.distanceMeters)) · \(DoodleGeometry.areaText(doodle.areaSquareMeters))")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 128)
    }

    // 空态保持安静；Walk Doodle 的独立入口在首页，不从历史页反向拉起记录。
    // （`PiboReleaseScope.miniGames`）。卡片保留，老数据仍要能看。
    private var emptyState: some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(LP.Content.tertiary)
            Text(AppLocalization.text("这一天还没有涂鸦"))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgSurfaceSecondary.opacity(0.5)))
    }
}
