# Pibo

> 你不是喂宠物，是 Pibo 为了让头上的花开，不得不从你身上吸能量。养得好它陪你更久，养不好它发疯、生病、离去。

一个 iOS-only 的 hackathon 项目。Pibo 是一只从异世界掉到地球的**种花小精灵**——傲娇、不喜欢人类、对地球一无所知，只在乎自己头上长的那株花。花要靠从你身上采集的能量才能开，所以它赖上了你，却死不承认。HealthKit 里的步数、睡眠、运动 …… 直接决定花的状态、Pibo 的心情和它陪你的时间。

> Bundle / scheme / 工程入口现在都已迁到 **Pibo**；旧 LifePulse 名称只应出现在历史说明或兼容迁移代码里。

---

## 核心玩法（魔丸态 · MVP）

MVP 是 **魔丸态** Pibo（相识第 1–14 天）：听不懂人话、说乱码音节、大部分时候不理你，只在乎头上的花。

**没有三状态、没有星光、没有今日步骤。** HealthKit 数据**直接**映射到 Pibo 的状态和花的形态，中间不经过 体力/精力/心情 这层。

| 能量 | 来源（HealthKit） | 对花的影响 |
|---|---|---|
| 🌙 睡眠能量 | 睡眠 | 精神力 —— 睡得好花挺立鲜亮，睡不好垂头 |
| 🏃 运动能量 | 步数 / Workout | 活力 —— 动得多花颜色鲜艳，不动发灰 |
| 📸 认知能量 | 拍照 | 解锁花的品种（后续） |
| 🎤 声音能量 | 喊 Pibo 名字 | 花的亲密度（后续） |

**活动区 6 状态**（时间节律 + 原始数据，优先级）：深眠 > 初醒(·睡够/·没睡够) > 活跃/烦躁 > 发呆（被打扰为选做）。
- **深眠** 22:00–06:00 或拔毛后 5 分钟 · **初醒** 06:00–10:00 首开 · **活跃** 步数≥10000 或有运动 · **烦躁** 步数<3000 无运动 或 睡眠<5h · **发呆** 默认。

**主页交互**：首页打招呼文案区（问候 + 与Pibo相识第 N 天 + 日记）· 活动区（拍一拍 / 拔毛）· 上滑 Dashboard（历史健康数据二楼，取代旧能量球）· 拍照交互（露珠相机 + Pibo 弹幕）。
- **拍一拍**：不理睬 或 说一句话，硬上限 10 分钟≤3 句 / 24 小时≤9 句，否则 30% 概率说话。
- **拔毛**：每晚 22:00–02:00 首开收花籽，按睡眠+运动评 好/中/坏，超时清空不补；拔毛后进入 5 分钟深眠。

寿命不固定，UI 只显示「与Pibo相识的第 N 天」，没有分母。养不好 → 发疯（glitch 故障艺术）→ 生病 → 离去，完成一个健康任务即可恢复。

源头文档：`product-web-prototype/0603Pibo世界观重构.md`（世界观）+ `product-web-prototype/pibo-home-features-spec.md`（主页功能 & 文案池）。原始 PRD `../lifepulse_md/运动健康的拓麻歌子.md` 与 `legacy_docs/` 为历史参考。

---

## 项目结构

```
Pibo.xcodeproj         # 单工程，两个 target
├── Pibo/              # iOS 应用（唯一活跃 target）
│   ├── App/                # @main · RootView · Tab 容器
│   ├── Features/
│   │   ├── Home/           # 主页：Pibo 活动区 / 拍一拍 / 拔毛 / 上滑 Dashboard / 拍照
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
                                                  （原始数据 + 时间 → 6 状态 / 能量卡片）
                                                                       │
                                                                       ▼
                                                                HomeView 动画
```

> 数据管道（observer + 后台投递 + 分 metric 读取）是现成的；`PetStateStore` 里的映射层仍是上一阶段的三状态/步骤卡代码，正在迁移到魔丸态模型——直接用原始数据派生状态，不再算三状态。

- 启动时调一次 `HKHealthStore.requestAuthorization`（仅 read），首次进入 `HealthAuthView`，结果记进 `UserDefaults`
- 每个 metric 注册 `HKObserverQuery` + `enableBackgroundDelivery(.immediate)`，watch 同步新样本时 iOS 会被唤醒
- 聚合类（步数 / 卡路里 / 站立 / 运动分钟 / 冥想）用 `HKStatisticsQuery cumulativeSum` 拿当日累计；
  HRV / RHR / HR 用 `HKSampleQueryDescriptor limit:1` 拿最新；
  睡眠按 category 求时长；
  workout 走 anchored query 拿增量（刚结束的运动用来触发能量收集卡片）
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

设备上没真实 HealthKit 数据时，`PetStateStore.demoMode` 会用上一阶段的硬编码值兜底：宠物名 **BEAN** / **D07** / 体力 88 · 精力 74 · 心情 82 / 状态 `EXCITED`——随魔丸态模型落地一并更新。Demo 也会走孵蛋动画（`UserDefaults` 的 `pibo.hatched.v1`）。

---

## 文案语气

- ❌ 不卖惨，不问责，不悲情，不直接说「你该运动了」（"分身替你死" / "你没好好活着"）
- ✅ 傲娇，把健康提醒包进「花的状态」（"花今天没精神…不是因为我在乎"），好玩、有期待感

魔丸态文案是**乱码但可读**的音节碎片，有主语（Pibo / 花），偶尔带语气词（啵 / 呢 / 啊）——像信号不好的外星人在拼句子，比如 `...花...睡了...` / `...发芽了啵！`。完整文案池见 `pibo-home-features-spec.md`（目前仅 §2 打招呼文案已定稿，其余审核中）。

---

## 路线图（hackathon 范围）

- [x] LP 设计系统
- [x] HealthKit 授权 + Observer 管道
- [x] 图鉴 + 纪念波形
- [x] Together（一起养）
- [x] iOS 主页骨架（仍是上一阶段的三状态条 / 步骤卡，待迁移）
- [ ] 魔丸态主页：打招呼文案 / 6 状态活动区 / 拍一拍 / 拔毛 / 能量收集
- [ ] 上滑 Dashboard（历史数据二楼，取代能量球）
- [ ] 拍照交互（露珠相机 + Pibo 弹幕）
- [ ] glitch / 生病 / 离去 衰退弧线
- [ ] 砍掉 watch 旧 WCSession / LiveCoding / Connectivity 死代码
