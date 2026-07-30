# Onboarding 与事件 01–03 跨平台 MVP 规格 v0.1

> 日期：2026-07-30  
> 状态：产品与架构方向已确认；Core 数值和账本合并细则待实现规格  
> 平台：iOS、HarmonyOS；共享规则：`pibo-core`  
> 范围：首次使用、事件 01–03、第一枚真实 `bo`、恢复和异常路径。本文不修改 App 代码。

## 1. 目标与非目标

本规格把已经确认的六场面 Onboarding 和前三个故事事件转换为可实现、可测试的跨平台行为。它不重新讨论世界观，也不扩大 MVP。

MVP 包含：

- 事件 01“错误抵达”；
- 事件 02“临时约定”；
- 事件 03“第一枚 `bo`”；
- HealthKit / Health Service Kit 权限；
- 通知权限；
- 真实健康数据形成 `bo`，成熟、拔取、库存与永久记录；
- 中断、拒绝、部分授权、稍后继续和跨启动恢复。

MVP 不包含：

- 登录教学、付费、商店、社交、战斗、其他小游戏；
- Onboarding 内的相机、定位、麦克风权限；
- 即时伪造第一枚 `bo`；
- LLM/VLM 动态剧情；
- 事件 04 以后的逐句剧本；
- 旧坠落求救、找光、命名、语音唤醒、契约失败和“Pibo 没电”。

## 2. 产品不变量

1. 首次设置是否结束、用户是否回应 Pibo、是否接受临时合作、平台权限是否请求过，必须是彼此独立的状态。
2. 平台健康授权不等于故事许可；故事许可也不等于平台已经提供可用数据。
3. 健康记录功能可以按平台权限工作；没有临时合作时，这些记录不能被 Pibo 转换为 `bo`。
4. 事件 02 只有在用户接受临时合作，且至少观察到一种可形成 `bo` 的真实健康数据后才完成。
5. 通知不是事件 02 或 `bo` 形成条件。拒绝通知不降低任何进度。
6. `bo` 只能来自已确认的真实健康来源。拍照、拍一拍、游戏、付费和打开 App 都不能生成 `bo`。
7. 进度只前进不倒退；缺少数据、撤回权限、长期不打开和低活动都不会伤害 Pibo 或清除成熟 `bo`。
8. 第一枚 `bo` 必须在正式主页自然发生，用户主动拔下后事件 03 才完成。

## 3. 持久状态模型

### 3.1 首次设置状态

```text
FirstRunFlow
  notStarted
  inProgress(checkpoint)
  completed

checkpoint
  encounter        // 屏 01
  identity         // 屏 02
  partnership      // 屏 03
  healthSetup      // 屏 04
  notificationSetup// 屏 05
  finishing        // 屏 06
```

`completed` 只表示用户已经离开首次设置流程，不代表故事或权限成功。App 冷启动只有在 `notStarted/inProgress` 时进入 Onboarding；`completed` 永远进入正式主页。

每到一个稳定屏幕先持久化 checkpoint，再展示界面。系统权限页返回、App 被杀死或设备重启后，从最近稳定 checkpoint 恢复，不从开场重播。

### 3.2 故事连接状态

```text
StoryConnection
  unresponded
  responded(respondedAt)
  accepted(acceptedAt, consentVersion)
  ended                 // 为后续事件 15 预留，MVP 不产生
```

- 点击“我在”：`unresponded → responded`，事件 01 完成；
- 点击“接受临时合作”：`responded → accepted`；
- “稍后”不提升状态；
- `acceptedAt` 是 Pibo 可以开始把授权健康记录用于 `bo` 的时间边界；接受前的数据不追溯转换为 `bo`；
- 撤回平台健康权限不撤回故事许可，只让数据通道停止；若未来提供“终止约定”，才进入 `ended`。

### 3.3 平台权限状态

平台权限只保存“流程事实”，实时权限尽量从系统查询：

```text
HealthSetup
  requestStatus: notRequested | requested
  requestedAt: Date?
  channelStatus: unavailable | noObservedSource | observedSource
  observedSources: Set<sleep | steps | stand | activeEnergy | workout>

NotificationSetup
  requestStatus: notRequested | requested
  requestedAt: Date?
```

说明：

- iOS 不可靠披露只读 HealthKit 的逐项授权状态，因此不得持久化“全部授权成功”；以请求完成和真实查询结果分开表达。
- HarmonyOS 可以读取已授权数据类型，但跨平台故事状态仍以是否观察到真实可用来源为准。
- 通知当前是否允许，在需要发送或设置页展示时查询系统；持久化值只用于证明首次流程已经请求过。

### 3.4 事件状态

沿用统一事件生命周期，但 MVP 只实例化前三项：

```text
StoryEventState
  locked
  available
  inProgress(checkpoint)
  completed(completedAt)
```

| 事件 | `available` 条件 | `completed` 条件 |
|---|---|---|
| 01 错误抵达 | 首次打开 | 用户点击“我在” |
| 02 临时约定 | 事件 01 完成 | `StoryConnection.accepted` 且至少一种真实来源已被观察到 |
| 03 第一枚 `bo` | 事件 02 完成且第一枚实体成熟 | 用户主动拔下第一枚实体 `bo` |

事件状态必须由事实派生或幂等写入，不能只依赖当前页面索引。

### 3.5 `bo` 状态

```text
BoState
  energyCarry: Decimal             // 距离下一枚的剩余累计
  pendingCount: Int                // 已成熟、仍在头顶等待拔取
  inventoryCount: Int              // 已拔取、可消费库存
  lifetimeMinted: Int              // 历史成熟量，只增不减
  lifetimeCollected: Int           // 历史拔取量，只增不减
  firstBoMintedAt: Date?
  firstBoCollectedAt: Date?
  scoringVersion: String
```

约束：

- `energyCarry >= 0`，`pendingCount/inventoryCount/lifetime* >= 0`；
- 成熟一次：`pendingCount +1`、`lifetimeMinted +1`；
- 拔取一次：`pendingCount -1`、`inventoryCount +1`、`lifetimeCollected +1`；
- 消费只减少 `inventoryCount`，不减少历史量，不让故事倒退；
- 头顶当前只需显示一枚成熟 `bo`。若后台累计出多枚，`pendingCount` 作为队列，逐枚拔取并播放已有动画；
- 成熟 `bo` 不过期，不因跨日、长期未打开、权限变化或低活动消失。

## 4. Onboarding 页面和状态转换

文案以 [`22-Onboarding台词与界面文案-v0.3.md`](22-Onboarding%E5%8F%B0%E8%AF%8D%E4%B8%8E%E7%95%8C%E9%9D%A2%E6%96%87%E6%A1%88-v0.3.md) 为准。

### 屏 01：有人收到信号

- 初始状态：事件 01 `available`，`StoryConnection.unresponded`；
- “我在”：保存 `responded` 和事件 01 完成，再进入屏 02；
- “稍后”：故事状态不变，进入精简设置路径；
- 不调用任何系统权限。

### 屏 02：Pibo 说明已知事实

- 只在用户已回应时出现；
- “继续”：进入屏 03；
- “稍后”：保留 `responded`，进入精简设置路径。

### 屏 03：临时合作

- “接受临时合作”：持久化 `acceptedAt` 和许可版本，再进入屏 04；
- “稍后”：保留当前故事状态，进入精简设置路径；
- 这里不调用平台健康授权。

### 屏 04：健康权限

- “连接健康记录”：先保存 checkpoint，再调用平台系统授权；无论用户允许、拒绝、部分允许或系统页被中断，返回后都记录 `requestStatus=requested`；
- “暂不连接”：不调用系统页，保持 `notRequested`；
- 请求返回后立即做一次有界查询，以更新 `observedSources`；
- 没有读到数据不显示“失败”，也不推断用户明确拒绝；
- 继续进入屏 05。

### 屏 05：通知权限

- 点击唯一主按钮后，先保存 checkpoint，再调用系统通知权限；
- iOS 使用 `UNUserNotificationCenter.requestAuthorization`；
- HarmonyOS 使用 `notificationManager.requestEnableNotification`；
- 系统页返回或抛错后均记录请求已完成，并进入屏 06；
- 不申请相机、麦克风或定位。

### 屏 06：进入正式主页

- 先写入 `FirstRunFlow.completed`，再切换到主页；
- 合作已接受且观察到真实来源：显示 06A；事件 02 完成；
- 合作已接受但未观察到来源：显示 06B；事件 02 保持可继续；
- 未回应或未接受：显示 06C；
- 任何分支都不能阻止进入主页。

### 精简设置路径

从屏 01–03 任一“稍后”进入同一系统说明页，然后依次经过健康权限、通知权限和 06C。未发生的 Pibo 台词不补播，平台授权不提升故事许可。

## 5. 主页恢复规则

首次流程完成后不自动重播 Onboarding。

- `unresponded`：自然打开 App 时可偶尔显示“上次的信号还没有收到回应”；点击后从屏 01 的回应动作继续；
- `responded`：可偶尔显示“那项临时合作，还需要你的决定”；点击后从屏 03 继续；
- `accepted + noObservedSource`：不催促；设置页提供稳定的健康连接入口，Pibo 偶尔提示“记录通道尚未接入”即可；
- 同一次前台会话最多展示一次恢复气泡；关闭后本次会话不再出现；
- 不使用红点、倒计时、虚弱动画或固定每次启动展示；
- 设置页始终提供“继续连接故事/管理健康权限”的稳定入口，但不新增主页常驻入口。

## 6. 第一枚真实 `bo`

### 6.1 计分资格

一条健康记录同时满足以下条件才可进入 `bo` 计分：

1. `StoryConnection == accepted`；
2. 记录类型属于睡眠、步数、站立、活动消耗或运动；
3. 记录结束时间不早于 `acceptedAt`；
4. 记录来自平台健康服务的真实样本或平台聚合，不是 Demo、DEBUG、拍照、游戏或手工伪造；
5. 具有稳定去重键，重复同步不重复计分。

HRV、心率和静息心率可用于健康趋势及已批准的恢复修正，但不能因为缺失而让用户失去睡眠、步数等基础贡献。

### 6.2 确定性规则归属

- 日聚合、曲线、单日上限、阈值、进位、去重语义和内容事件键属于 `pibo-core`；
- iOS/HarmonyOS 只负责读取平台数据、转换单位、提供稳定样本 ID、持久化和播放；
- 后端负责账号账本、跨设备同步、幂等校验和反作弊，不应拥有一套与 Core 不同的计分算法；
- 规则必须带 `scoringVersion`，同一输入在 iOS、HarmonyOS、后端校验中得到同一结果。

当前后端已有一套 `75 energy → 1 bo`、健康日上限 `110` 的曲线实现，但 `pibo-core` 尚无对应 API。该实现只能作为迁移和审计候选，具体数值不因当前存在而自动成为产品决定。正式编码前需先把确认后的规则发布到 Core，再按仓库规定更新两端固定版本。

### 6.3 形成与呈现

1. 合格数据进入 Core，更新 `energyCarry`；
2. 跨过阈值时产生幂等 `bo_minted` 领域事件；
3. 更新 `pendingCount/lifetimeMinted` 后持久化，再请求 UI 播放现有能量特写、头顶生长和成熟动画；
4. 动画被打断不回滚成熟事实；下次进入主页直接显示成熟状态；
5. 第一枚成熟时事件 03 从 `locked` 变为 `available`，但仍未完成。

系统说明只陈述可验证来源，例如“这枚 `bo` 由睡眠和步行记录逐渐形成”。没有的数据不补写，不推测用户动机。

### 6.4 拔取与库存

- 成熟后用户可直接在主页使用现有头顶拖拽/拔取手势；不限制 22:00–02:00；
- 拔取提交必须使用稳定事件 ID，重复回调、重试和跨设备同步不能重复入库；
- 先原子更新本地/权威账本，再播放掉落动画；动画失败不重复发放；
- 第一枚拔取成功后记录共同历史，事件 03 完成；
- Pibo 的反应以“实验路线成立”为主，不感谢投喂，不进入深眠，不说用户把它救活了；
- 未拔取时不提示损失，不影响继续积累；成熟状态永久保留。

## 7. 平台与模块职责

| 责任 | `pibo-core` | iOS | HarmonyOS | 后端 |
|---|---|---|---|---|
| 事件 01–03 前置与完成判定 | 是 | 映射/持久化 | 映射/持久化 | 可镜像 |
| 健康计分、阈值、单日封顶、进位 | 唯一规则源 | 不复制 | 不复制 | 同版本校验 |
| Health 数据获取 | 否 | HealthKit | Health Service Kit | 否 |
| 通知权限 | 否 | UserNotifications | notificationManager | 否 |
| 故事/权限状态持久化 | 状态类型与迁移语义 | UserDefaults/本地存储 | Preferences | 账号镜像可选 |
| 样本去重键 | 规范 | HK UUID/稳定聚合键 | 平台 ID/稳定聚合键 | 强制唯一 |
| 动画和触觉 | 语义事件 ID | SwiftUI/SpriteKit | ArkUI/现有舞台 | 否 |
| `bo` 账本与跨设备 | 状态转换 | 本地队列/镜像 | 本地队列/镜像 | 登录后权威账本 |

## 8. 当前实现迁移清单

### 8.1 iOS

保留：

- `RootView` 的首次启动门禁位置；
- 正式森林主页、SpriteKit 舞台、Pibo 待机与转向能力；
- `HealthDataService` 的 HealthKit 请求、查询和观察能力；
- 现有能量特写、发芽、头顶拖拽和掉落动画；
- `EconomyService` 的网络幂等与账本 DTO 思路；
- 足迹、餐食相机、Walk Doodle 等已确定功能入口。

替换或隔离：

- `HealthAuthView` 当前全部旧场面、旧台词和拒绝阻断页；
- 单一 `onboardingDone` 无法表达完整状态，保留门禁键但新增分离状态；
- `onboardingResumeAuth` 只恢复授权页的旧模型；
- `PiboStoryline` 的“坠落/魔丸/拍一拍掉线索”内容；
- 22:00–02:00 拔毛窗口、按夜次数、拔后 5 分钟深眠和随机旧人格台词；
- 仅运动触发的发芽进度，不可作为新 `bo` 计分；
- 拍照/游戏行为向 Economy 上报能量的路径。

新增：

- `FirstRunFlow`、`StoryConnection`、权限请求事实、事件状态与版本化迁移；
- 通知权限 Onboarding 步骤；
- 主页低打扰恢复入口；
- Core `bo` 状态适配器、成熟队列、库存和共同记录。

### 8.2 HarmonyOS

保留：

- `Index` 的启动恢复与主页门禁位置；
- `HealthDataService` / provider 的 Health Service Kit 请求与查询；
- `notificationManager` 的现有通知能力；
- 正式主页、舞台、能量与拔取动画资产；
- Preferences 持久化设施。

替换或隔离：

- `OnboardingPage` 当前“精灵降临—找光—取名—喊名字—签约—即时能量—拔芽”流程；
- `resumeAuth` 单点恢复；
- Demo/真实健康/稍后三选一与故事状态混合的模型；
- 当前固定夜间拔毛和旧故事线；
- 拍照/游戏行为能量。

新增项与 iOS 相同，并使用完全相同的 Core 状态与内容键。

## 9. 已收口的架构方向与迁移项

以下方向已经由决定 031 收口，但现有代码仍需迁移：

1. **Core 与后端双规则源**：统一迁入 `pibo-core`；客户端本地运行同一 Core，后端 MVP 保存和合并账本，未来也运行同一 Core 产物复算，不在 Go 中另写算法。
2. **未登录无法形成 `bo`**：改为本地优先形成、登录后幂等合并；不增加第七个登录场面。
3. **旧拔毛不是库存系统**：现有拔毛只记录夜间日期和播放动画，没有 `pending → inventory` 原子账本，不能直接视为事件 03 已实现。
4. **旧非健康能量冲突**：后端当前允许 photo/game action energy；新规则明确这些不能铸造 `bo`。
5. **站立与活动来源不完整**：已确认来源包括站立和活动，但当前经济上传重点是睡眠与步数。Core 输入和双平台适配需要补齐，同时保证无手表用户仍可靠步数缓慢前进。

## 10. 验收用例

### 10.1 Onboarding

1. 新安装点击“我在”、接受合作、请求健康和通知后进入主页；首次流程不再重播。
2. 屏 01 点击“稍后”，仍经过精简权限设置并进入主页；事件 01/02 均未被误标完成。
3. 屏 02 点击“稍后”，事件 01 完成、事件 02 未完成。
4. 屏 03 点击“稍后”，平台健康授权即使可用也不形成 `bo`。
5. 健康权限拒绝、部分授权、无数据或平台不可用时均可进入主页，无失败/虚弱画面。
6. 通知拒绝后健康记录、故事状态和 `bo` 形成不受影响。
7. 每个稳定 checkpoint 杀掉 App，重启后从该 checkpoint 或下一安全步骤继续，不重放已完成决定。
8. 系统权限页返回异常或 App 进入后台，不重复弹出同一个请求，不把异常记为授权成功。

### 10.2 故事许可与数据

9. 已有平台健康权限但未接受临时合作：健康历史可显示，`bo` 计分为零。
10. 接受合作后只计入 `acceptedAt` 之后的合格记录；接受前历史不追溯转换。
11. iOS 请求返回但没有读到样本时，事件 02 不完成，也不写“授权失败”。
12. 只拥有手机步数、没有手表和睡眠数据的用户可以缓慢形成 `bo`。
13. 只有睡眠数据、没有运动的用户也能积累；低活动不会永久卡死。
14. 撤回权限后已有历史、库存和成熟 `bo` 保留，新数据停止进入计分。

### 10.3 第一枚 `bo`

15. 同一组输入和同一规则版本在 iOS、HarmonyOS、后端校验结果完全一致。
16. 重复上传同一样本、网络重试或 App 重启不重复增加能量或铸造 `bo`。
17. 达到阈值后先保存成熟事实再播放动画；动画中断后重启仍显示成熟 `bo`。
18. 成熟数日不拔不会过期、回退、伤害 Pibo 或出现催促。
19. 任意时间拔取成熟 `bo`，库存恰好加一，历史量只增一次，事件 03 完成一次。
20. 连续积累出多枚时头顶逐枚呈现，`pendingCount` 与库存守恒。
21. 拍照、拍一拍、Walk Doodle、游戏、购买和 Demo 数据都不能铸造 `bo`。
22. 消费库存后事件 03 和共同记录仍保持完成，不发生故事倒退。

## 11. 测试层级

- `pibo-core`：状态转换、日聚合、阈值、封顶、重复样本、时区/跨日、第一枚事件键的表驱动测试；
- iOS `PiboTests`：持久化迁移、HealthKit 映射、checkpoint 恢复、故事许可门禁、成熟/拔取幂等；
- HarmonyOS：同一组 Core fixture、Preferences 恢复、Health Service Kit 部分授权与通知拒绝；
- 后端：账本守恒、幂等键、规则版本不匹配、登录后合并/匿名身份方案；
- UI：六屏三种结束状态、低打扰恢复气泡、第一枚成熟和拔取录屏。

## 12. 实施顺序

1. 确定 Core 首版数值与本地/远端账本合并协议；
2. 在 `pibo-core` 定义状态、计分和领域事件，发布 SemVer；
3. 两端更新固定 Core 版本和持久化模型；
4. 替换双平台 Onboarding 状态机，接入通知权限；
5. 接入真实健康来源、第一枚成熟、拔取库存和共同记录；
6. 隔离旧故事、夜间拔毛和非健康能量；
7. 跑跨平台 fixture、回归测试和 UI 验收；
8. MVP 实现并行继续深化事件 04。

## 13. 本次盘点结论

- 两个平台都有可复用的首次启动门禁、健康授权、正式主页和动画资产；
- 两个平台 Onboarding 仍主要承载旧叙事，不能通过换几句台词完成迁移；
- 当前权限、故事许可、首次流程完成被混在少量布尔值中，需要版本化状态模型；
- 第一枚 `bo` 的视觉资产大体存在，但新的形成规则、成熟持久化、库存账本和事件完成尚未实现；
- Core/后端规则源与未登录产出方向已经收口；下一项工程工作是 Core 数值输入和账本合并协议。
