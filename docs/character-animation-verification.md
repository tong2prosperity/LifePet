# 角色动画移植 · 待你验证清单

12 状态角色动画的移植已经写完（本轮范围 6 个状态）。这份清单是需要你验的部分，按「必须真机 / 需要人眼 / 需要你决策」分组。技术背景与决策记录见 [character-animation-port.md](character-animation-port.md)。

## 怎么开

矢量角色**默认关着**，旧的双 sprite 路径原样保留，可以随时并排比较：

```bash
# 矢量角色（本次移植的成果）
xcrun simctl launch <device> fun.tiebao.co.Pibo -PiboVectorCharacter
# 现状对照
xcrun simctl launch <device> fun.tiebao.co.Pibo -PiboLegacyCharacter
# 顺带：收起 DEBUG「森林细节」面板，它会挡住椰壳
xcrun simctl launch <device> fun.tiebao.co.Pibo -PiboVectorCharacter -PiboHideTuning
```

角色实验台（不受森林光照 / 倒影 / 天气干扰，问题能单独暴露）：

```bash
xcrun simctl launch <device> fun.tiebao.co.Pibo -PiboCharacterLab
```

Lab 参数：`-PiboLabState <default|muscle|pigu|sleep-1|sleep-2|awake>`、`-PiboLabZoom <0.5–4>`（真实重建放大，不是节点缩放）、`-PiboLabCycle`（自动巡演全部状态）、`-PiboLabCelebrate`（直接播运动完成剧本）、`-PiboLabReflection`（把倒影快照显示出来）、`-PiboLabNoWarp`。

---

## A · 必须在真机上验

模拟器的 GPU 路径与真机不同，这几条我给不出结论。

| # | 验什么 | 怎么验 | 关注点 |
|---|---|---|---|
| **A1** | **帧率** | 首页开矢量角色，叠在森林现有的着色器与风摆之上 | 静止时、600ms 状态切换中、muscle/pigu 连招中各看一次。模拟器上是稳定 60fps，但那不算数 |
| **A2** | **拖毛手感** | 按住头顶的芽拖动、松手，与 `-PiboLegacyCharacter` 对比 | 弹簧 rig 的宿主从贴图换成了矢量芽的离屏节点。参数没动，但手感是否一致只能上手 |
| **A3** | **水面倒影** | 看河面上有没有 Pibo 的倒影；切状态时倒影是否跟着变 | 倒影靠定期快照供图，快照只跟几何变化走、不跟待机走 —— 看这个取舍是否可接受 |
| **A4** | **抗锯齿** | 放大看芽的边缘，尤其叶片上那条白色高光线 | 离屏超采样按 3 倍定的（模拟器上足够），真机分辨率不同 |
| **A5** | **发芽特写** | 触发一次运动完成，看相机推近是否对准芽根 | 聚焦点改成按状态混合的芽根算，不再是旧的固定贴图位置 |

## B · 需要人眼判手感

设计包的验收基准是 **`pibo_context/preview/` 跑出来的效果**，不是文档。这几条我只能保证「跑起来了、没崩」，判不了「对不对」。

| # | 验什么 | 怎么验 |
|---|---|---|
| **B1** | **变形节奏** | 与 preview 并排跑同一组切换，看 600ms 加速冲入 + 落定 biu 的手感。设计师为这个节奏否过三版 |
| **B2** | **muscle / pigu 连招** | 并排逐动作核对时序：挥手→腹肌弹出+翘脚→芽抖；跺脚→屁股 duang×2+wink+✨飞星→芽抖 |
| **B3** | **闪亮登场** | 切到 muscle / pigu 时的单周期膨胀 + 金光，是否读作「亮相定格」而不是「弹一下」 |
| **B4** | **巢区落位** | 睡眠三态坐在椰壳洞口里的位置与大小。我按洞口目测调到 `(146, 358)` / 体宽 112，接近但可能还需要微调 |
| **B5** | **装饰进出时序** | 切状态时，旧装饰在前 22% 退干净、新装饰等身体走到 85% 才出现 —— 看有没有「手比身体先到」的怪感 |

## C · 需要你决策

| # | 事项 | 说明 |
|---|---|---|
| **C1** | **pibo-assets 首次提交** | 该仓目前**零 commit**，我只写了文件没提交。首次提交牵涉 Git LFS 与仓库历史形态，是你的决定。新增内容：`source/character-states/`（12 个源 SVG）、`tools/prematch/`（生成器 + 验收脚本）、`docs/character-animation/`（SPEC / DESIGN-NOTES / PIPELINE）、`ios/character/PiboCharacterData.json`、`manifest.json` |
| **C2** | **pibo-core 发版** | 我在 Core 里加了 `src/animation.rs`（+5 个测试，95 个全过）并重建了 xcframework，但**没有提交、没有发 tag**。发布流程：<br>`cd pibo-core && git add -A && git commit && git tag 0.4.0 && git push --tags`<br>→ 更新 App 的 exact pin 到 `0.4.0` 并提交 `Package.resolved`<br>→ 删掉本地 `Pibo.xcworkspace`<br>→ 同步 HarmonyPibo submodule 指针 |
| **C3** | **矢量角色默认开关** | 验收通过后把 `PiboVectorCharacterFlag` 默认打开（改 `UserDefaults` 默认值或直接返回 true），并决定何时删掉旧的双 sprite 路径 |
| **C4** | **椰壳素材精度** | 现用的是设计包自带的 `background/yeke.png`（504×950 = @2x）。它是干净的透明空壳，但在 3x 屏上会被放大 1.5 倍。要更清晰的话需要设计师出一版 @3x 空壳 —— Figma 里那几个 252×475 的组都把角色烘进去了、且带灰底，不能直接用 |
| **C5** | **未移植的 6 个状态** | `weak` / `angry` / `boring` / `tired` / `dive` / `coolhide` 的源母版已在 `pibo-assets`，标 `scope: deferred`。**Core 已经会返回它们了**，App 侧用一张 `available` 白名单挡着降级成 `default`。补齐这些状态需要设计师先做连招编排（当前只有基础待机） |

---

## 已经验过的（不用重复）

这些我在模拟器上验证过，列出来是为了让你知道边界在哪：

- 6 个状态全部完整渲染（五官 / 四肢 / muscle 腹肌 / pigu 腮红翘臀 / sleep 的 Zzz 与鼻涕泡 / awake 倒挂）
- 预匹配几何偏差最大 **0.135 设计单位 ≈ 0.067 pt**（@3x 下不到五分之一物理像素）；`boline` 结构化插值 6 态往返 **0.000000**
- `SKWarpGeometryGrid` 作用于 `SKShapeNode` 子节点成立；离屏超采样 3 倍能恢复抗锯齿
- 弹簧 rig 在 `default`（芽向上）与 `awake`（芽倒挂）两个根梢方向都正确
- 「运动完成 → muscle → pigu → 回常驻态」剧本端到端跑通
- 椰壳渲染 + Pibo 睡在洞里
- Rust 95 个测试、App 全部单元测试通过
