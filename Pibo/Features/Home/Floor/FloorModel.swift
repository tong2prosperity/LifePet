import SwiftUI
import QuartzCore
import Observation

/// Drives the 上滑二楼 pull. Owned by `HomeView` for its lifetime but read **only**
/// by `FloorContainer`, so mutating `progress` re-renders just the thin transform
/// shell — never the stage / chrome / 二楼 subtrees.
///
/// 点击和拖动是**两个独立交互**：
///   • 拖动时 `progress` 由手指逐帧直接写入（1:1 跟手），没有动画。
///   • 点击 / 松手走 `animate(to:initialVelocity:)` —— 一段**物理弹簧**整定到目标。
///     用 SwiftUI 自带的 `Spring` 求值，所以曲线**就是系统曲线**；松手时把手指的
///     释放速度 (`initialVelocity`) 喂进弹簧，于是「快甩接着快、慢放轻轻落」——
///     与 iOS 系统 sheet / 抽屉的默认手感一致。点击没有手指速度（v0=0），从静止
///     干脆弹到目标。默认弹簧 `FloorAnim.settle` 临界阻尼（无回弹 → 关闭时不会越过
///     底墙露出缝隙）；`step` 再把 `progress` clamp 到 [0,1] 兜底。
///
/// **为什么是 `CADisplayLink` 弹簧积分而不是 `withAnimation(.spring)`（承重墙，别"简化"掉）：**
/// 每帧把 `progress` 更新为**真实屏幕位置**，而 `progress` 不只是渲染输入，还被当作
/// **数据**读取来驱动逻辑：
///   • SpriteKit 暂停阈值 `p > coverThreshold` —— 必须等抽屉真的盖住 Pibo 才暂停，
///     否则 Pibo 会在还露着半身时就被冻住。
///   • 手势掩码 / 命中测试 —— 与画面位置一致。
///   • **拖动从动画中途接管**：`drag().onChanged` 会 `stop()` 再 `dragBase = progress`。
/// `withAnimation(.spring)` 只动画*渲染*插值、不把中间值暴露成数据，且**无法**把
/// `DragGesture` 的释放速度种进弹簧：`floor.progress` 会立刻等于目标值（0/1），于是
/// 中途抓取会**跳变**、cover 阈值会在动画一开始就误触发、甩动速度也丢了。所以这里用
/// 一个能逐帧读真实进度、又能接收 `initialVelocity` 的显式弹簧驱动器 —— `Spring` 负责
/// 曲线，`CADisplayLink` 负责对齐 vsync 地逐帧推进（无 `Task.sleep` / 定时器唤醒抖动）。
@Observable final class FloorModel {
    var progress: CGFloat = 0

    // Spring trajectory state, advanced once per display refresh by a `CADisplayLink`.
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var spring: Spring = FloorAnim.settle
    @ObservationIgnored private var from: CGFloat = 0
    @ObservationIgnored private var to: CGFloat = 0
    /// Release velocity seeded into the spring, in **progress units / sec** (finger
    /// points/sec ÷ travel; up = +progress). 0 for taps / cancellations.
    @ObservationIgnored private var v0: CGFloat = 0
    /// Stamped from the link clock on the first frame (so the curve starts cleanly
    /// even if the first vsync is a beat late). `< 0` = not yet started.
    @ObservationIgnored private var startTime: CFTimeInterval = -1
    /// How long the spring takes to settle within `epsilon` of `to` given `v0` —
    /// the natural end of the animation (no fixed duration anymore).
    @ObservationIgnored private var settleDuration: CFTimeInterval = 0
    @ObservationIgnored private var completion: (() -> Void)?

    /// True while a settle spring is running.
    var isAnimating: Bool { link != nil }

    /// Stop any in-flight spring, leaving `progress` exactly where it visually is
    /// (a finger taking over the drag, or a new spring replacing this one).
    func stop() {
        link?.invalidate()
        link = nil
        completion = nil
    }

    /// Spring `progress` to `target`, seeding the spring with the release velocity
    /// so the settle continues the flick's pace (the iOS system feel). `completion`
    /// fires only when the spring lands naturally (never when stopped or replaced).
    ///
    /// `initialVelocity` is in progress units / sec (see `v0`); pass 0 for a tap or a
    /// cancellation (settle from rest). `spring` defaults to the shared settle spring.
    func animate(to target: CGFloat, initialVelocity: CGFloat = 0,
                 spring: Spring = FloorAnim.settle, completion: (() -> Void)? = nil) {
        stop()
        from = progress
        to = target
        v0 = initialVelocity
        self.spring = spring
        self.completion = completion
        startTime = -1
        // epsilon 0.001 = land within 0.1% of the 0…1 range. settlingDuration with
        // from == to is ~0 (and a residual v0 still damps in finite time), so a
        // no-op animate completes on the next frame rather than spinning.
        settleDuration = spring.settlingDuration(fromValue: from, toValue: to,
                                                 initialVelocity: v0, epsilon: 0.001)
        let proxy = FloorDisplayLinkProxy { [weak self] link in self?.step(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(FloorDisplayLinkProxy.handle(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// One vsync step of the velocity-seeded spring trajectory.
    private func step(_ link: CADisplayLink) {
        if startTime < 0 { startTime = link.timestamp }
        let t = link.timestamp - startTime
        if t >= settleDuration {
            progress = to
            let done = completion
            stop()
            done?()
            return
        }
        // SwiftUI's own spring solver → the curve *is* the system curve. Clamp to
        // [0,1] so any underdamped overshoot can't reveal a gap past the closed wall.
        let value = spring.value(fromValue: from, toValue: to, initialVelocity: v0, time: t)
        progress = min(1, max(0, value))
    }
}

/// Retains a `CADisplayLink` callback as a target + selector (CADisplayLink has no
/// block initializer). The link retains this proxy; the proxy captures `FloorModel`
/// weakly, so there's no retain cycle.
private final class FloorDisplayLinkProxy: NSObject {
    private let onFrame: (CADisplayLink) -> Void
    init(_ onFrame: @escaping (CADisplayLink) -> Void) {
        self.onFrame = onFrame
        super.init()
    }
    @objc func handle(_ link: CADisplayLink) { onFrame(link) }
}

/// The 上滑二楼 settle spring. **One** spring serves taps *and* drag-releases — the
/// release velocity (seeded per-call) is what differentiates them, so a hard flick
/// settles fast and a tap (v0=0) takes the spring's natural pace; no need for two
/// separate durations. Tuned to the iOS system feel: `duration` 0.42 (perceptual
/// pace) with `bounce: 0` = essentially critically damped — quick, no visible
/// overshoot, so closing never dips past the bottom wall to flash a gap. Want a
/// livelier open? Nudge `bounce` up (≈0.12) and rely on the `step` clamp; want it
/// snappier? Lower `duration`. The whole pull (panel · content · dome crown · stage
/// parallax) rides this one `progress` spring; there is no second motion track.
enum FloorAnim {
    static let settle = Spring(duration: 0.42, bounce: 0)
}

extension EnvironmentValues {
    /// 二楼是否完全打开（`p > coverThreshold`）。由 `FloorContainer` 写入 content
    /// 子树，历史页里的 `WaterSurface` 据此门控水面着色器 / `TimelineView` —— 合上
    /// 即停转，零开销。阈值翻转才变化（不是每帧），所以只在跨阈值那一刻让读它的
    /// `WaterSurface` 失效，不会让历史页逐帧重渲染。默认 `true`：未托管在
    /// `FloorContainer` 时（如 `PiboHistoryView` 预览）水面照常播放。
    @Entry var floorIsOpen: Bool = true
}
