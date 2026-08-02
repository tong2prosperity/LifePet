import CoreGraphics

/// 今日脚步卡的列几何 —— 植物行、拖动杆竖线、以及拖动命中判定三者共用同一套算式。
///
/// 拆出来是因为它是这条交互里**唯一会算错**的部分：`plantRow` 是一个左右内边距
/// `rowInset`、列间距 `columnSpacing` 的等宽 `HStack`，只要竖线和命中判定各自用一
/// 份「差不多」的算式，拖动杆就会和植物错开半列 —— 而这种错位在静态截图上很难看
/// 出来，得靠测试钉住。
struct StepsColumnGeometry: Equatable {
    /// 列数（今日脚步是 06:00–22:00 共 16 列）。
    let count: Int

    /// 与 `GrassField.plantRow` 的 `.padding(.horizontal:)` 一致。
    static let rowInset: CGFloat = 8
    /// 与 `GrassField.plantRow` 的 `HStack(spacing:)` 一致。
    static let columnSpacing: CGFloat = 1

    init(count: Int) {
        self.count = max(1, count)
    }

    /// 单列宽度：可用宽度扣掉两侧内边距和 (n-1) 个列间距后均分。
    func columnWidth(in totalWidth: CGFloat) -> CGFloat {
        let n = CGFloat(count)
        let usable = totalWidth - Self.rowInset * 2 - Self.columnSpacing * (n - 1)
        return max(1, usable / n)
    }

    /// 第 `index` 列的中心 x —— 竖线画在这里。
    func centerX(of index: Int, in totalWidth: CGFloat) -> CGFloat {
        let w = columnWidth(in: totalWidth)
        return Self.rowInset + CGFloat(index) * (w + Self.columnSpacing) + w / 2
    }

    /// 手指落点 x 命中的列。超出两端会夹到首/尾列 —— 拖到卡片边缘外不应该丢选中。
    func index(atX x: CGFloat, in totalWidth: CGFloat) -> Int {
        let w = columnWidth(in: totalWidth)
        let raw = ((x - Self.rowInset) / (w + Self.columnSpacing)).rounded(.down)
        guard raw.isFinite else { return 0 }
        return min(max(0, Int(raw)), count - 1)
    }
}
