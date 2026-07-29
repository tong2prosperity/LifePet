# Pibo 角色动画移植日志

把设计交付包 `pibo_context`(lulu-design)的 12 状态角色变形动画，移植进 iOS 首页的 SpriteKit 森林场景。本文件记录**决策与实测结论**，不重复文档已有的内容 —— 行为契约看 `pibo-assets/docs/character-animation/SPEC.md`，构建期管线看 `pibo-assets/tools/prematch/README.md`。

## 本轮范围

6 个状态：`default` / `muscle` / `pigu` / `sleep-1` / `sleep-2` / `awake`。

muscle 与 pigu 是交付包里唯二做了精细连招编排 + 闪亮登场的状态，直接支撑「运动完成 → 高光表演」这条链路；sleep 三态支撑夜间。其余 6 态源母版已在 `pibo-assets/source/character-states/` 里，标记 `scope: deferred`。

`dive` / `coolhide` 的触发条件已定但本轮不做：同一条压力 z-score 的两端 —— 焦虑高 → dive 钻水，放松 → coolhide 耍酷。映射层的 Core 接口第一版就要把压力作为输入维度留进去，否则补这两个状态时要改 ABI 再发一次 tag。

## 架构选择

**路径变形（非骨骼、非序列帧、非 Rive）。** Pibo 是没有关节的团子，`body` 从 default 到 pigu 到 muscle 是整体轮廓的非刚性变化，绑骨骼要把团子切开重做蒙皮；12 状态两两组合 132 条过渡烘不动序列帧。路径变形恰好是这个形状唯一明显占优的场景。

不选 Rive 的原因不是它不好 —— 从零开始做这个功能大概率该用 Rive。是因为设计已在 Web 引擎里验收完毕，重做等于重走一遍 pigu/muscle 那几轮逐帧评审；而且 Rive 用自己的 Metal 渲染器，角色会掉出 SpriteKit，水面倒影 / 时段光照 / 发芽相机推近全部要重接。**什么时候该换：状态数涨到 30 以上，或设计师开始要「手臂挥舞、抬腿走路」这类关节运动。**

**变形的对应关系在构建期解决。** Web 用 flubber 运行时重采样，Swift 没有对应库。生成器把全部状态重采样到同一套拓扑，运行时只剩逐点 lerp —— N 个状态的 N² 种切换全部自动可用，数据量只有 O(N)。实测重采样几何偏差最大 0.135 设计单位（屏幕上约 0.067 pt，@3x 下不到五分之一物理像素）；`boline` 结构一致走精确贝塞尔插值，往返偏差 0.000000。

**芽（bo）参与 morph，同时保留现有弹簧 rig。** 这两件事一度被认为互斥，其实不是 —— `SKWarpGeometryGrid` 作用在渲染网格上，不碰路径数据。把 `bo` + `boline` 两个 `SKShapeNode` 放进一个 `SKEffectNode`，现有的 6 段骨骼阻尼弹簧 rig 原样驱动那个 effect node 即可。SPEC §7 第 6、7 条那两个坑（路径级形变把变形中间帧缓存成基准形状、待机与变形抢 `d` 属性）是 Web 引擎的实现债，在这个结构下不存在，因为 rig 根本不读路径。

## G0 实测结论（2026-07-28，Character Lab，iPhone 17 模拟器）

进 lab：`-PiboCharacterLab`，实验矩阵全走启动参数（`-PiboLabHost` / `-PiboLabSupersample` / `-PiboLabZoom` / `-PiboLabProgress` / `-PiboLabStroked` / `-PiboLabAutoMorph`），配合 `simctl io screenshot` 免点击取证。

**① `SKWarpGeometryGrid` 确实作用于以 `SKShapeNode` 为子节点的 `SKEffectNode`。** A 方案的地基成立。

**② 抗锯齿的损失来自 `SKEffectNode` 的离屏栅格化，不是 `SKShapeNode`。** 对照实验：不经离屏的芽边缘完全平滑；进离屏后边缘明显毛糙；**芽按 3 倍尺度建路径、宿主缩回 1/3（离屏超采样）后恢复平滑**。这是必须带进阶段 1 的实现约束。

> 一个方法教训：第一轮我用 `sips -Z` 放大截图来看细节，最近邻插值把平滑的抗锯齿渐变变成了硬阶梯，导致我先误判「`SKShapeNode` 也在锯齿」。**判断画质必须让角色真实渲染得更大（重建路径），截图不做任何缩放。**

**③ `boline` 两种模式在超采样之后都干净。** 默认仍用「描边转填充」：不依赖 SpriteKit 较弱的描边光栅化路径，也避开变形中短段产生的线帽伪影（porting guide 明确警告过）。中线插值（12 段贝塞尔，精确）之后再 `CGPath.copy(strokingWithWidth:)`，结构对应关系不受影响。

**④ 帧率 60fps 稳定（nodes 33 / draws 76，含自动变形逐帧重建路径）—— 但这是模拟器，GPU 路径与真机不同，此项结论暂定，需在真机复测。** draws 偏高是因为 spike 阶段所有元素都走矢量；生产上装饰改贴图后会降下来。

## 待验 / 已知未决

- **真机帧率复测**，尤其是叠在森林场景现有的 `.fsh` 着色器与 `ForestFoliageNode` 风摆之上时
- **`boline` 是否需要运行时 `SKCropNode` 裁剪**。SPEC §3 要求高光线始终裁剪在 bo 当前帧轮廓内；Web 那边会探出是因为 flubber 让两条路径收缩速度不一致，我们是同拓扑一起插值，大概率不会。阶段 3 目测 6 态之间 15 条过渡后再定
- **两套待机会打架**：rig 自带一条自主 idle，设计包也给 bo 配了门控 `rotate-around-point` + `path-wiggle`。阶段 2 把 rig 的自主 idle 系数降到 0，待机摆动交还设计包，rig 只保留风吹 + 交互 + 冲量
- **发芽 `growthStage`** 与新系统的共存（rig 目前把 growth 钉死为 1）

## 进度（2026-07-28）

### 已完成并验证

**阶段 0 全部完成。** 本地 Core 覆盖机制、素材并入 pibo-assets、预匹配生成器、G0 决策门（结论见上）。

**角色运行时（阶段 1 的组件部分）。** `Pibo/Features/Home/Stage/Character/`：

| 文件 | 职责 |
|---|---|
| `PiboCharacterData` | 生成数据的解码，跨端共用同一份 JSON |
| `PiboCharacterGeometry` | 控制点 → `CGPath`、状态间插值、描边转填充、两个路径形变场 |
| `PiboVectorCharacter` | 元素树、z-order、装饰淡入淡出、落定脉冲锚点、芽的离屏宿主 |
| `PiboStateTransition` | 600ms 加速贝塞尔 / 90ms 跨区硬切 / 落定脉冲 / 待机幅度融合 |
| `PiboIdleAnimator` | 门控时间线 + 本轮 10 个原语 |
| `PiboCharacterLighting` | 时段光照的 CPU 版颜色变换 |
| `PiboCharacterPlaybook` | 剧本：演完一段回到常驻态 |

Character Lab 里验过：6 个状态全部完整渲染（五官 / 四肢 / muscle 腹肌 / pigu 腮红翘臀 / sleep 的 Zzz 与鼻涕泡 / awake 倒挂）；待机编排运行时角色保持连贯、无元素飞出；**「运动完成 → muscle → pigu → 回常驻态」剧本端到端跑通**，装饰的 22% 退场 / 85% 入场时序在过渡帧上肉眼可辨。

一个结构上的收获：每帧的顺序是「重建基准路径 → 归位上一帧的待机姿态与形变 → 叠加这一帧待机」。因此路径级原语永远从一份干净的基准出发，不需要自己缓存「静止形状」——SPEC §7 第 6、7 条那两个坑（变形尾段启动的原语把中间帧缓存成基准、待机与变形抢 `d`）在这个结构下不成立。顺带让静止时的每帧开销塌缩成一遍变换归位，不做几何重建。

### 未完成

**阶段 1 的接入部分（决策门 G1 未过）。** 角色运行时目前只在 Character Lab 里跑，**尚未替换首页 `PiboCharacterRenderer` 里的双 sprite**。

**水面倒影这条已经验证可行。** `ForestReflectionProxy` 靠采样一个 `SKSpriteNode` 的纹理来做镜像，而一棵 shape 节点树没有纹理。解法是角色自带一个隐藏的 `reflectionSource` sprite，用 `SKView.texture(from:)` 定期给它拍快照 —— 已在 Lab 里验过，抓到的是完整分辨率的角色。投影侧加了一个 `treatsSourceAsInvisibleProxy` 模式：source 只提供几何与像素，自身的 `isHidden` / `alpha` 不再传导给镜像（原逻辑会因为 source 隐藏而把倒影一起藏掉）。快照只跟**几何**变化走（切状态、变形帧），不跟待机走 —— 待机是几个点的摆动，而倒影是水下一层暗淡带波纹的镜像，为它每帧付一次 render-to-texture 远不划算。

剩下两件：

1. ~~**弹簧 rig 接入**~~ —— **已完成并验证**。`PiboHeadRigDeformer` 的目标从 `SKSpriteNode` 泛化到 `SKNode & SKWarpable`（它只写 warp 网格，不关心宿主是谁），新增 `attach(toSprout:axisInverted:pivotFraction:)`。两个参数都是必需的：rig 的模型是「根部钉死、越往梢部越软」，而 `awake` 的芽倒挂出椰壳洞口、梢在根**下方**，不翻转就会从错误的一端弯；`pivotFraction` 则因为叶根在每个姿势里落在包围盒的不同位置，原来那个从旧贴图烘出来的常数只对 default 成立。逐状态的根梢由 `sproutWarpAnchor` 按 effect node 的实际内容边界算出（那才是 `SKWarpGeometryGrid` 归一化的空间）。Lab 里验过 default（芽向上）与 awake（芽倒挂）两个方向都正确。
2. **首页接入已打通（开关后面）。** `PiboCharacterRenderer` 里加了矢量分支，由 `PiboVectorCharacterFlag` 控制（DEBUG 下 `-PiboVectorCharacter` / `-PiboLegacyCharacter`，否则读 UserDefaults）。旧的双 sprite 路径原样保留，两条路可以在真机上并排比较。已接通：构建、站位、状态映射（`PiboAnimationStateMap`）、每帧驱动（过渡 + 待机 + rig + 倒影快照）、命中测试、拍一拍、天气落点、Zzz。**矢量角色已在真实森林场景里渲染出来并显示正确状态。**

   命中测试顺带变好了：几何直接取自正在显示的路径，看到的轮廓与摸得到的轮廓不可能漂移；旧路径靠贴图逐像素采样，形变时两者会分家。

   **FX 复核结果比预期好。** `playEnergyGain` / `playPluck` / `playSproutGrowth` 走的是 `headRig.isEnabled` 分支，而 rig 已经挂在矢量芽上，所以它们**已经生效**（冲量、种子掉落、火花都正常），只有对隐藏 `headNode` 的那句 scale 是空转。真正需要矢量分支的只有 `playSproutCloseup` —— 它按 `headNode.position` 算聚焦点，矢量路径下那个值恒为 0；已改为取 `sproutAxis` 混合出的芽根。

   **G1 剩下的是真机交互验证**：拖毛手感、水面倒影是否正确出现在河面上。这两件截图证明不了。

**舞台定位已完成（地面区）。** 一度以为 Figma 那 13 个 `home` 帧是「每状态一份定位」，查下来不是：帧与帧之间换的是**状态本身**（5663:4433 放的是 weak、5675:3278 放的是另一个、5758:956 是空场景），而同区状态的相对位置早已烘在各自的 300×300 画板里。正确的模型是**按区一份**（地面 / 巢），与 DESIGN-NOTES §3「跨区位置差异太大要硬切」自洽。

也不必从 Figma 反解：`ForestSceneManifest.piboFootPoint = (196.5, 610)` 是 App 里已经调好的落脚点，新美术是同一个角色，直接沿用。`PiboVectorCharacter.fit(bodyWidth:footPoint:)` 按当前混合姿态的 body 包围盒把角色底线贴到该点，体宽沿用现有的 `181.1602 × mapper.scale`。Lab 里画了地线核对，default / muscle / pigu 三态都稳稳站在线上、体宽一致。巢区等椰壳图层进场景后再定。

（试过从 Figma 的 `Group 276`（weak 在 5663:4433 里的落位，208×185 @ 61.7,481）反解比例，横纵解出 0.857 与 0.968 明显不一致 —— 用路径数字对估的包围盒把控制点也算了进去，x/y 膨胀量不同。这条路作废，记在这里免得有人再走一遍。）

时段光照这条已经解决——不走 shader，改成 CPU 颜色变换（数学与 `ForestMaterial.fsh` 逐行一致），反而比原方案好：不需要离屏，不损抗锯齿。

**阶段 2 —— 编排引擎与登场（代码完成，G2 验收待人眼）。** 10 个原语 + 门控时间线 + 剧本都实现了。闪亮登场也做了：过渡驱动多一个 `.intro` 阶段，落定之后走单周期阻尼正弦（膨胀→缩回→定格）＋两层 `glowWidth` 描边的金光（快起慢收、自行消散），期间常规连招暂停 —— 亮相是定格 pose，不是把动作演快（设计师否掉过「首轮连招压缩快放」那版）。连招时间轴改由 `onIntroFinished` 触发，所以没有登场的状态也仍然从自己的 0 秒起播。

**但 G2 没过**：没有与 `preview/` 做逐动作的时序比对。设计包的验收基准是「preview 跑出来的效果」，静态截图证明不了手感，这一条需要并排录屏，见验证清单 B1–B3。

### 阶段 3 —— 椰壳与巢区（完成）

椰壳进 `ForestSceneManifest`（`forest_yeke`，落位 `(20, -37, 252×475)` 取自 Figma home 帧 5758:956）。**只有一层，且垫在角色底下**：睡眠三态的角色形状已经按洞口手工裁切（蒙版烘焙进美术里），整体压上去就是对的；把椰壳打进角色动画会得到「空壳」与「带角色的壳」两份对不齐的资产，而且呼吸会把壳带歪（DESIGN-NOTES §3）。我一度以为要拆前后两层，那是外推错了。

素材用的是设计包自带的 `background/yeke.png`（504×950 = @2x，干净透明空壳）。Figma 里那几个 252×475 的组**不能直接用** —— 它们把角色烘进去了，而且导出带不透明灰底。@3x 空壳需要设计师补，见验证清单 C4。

巢区定位是第二个锚点 `piboNestAnchor`，跨区 90ms 硬切正因为两个区位置差太远、插值没有意义。

### 阶段 4 —— Core 映射层（完成）

`pibo-core/src/animation.rs`：输入（六态 + 压力 z-score + 是否有基线 + 是否睡够 + 连续低能量天数）→ 输出（`AnimationState` + 是否允许运动庆祝）。ABI 两个函数，Swift 包装 `Sources/PiboCore/PiboAnimation.swift`，App 侧 `PiboCoreAnimationAdapter`。Rust 95 个测试全过（含新增 5 个）。

三个设计要点：

- **冷启动的 z-score 不算数。** 没有基线时的 0 是「没有数据」，不是「今天很平静」，据此挑 `coolhide` 是在编造情绪。有专门的测试钉住这一条。
- **衰退线压过当日读数。** 连续多天低能量时 Pibo 是 `weak`，不会因为今天步数凑巧达标就精神抖擞。
- **不是每次运动都值得庆祝。** 深眠里被叫醒秀肌肉会读成 bug；正处在颓势姿态上突然亮相会把那个姿态的意义抵消掉。

App 侧接线在 `HomeView` 的发芽流程收尾处：发芽讲的是「收集到能量」，剧本讲的是「你今天动过了」，两件事接着演而不是抢同一个时刻。

Core 已经会返回全部 12 态，但只有 6 态有运行时美术，所以 `PiboAnimationStateMap.available` 白名单把其余的降级成 `default` —— Core 跑在移植前面时降级，而不是渲染不出东西。

### 阶段 5 —— 收口（待你决策）

代码与文档都就位，但**跨仓提交与发版没有做**，那是你的决定：`pibo-assets` 目前零 commit；`pibo-core` 的改动未提交未发 tag，App 仍通过本地 workspace 覆盖消费。完整流程与命令见 [character-animation-verification.md](character-animation-verification.md) 的 C1 / C2。

### 顺序建议的调整

原计划是先接首页再做编排。实际做下来，**先在 Lab 里把编排和剧本做完、最后一次性接首页**更划算：Lab 没有光照 / 倒影 / 天气的干扰，角色本身的问题能被单独暴露；而接入要动的倒影、rig、FX 三处本来就都排在阶段 3。

## 依赖与收口

开发期用 `Pibo.xcworkspace`（已 gitignore）把本地 `pibo-core` 覆盖到远程 exact pin 之上，免去每改一次 Rust 就发 tag。已验证：走 workspace 解析到本地 checkout，走 `.xcodeproj` 解析到远程 `0.3.0`，且 `project.pbxproj` 与 `Package.resolved` 零 diff。**回到正式依赖 = 打开 `.xcodeproj` 而不是 `.xcworkspace`**，没有需要记得撤销的改动。

发布前：pibo-core 发 plain SemVer tag → 更新 App exact pin 并提交 `Package.resolved` → 删除本地 workspace → 同步 HarmonyPibo submodule。
