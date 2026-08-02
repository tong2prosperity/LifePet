import XCTest
@testable import Pibo

/// Pins 今日脚步 拖动杆 的列几何。
///
/// 这条交互里会错的只有这一处：竖线画在哪、手指点到哪一列。两者必须是同一个算式的
/// 正反两面，否则拖动杆会和植物错开半列 —— 静态截图看不出来，只有拖的时候才发现
/// 「明明按在这棵树上，显示的却是隔壁那小时」。所以下面钉的是**往返一致性**，而不是
/// 某几个魔法数字。
final class StepsColumnGeometryTests: XCTestCase {

    /// 一张真实卡片的宽度（iPhone 17 上 353pt 的内容宽），16 列 = 06:00–22:00。
    private let width: CGFloat = 353
    private let geometry = StepsColumnGeometry(count: 16)

    /// 往返：每一列的中心点必须命中它自己。这条挂了就是拖动杆错位。
    func testCenterOfEachColumnHitsItself() {
        for i in 0..<geometry.count {
            let x = geometry.centerX(of: i, in: width)
            XCTAssertEqual(geometry.index(atX: x, in: width), i,
                           "第 \(i) 列的中心 x=\(x) 命中到了别的列")
        }
    }

    /// 列在卡片内按顺序排开，且都落在绘制区内（不能溢出到内边距外）。
    func testColumnsAreOrderedAndInsideTheField() {
        let centers = (0..<geometry.count).map { geometry.centerX(of: $0, in: width) }
        XCTAssertEqual(centers, centers.sorted(), "列中心不是单调递增的")
        XCTAssertGreaterThan(centers.first ?? 0, StepsColumnGeometry.rowInset)
        XCTAssertLessThan(centers.last ?? width, width - StepsColumnGeometry.rowInset)
    }

    /// 拖出卡片两端不应该丢选中，而是夹在首/尾列 —— 手指滑到边缘外是常态。
    func testOutOfBoundsClampsInsteadOfDropping() {
        XCTAssertEqual(geometry.index(atX: -400, in: width), 0)
        XCTAssertEqual(geometry.index(atX: 0, in: width), 0)
        XCTAssertEqual(geometry.index(atX: width + 400, in: width), geometry.count - 1)
    }

    /// 相邻列的中心间距 = 列宽 + 列间距，且与 `plantRow` 的常量一致。
    func testSpacingMatchesTheLayoutConstants() {
        let w = geometry.columnWidth(in: width)
        let step = geometry.centerX(of: 1, in: width) - geometry.centerX(of: 0, in: width)
        XCTAssertEqual(step, w + StepsColumnGeometry.columnSpacing, accuracy: 0.001)
    }

    /// 退化输入不能崩：0 列会被夹到 1 列，极窄宽度下列宽有下限。
    func testDegenerateInputsStaySafe() {
        let single = StepsColumnGeometry(count: 0)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.index(atX: 10, in: 0), 0)
        XCTAssertGreaterThanOrEqual(single.columnWidth(in: 0), 1)
    }
}
