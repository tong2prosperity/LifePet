# Pibo

> 你不是喂宠物，你的身体就是宠物的食物。养得好它陪你更久，养不好它早早走掉。

一个 iOS-only 的 hackathon 项目，把 HealthKit 里的日常健康数据变成一只拓麻歌子（Tamagotchi）：步数、睡眠、心率变异 …… 都直接喂给你的小宠物，决定它今天的状态、寿命、命运。

> Bundle / scheme / 工程入口现在都已迁到 **Pibo**；旧 LifePulse 名称只应出现在历史说明或兼容迁移代码里。

---

## 核心玩法

宠物的生死只看三个数（每个 0–100）：

| Stat | 来源（HealthKit） | 公式 |
|---|---|---|
| 💪 **体力** vitality | 步数 · 运动分钟 · 活动卡路里 · 站立时长 | `20 + (步数/10000)·40 + (运动分钟/30)·30 + (kcal/300)·10` |
| ⚡ **精力** energy | 总睡眠 · 深睡 · REM | `(总睡眠h/8)·50 + (深睡h/2)·30 + (REMh/1.5)·20` |
| ❤️ **心情** mood | HRV · 心率稳定度 · 压力峰值 | `50 + (HRV_今 - HRV_基线)·0.8 − 压力峰值·5` |

**自然衰减：** 每 4 小时三个状态各 −5（最低 10）。睡觉时精力不衰减。

宠物有 6 种视觉状态，按优先级评估：`SICK` (心情<30) → `SLEEPING` (精力<30) → `TIRED` (体力<30) → `BLISSFUL` (心情>85) → `EXCITED` (体力>85) → `NORMAL`。

寿命不固定。UI 永远只显示「已陪伴第 N 天」，没有分母；条件触发死亡（连续 7 天压力 / 10 天零运动 / 任一状态 = 0 超 48h ……），也有续命奖励（三项 > 60 持续 7 天自动续命）。

完整 PRD 见 `../lifepulse_md/运动健康的拓麻歌子.md`。

---

## 项目结构

```
Pibo.xcodeproj         # 单工程，两个 target
├── Pibo/              # iOS 应用（唯一活跃 target）
│   ├── App/                # @main · RootView · Tab 容器
│   ├── Features/
│   │   ├── Home/           # 主页：宠物舞台 / 三状态条 / 今日步骤
│   │   ├── Catalog/        # 图鉴 + 死亡纪念波形
│   │   ├── Together/       # 一起养（朋友 / 邀请）
│   │   ├── Pet/            # Sprite 序列与目录
│   │   ├── Onboarding/     # HealthKit 授权
│   │   └── ⚠️ Generation / Playback / Session — 旧方向死代码，待清理
│   ├── Services/
│   │   ├── HealthData/     # HKObserverQuery + Anchored + 后台投递
│   │   ├── Identity/       # 宠物 UUID / 名字 / 出生日 持久化
│   │   ├── History/        # 每日快照（DailySnapshot）
│   │   ├── Logging/        # os.Logger 包装
│   │   └── ⚠️ LiveCoding / MusicGeneration / Visualization / Playback / Connectivity — 旧方向死代码
│   └── Assets.xcassets/sprites/   # 像素宠物动画帧
├── Pibo Watch App/    # ⚠️ vestigial，新功能不要往这里加
├── Shared/
│   ├── DesignSystem/       # LP.* tokens + 组件 + 修饰器
│   ├── Models/             # ⚠️ Vital* 系列旧 wire-format，待替换
│   └── Connectivity/       # ⚠️ 旧 WatchConnectivity，待清理
└── mocks/                  # JSONL 测试流（旧）
```

**重要：** 两个 target 都使用 `PBXFileSystemSynchronizedRootGroup` —— 把 `.swift` 丢进对应文件夹会自动加入编译，**不要手动改 `project.pbxproj`** 来注册源文件。

### Pivot 说明

最初的设计是 Apple Watch app + `WCSession` 实时推流。**这条线已经砍掉。**
现在 watch 不写自定义 app —— 用户原本佩戴的 Apple Watch 把步数 / 心率 / 睡眠写进 HealthKit，iOS 端通过 `HKObserverQuery` + 后台投递被动读取就够了。所有 `Connectivity/` / `Generation/` / `Playback/` / `Session*` / `Pibo Watch App/` 都是上一阶段的尸体，不要继续在上面加功能。

---

## 数据管道（HealthKit）

```
HKObserverQuery ── 通知 ──► HKAnchoredObjectQuery ── 增量样本 ──► HealthEvent
                                                                       │
                                                                       ▼
                                                                PetStateStore
                                                          （计算三状态 + 派生 PetState）
                                                                       │
                                                                       ▼
                                                                HomeView 动画
```

- 启动时调一次 `HKHealthStore.requestAuthorization`（仅 read），首次进入 `HealthAuthView`，结果记进 `UserDefaults`
- 每个 metric 注册 `HKObserverQuery` + `enableBackgroundDelivery(.immediate)`，watch 同步新样本时 iOS 会被唤醒
- 聚合类（步数 / 卡路里 / 站立 / 运动分钟 / 冥想）用 `HKStatisticsQuery cumulativeSum` 拿当日累计；
  HRV / RHR / HR 用 `HKSampleQueryDescriptor limit:1` 拿最新；
  睡眠按 category 求时长；
  workout 走 anchored query 拿增量（用来自动勾选「今日步骤」里的建议卡）
- `scenePhase == .active` 时跑一次 `reconcile()` 兜底
- 跨天时 `PetStateStore.checkDayRollover` → `applyDecayCatchup` → 新一天的 reconcile

授权所需 Info.plist key：`NSHealthShareUsageDescription`；目标需要勾选 HealthKit capability。

---

## 设计系统（`Shared/DesignSystem/`）

**做新 UI 之前先看这里**，不要随手定义颜色 / 字号 / 卡片。

- **Tokens**：`LP.Colors` / `LP.Typography` / `LP.Spacing` / `LP.Radius` / `LP.BorderWidth` / `LP.Shadow` / `LP.DashPattern`
- **Components**：`LPCard` · `LPStatBar` · `LPButton` · `LPPill` · `LPStickyNote` · `LPSpeechBubble` · `LPStamp` · `LPDashedRule`
- **Modifiers**：`.lpCard()` · `.lpStampedCard()` · `.lpDashedBorder()` · `.lpPaper()`

调色板是 light-only 纸张感，两个 App 入口都钉了 `.preferredColorScheme(.light)` —— 暂时不要碰 dark mode。

---

## 构建运行

要求：**Xcode 26.2 / Swift 5.0 / iOS 26.2**，`DEVELOPMENT_TEAM = 4626WN8J3B`，自动签名。

日常用 Xcode 选 `Pibo` scheme + ⌘R 即可。命令行：

```bash
# 构建 iOS 应用（也会顺带编译 watch target）
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build

# 仅构建 watch
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build

# 列出 schemes / targets
xcodebuild -project Pibo.xcodeproj -list

# 清理
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean
```

依赖管理：没有 `Package.swift` / CocoaPods / Carthage —— 要加包请用 Xcode 内置 SwiftPM。

并发设置：两个 target 都开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，新类型默认 `@MainActor`。HealthKit / 后台 / 音频任务要显式 `nonisolated` / `Task.detached`。

### Demo Mode

设备上没真实 HealthKit 数据时，`PetStateStore.demoMode` 会用硬编码值兜底：宠物名 **BEAN** / **D07** / 体力 88 · 精力 74 · 心情 82 / 状态 `EXCITED`。Demo 也会走孵蛋动画（`UserDefaults` 的 `pibo.hatched.v1`）。

---

## 文案语气

- ❌ 不卖惨，不问责，不悲情（"分身替你死" / "你没好好活着"）
- ✅ 统计、好玩、期待感（"已经陪过 4 只" / "又被你熬死了" / "下一只想养什么类型？"）

「今日步骤」副标题永远是固定那句，不要改：
**"打 ✅ 它开心，打 ❌ 不扣分 —— 但它会记住，下次少推。"**

---

## 路线图（hackathon 范围）

- [x] iOS 主页（宠物舞台 / 三状态条 / 步骤卡）
- [x] LP 设计系统
- [x] HealthKit 授权 + Observer 管道
- [x] 图鉴 + 纪念波形
- [x] Together（一起养）
- [ ] 砍掉 watch target / 旧 LiveCoding / Connectivity 死代码
- [ ] 死亡触发评估循环
- [ ] 续命奖励簿记
- [ ] AI 建议卡排序（目前是静态卡）
