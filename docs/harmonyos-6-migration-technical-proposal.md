# LifePet HarmonyOS 6.0 移植技术方案概述

版本：v0.1  
日期：2026-05-11  
用途：2026 HarmonyOS 创新赛·极客赛道报名、作品介绍文档和产品技术沟通

## 1. 项目定位

LifePet 是一个把用户日常健康数据拟人化、游戏化的数字宠物应用。它不是让用户手动喂养宠物，而是把用户真实的运动、睡眠、心率和恢复状态转化为宠物的生命状态：用户走路、运动、睡好觉、冥想，宠物就会更有体力、精力和心情；长期缺少运动、睡眠不足或压力持续偏高，宠物会疲惫、生病，最终进入图鉴成为一段可回顾的健康故事。

当前 iOS MVP 的产品名是 LifePet，工程和 bundle 历史名称仍为 LifePulse。活跃产品只包含 iOS App，Watch target、WatchConnectivity、LiveCoding、MusicGeneration、Playback、Session 相关代码是早期方向遗留，不作为本次鸿蒙移植主线。

本次移植目标是基于 HarmonyOS 6.0 构建原生鸿蒙版本，以华为运动健康开放能力替代 iOS HealthKit，以 ArkTS/ArkUI 重建移动端体验，并面向鸿蒙生态补充全场景入口：手机应用、元服务/服务卡片、小艺交互、可选穿戴设备联动和云端社交同步。

## 2. 参赛背景和申报口径

根据华为开发者联盟 2026 HarmonyOS 创新赛·极客赛道活动页，赛事为开放式命题，鼓励基于 HarmonyOS 最新技术，如 AI 智能、全场景特性，探索应用、游戏、元服务与小艺智能体等方向。官网披露的日程为：报名/提交作品开始 2026-03-18 24:00，报名/提交作品截止 2026-05-15 24:00，入围作品公布 2026-05-30，决赛开始 2026-06-12。提交附件要求为 ZIP，大小不超过 200 MB，内容包括应用 HAP、作品介绍文档、演示及讲解视频等。

因此，本作品的鸿蒙相关技术描述建议围绕三点展开：

1. 健康数据驱动：使用鸿蒙生态运动健康开放能力，把华为穿戴设备、华为运动健康数据和 LifePet 宠物状态引擎连接起来。
2. 全场景体验：不仅是一个手机 App，还可扩展为桌面服务卡片、元服务轻入口、小艺语音/智能体入口和穿戴设备提醒。
3. AI 智能化：后续用用户历史健康趋势、宠物生命状态和偏好反馈生成个性化建议卡，降低健康管理压力，提高趣味性和持续使用意愿。

## 3. 当前 iOS MVP 功能和技术点

### 3.1 活跃功能

当前工程中实际进入主流程的是 `RootView -> MainTabs` 三个 Tab：

| 模块 | 当前状态 | 主要能力 |
| --- | --- | --- |
| Onboarding | 已实现 | 首启读取 HealthKit 授权说明；支持连接 HealthKit、Demo 数据继续、以后再说 |
| Home | 已实现 | 宠物舞台、孵蛋动画、三状态条、今日步骤/建议卡、运动完成弹窗、喂养动画 |
| Catalog | MVP 静态 + 局部实时 | 图鉴列表、已陪伴/已升天宠物、生命轨迹、关键时刻、纪念故事、分享卡 |
| Together | Mock | 朋友列表、双人空间、健康对比、消息线程、广场社区目标 |
| Daily history | 已有本地结构 | 每日快照写入 Application Support，用于 HRV baseline、未来死亡判断和图鉴数据 |
| Demo mode | 已实现 | 无真实健康数据时展示固定宠物 BEAN/D07 和演示步骤卡 |

### 3.2 健康数据管道

核心文件：

- `LifePulse/Services/HealthData/HealthDataService.swift`
- `LifePulse/Services/HealthData/HealthMetric.swift`
- `LifePulse/Services/HealthData/HealthEvent.swift`
- `LifePulse/Features/Home/PetStateStore.swift`

iOS 端通过只读 HealthKit 管道读取以下数据：

| iOS HealthKit 指标 | 用途 | 当前读取策略 |
| --- | --- | --- |
| stepCount | 体力 | 今日累计 |
| appleExerciseTime | 体力 | 今日累计 |
| activeEnergyBurned | 体力 | 今日累计 |
| appleStandTime | 体力 | 今日累计 |
| heartRate | 心情辅助 | 最新样本 |
| heartRateVariabilitySDNN | 心情核心 | 最新样本，结合 7 日 baseline |
| restingHeartRate | 心情辅助 | 最新样本 |
| sleepAnalysis | 精力 | 最近睡眠 session，统计 total/deep/REM |
| mindfulSession | 心情辅助 | 今日累计冥想分钟 |
| workout | 今日卡片和喂养反馈 | anchored query 增量读取，识别刚结束运动 |

数据流如下：

```text
HealthKit authorization
  -> HKObserverQuery / background delivery / foreground reconcile
  -> HealthEvent
  -> PetStateStore.ingest()
  -> RawMetrics
  -> 体力/精力/心情公式
  -> PetState 派生
  -> HomeView 动画和图鉴快照
```

当前 iOS 的关键实现点：

- `HealthDataService` 启动后按 metric 注册 observer，并在前台 `scenePhase == .active` 时执行 `reconcile()` 兜底。
- `workout` 使用 anchored query，避免反复读全量运动记录；首次读取限制最近 36 小时。
- 睡眠读取做了去重和 session 聚合，避免多来源 sleep stage 与 legacy asleep 数据重复计入。
- `PetStateStore` 是唯一宠物状态源，视图只订阅派生后的 `stats/state/steps/pendingWorkout`。
- 本地 `DailySnapshotStore` 按 `(petId, date)` 写 JSON 文件，后续图鉴和死亡判断可以直接复用。

### 3.3 宠物状态模型

LifePet 当前将健康数据压缩成三个 0 到 100 的核心状态：

| 状态 | 来源 | 当前公式 |
| --- | --- | --- |
| 体力 vitality | 步数、运动分钟、活动卡路里 | `20 + steps/10000*40 + exerciseMinutes/30*30 + activeKcal/300*10` |
| 精力 energy | 总睡眠、深睡、REM | `sleepTotalH/8*50 + deepH/2*30 + remH/1.5*20 + sleepScoreModifier` |
| 心情 mood | HRV 与个人 baseline | `50 + (todayHRV - baselineHRV) * 0.8`，无 baseline 时回落到 50 |

宠物状态按优先级派生：

```text
mood < 30       -> SICK
energy < 30     -> SLEEPING
vitality < 30   -> TIRED
mood > 85       -> BLISSFUL
vitality > 85   -> EXCITED
otherwise       -> NORMAL
```

自然衰减逻辑已经存在：每 4 小时体力/心情下降 5，精力在 0:00 到 7:00 睡眠窗口内不衰减。衰减以 `decayPending` 形式叠加，不直接覆盖健康数据公式，保证真实健康数据仍然是主信号。

### 3.4 当前未完全产品化但应纳入鸿蒙规划的能力

- 宠物死亡触发：连续压力、连续零运动、任一状态长期归零等规则已有 PRD 和图鉴模型暗示，但 MVP 未完整实现。
- 续命奖励：三项状态持续达标后的奖励簿记未实现。
- AI 建议卡排序：当前建议卡主要是规则和静态卡，未来应基于历史趋势、用户 quit 行为和当日状态智能排序。
- 真实社交：Together 现在是 mock，未来需要账号、好友关系、云同步、隐私授权和社区目标。
- 图鉴真实数据：Catalog 当前死宠数据为 demo，后续应由每日快照和死亡日志生成。
- 纪念音频/纪念曲：仓库存在旧音频和播放相关代码，但未接入当前主流程；鸿蒙版可作为后续增强。

## 4. HarmonyOS 6.0 总体技术架构

### 4.1 推荐技术栈

| 层级 | HarmonyOS 方案 | 对应 iOS MVP |
| --- | --- | --- |
| UI | ArkTS + ArkUI 声明式 UI | SwiftUI |
| 应用模型 | Stage 模型，EntryAbility/UIAbility 管理生命周期 | `LifePulseApp` + `scenePhase` |
| 状态管理 | ArkUI 状态管理 + 自定义 Store/Service | `@Observable` + `@Environment` |
| 健康数据 | Health Service Kit / 华为运动健康开放能力 | HealthKit |
| 本地偏好 | Preferences | UserDefaults |
| 本地历史 | relationalStore 或文件 JSON | Application Support JSON |
| 资源 | resources/base/media 下的像素宠物帧 | Assets.xcassets sprites |
| 日志 | hilog | os.Logger |
| 社交云同步 | AppGallery Connect 云数据库/云函数/云存储 | 当前无后端 |
| 账号 | 华为账号能力 | 当前本地 ownerName/petName |
| 通知 | Push Kit / 本地通知 | 当前无完整提醒 |
| 全场景入口 | 元服务、服务卡片、小艺意图/智能体 | 当前仅 iOS App Tab |

### 4.2 目标代码结构

建议在鸿蒙仓库中采用下列结构，保持与现有 iOS 模块对应，降低产品和研发沟通成本：

```text
entry/src/main/ets/
  app/
    EntryAbility.ets
    RootView.ets
    MainTabs.ets
  features/
    onboarding/
      HealthAuthPage.ets
    home/
      HomePage.ets
      PetStage.ets
      StatsTriad.ets
      StepsSection.ets
      WorkoutFeedSheet.ets
    catalog/
      CatalogPage.ets
      CatalogDetailPage.ets
      TrajectoryChart.ets
    together/
      TogetherPage.ets
      FriendDetailPage.ets
      PlazaPage.ets
  services/
    health/
      HealthDataService.ets
      HealthMetric.ets
      HealthEvent.ets
      HuaweiHealthAdapter.ets
    pet/
      PetStateStore.ets
      PetStateEngine.ets
      SuggestionEngine.ets
    history/
      DailySnapshot.ets
      DailySnapshotRepository.ets
    identity/
      PetIdentityStore.ets
    cloud/
      AccountService.ets
      FriendSyncService.ets
      CommunityGoalService.ets
  design/
    tokens/
    components/
  common/
    date/
    logging/
    privacy/
```

### 4.3 迁移原则

1. 先移植状态引擎，再移植 UI。`PetStateStore` 的公式、衰减、状态优先级和今日卡片逻辑是产品核心，应独立成纯 ArkTS 模块，便于单元测试和多入口复用。
2. 健康服务做适配层。不要让页面直接调用 Health Service Kit，而是保留 `HealthEvent -> PetStateStore` 这种事件流，避免未来替换数据源或增加穿戴端实时流时冲击 UI。
3. 本地只保存派生结果，不保存原始健康样本。继续沿用 DailySnapshot 思路，存每日 stat 和必要聚合，减少隐私风险。
4. MVP 先保证手机端闭环，元服务/服务卡片/小艺作为可演示亮点逐步增强。
5. Together 和图鉴先从 mock/本地历史迁移，真实社交上云放在第二阶段，避免一开始引入过重后端和隐私授权复杂度。

## 5. 作品应用到的鸿蒙开放能力或鸿蒙特性能力

这是报名表中“作品应用到了何种鸿蒙开放能力或鸿蒙特性能力”可直接展开的核心内容。

| 鸿蒙开放能力/特性 | 在 LifePet 中的使用方式 | 参赛价值 |
| --- | --- | --- |
| Health Service Kit / 华为运动健康服务 | 在用户授权后读取华为运动健康和生态伙伴开放的步数、运动、卡路里、心率、睡眠、压力/恢复等数据，作为宠物三状态计算输入 | 替代 iOS HealthKit，是作品最核心的鸿蒙生态能力 |
| ArkTS + ArkUI | 用鸿蒙声明式 UI 重建主页宠物舞台、三状态卡、今日步骤、图鉴、一起养等交互 | 原生鸿蒙体验，保证动效、响应式布局和系统一致性 |
| Stage 模型和生命周期 | 在应用启动、前台恢复、跨天时执行健康数据 reconcile、衰减 catchup 和快照写入 | 对齐现有 iOS `scenePhase` 逻辑，提升数据可靠性 |
| Preferences / relationalStore / 文件管理 | 保存宠物身份、首启授权状态、衰减时间戳、每日快照和图鉴记录 | 支撑长期养成和死亡/复活/图鉴闭环 |
| 元服务 / 服务卡片 | 提供桌面 LifePet 卡片：显示宠物状态、今日三项数值、待完成建议、低状态提醒；可从卡片直达喂养/建议页 | 体现鸿蒙轻量化、全场景分发能力 |
| 小艺开放平台 / 意图能力 | 支持“我的 LifePet 今天怎么样”“帮我开始 1 分钟深呼吸”“今天还差多少步”等自然语言入口 | 把健康建议从 App 内扩展到系统智能体入口 |
| 华为账号能力 | 绑定用户身份，支撑多设备同步、好友邀请、Together 关系链 | 让“陪伴”和社交从单机体验变为可持续账户体系 |
| AppGallery Connect 云服务 | 云数据库保存宠物每日派生状态、好友关系、社区目标；云函数计算排行榜和群体活动 | 支撑 Together、广场、跨设备恢复，不上传原始健康样本 |
| Push Kit / 通知能力 | 在宠物状态危险、刚完成运动、睡眠不足趋势、朋友鼓励等场景触达用户 | 提高留存，同时避免过度打扰 |
| 穿戴设备生态 / 可选 Wear Engine | MVP 依赖华为运动健康数据同步；后续可加手表端轻应用或实时运动结束提醒 | 增强“刚运动完就喂宠物”的即时反馈 |
| AI 能力 / 小艺智能体 | 结合健康趋势、历史快照和用户偏好，生成个性化建议卡、宠物故事和纪念总结 | 对应赛事鼓励的 AI 智能化方向 |

建议报名表短版描述：

> LifePet 基于 HarmonyOS 6.0 原生 ArkTS/ArkUI 开发，核心接入 Health Service Kit/华为运动健康服务，在用户授权后读取步数、运动、卡路里、心率、睡眠等健康数据，并通过本地宠物状态引擎实时转化为体力、精力、心情和宠物生命阶段。作品同时规划使用鸿蒙元服务/服务卡片提供桌面轻入口，使用小艺开放平台提供自然语言健康问答和快捷行动，结合华为账号、AppGallery Connect 云服务和通知能力实现好友一起养、社区目标和跨设备同步，体现健康数据、AI 建议和全场景鸿蒙体验的结合。

## 6. HealthKit 到鸿蒙健康能力的数据映射

Health Service Kit 官方介绍显示，其面向应用和服务开发者提供运动健康数据开放接口，支持在取得用户授权的前提下读取华为和生态伙伴开放的运动健康数据或写入数据到华为运动健康服务。鸿蒙版应按“可授权、可读取、可回退”的原则设计，而不是假设每个设备都能提供完整字段。

| LifePet 指标 | iOS HealthKit | HarmonyOS 数据来源建议 | 回退策略 |
| --- | --- | --- | --- |
| 今日步数 | `stepCount` | Health Service Kit 步数/活动数据 | 没有授权时使用 Demo 或用户手动记录 |
| 运动分钟 | `appleExerciseTime` + workout duration | Health Service Kit 运动记录、活动时长 | 用 workout duration 汇总 |
| 活动卡路里 | `activeEnergyBurned` | Health Service Kit 能量消耗/运动记录卡路里 | 无卡路里时只按步数和运动分钟算体力 |
| 站立/活动时长 | `appleStandTime` | 华为健康活动类数据，如支持则读取 | MVP 可不作为主公式输入 |
| 心率 | `heartRate` | Health Service Kit 心率数据 | 用静息心率或心率稳定度近似 |
| HRV | `heartRateVariabilitySDNN` | 华为可穿戴恢复/HRV/压力相关数据，以开放字段为准 | 用压力值、静息心率偏离、睡眠恢复指标替代 |
| 静息心率 | `restingHeartRate` | 静息心率/心率趋势数据 | 用最新低心率窗口近似 |
| 睡眠总时长 | `sleepAnalysis` | Health Service Kit 睡眠记录 | 无分期时只用总时长 |
| 深睡/REM | `asleepDeep` / `asleepREM` | 睡眠分期数据，如支持则读取 | 不支持分期时用总睡眠估算精力，降低权重 |
| 冥想/正念 | `mindfulSession` | App 内呼吸/冥想记录，必要时写入健康服务 | 先做本地事件，不依赖系统健康字段 |
| 运动完成事件 | `workout` anchored query | Health Service Kit 运动记录增量查询；可选穿戴侧即时回传 | 前台恢复时 reconcile 最近 36 小时，避免漏记 |

需要重点注意：

- iOS 端的 `HKObserverQuery + enableBackgroundDelivery(.immediate)` 是非常强的后台增量机制。鸿蒙版应以 Health Service Kit 实际可用的事件/查询能力为准，至少实现启动和前台恢复时的全量 reconcile，以及合理的后台刷新或通知策略。
- “刚结束运动 5 分钟内弹喂养 sheet”对时效性要求较高。如果 Health Service Kit 同步存在延迟，可以先在前台恢复时触发；后续再增加穿戴端轻应用或实时通知能力。
- HRV、睡眠分期、压力等字段可能受设备型号、用户授权和开放范围影响。状态公式需要允许缺项，并在 UI 上清晰说明“本次按可用数据估算”。
- 不建议上传原始健康样本到自有服务。云端只同步 LifePet 派生快照，如 `vitality/energy/mood/stateTag/dayCount/completedStepKinds`，从产品和合规角度都更稳。

## 7. 鸿蒙版核心业务流程

### 7.1 首启和授权

```text
首次启动
  -> HealthAuthPage 展示读取范围和用途
  -> 用户选择连接华为运动健康 / Demo 数据继续 / 以后再说
  -> HealthDataService.requestAuthorization()
  -> 成功后写入授权提示标记
  -> 启动 reconcile()
  -> 进入 MainTabs
```

授权页文案应延续当前 iOS 逻辑，强调：

- 读取而非默认写入。
- 读取用途是计算宠物状态和生成健康建议。
- 用户可用 Demo 模式体验，不强迫授权。
- Together 分享默认只分享派生宠物状态，不分享原始健康数据。

### 7.2 首页状态更新

```text
HealthDataService.reconcile()
  -> 拉取今日步数/运动/卡路里/心率/睡眠等数据
  -> 生成 HealthEvent
  -> PetStateStore.ingest(event)
  -> RawMetrics 更新
  -> PetStateEngine.recompute()
  -> ArkUI 状态刷新
  -> 宠物动画/状态条/今日步骤卡更新
  -> DailySnapshotRepository.write()
```

### 7.3 跨天和衰减

保留 iOS 端已经验证过的机制：

- 应用启动和前台恢复时检查 `lastSeenDate`。
- 跨天时先写入前一日快照，再清空今日步骤卡和 day-bound 状态。
- 每 4 小时结算一次自然衰减；睡眠窗口内精力不衰减。
- reconcile 在衰减之后执行，最终状态等于“今日真实健康数据 - 已经过的自然压力”。

### 7.4 图鉴和死亡生命周期

鸿蒙版建议第一阶段保留 demo 图鉴，并把当前宠物实时覆盖到 BEAN。第二阶段接入真实生命周期：

```text
DailySnapshotRepository.recent()
  -> DeathRuleEngine.evaluate()
  -> PetLifecycleStore.closeCurrentPet()
  -> CatalogRepository.appendDeadPet()
  -> PetIdentityStore.resetToFreshPet()
```

死亡规则建议：

- 慢性风险：连续多日低运动/低体力。
- 压力风险：连续多日心情低于阈值。
- 睡眠风险：连续多日睡眠严重不足。
- 急性风险：任一状态归零超过 48 小时。
- 圆满结局：持续健康达标，宠物自然升天并生成稀有图鉴。

### 7.5 Together 和社区

Together 当前是 mock，鸿蒙版可以按以下层级推进：

1. 单机展示：沿用 mock 数据，验证 UI。
2. 账号绑定：接入华为账号，生成用户和宠物云端 ID。
3. 好友关系：邀请链接/二维码，好友可见对方派生状态和鼓励消息。
4. 社区目标：云函数维护全社区步数目标、排行榜和活动奖励。
5. 隐私控制：用户可选择分享“宠物状态”“今日步数区间”“完整派生三状态”，默认不分享原始健康数据。

## 8. AI 和小艺智能体规划

为了贴合赛事对 AI 智能化和小艺智能体方向的鼓励，建议把 AI 能力定义为“低压力的健康行为建议引擎”，不是医疗诊断。

### 8.1 AI 建议卡

输入：

- 今日三状态和变化趋势。
- 近 7 日 DailySnapshot。
- 用户对建议卡的完成/跳过行为。
- 当日时间、天气/日程等可选上下文。

输出：

- 2 到 3 张低门槛建议卡，例如“再走 1200 步”“做 1 分钟呼吸”“今晚提前 20 分钟睡”。
- 每张卡说明影响哪个宠物状态，但不使用医疗化表述。
- 对连续跳过的建议降低频率，避免打扰。

### 8.2 小艺可支持的意图

建议定义以下高频意图：

| 用户说法 | 行为 |
| --- | --- |
| “小艺，我的 LifePet 今天怎么样？” | 返回宠物状态、三项数值和一条最重要建议 |
| “帮我喂一下 LifePet” | 打开今日可喂养/已完成运动确认页 |
| “开始一分钟深呼吸” | 打开呼吸计时器，完成后增加心情事件 |
| “我还差多少步？” | 返回今日步数、体力变化和建议目标 |
| “看看我的宠物图鉴” | 打开图鉴页或最近一只宠物详情 |

### 8.3 AI 安全边界

- 不输出诊断结论，不评价疾病风险。
- 不替代医生建议。
- 健康数据解释保持“趋势”和“游戏状态”口径。
- 社交场景默认脱敏，避免对好友暴露具体健康数值。

## 9. 隐私、合规和安全设计

LifePet 的健康数据处理策略应作为参赛材料中的亮点：

1. 最小化采集：只读取计算宠物状态所需的健康聚合数据。
2. 本地优先：原始健康样本只在端侧参与计算，不上传到 LifePet 服务端。
3. 派生同步：云端只保存宠物派生数据和用户主动分享的数据。
4. 明示授权：授权页列明读取数据类型和用途，允许 Demo 模式。
5. 可撤回：用户可以在系统设置撤回健康授权，App 进入 Demo 或缺项估算状态。
6. 分级分享：Together 默认分享宠物状态，不直接分享心率、睡眠、HRV 等敏感原始数据。
7. 数据留存：每日快照按 petId 管理，提供清除数据和重置宠物能力。

## 10. 迁移里程碑

### 阶段 0：技术验证，1 到 2 天

- 确认 HarmonyOS 6 开发套件、DevEco Studio、签名和 HAP 打包流程。
- 确认 Health Service Kit 在目标账号/设备上的数据类型开放范围。
- 跑通读取步数、睡眠、心率或可替代数据的最小 demo。

### 阶段 1：手机端 MVP，5 到 7 天

- 用 ArkTS 迁移 `PetStateEngine` 和基础 Store。
- 实现 Onboarding、Home、Catalog、Together 三 Tab 基础 UI。
- 迁移像素宠物资源和 LP light-only 设计系统。
- 实现 Preferences 和 DailySnapshot 本地持久化。
- 用 Health Service Kit 驱动体力/精力/心情。

### 阶段 2：参赛增强，3 到 5 天

- 实现桌面服务卡片：宠物状态、今日三项、待完成建议。
- 实现小艺高频意图 demo。
- 实现 AI/规则混合建议卡排序。
- 完成演示视频脚本和作品介绍文档。

### 阶段 3：产品化增强，2 到 4 周

- 接入华为账号和 AGC 云端。
- Together 真实好友关系和社区目标。
- 图鉴由真实死亡日志和每日快照生成。
- 更细的健康数据兼容和缺项估算。
- 可选穿戴端轻应用或即时运动结束反馈。

## 11. 风险和应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| Health Service Kit 数据字段与 HealthKit 不完全一致 | HRV、睡眠分期、冥想等公式可能缺项 | 公式支持缺项降级；把状态定义为估算值；阶段 0 先验证字段 |
| 后台增量能力不等同于 HKObserverQuery | 刚完成运动的喂养弹窗可能延迟 | 前台 reconcile 最近 36 小时；后续加穿戴端或通知触发 |
| 赛事 HarmonyOS 6 受控资源需要申请 | API 名称或能力可能与公开文档不同 | 报名后按官网要求添加开发者小助手获取权限，保留适配层 |
| 社交同步涉及健康隐私 | 容易引发合规和用户顾虑 | 默认仅同步派生宠物状态，好友详情按用户主动授权分级 |
| ArkUI 动效与 SwiftUI 差异 | 像素宠物动效需要重新调参 | 先迁移精灵帧动画和状态条，再补粒子/震动等增强动效 |
| 200 MB ZIP 附件限制 | HAP、视频、文档和素材打包需控制体积 | 像素资源压缩，视频单独控制码率，旧无关代码不打包 |

## 12. 可用于作品介绍的技术摘要

LifePet HarmonyOS 6.0 版本采用 ArkTS/ArkUI 原生开发，以 Health Service Kit/华为运动健康服务作为核心数据来源，在用户授权后读取华为穿戴设备和运动健康生态中的步数、运动、卡路里、心率、睡眠等数据。应用通过端侧宠物状态引擎将健康数据实时转化为体力、精力、心情三项生命值，再派生出 SICK、SLEEPING、TIRED、NORMAL、EXCITED、BLISSFUL 等宠物状态，并用像素宠物动画、今日建议卡、喂养反馈和图鉴生命周期形成持续陪伴体验。

在鸿蒙生态侧，作品不仅提供手机 App，还规划接入元服务/服务卡片，让用户无需打开 App 即可看到宠物状态和今日建议；接入小艺开放平台，通过自然语言查询宠物状态、开始深呼吸、查看今日步数；结合华为账号、AppGallery Connect 云数据库和云函数实现好友一起养、社区步数目标和跨设备同步。所有原始健康数据默认只在端侧计算，云端只保存用户主动分享的派生宠物状态，兼顾趣味性、全场景体验和隐私保护。

## 13. 资料来源

- 2026 HarmonyOS 创新赛·极客赛道活动页：https://developer.huawei.com/consumer/cn/activity/digixActivity/digixcmsdetail/101773710117484023?pageIndex=1
- Health Service Kit/华为运动健康服务介绍：https://developer.huawei.com/consumer/cn/hms/huaweihealth/
- HarmonyOS SDK 开放能力说明：同赛事活动页“学习开发资源”部分。
- 小艺开放平台：https://developer.huawei.com/consumer/cn/celia
- HarmonyOS 意图框架：https://developer.huawei.com/consumer/cn/huawei-hag/
- HarmonyOS 开发文档入口：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/
