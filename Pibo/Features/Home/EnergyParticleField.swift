import SwiftUI

/// "喂养" 时从屏幕底部 1/3（按钮所在区域）抛物线飞向宠物中心的能量粒子层。
///
/// 翻译自 `原型-01-主页.html` 的 `.energy-dot` 动画 —— 单帧 spec：
/// ```
/// energyFly  0%   opacity:1 transform: translate(0,0) scale(1)
/// energyFly  80%  opacity:1
/// energyFly  100% opacity:0 transform: var(--fly-to) scale(0.3)
/// ```
/// SwiftUI 这边改成驱动一个 `progress: 0…1` 的 `TimelineView`，每帧重新求值
/// 每颗粒子的位置 / 缩放 / 透明度。
///
/// 触发：父视图把 `feedToken` 通过 init 传进来，token 变化（用户点了「喂养」）
/// 就 spawn 一批 ~16 颗，每颗带 30~60ms stagger。所有粒子共享一个全局起点
/// （sheet 按钮估算位置）和宠物中心（来自 `PetCenterAnchorKey`）。
struct EnergyParticleField: View {
    /// 父视图通过 onChange 同步过来；变化时 spawn 一批新粒子。
    let token: UUID?
    /// 宠物中心点（HomeView 已经从 anchorPreference + GeometryProxy 解到本视
    /// 图坐标系）。`nil` 时不 spawn —— 没有目标点的话粒子无处可去。
    let petCenter: CGPoint?
    /// 容器尺寸，用于估算粒子起点（屏幕底部 1/3，居中横向 ±100pt 抖动）。
    let size: CGSize

    @State private var particles: [Particle] = []
    @State private var lastToken: UUID? = nil

    var body: some View {
        // `paused: particles.isEmpty` 让 99% 没粒子的时候 TimelineView 不再以
        // 60fps tick —— 否则即使 home 切到 catalog tab 之后，这个 overlay 仍
        // 在后台每秒评估 60 次 Canvas 闭包（SwiftUI 不一定会把不可见 tab 内
        // 的 TimelineView 自动暂停掉，尤其 paused 写死 false 时）。叠加 home
        // 内其他 30fps TimelineView + catalog 自身的 BreathingSprite + HK
        // observer 偶发 fire 引发的 store mutation 重算，能复现切换卡顿。
        // particles 变非空时 paused 自动翻 false，TimelineView 立刻 resume。
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: particles.isEmpty)) { ctx in
            Canvas { gctx, _ in
                let now = ctx.date
                for p in particles {
                    let elapsed = now.timeIntervalSince(p.launchedAt)
                    guard elapsed >= 0 else { continue }
                    let t = min(1.0, elapsed / p.duration)
                    // ease-in: t² — 模拟原型 CSS 的 ease-in（默认 cubic-bezier
                    // 也是越往末尾越快）。
                    let eased = t * t
                    // Position: lerp + parabolic lift（中段微抬，让弧线更"飘"）。
                    let dx = (p.target.x - p.start.x) * eased
                    let dy = (p.target.y - p.start.y) * eased
                    // Lift: 4·t·(1-t) 在 t=0.5 处取最大，乘上 -28pt（屏幕坐标
                    // 系 Y 向下，负值是往上抬）。
                    let lift = -28.0 * 4.0 * t * (1.0 - t)
                    let x = p.start.x + dx
                    let y = p.start.y + dy + lift
                    // Scale: 1 → 0.3
                    let scale = 1.0 - 0.7 * eased
                    // Opacity: 1 → 1 (until 80%) → 0
                    let opacity: Double = t < 0.8 ? 1.0 : (1.0 - (t - 0.8) / 0.2)
                    let radius = 4.0 * scale
                    let rect = CGRect(
                        x: x - radius, y: y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    gctx.opacity = opacity
                    gctx.fill(Path(ellipseIn: rect), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: token) { _, new in
            guard let new, new != lastToken, let target = petCenter else { return }
            lastToken = new
            spawnBatch(target: target)
        }
    }

    private func spawnBatch(target: CGPoint) {
        // 起点：屏幕底部 ~78% 高度（喂养按钮中心估算位置），横向 ±100pt 抖动。
        let baseY = size.height * 0.78
        let baseX = size.width / 2
        let now = Date()
        let count = 16
        var batch: [Particle] = []
        batch.reserveCapacity(count)
        for i in 0..<count {
            let jitterX = CGFloat.random(in: -100...100)
            let jitterY = CGFloat.random(in: -20...20)
            let start = CGPoint(x: baseX + jitterX, y: baseY + jitterY)
            // Stagger 30~50ms，越后越慢，不要一起飞像一发炮弹。
            let delay = Double(i) * 0.038
            let launchAt = now.addingTimeInterval(delay)
            // 颜色三选一：sage（绿）、coralSoft（暖橙）、ink mint（蓝青），让
            // 视觉里能感到三种 stat 在被一起喂回去（虽然实际只 vitality 入账）。
            let color: Color = {
                switch i % 3 {
                case 0:  return Color(hex: 0x3EB24E)
                case 1:  return Color(hex: 0xD14B3D)
                default: return Color(hex: 0x4A90D9)
                }
            }()
            batch.append(Particle(
                id: UUID(), start: start, target: target,
                color: color, launchedAt: launchAt, duration: 0.9
            ))
        }
        particles.append(contentsOf: batch)
        // GC：动画跑完后批量丢弃已结束的粒子。TimelineView 每帧 enumerate 全
        // 表，放着不清会让数组无界增长（spam 点击场景）。
        Task {
            try? await Task.sleep(for: .seconds(1.2 + Double(count) * 0.038))
            let cutoffNow = Date()
            particles.removeAll { cutoffNow.timeIntervalSince($0.launchedAt) > $0.duration }
        }
    }
}

// MARK: - Particle model

private struct Particle: Identifiable {
    let id: UUID
    let start: CGPoint
    let target: CGPoint
    let color: Color
    let launchedAt: Date
    let duration: TimeInterval
}

// MARK: - Preview

#Preview("Energy field") {
    struct Demo: View {
        @State private var token: UUID? = nil
        var body: some View {
            GeometryReader { geo in
                ZStack {
                    Color(hex: 0xFAF7EF).ignoresSafeArea()
                    Circle()
                        .fill(Color.black)
                        .frame(width: 60, height: 60)
                        .position(x: geo.size.width / 2, y: 200)
                    EnergyParticleField(
                        token: token,
                        petCenter: CGPoint(x: geo.size.width / 2, y: 200),
                        size: geo.size
                    )
                    VStack {
                        Spacer()
                        Button("Fire") { token = UUID() }
                            .padding()
                    }
                }
            }
        }
    }
    return Demo()
}
