import SwiftUI

extension EnvironmentValues {
    /// 历史页是否"正在前台显示"（可见即播）。历史页里的 `WaterSurface` /
    /// `HistoryStepsCard` 据此门控水面着色器 / `TimelineView` —— 不可见即停转，零开销。
    ///
    /// 旧的上滑数据二楼由 `FloorContainer` 在跨打开阈值那一刻写入此值；新的设计里
    /// 历史页是 `fullScreenCover`（手绘 icon 进入），只要它在场就是可见的，默认 `true`
    /// 即可。保留这个环境值是为了不动 `WaterSurface` / `HistoryStepsCard` 的门控逻辑。
    @Entry var floorIsOpen: Bool = true
}
