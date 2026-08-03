# pibo-context 动画迁移与集成规格

> 状态：iOS 与 Core 已实施；300×300 终态、460×460 播放器坐标和切换时序已在 Simulator 重新验收；未向真机安装  
> 更新：2026-07-31  
> 目标：将 `/Users/trevorlink/Project/PiboWorld/pibo_context` 的 12 状态角色动画完整集成到 Pibo iOS 首页，并形成可与 HarmonyOS 共享的确定性规则。  
> 当前依赖：App 精确固定已发布的 `pibo-core 0.5.2`；HarmonyPibo 必须在本轮 iOS 验证后按发布顺序更新到同一版本。

本文是本轮动画集成的实施依据。旧的 [`character-animation-port.md`](character-animation-port.md) 是早期技术移植日志，其中关于 6 态范围、Core 版本和旧映射的内容只作历史参考；与本文冲突时以本文及用户后续确认结果为准。

## 1. 产品意图

动画的工作不是表现“用户把 Pibo 养好或养坏了”，而是让用户感到自己的行为与 Pibo 有联系：

> 健康数据触发 Pibo 主动调整当天节奏；动画是 Pibo 对用户的回应和镜像，不代表用户把 Pibo 弄伤、养坏或导致关系倒退。

因此：

- 所有状态都必须能追溯到用户的行为、身体状态、时间或与 Pibo 的直接交互；
- MVP 不依赖尚不存在的实验、探索、通信或任务资源；
- 低活动、睡眠不足、无数据和权限拒绝都不能使 Pibo 受伤、衰败、责怪用户或关系倒退；
- `weak` 对用户的定义是“Pibo 主动收束动作、以低速状态同行”，不是疾病或严重虚弱；
- 素材中的枯黄、瘫软和叹气存在误读风险，产品文案必须把它解释为降低动作、靠树观察，用户侧不得称“严重虚弱”。

## 2. 源与职责边界

### 2.1 动画源

- 视觉和动作验收基准：`pibo_context/preview/` 的实际播放效果；
- 状态路径与参数源：`pibo_context/pibo.states.js` 与 `build-states.js`；
- 12 个 SVG 母版：`pibo_context/character-states/`；
- iOS/HarmonyOS 共用的正式动画资产应进入 sibling 仓库 `pibo-assets`，不把动画二进制放入 `pibo-core`；
- 睡眠场景是**椰壳**。Harmony 原型中的“吊床”文案以及 `sleep-hammock-3x.png` 文件名均为误读，不代表新增吊床资产。

### 2.2 Core 与 App

`pibo-core` 负责跨平台纯规则：

- 从原始领域输入选择稳定的语义动画 ID；
- 时间窗、阈值、冷启动、容差、滞回和每日确定性选择；
- 状态优先级、事件去重、冷却及稳定 content key；
- 不返回平台文件名、绝对路径或本地化文案。

iOS App 负责平台能力：

- HealthKit 读取、通知调度与点击路由；
- 持久化“已处理/已展示/最后一次成果”等状态；
- SpriteKit 渲染、场景落位、Modal、音效、触觉和本地化文案；
- 前后台生命周期以及真机性能。

不得在 Swift 中复制 Core 拥有的阈值和选择算法。

## 3. 12 个状态的已确认语义

| 动画 ID | 已确认语义或触发 | 场景区域 |
| --- | --- | --- |
| `default` | 未命中特殊状态时的正常同行 | `ground` |
| `awake` | 06:00–10:00，睡眠正常或没有有效睡眠数据 | `nest`，椰壳 |
| `tired` | 睡眠少于个人基线（含容差） | `ground` |
| `boring` | 14:00 后，睡眠正常且活动较少 | `treeTraverse` / `treeRest` |
| `weak` | 14:00 后，睡眠不足且活动较少；表示主动降速同行 | `treeRest`，靠中心树干且尾部不悬空 |
| `pigu` | 用户完成一项 HealthKit workout 后的成果反馈 | 只在 Modal 内播放；主场景不出现 |
| `muscle` | 当天步数首次从 `<10,000` 跨到 `≥10,000` | Modal 内播放；确认后 `ground` 保持成果姿势 |
| `angry` | 10 分钟内发生第 3 次真实拍击 | `ground`，临时覆盖状态 |
| `dive` | 静息真实 RMSSD 明显低于个人压力基线，Pibo 主动降低刺激 | `water`，水面左侧大石后 |
| `coolhide` | 静息真实 RMSSD 明显高于个人压力基线，表示用户明显放松 | `grassHide`，圆形草丛后仅露头、墨镜和上半脸 |
| `sleep-1` | 22:00–06:00 的睡姿 A | `nest`，椰壳 |
| `sleep-2` | 22:00–06:00 的睡姿 B；拔毛后的短睡固定使用此状态 | `nest`，椰壳 |

## 4. 持续健康状态规则

### 4.1 睡眠不足

- 优先使用用户个人睡眠基线；
- 基线取最近最多 28 个已完成夜晚的睡眠时长中位数；
- 至少 5 个有效夜晚才形成个人基线；
- 尚未形成基线时使用 7 小时；
- 容差为 `max(基线 × 4%, 0.1 小时)`；
- 判定：`睡眠时长 < 基线 - 容差`；
- 没有有效睡眠数据时不判断为睡眠不足。

### 4.2 活动较少

只在 14:00 后判断：

```text
steps < 3000 && 当天没有 workout
```

没有有效活动数据时不判断为活动较少。

### 4.3 按时间选择

| 时间 | 结果 |
| --- | --- |
| 06:00–10:00 | 睡眠不足 → `tired`；否则（含无睡眠数据）→ `awake` |
| 10:00–14:00 | 睡眠不足 → `tired`；否则 → `default` |
| 14:00–22:00 | 睡眠正常＋活动较少 → `boring`；睡眠不足＋活动较少 → `weak`；仅睡眠不足 → `tired`；否则 → `default` |
| 22:00–06:00 | `sleep-1` 或 `sleep-2` |

状态只在有意义的事件上重算：App 进入前台、HealthKit 更新、06/10/14/22 点、跨日、拍击窗口变化、压力数据更新或过期、成果 Modal 确认。不得每帧重新计算领域状态。

## 5. 成果动画

### 5.1 `pigu`：完成运动

```text
完成 HealthKit workout
→ 发出或替换本地通知
→ 用户点击通知，或直接打开 App
→ 展示成果 Modal
→ Modal 内完整播放一次 pigu
→ 显示 Pibo 文案入口、运动摘要和“确定”按钮
→ 点击确定关闭
→ 首页直接切回 Core 判定的健康状态，**不保留 `pigu`**
```

规则：

- 多项运动只播放一次，使用最后一项运动；
- 其他运动仍正常记录并参与 `bo`，只是合并动画反馈；
- pending 通知合并/替换，只保留最后一条；
- 当天尚未展示时可在直接打开 App 后补播，跨日不补播；
- 深眠期间不立即播放；
- **`pigu` 只在成果卡片里演，主场景任何时候都不出现**（2026-08-04 决定）。它不是一种「今天的状态」，挂一整天会盖掉真正在变化的东西。旧的「发芽收尾再演一遍首页剧本」那条路径同时移除 —— 那等于同一件事演两次；
- 当前旧的 `muscle → pigu` 连播必须拆开，运动完成只播放 `pigu`。

### 5.2 `muscle`：首次达到一万步

- 当天步数首次从 `<10,000` 跨到 `≥10,000` 时触发；
- 每天最多一次，历史回填不补播；
- 使用与 `pigu` 相同的通知、Modal 和确定按钮规则；
- 与 `pigu` 不同的是，`muscle` 确认后会留在首页并保持至 22:00；
- 通常由最近发生的成果决定最终首页姿势；
- 同一批 HealthKit 更新同时发现 workout 和万步时，只展示 `pigu`，同时将万步标记为已处理；
- “同一批”在实现中精确定义为一次确定性的 HealthKit 成果采集/对账：先评估 steps，再评估 workout；两个事实都在该轮被发现时，后评估的 workout 替换共享 pending 与共享通知，因此最终只呈现 `pigu`；
- 先发生 `muscle`、后发生 workout，最终保持 `pigu`；反过来则最终保持 `muscle`。

### 5.3 成果 Modal 的播放与关闭

- Modal 打开后自动播放一次目标状态的完整动画：约 0.9 秒登场加一轮约 6 秒连招；连招随后按自己的 `gateCycle` 继续循环，与 `preview/` 的播放器一致；
- 关闭 Modal 后首页不再演连招：`pigu` 直接切回健康状态，`muscle` 改用设计侧 `setIdleOverride` 的那条 `breathe-y`（见 §5.6）；
- “确定”按钮从 Modal 出现时就可用；提前点击代表跳过剩余动画并关闭，不强迫用户等待约 7 秒；
- 禁止下滑关闭和点击背景关闭，避免成果被误操作跳过；
- 无论完整播放还是提前点击确定，都记录为当天已经展示，不再次补播；
- Modal 的文案和运动摘要从打开时即可阅读，不等待动画结束。

### 5.4 白色能量汇聚

- 保留 Harmony 原型使用的 170–250 帧白色汇聚段；源 MOV 为 1.35 秒，运行时按原型精确压缩为 1.22 秒；
- 它表达“用户完成的成果汇聚到 Pibo 身上”，不是通用加载动画；
- 播放顺序为：白色汇聚 → 直接显示目标 `pigu/muscle` → 目标状态 intro → 一轮完整连招；
- 汇聚期间隐藏 Pibo；汇聚结束不显示 `default`，也不播放 `default → 目标状态` Morph；
- 用户提前点击“确定”时立即停止汇聚或后续角色动画并关闭；
- 不为这一段动画给 App 增加完整 Lottie 运行时依赖；
- 原始 JSON 进入 `pibo-assets/source/`，生成透明 ProRes 4444 母版与 iOS HEVC Alpha 衍生文件，App 只复制并播放版本化的 iOS 衍生物；

### 5.5 成果文案

Core 只返回稳定 content key 和结构化参数，App 负责本地化文本与运动类型名称。MVP 使用：

| Content key | 场景 | 中文文案 |
| --- | --- | --- |
| `animation.workout.notification` | workout 本地通知 | 你刚完成了「{运动类型}」。我注意到了。 |
| `animation.pigu.modal` | `pigu` Modal | 你动起来以后，我这里也有了变化。 |
| `animation.steps_10000.notification` | 万步本地通知 | 今天走到 10,000 步了。我注意到了。 |
| `animation.muscle.modal` | `muscle` Modal | 走了这么远，我也想试试这个姿势。 |

文案不使用夸奖、训导、卖萌、傲娇、病弱、喂养、“花精神了”或旧星光语义。

### 5.6 首页成果保持态的微动

只有 `muscle` 会停在主场景。`pigu` 见 §5.1：运动完成只在成果卡片里演一次，确认后
首页直接切回健康状态。

`muscle` 的保持参数取自设计侧的集成原型（`pibo_design/integration/harmony-home-preview/index.html`
的 `resultIdleConfigs` / `setIdleOverride`）：`breathe-y` · 4.2s · amplitude 0.018 ·
仅纵向 · origin `150px 270px`（它自己的着地点）。override 会**整体替换**该状态的
idle，所以保持期间没有挥手、腹肌弹动或芽抖。保持至 22:00。

设计包里 `pigu` 也有一条同规格的 override（origin `165px 292px`），本轮没有落点 ——
不是漏了，是它不再有主场景保持态。

## 6. 拍击与 `angry`

- 统计真实拍击次数，不统计“成功说出文案”的次数；
- 10 分钟窗口内第 3 次真实拍击触发 `angry`；
- `sleep-1`、`sleep-2` 和 `awake` 期间拍击只显示文案，不触发 `angry`、不切状态；
- `angry` 可以临时覆盖已经保持的 `muscle` 成果姿势；
- `angry` 保持 10 分钟，期间继续拍击不延长时间，避免永久锁定；
- 10 分钟结束后清空本轮拍击计数，并重新计算状态：优先恢复当日成果姿势，否则恢复健康状态；
- 成果 Modal 可覆盖 `angry`；Modal 关闭时若 `angry` 尚未结束，则继续 `angry`；
- Modal 跨过 22:00 时允许用户看完，确认后直接进入睡眠，不恢复 `angry`。

拍击文案同样由 Core 返回稳定 content key，App 本地化：

| Content key | 场景 | 中文文案 | 气泡 |
| --- | --- | --- | --- |
| `animation.sleep.pat` | `sleep-1/sleep-2` 拍击 | Pibo 设置了请勿打扰 | **系统提示**（青色描边 + 月亮图标） |
| `animation.awake.pat` | `awake` 拍击 | 我刚醒。让我再待一会儿。 | Pibo 正常气泡 |
| `animation.angry.enter` | 第 3 次真实拍击进入 `angry` | 三次了。我需要安静一会儿。 | Pibo 生气气泡 |

睡眠态的那条不是 Pibo 说的话——睡着的角色不该开口，所以它走
`PiboSpeechSource.system`，用与 Pibo 任何情绪都不同的青色描边渲染，光凭颜色就能
分辨"这不是一句话"。它也不消耗拍一拍的说话额度。

## 7. 压力动画

- `dive/coolhide` 的触发来源是 Apple Watch 心跳间期计算出的真实 RMSSD，而不是 HealthKit 预计算的 SDNN；
- 不允许用 SDNN、纯心率估算或其他代理值降级猜测；
- RMSSD 必须通过现有心跳序列质量过滤；
- 测量期间不能与 workout 或睡眠重叠；
- 至少 7 个有效历史日才形成压力基线；
- RMSSD 样本最长有效 6 小时；
- 基线不足或没有有效样本时不触发 `dive/coolhide`；
- 只在 10:00–22:00 展示 `dive/coolhide`；
- `z ≤ -1.0` 进入 `dive`；`dive` 在 `z > -0.5` 时退出；
- `z ≥ +1.0` 进入 `coolhide`；`coolhide` 在 `z < +0.5` 时退出；
- 不把 `dive` 放入普通拍一拍或无数据随机池。

低 RMSSD 不能被表述成“用户现在有压力”或“用户正在焦虑”，因为睡眠、疲劳、饮酒、疾病、呼吸和测量姿势等都可能影响它。`dive` 的产品含义是：Pibo 观察到用户当前恢复/调节状态明显低于自己的平常水平，因此主动降低刺激。没有 Apple Watch、没有可信心跳序列或未形成基线的用户可能始终不会看到 `dive/coolhide`；MVP 接受这个覆盖率取舍，以保证状态含义可信。

Core `0.5.0` 曾存在方向错误：系统语义是负 z 更紧张、正 z 更放松，但动画选择代码反向映射。该问题已在 `0.5.1` 修正；当前 `0.5.2` 继续覆盖方向、边界、滞回、过期及语义 transition intent。

## 8. 睡眠动画

- 每个自然夜晚按日期稳定选择 `sleep-1` 70% / `sleep-2` 30%，同一夜不变化；
- 两者只是睡姿变化，不表示睡眠质量好坏；
- 拔毛后的短睡固定 `sleep-2`；
- `sleep-1 / sleep-2 / awake` 期间连续拍击也不能切换成 disturbed/angry；
- 睡眠三态全部使用现有椰壳，不新增“吊床”。

## 9. 场景区域与过渡

iOS 迁移前只有 `ground / nest`，本轮已经扩展为：

```text
ground / nest / treeTraverse / treeRest / water / grassHide
```

- `boring`：主树后，12 秒进入＋4 秒停留＋12 秒离开循环；
- `weak`：靠中心树干，尾部不能悬空；
- `dive`：水面、左侧大石后；
- `coolhide`：圆形草丛后，只露头、墨镜和上半脸；
- `sleep-* / awake`：椰壳；
- 其他状态：中央地面。

业务切换与定位规则：

- 角色几何始终使用完整 300×300 设计画板注册，不能按每个状态的 body bounds 单独 `fit`；
- 首页落位的真实合同是一个 460×460 播放器：300×300 画板在播放器四边各留 80px；状态 CSS 的 `left/top/scale` 作用于播放器，不直接作用于裁掉透明边距后的画板；
- `bounceCut` 必须缩放完整播放器，缩放中心是播放器 `50% 58%`。换算到 300×300 画板局部坐标后是 `50% 62.2667%`，不能复用落地 pulse 的 `50% 80%` 锚点；
- 数据驱动的普通状态切换使用 `hardCut`，目标状态和目标画板落点在同一次更新中生效；不播放 600ms 路径 Morph，也不增加 90ms 跨区淡入淡出；
- 路径 Morph 只保留给明确要求 authored transition 的独立表演/工具入口，不是首页业务状态切换策略；
- 冷启动直接落在最终区域与最终状态；
- `boring` 的 12 秒进入与 12 秒离开均使用原型的 `cubic-bezier(.42, 0, .58, 1)`，中间停留 4 秒；
- 当前森林已有树、水、石和草，不新增背景场景资源。

原型 393×852 画布中的固定画板合同：

| 状态区域 | 300×300 画板外框（x, y, w, h） | 遮挡层级 |
| --- | --- | --- |
| 普通地面 | `(61.5, 356, 270, 270)` | 前景角色层 |
| 椰壳 `sleep-* / awake` | `(25, 146.8, 210, 210)` | 椰壳上方 |
| `weak` | `(61.5, 442, 270, 270)` | 尾部搭中心树干 |
| `dive` | `(61.5, 580, 270, 270)` | 主树上、左前景石下 |
| `coolhide` | `(190, 292, 195, 195)` | 圆草丛下 |
| `boring` | `y=364, 270×270`；x 为 `-300 → 61.5 → 393` | 主树下 |

### 9.1 已确认：`angry` 的 `bounceCut`

第 3 次真实拍击进入 `angry` 时使用 Core `0.5.2` 返回的 `bounceCut` intent；其他普通健康状态仍使用 `hardCut`。精确节奏来自 `pibo_context/preview/app.jsx`：

1. 旧状态留在旧落位，190ms 缩小退出；缓动 `cubic-bezier(.58,.02,.9,.45)`，scale 为 `1 → .84@42% → .04`，alpha 为 `1 → 1 → 0`；
2. 在 190ms 边界同时切换状态、播放器落位和遮挡层，不能先换形象后换位置或晚一帧换位；
3. 新状态在新落位用 520ms 进入；缓动 `cubic-bezier(.18,.82,.25,1)`，X/Y scale 依次为 `.04/.04 → 1.18/.86@38% → .88/1.12@60% → 1.07/.95@76% → .98/1.025@90% → 1/1`；
4. 710ms 结束时 alpha 和 X/Y scale 必须精确归一，并从目标状态待机时间轴的起点开始。

## 10. 已解决的代码与迁移缺口

迁移前 iOS 仅接入以下 6 态：

```text
default / muscle / pigu / sleep-1 / sleep-2 / awake
```

以下 6 态当时尚未进入可用白名单：

```text
weak / angry / boring / tired / dive / coolhide
```

本轮已经完成：

1. 将最新 `pibo_context` 数据重新走 `pibo-assets` 的生成与版本流程，不能从设计目录运行时直读；
2. iOS 待机运行时补齐或核对 `sigh-sequence`、`bring-to-front`、`pop-loop`、`bubble-breathe`、`wink-morph`、随机眨眼、多段 `gateRanges`、`controlsOnly`、`shake/bob/sway`；
3. 修复非 `compound` idle 被解析为空的问题，否则部分状态只有静态姿势；
4. 将场景区域从 2 个扩为 6 个，并按原型实现状态与落点同步 hard-cut；
5. 中途重定向 Morph 需要从当前几何继续，不能跳回旧起点；
6. 通知路由增加 workout/万步成果入口；pending 从“最多恢复一小时”改为“同日有效”；
7. 新建独立成果 Modal，拆除现有“发芽特写＋能量卡”和 `muscle → pigu` 旧剧本的绑定；
8. 增加动画状态、阈值边界、事件去重、优先级和跨日测试；
9. Simulator 已完成 12 态、六区、成果 Modal、白色汇聚和退出路径验收；帧率、拖毛、抗锯齿、水面倒影、HEVC Alpha 硬件解码与椰壳 @2x 清晰度不属于本轮 Simulator 验收结论。

系统“减弱动态效果”适配不是本轮上架硬性门槛，MVP 动画迁移明确不纳入 Reduce Motion 分支；后续如要提升无障碍体验，作为独立任务评估，不阻塞本轮开工与验收。

## 11. 已确认的覆盖关系

以下覆盖关系已经确认：

1. 成果 Modal 是最前台的一次性呈现；
2. Modal 跨 22:00 可播放完，关闭后直接进入睡眠；
3. 非睡眠时间内，`angry` 临时覆盖成果保持姿势；
4. `angry` 结束后恢复当日成果姿势，没有成果才回到持续健康状态；
5. 同批 workout 与万步事件只展示 `pigu`；不同时发生时，最近成果决定保持姿势。

持续状态的全局优先级为：

```text
成果 Modal
→ 睡眠
→ angry
→ pigu/muscle 成果保持
→ weak
→ tired
→ boring
→ dive/coolhide
→ awake/default
```

`dive/coolhide` 是正常白天状态的细分，不覆盖更明确的睡眠、运动、拍击、睡眠不足或低活动事实。

## 12. 待机动作验收

MVP 直接以 `pibo_context/preview/` 当前效果作为以下状态的动作验收基准：

- `default`：呼吸、眨眼、间歇小跳、芽摆动；
- `tired`：4.2 秒缓慢呼吸；
- `boring`：原地蠕动、芽摇摆、随机眨眼，配合 28 秒穿场；
- `weak`：叹气式收缩、垂芽慢摆、低频眨眼。

MVP 不要求设计侧重新编排。只有本轮 Simulator 验收或后续发布前验收发现明显穿模、悬空、动作语义误读或性能问题时，才针对问题调整。

至此，开工前产品决策已经闭合；后续发现的新问题按实现缺陷或变更请求处理，不再阻塞进入编码阶段。

## 13. 实施顺序

1. 先以 `pibo-core 0.5.1` 修正压力方向并发布，随后以 `0.5.2` 增加 semantic transition intent；
2. 将最新动画源生成到 `pibo-assets`，版本化后复制 iOS derivative；
3. 补齐 iOS 12 态运行时、待机原语与 6 区落位；
4. 实现 HealthKit 事件去重、本地通知、路由、成果 Modal 和同日恢复；
5. 增加单元/集成测试，在 Simulator 完成状态矩阵；
6. 在 Simulator 完成动作时序、成果终态、退出路径和 Figma 对照验收；
7. 打开矢量角色默认开关，保留旧渲染路径作为短期回退，稳定后再单独决定删除。

## 14. 完成定义

- 12 个状态均可由稳定语义 ID 渲染，无降级白名单；
- 所有已确认阈值、时间窗、去重、跨日和覆盖关系有自动测试；
- iOS 与 HarmonyOS 对相同领域输入选择相同语义状态；
- `pigu/muscle` 通知进入、直接打开 App、同日补播和多事件合并均通过；
- 睡眠拍击不会触发 angry，压力方向不再反转；
- 6 个场景区域按固定 300×300 画板落位正确，业务切换不出现长距离形变或晚一帧换位；
- 本轮按 2026-07-30 的明确决定只做 Simulator 验收；真机帧率、抗锯齿、倒影、拖毛、硬件解码和椰壳清晰度留作发布前独立验收，不安装到用户真机；
- 所有用户文案符合当前 Pibo 人物与伦理边界。

## 15. 2026-07-30 实施与验证记录

### 2026-07-31 定位与切换坐标系复审

- 用户复审指出当前角色定位和切换位置与 `pibo_context` 不一致。原自动测试只证明裁切后的 300×300 画板坐标相等，不能证明运行时完整播放器的缩放中心、遮挡与切换帧相等；旧结论据此撤回并重新验收；
- App 已固定 `pibo-core 0.5.2`，`angry` 入场是否使用 `bounceCut` 由 Core 的 semantic transition intent 决定；
- iOS 现保留 460×460 播放器坐标合同，并把 80/460 透明边距显式换算为画板 frame 和 `50% 62.2667%` 的局部 bounce 锚点；
- 状态、落位和 z 层在退出满 190ms 时同步交换；进入段使用独立 X/Y squash-and-stretch，结束后强制恢复 alpha=1、scale=1；
- bounce 同步更新 playbook 的 ambient destination，避免后续成果动画结束时错误返回切换前状态；
- 角色初始化原先只建立节点层级、不构建初始状态；因为 transition driver 的首帧又会命中 no-op，Character Lab / 首页初态依赖后续状态变化才出现。现由 `PiboVectorCharacter` 初始化时直接构建当前状态；
- `angry` 的 body 使用 SVG `url(#angryShade)` 填充，旧的 `UIColor(svgColor:)` 无法解析而把整个身体画成透明，只剩怒气符号。现用 SpriteKit fill shader 复刻源文件的椭圆模糊黑影；与 Figma 300×300 终态截图的 SSIM 从 `0.843520` 提升到 `0.992381`；
- 12 态均在 iPhone 17 Pro / iOS 26.5 Simulator 以 1:1 的 300×300 画板重新截图。其余 11 态 SSIM 为 `0.993–0.999`；可见像素框与 Figma 每边差异不超过约 2px。`sleep-1 / sleep-2 / awake` 的比较只使用 300×300 角色状态画板；椰壳是首页场景组合层，不能把组合层元数据框当成角色自身边界；
- 几何自动测试不再使用包含透明辅助路径、控制点或组合层的 Figma 元数据框，改为实际可见像素框；SpriteKit 验证面同时排除无 fill/无 stroke 路径，并使用 CGPath 的真实路径边界；
- 最终动画专项测试通过 22/22，全量测试通过 91/91，Debug Simulator build 通过，动画迁移范围内的 `git diff --check` 通过；确定性 `-PiboBounceTo=` 抓帧入口仅存在于 DEBUG；
- 最终 bounce Simulator 录屏与关键帧位于 `.tmp/animation-runtime-bounce-final/`，12 态与 Figma 对照位于 `.tmp/animation-verification/{figma-states,simulator-states}/`。录屏验证仍按 190ms 时状态、落位和 z 层同步交换，710ms 时 alpha/scale 精确归一；本轮未向真机安装。

- `pibo-core 0.5.1` 完成压力方向修正后已发布；当前 App 与 `Package.resolved` 已进一步精确固定已发布的 `0.5.2`，用其 semantic transition intent 决定 `bounceCut / hardCut`；
- HarmonyPibo 的版本更新不在本 iOS 仓库内完成；必须遵循 Core 发布顺序单独把其 submodule 从 `0.5.1` 更新到 `0.5.2`，不能把本轮 iOS 通过误写成 Harmony 已同步；
- `pibo-assets 0.3.0` 已同步 12 个 SVG、状态数据和六区信息；白色汇聚已生成 ProRes 4444 母版与 HEVC Alpha iOS 衍生物；
- iOS 已启用 12 态矢量运行时，补齐待机原语、六区固定画板落位和 `boring` 的 12＋4＋12 秒穿场；后续复审删除了不属于业务原型的 600ms Morph 与 90ms 跨区淡入淡出；
- workout/万步事件、通知替换、点击路由、同日 pending、成果保持、拍击 angry 和 RMSSD 规则均已接入；
- 同日万步已持久去重，HealthKit 批量 workout 按结束时间排序且只保留最新一项；同批 workout 覆盖万步时，万步仍记为当日已处理；
- 共享成果通知使用串行发布队列；即使旧的通知写入已经在异步执行、无法再靠 Task cancellation 终止，后发生的成果仍保证最后写入共享 request ID；
- RMSSD 可用性同时排除 workout 与真实睡眠重叠；压力滞回在更高优先级状态覆盖期间保留；`angry` 到期使用精确定时刷新；
- 睡眠态延迟尚未打开的成果 Modal，已打开的 Modal 可跨 22:00 完成；成果通知和 Modal 文案均由 Core `content key` 选择后在 App 本地化；
- 待机保真补齐随机眨眼、仅贝塞尔控制点 `controlsOnly`、睡眠符号的缩放/位移/旋转，以及 `awake` 圆眼与 wink 三角的闭眼过渡；
- App 动画专项现为 22 项，覆盖 12 态资源解析、6 区固定画板与层级、190ms 状态/落位/z 层同步切换、`boring` 方向/缓动、业务 hard-cut、目标原生 intro、4% 睡眠容差、时间与无数据边界、压力窗口和优先级、成果策略、汇聚 MOV 尺寸/时长以及持久化；最终全量测试数量以本节末尾的最新验证命令为准；12 个强制状态均在 iPhone 17 Pro / iOS 26.5 Simulator 独立启动并截图；本轮未向真机安装；
- `pigu` 与 `muscle` Modal 均重新验证白色汇聚、单次 6 秒连招、最终微浮动定格、文案和摘要；即时“确定”按钮在汇聚阶段可关闭 Modal；
- Figma `😊 pibo状态`（`5663:9`）中的成果终态以两个独立 300×300 节点为准：`pigu`=`5753:332`，内容框 `5753:344` 为 `(44, 6, 211.368×287.005)`；`muscle`=`5755:538`，内容框 `5755:534` 为 `(37, 9, 225.533×282.929)`。外框无背景填充，Figma 截图中的灰色仅是透明区域预览，不能移植为 App 背景；
- Simulator 对照发现 Modal 场景原实现先居中、再调用世界场景专用的 `fit(bodyWidth:footPoint:)`，后者覆盖了根节点位置，导致 `pigu` 完全离开角色区、`muscle` 仅剩左侧局部；仅移除 `fit` 又暴露了默认 scale 不触发几何构建和首次布局尺寸为零的问题。现已改为显式 `setState` 构建 1:1 的 300 设计单位几何，并在 `didChangeSize` 后将设计画板中心重新对齐容器中心；首页世界场景仍保留按落脚点 `fit`，两者职责分离；
- 完成条件复审发现“中途重定向 Morph 从当前几何继续”原先只在 `PiboStateTransition` 中选择较近的命名状态，下一帧仍会跳回该状态的完整轮廓。矢量运行时现会在重定向瞬间捕获当前 `body/bo/boline` 控制点，并以该实时几何作为新过渡起点；自动测试比较中断前后全部 CGPath 点，最大差值小于 `0.001pt`；
- 修复后 Figma SVG 与 Simulator 截图的边缘模板匹配，`pigu`、`muscle` 均只在原始 `1.00×` 比例取得唯一最佳匹配，300×300 画板在 3×截图中同为 `(153, 585, 900×900)`。后续新鲜取样发现此前只核对了 body/脸，漏掉了 `bo/boline`；根因是 Modal 的 scale 恰好为 1 时命中 fast path，3×超采样芽没有缩回 1/3。现已在角色初始化时固定安装 1/3 宿主缩放并加入测试；新 `pigu` 取样中芽主色边界为 `(211,17)…(386,183)`，Figma 为 `(211,18)…(385,184)`，完整角色主色边界相差不超过 2 个 3×像素；
- 确认关闭 Modal 后的成果保持仍使用同一个 `PiboCharacterData` 状态几何；Simulator 已分别用 `-PiboAnimationState=pigu/muscle` 验证首页落脚缩放后的固定姿势，证据为 `pigu-home-hold-current.png` 与 `muscle-home-hold-current.png`；
- 最新 Debug App 再次运行后，UI 层确认 `pigu` 文案、跑步摘要和即时“确定”按钮存在，点击后 Modal 消失；运行日志未出现 App 解码或崩溃错误；
- 白色汇聚 MOV 已确认打入 Simulator App bundle 且 SHA-256 与源文件一致；macOS AVFoundation 实际解码得到 1080×1080 BGRA 帧与 0…254 alpha，Spotlight 识别为 `HEVC with Alpha`；椰壳 `forest_yeke@2x.png` 为 504×950，精确对应 252×475pt 的 @2x 场景尺寸；
- Simulator 新鲜取样发现白色汇聚在纯白 Sheet 上视觉上完全消失；原始 Harmony 首页整合预览明确把成果页放在 `#DFF7ED → #EEF8D8 → #FFF4CD` 浅绿黄渐变上，并记录汇聚段全部为白色。iOS 成果 Sheet 已恢复同一渐变背景，既让白色汇聚有可见对比，也不把 Figma 的透明预览灰误当成角色画板背景；`pigu/muscle` 终态仍保持透明；
- 渐变修复后在 iPhone 17 Pro / iOS 26.5 Simulator 分别重新取样 `pigu` 与 `muscle` 的汇聚、连招和终态；汇聚期间点击“确定”会立即停止流程并回到首页；
- 重新校正后的 Simulator 素材位于 `.tmp/animation-runtime-final/`，Figma 对照位于 `.tmp/animation-verification/figma/`；两者均不进入版本控制；
- 根据本轮明确决定，不向真机安装 App；真机持续帧率、拖毛手感、抗锯齿、水面倒影、HEVC Alpha 硬件解码和椰壳实际显示清晰度不再作为本轮 Simulator 集成验收门槛，记录为发布前独立验收项。

### 可重复的最终验证

Figma 的 12 张 300×300 状态参考图放在 `.tmp/animation-verification/figma-states/` 后，使用以下命令从已安装的 Debug App 重新取样并比较：

```bash
Tools/capture-pibo-animation-states.sh \
  E2FABF85-E748-4221-AE3E-98C3BFC8A16C \
  .tmp/animation-verification/simulator-states-recheck

Tools/verify-pibo-animation-states.sh \
  .tmp/animation-verification/figma-states \
  .tmp/animation-verification/simulator-states-recheck
```

验证器要求每张图都是 300×300、SSIM 不低于 `0.990000`，且实际可见内容框的四条边与 Figma 相差不超过 2px。2026-07-31 从空目录重新抓取后的结果为：

| 状态 | SSIM | 最大边缘偏差 |
| --- | ---: | ---: |
| `default` | 0.993823 | 1px |
| `weak` | 0.993693 | 1px |
| `pigu` | 0.994932 | 1px |
| `muscle` | 0.995632 | 1px |
| `tired` | 0.996347 | 1px |
| `angry` | 0.992381 | 1px |
| `dive` | 0.993512 | 1px |
| `boring` | 0.996460 | 1px |
| `coolhide` | 0.995611 | 1px |
| `sleep-1` | 0.998998 | 1px |
| `sleep-2` | 0.999046 | 1px |
| `awake` | 0.995687 | 1px |

切换行为由 `PiboAnimationIntegrationTests` 独立验证：189ms 仍使用旧状态、旧播放器位置和旧 z 层；190ms 同时切换三者；710ms 后 alpha 与 X/Y scale 精确恢复为 1。视觉对照和时序测试必须同时通过，不能用其中一个替代另一个。

### 2026-07-31 最终完成审计

- 使用本轮源代码重新构建并安装 Debug App 到 iPhone 17 Pro / iOS 26.5 Simulator；没有连接或安装到真机；
- 全量测试结果位于 `Test-Pibo-2026.07.31_01-44-39-+0800.xcresult`：总计 91 项，91 通过、0 失败、0 跳过；动画专项 22 项全部通过；
- 从重新安装的 App 再次从空目录抓取 12 态，结果位于 `.tmp/animation-final-audit-20260731/states/`。与 Figma 参考帧的 SSIM 和边缘偏差逐项复现了上表结果；
- 真实首页的固定状态截图位于 `.tmp/animation-final-audit-20260731/home-{default,coolhide}.png`。把 Figma 白色像素模板按 460×460 player 合同映射到 1206×2622 Simulator 截图后，在预测位置周围 ±6px 扫描：`default` 最佳点为 `x=0px, y=-3px`，`coolhide` 最佳点为 `x=0px, y=0px`；这里的 3px 等于 1pt；
- `coolhide` 顶部 80px 的白色模板覆盖率为 86.83%，完整模板覆盖率降为 38.46%，与角色被既有圆形草丛遮住、只露头和上半脸的设计一致；
- 新的真实首页切换录屏位于 `.tmp/animation-final-audit-20260731/home-bounce.mp4`。视频像素信号显示旧位置角色先退出，目标角色随后只在 `coolhide` 区域出现；精确 190ms/520ms/710ms 边界继续由不受录屏采样率影响的确定性测试证明；
- 最近 10 分钟的 App Simulator 日志未出现 fatal、crash 或 shader error；
- 动画迁移涉及的项目、App、测试、工具和本文档均通过 `git diff --check`，两个验证脚本均通过 `bash -n`。整个 dirty worktree 另有叙事文档自己的行尾空格，不属于动画迁移，本轮没有覆盖该用户改动。

### 2026-07-31 实现复审修正

- 修正 `boring` 穿场时钟的归属：计时现在跟随实际显示的状态，而不是已经提前写入的业务目标。`bounceCut` 的前 190ms 只缩小旧角色，190ms 换位后的 `boring` 从穿场起点开始，不再提前走掉退出段的 190ms；
- 修正运动完成的新鲜度判断：此前代码虽然取得 Core `eventPolicy.isFresh`，却错误使用 HealthKit 是否已有 anchor 的 `isHistorical` 作为展示条件。这会让首次打开 App 时刚完成的运动不弹成果 Modal，也可能把延迟送达的旧 delta 当作新运动。现在统一使用 Core 0.5.2 的年龄策略，并继续要求运动发生在本地当天；
- 新增上述两项回归。最新 iPhone 17 Pro / iOS 26.5 Simulator 全量结果为 93/93 通过、0 失败、0 跳过，位于 `Test-Pibo-2026.07.31_02-13-25-+0800.xcresult`；
- 重新安装到同一 Simulator 后录制 `boring` 切换，证据位于 `.tmp/animation-review-fix-20260731/boring-bounce.mp4`；最近运行日志未出现 fatal、crash 或 shader error。仍未安装到真机；
- App 工程与 `Package.resolved` 继续精确固定 `pibo-core 0.5.2`，本次只修 App patch，没有改 Core 版本。

### 2026-07-31 扩大范围复审修正

- 修正成果 playbook 在“当前已是目标状态”时永久等待的问题。`transition(to:)` 会去重同一目标，旧 playbook 却仍等待永远不会到来的 settle 回调；现在同目标重播会清理等待态并从目标原生 intro 重新开始；
- 修正成果通知点击信号没有消费者的问题。通知路由现在产生唯一 request ID，Home 把它纳入刷新 token；每一次通知点击都能重新尝试展示 pending Modal，而不是只改一个无人观察的 Bool；
- 修正 Modal 展示期间被更新成果替换后无法关闭的问题。若 HealthKit 送来更新的 pending UUID，当前 Sheet 会原位换成最新 payload；若 pending 被清除则关闭，不再让“确定”按钮对着过期 UUID 成为无响应；
- 修正压力滞回只存在内存中的问题。`default/dive/coolhide` 的上一压力状态现在持久化，App 重启后仍能正确应用 Core 的进入/退出滞回；
- 修正矢量睡眠状态与旧程序化 `Zzz` 叠加的问题。`sleep-1/sleep-2` 已自带设计内的 Z/气泡，旧标签现在只服务 legacy sprite 路径；
- 修正降水命中点把 vector 局部坐标直接当场景坐标的问题；采样点现在经过 content、pulse、业务 bounce、角色根节点到 scene 的完整坐标转换，雨滴/雪花会跟随屏幕上的真实轮廓；
- 修正水面倒影没有继承 `bounceCut` 和落地 pulse 容器的问题。隐藏快照代理现在位于 `pulseNode` 下、与内容节点同级，既继承完整播放器缩放，又不会把代理递归拍进自己的纹理；自动测试进一步验证 X/Y 业务缩放和 pulse 缩放按层级相乘；
- 修正“先 workout、后独立达到万步”时 workout 事实被悬空的问题。`muscle` 仍按已确认规则替换可见 `pigu` 成果，但被替换 workout 会静默结算其 bo/历史效果；展示去重不再造成运动结果丢失；
- 动画专项测试为 27/27，通过结果位于 `Test-Pibo-2026.07.31_11-28-21-+0800.xcresult`；最终代码的全量测试为 97/97、0 失败、0 跳过，位于 `Test-Pibo-2026.07.31_11-30-30-+0800.xcresult`；
- 最新 Debug App 仅安装到 iPhone 17 Pro / iOS 26.5 Simulator。从空目录重抓 12 态后，SSIM 再次为 `0.992381–0.999046`，所有可见框边缘偏差均为 1px；结果位于 `.tmp/animation-expanded-review-20260731/states/`。首页强制 `sleep-1` 截图位于同目录的 `home-sleep-1.png`，没有再识别到旧的独立 `Zzz` 标签；本轮仍未安装到真机。

### bo 阶段进展反馈（2026-08-01 已实现）

#### 已确认的产品规则

- 下一颗 bo 的积累进度跨过 `25% / 50% / 75% / 90%` 时触发一次阶段进展反馈；这些阈值是确定性跨平台规则，应由 `pibo-core` 返回稳定语义事件，平台端不重复定义；
- 进度来源是本地 bo 账本中由 Core 更新的 `energyCarry` 相对下一枚 bo 阈值的比例，不使用旧的 `headSproutGrowthProgress`。旧值只服务此前的运动发芽流程，不能替代真实睡眠、步数、站立和运动共同形成的 bo 进度；
- 用户不在首页或场景暂时被 Modal、全屏功能覆盖时不立即播放。期间发生的多个阶段进展合并为一次，回到可见且可播放的首页后只呈现最新进度；
- 尝试呈现时如果用户停留在 studio、gym，或 Pibo/头草锚点不在当前镜头可见范围，直接丢弃这次视觉提醒；不自动移动镜头、不等待重新可见，也不补播。bo 账本和真实进度仍正常更新；
- 一次数据更新跨过多个阈值时不连续补播，只播放一次并采用本次跨过的最高阈值；
- 待播放的 `90%` 阶段反馈尚未呈现时，如果进度已经达到 `100%`，直接取消阶段反馈并由新 bo 生成动画取代；
- 该反馈表达“能量已经进入 Pibo 的 bo，正在接近下一颗 bo”，不是新 bo 已经生成。到达 `100%` 后的新 bo 生成属于另一条更强的结果动画；
- 全部 12 个动画状态都必须支持该反馈，包括 `boring` 穿场、`dive`、`coolhide`、`weak`、睡眠和椰壳中的 `awake`，不能为状态维护屏幕绝对坐标。

#### 已确认的定位与表现方案

- `PiboCharacterData.json` 的每个状态都已有 `sprout.root / sprout.tip`。运行时以插值后的 `sprout.root` 作为“能量进入 bo”的语义锚点，并经过设计坐标、当前几何/待机容器、角色播放器落位和 SpriteKit 场景的完整坐标转换；
- 粒子宿主在播放期间持续跟随锚点，不能只在触发帧读取一次位置，否则 `boring` 穿场、呼吸和角色位移会让粒子与头草分离；
- `bounceCut` 或其他状态切换尚未落定时暂存反馈，等目标状态完成切换后再播放，避免锚点在 190ms 换位点跳跃；
- 粒子从头草周围向根部汇入，结束时只给头草一次轻微亮起或摆动。睡眠态保留可见反馈，但不唤醒 Pibo、不触发强抖动或强音效；
- 粒子汇入时在头草附近显示一条短暂的非角色台词提示：`25% / 50% / 75%` 使用“bo 正在形成 · {进度}%”，`90%` 使用“bo 快形成了 · 90%”；不打开 Modal，也不把系统状态提示伪装成 Pibo 说话；
- 本期只播放视觉反馈，不播放声音、不触发振动；播放器保留可选的声音与振动能力接口并默认关闭，当前不接入空的系统调用，后续只有在另行确认具体声音和触感后才启用；
- 当前 `playEnergyGain()` 使用“角色中心 + 身高比例”的估算位置，无法满足异位状态，实施时必须替换为语义锚点；找不到锚点时应延后并记录错误，不能回退到猜测的屏幕中心。

#### 实现记录

- `pibo-core 0.5.3` 新增稳定 `BoProgressEvent`，一次账本更新只返回跨过的最高阶段，mint 优先于所有阶段提醒；iOS Swift Package 与 HarmonyOS submodule 均精确固定到正式 `0.5.3`；
- iOS 与 HarmonyOS 的服务器账本同步成功后均把前后 `energyPool` 和 `mintedCount` 交给 Core，再写入各自的持久单槽队列；首次取得服务器状态没有可比较基线时不伪造阶段事件；
- 两端均在首页无遮挡且场景空闲时消费队列；切换中延后，呈现时锚点离屏则消费并丢弃，不移动镜头、不补播；
- iOS SpriteKit 与 Harmony ArkUI 均从每态 `sprout.root` 出发并经过当前角色变形和场景落位，播放向根部汇入的粒子及同一文案；播放期间跟随 `boring` 等动态落位；睡眠态不施加强头草冲量；
- 声音与振动只保留可选接口，当前均未绑定平台副作用；
- iOS 全量 Simulator 测试、HarmonyOS 全部本地检查及 Debug HAP 构建通过；未向真机安装。

### 待机保真复核（2026-08-03，仅 iOS）

复核对象是 `pibo_design/preview/engine.jsx`（验收基准）与 App 的 `PiboIdleAnimator`。
先确认了**数据层没有欠账**：12 个状态的 idle 配置块与设计包逐字节相同，元素集合逐状态
一致，设计包自 2026-07-30 起未再改动。差异全部在运行时实现上：

- **`origin` 从未接入。** `PiboCharacterData.Idle.Part` 一直解码 `origin`，但动画器没有
  读过它，整体待机变换写在 `contentNode` 上、绕画板中心缩放。设计包 12 态里有 11 个
  的整体原语带 `origin`，且引擎默认支点是 `BOTTOM_CENTER`——都在角色着地点附近。
  后果是呼吸时脚会跟着上下滑。现改为 `PiboVectorCharacter.BodyTransform` 统一复合
  缩放/旋转/位移并钉住支点（`position = contentRest + O + offset − R·S·O`），
  `offset` 用设计单位、Y 向下书写，与源 `translate(...)` 同形；
- **旋转方向系统性相反。** 几何按 `scaleX: s, y: -s` 翻转 Y，而 `zRotation` 直接取
  正角度；CSS `rotate(+deg)` 在 Y-down 下是顺时针，同一数值在场景空间里读作逆时针。
  对称摆动只差半个周期看不出来，但 `unipolar` / `hold` / ✨ 的 `rotate` 是单向的。
  现在所有授权角度统一经 `radians(designDegrees:)` 取负；
- **波形与编排逐条对齐**：`breathe` 改回半波（只向外鼓）、`breathe-hop` 改为仅纵向且
  跳跃窗口落在周期末（第二跳 0.55 倍）、`waggle-sequence` 换成 4/0.4/4/0.4/4 的
  ramp-hold 编排 + easeInOutSine、`shake` 从水平位移改回绕支点旋转、`bob` 改为
  只向上的半波、`sigh-sequence` 的 X 改为收窄（等体积）、`unipolar` = `-|sin|`、
  `hold` = 常量 −1、`blink` 的 `minScale` 默认 0.1（原来闭到 0 会让眼睛消失）、
  随机眨眼默认周期 2.6–5.8s、gate 边缘改用引擎的 easeInOut、默认 `gateFade` 0.05；
- **`path-bulge` / `pulse-scale` 改为在门控窗口内走完一次阻尼振荡**。此前用的是自由
  周期（缺省 1s）再乘门控包络，pigu 的「屁股 duang·duang」因此变成了错速的连续抖动；
- **✨ 的飞出**改用 easeOutCubic 的位移/旋转、0.35 处的缩放拐点与 18%/55% 的透明度节点，
  并跳过首个不完整周期。

首页成果保持态按 §5.6 改用设计侧的 `setIdleOverride` 配置，删掉了原来自拟的
4.8s / ±0.8% / ±1.2pt 组合；Modal 侧不变，仍是汇聚 → 硬切 → authored intro → 连招循环。

验证：新增 5 项待机保真测试（支点钉死、`breathe` 半波、`unipolar`/`hold` 单向、
`path-bulge` 走完门控窗口、保持态取设计参数），`PiboAnimationIntegrationTests` 33/33 通过。
iPhone 17 / iOS 26.5 Simulator 上以 `-PiboSkipOnboarding -PiboAnimationState=pigu` 连拍 9 帧：
白色区域面积随呼吸变化（86626–87267 像素），而角色底边**每一帧都停在同一行**，
即支点已钉在着地点。`-PiboShowAchievement=pigu` 复核 Modal 仍逐帧变化。未向真机安装。

注：`StageArchitectureTests.testAllForegroundFoliageUsesIndependentFigmaAssets` 当前失败
（`forest_main_leaf_2` 的 Figma 节点 id 与尺寸对不上），与本轮无关——在剥离本轮改动的基线上
同样失败，属于工作区里另一份未提交的森林素材改动。

### `pigu` 退出主场景（2026-08-04）

产品决定：**运动完成的 `pigu` 只在成果卡片里演一次，主场景任何时候都不出现，
确认后直接切到其他状态。** 万步的 `muscle` 不变，仍然保持到 22:00。

两端同步落地：

- 规则写在类型上而不是散在判断里 —— iOS `PiboAnimationAchievementKind.holdsOnHome`
  （`pigu` = false），鸿蒙 `PetStateStore.holdsOnHome(...)`。确认成果时只为会保持的
  那种记保持槽；映射层（iOS `stateIDByApplyingAchievementHold`、鸿蒙
  `HomePage.animationState`）再守一道，因为旧版本可能已经把 `pigu` 写进过持久化的
  保持槽，升级上来的设备要能自愈；
- iOS 另外拆掉了发芽收尾处的 `playWorkoutCelebration()` —— 那条路径在成果卡片之外
  又在首页演一遍 `pigu` 剧本，是集成规格 §10.7 早就要求解绑、但当时没拆干净的部分。
  随之失去调用者的 `PiboCoreAnimationAdapter.workoutCelebrationAllowed`、命令控制器/
  场景/渲染器的 `playAchievement` 与 `PiboAnimationStateMap.achievement` 一并删除。
  Character Lab 自己构造 beats，不受影响，仍可在隔离环境里看这段表演；
- 鸿蒙本来就没有这条发芽剧本，只改了保持槽与首页映射。

验证：iOS 动画专项 34 项全过、全量 145 项仅剩一处与本轮无关的既有失败
（`StageArchitectureTests` 的森林叶片素材，基线同样失败）；鸿蒙 `run_all_checks`
全绿（`check_character_animation_port.mjs` 新增固定「只有 muscle 保持」与
「首页不得出现 pigu 保持分支」），Debug HAP 构建通过。
