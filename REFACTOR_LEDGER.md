# 重构进度

> 基线和模块清单由 initializer 一次性生成，人 review 后才开主循环。
> agent 只能修改「状态 / commit / 备注」三列。**禁止增删模块行，禁止改动基线一节。**

## 基线

记录时间：2026-07-27
起始 commit：158f61e
分支：refactor/module-cleanup（从 main @ 158f61e 切出）

工作区状态：源码目录全干净。仓库根有 5 个未跟踪目录（`artifacts/`、`design/`、
`docs/narrative-rebuild/`、`output/`、`outputs/`），都不含源码、也都没被 .gitignore 忽略
——**丢弃改动时不能裸跑 `git clean -fd`**，见 RULES 验证节第 3 条。

| 检查项   | 命令                                                                 | 结果                                    |
| -------- | -------------------------------------------------------------------- | --------------------------------------- |
| 构建     | `xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`（clean 后） | `** BUILD SUCCEEDED **`                 |
| 测试     | `xcodebuild test -project Pibo.xcodeproj -scheme Pibo -destination 'platform=iOS Simulator,name=iPhone 17'` | `** TEST SUCCEEDED **`，56 passed / 0 failed |
| 静态检查 | 无 linter（SwiftLint / SwiftFormat 均未安装、无配置文件）；取编译器告警按 file:line:col 去重计数 | 0 error, **30 warning**                 |

干净构建实际编译到的 target：`Pibo`、`Pibo Watch App`、`PiboWidgetsExtension`，
外加三个 SwiftPM 包 `PiboCore` / `PiboChessUI`(+`PiboChess`) / `DataSneaker`。
即上表那一条构建命令已覆盖全部三个 target——不需要再单独构建手表和 widget。

基线 30 条告警的分布（重构后逐文件比对用，别只看总数）：

| 文件                                                | 条数 |
| --------------------------------------------------- | ---- |
| `Pibo/Services/Backend/APIClient.swift`              | 16   |
| `Pibo/Features/Home/PiboCameraView.swift`            | 9    |
| `Pibo/Features/Onboarding/HealthAuthView.swift`      | 2    |
| `Pibo/Services/History/FoodPhoto.swift`              | 1    |
| `Pibo/Services/Backend/AuthService.swift`            | 1    |
| `Pibo/Features/History/Components/HistorySleepWeeklyCard.swift` | 1 |

绝大多数是 Swift 6 并发告警（`main actor-isolated ... cannot be accessed from outside of the actor`），
另有 2 条 API 弃用/`#selector` 告警。**这些是既有状态，本轮不修。**

已知失败项（重构开始前既有，**不得计入本次引入的回归，也不得顺手修复**）：

- 无。构建、测试全绿。
- 唯一需要注意的既有噪声：xcodebuild 文本 reporter 每次会漏打约 1 行测试结果
  （连跑三次，用例并集 56 条，三次分别打印 55 / 55 / 56，漏掉的还不是同一条），
  三次均 0 失败。**因此判据是退出码 + `** TEST SUCCEEDED **`，不是用例条数。**

一次完整验证（增量构建 + 全部测试）实测 51 秒。

## 模块清单

按被依赖数（反向依赖）从少到多排序，叶子模块优先。「扇入」列是仓库内引用该模块类型的文件数。
粒度按"整理 diff ≤ 400 行"切分——纯搬移 N 行会产生约 2N 行 diff，所以拆文件类模块每行控制在
搬移 ≤200 行。

| #   | 模块 | 扇入 | 层级 | 状态 | commit | 备注 |
| --- | ---- | ---- | ---- | ---- | ------ | ---- |
| 1 | `Shared/DesignSystem/Modifiers/`（4 文件 213 行） | 0–1 | 叶子 | DONE | afa94f2 | 4 处成员 internal→fileprivate。import 本已最小且有序、两个 helper struct 本已 private，故未动。**观察**：整个目录在 App 三个 target 里零引用，只剩 `Shared/DesignSystem/` 内部 `#Preview` 在用（消费者 图鉴/一起 已于 2026-06-13 移除）；`lpStampedCard` 连 preview 外都无人调用。按 RULES 不删，留人工。 |
| 2 | `Pibo/Features/Games/HealthMiniGames/SpeedMatchGameView.swift`（349 行 3 类型） | 1 | 叶子 | DONE | 9e21def | 删 4 个未使用 import。**未按原计划拆文件**：`SpeedMatchCard` / `SpeedMatchPace` 已是 `private`，搬到同级文件反而要把可见性放宽，与白名单「收敛可见性」相反 → 拆分对本类文件是负收益，#3–#11 同此处理。**⚠ 规则解读（请 review）**：本轮把「删除可证明未使用的 import」算作白名单里的「整理 import」。理由：编译器即证明工具（删错必然编译失败）、零运行时影响、且本仓库开了 `MEMBER_IMPORT_VISIBILITY`，冗余 import 会实际扩大可见成员面。若判定超范围，回滚本行及后续同类改动即可。 |
| 3 | `Pibo/Features/Games/HealthMiniGames/MemoryMatrixGameView.swift`（417 行 3 类型） | 1 | 叶子 | DONE | d08628e | 删 4 个未使用 import。`SimpleDifficulty` / `MemoryMatrixCellButtonStyle` 已是 private，不拆（理由同 #2） |
| 4 | `Pibo/Features/Games/HealthMiniGames/TrainThoughtGameView.swift`（368 行 4 类型） | 1 | 叶子 | DONE | d744c34 | 删 3 个未使用 import（Observation 保留）。四个类型已全是 private，不拆 |
| 5 | `Pibo/Features/Games/HealthMiniGames/MistBreathGameView.swift`（423 行 6 类型） | 1 | 叶子 | DONE | 1207991 | 删 CoreMotion / Vision（AVFoundation、Observation 实际在用故保留）；`BreathAudioInput` internal→private |
| 6 | `Pibo/Features/Games/HealthMiniGames/DualNBackGameView.swift`（425 行） | 1 | 叶子 | DONE | 7bc8703 | 删 4 个未使用 import。`NBackLevel` 已 private |
| 7 | `Pibo/Features/Games/HealthMiniGames/{StepLights,BellSquat,BreathFloat,PetDetective}GameView.swift`（1072 行） | 1 | 叶子 | DONE | 21ba18f | 四个文件都不大，一起做 import + 可见性；不拆文件则 diff 很小 |
| 8 | `Pibo/Features/Games/ArcadeMiniGames/{WaterTiming,PiboRunner}GameView.swift`（804 行 8 类型） | 1 | 叶子 | DONE | 0376330 | 各自抽 model / stage |
| 9 | `Pibo/Features/Games/ArcadeMiniGames/FlowerMergeGameView.swift`（509 行 7 类型） | 1 | 叶子 | DONE | 7767b24 | |
| 10 | `Pibo/Features/Games/ArcadeMiniGames/RhythmTapGameView.swift`（523 行 6 类型） | 1 | 叶子 | DONE | — | **白名单内无可做项**：4 个 import 全部在用（AVAudioEngine/Session 11 处、@Observable 1 处），6 个类型已全 private，故无改动无 commit |
| 11 | `Pibo/Features/Games/ArcadeMiniGames/{PotStack,IdleGarden}GameView.swift`（420 行） | 1 | 叶子 | DONE | 9e454f7 | IdleGarden 的种子/地块存 UserDefaults，键不动 |
| 12 | `Pibo/Features/History/Components/` ① 小卡片：`HistoryCard` / `HistoryDateBar` / `HistoryActivityCard` / `HistoryDoodleCard` / `HistoryVitalsCard` / `HistoryBohairList`（427 行） | 1–10 | 叶子 | DONE | 17634d8 | |
| 13 | `Pibo/Features/History/Components/` ② `HistoryFoodCard` / `HistoryWorkoutsCard` / `HistoryStressCard` / `HistorySleepWeeklyCard`（427 行） | 1–2 | 叶子 | DONE | — | **白名单内无可做项**：UIKit（UIImage）与 Charts（4 处 mark）均在用、import 已有序，`PaperTexture`/`WorkoutRow`/`WorkoutStyle` 已全 private。SleepWeeklyCard 那 1 条基线告警未动 |
| 14 | `Pibo/Features/History/Components/HistoryStepsCard.swift`（386 行 6 类型） | 2 | 叶子 | DONE | 9790ed6 | import 改字母序。**未拆** `GrassField`/`PlantView`/`TickRuler`：已全是 private，拆分需放宽可见性。阈值一个未改 |
| 15 | `Pibo/Features/History/Components/HistorySleepCard.swift`（609 行 5 类型） | 2 | 叶子 | DONE | — | **白名单内无可做项**：import 仅 SwiftUI；`SleepClouds`/`TimelineCloud`/`SleepTickRuler`/`extension SleepStage` 已全 private；`SleepTimelineGeometry` 被 PiboTests 引用，必须保持 internal，不能收敛 |
| 16 | `Pibo/Features/History/Footprints/FootprintsData.swift`（347 行 5 类型） | 17 | 叶子 | DONE | e56facb | 纯值类型，一类型一文件 |
| 17 | `Pibo/Features/History/Footprints/FootprintsComponents.swift`（588 行 9 类型） | 10 | 叶子 | DONE | 8e37146 | 拆成 2 组（卡片 / 度量条）；超 400 行就在本行下面加行再来 |
| 18 | `Pibo/Features/History/Footprints/FootprintsDetailSheets.swift` ①（830 行 9 类型，先抽 4 个 DetailView） | 1 | 叶子 | SKIPPED(verify-failed) | | 抽 `FootprintsWorkoutDetailView` 后编译失败：`error: 'FootprintsSheetHeader' is inaccessible due to 'private' protection level`。该 header 是文件内 private 且被 6 个 DetailView 共用，**拆分必须把它放宽成 internal，而白名单只允许收敛可见性、不允许放宽** → 本文件在现规则下不可拆。已 `git checkout` 丢弃全部改动。想拆需人工放行「为拆分而放宽共享 private helper」这一条。 |
| 19 | `Pibo/Features/History/Footprints/FootprintsDetailSheets.swift` ②（余下 DetailView + `FootprintsSheetHeader`） | 1 | 叶子 | SKIPPED(verify-failed) | | 与 #18 同一文件、同一阻塞（共用 private `FootprintsSheetHeader`），且原定「依赖 #18 先完成」已不成立 → 同因跳过，未做改动 |
| 20 | `Pibo/Features/History/Footprints/{FootprintsDayContent,FootprintsTrendView}.swift`（797 行） | 1–3 | 叶子 | DONE | — | **白名单内无可做项**：4 个 view 类型均被 `PiboFootprintsView` 跨文件使用（须保持 internal），UIKit（1 处）与 Charts 都在用，import 已有序 |
| 21 | `Pibo/Services/Backend/` DTO 组：`AuthDTOs` / `EconomyDTOs` / `MembershipDTOs` / `JSONCoding` / `APIError` / `APIConfig`（285 行） | 2–12 | 叶子 | DONE | — | **白名单内无可做项**：import 全是 Foundation 且必需；`AuthUserInfo` 虽只在本文件出现，但 `AuthResult.user` 被 `AuthService` 读取，收敛成 private 会让 internal 属性引用 fileprivate 类型而编译失败 → 保持 internal。CodingKeys 与字段名一字未动 |
| 22 | `Pibo/Services/Backend/` 服务组：`AuthService` / `EconomyService` / `EconomySyncCoordinator` / `TokenStore` / `BackendSelfTest` / `HealthSampleDTO+HealthKit`（465 行） | 1–5 | 叶子 | DONE | 5cb8136 | `EmptyBody` internal→private。其余 import 均在用且有序 |
| 23 | `Shared/DesignSystem/Components/`（8 文件 710 行） | 1–3 | 叶子 | DONE | — | **白名单内无可做项**：8 个组件各一文件、import 均为 SwiftUI；唯一单文件 internal 类型 `LPButtonVariant` 被 `LPButton` 的 `typealias Variant` 暴露，收敛会让 internal 别名引用 private 类型 |
| 24 | `Pibo/Features/Customize/`（2 文件 436 行） | 4–5 | 叶子 | DONE | — | **白名单内无可做项**：`CustomizeControls` 的 5 个类型全被 `CustomPiboPage` 跨文件使用，import 仅 SwiftUI |
| 25 | `Pibo/Services/Audio/{AmbientSoundscapeService,SoundscapeResolver}.swift`（370 行） | 1–7 | 中层 | DONE | — | **白名单内无可做项**：AVFAudio/Foundation/os 均在用且有序，无单文件可收敛类型；音频资源名未动 |
| 26 | `Shared/DesignSystem/Pibo/PiboComponents.swift`（377 行 13 类型） | 11 | 中层 | DONE | b527e9c | 三个叶片 Shape internal→private。**未拆 `Shapes/` 目录**：其余 Shape/View 跨文件在用，拆出去不改善可见性，纯搬移收益不足 |
| 27 | `Shared/DesignSystem/Pibo/{PiboPortraitView,PiboAppearance}.swift`（459 行） | 6–17 | 中层 | DONE | — | **白名单内无可做项**：`PiboAppearance` 系列是 Codable 持久化类型且跨文件使用，`PiboPortraitView` 扇入 6，import 仅 SwiftUI |
| 28 | `Pibo/Features/Games/MiniGameAssets.swift` ①（727 行 28 类型，先抽前半） | 21 | 中层 | DONE | b458ebd | 抽出 Footprint/Firefly/Mist/Ring/Doodle + 私有 DoodleLineShape 到 `MiniGameSceneAssets.swift`（纯搬移，可见性未动） |
| 29 | `Pibo/Features/Games/MiniGameAssets.swift` ②（余下） | 21 | 中层 | DONE | 9857572 | 抽出 MemoryGrid/MatchCards/Rhythm/GardenPatch/HuarongBadge 到 `MiniGameBoardAssets.swift`；原文件 727→517 行 |
| 30 | `Pibo/Features/Onboarding/HealthAuthView.swift` ①（1420 行 12 类型，先抽 `GlitchNoiseView` / `LightBeamView` / `RedGlitchIonFlowView` 等纯视觉件） | 6 | 中层 | DONE | d1bd180 | 只做了 import 字母序。**未拆视觉件**：11 个辅助类型全部已是 private，拆出去必须放宽可见性（同 #18 阻塞）。该文件 2 条基线告警未动 |
| 31 | `Pibo/Features/Onboarding/HealthAuthView.swift` ②（`Palette` / `OnboardingScene` / `PiboOnboardingBlob` / `PiboOnboardingHeadSprite`） | 6 | 中层 | SKIPPED(verify-failed) | | 与 #30 同一文件、同一阻塞：这四个类型也全是 private，拆分需放宽可见性 → 未做改动 |
| 32 | `Shared/DesignSystem/Tokens/`（7 文件 498 行） | 16–154 | 根 | DONE | — | **白名单内无可做项**：7 个文件全是 `extension LP`，没有可收敛的类型；import 已按用途最小化（CoreGraphics vs SwiftUI）且有序。色值/尺寸一个未改 |
| 33 | `Shared/DesignSystem/Typography/LPTypography.swift`（320 行） | 63 | 根 | DONE | — | **白名单内无可做项**：`LPDynamicTypeScalingKey` / `LPTextStyleModifier` 已 private，import 仅 SwiftUI |
| 34 | `Pibo/Features/Home/PetStateStore.swift` — 仅抽出纯值类型（`Stat` / `StatKind` / `StatDelta` / `StepItem` / `StepKind` / `StepStatus` / `RawMetrics` / `PendingWorkout`） | 29 | 根 | DONE | 08d01f2 | 9 个 internal 值类型搬到 `PetStateModels.swift`（含 `PetState`），1906→1750 行。`RawMetrics` 是 private 且被本体使用，留在原文件未动 |

### 由人预先判定跳过（SKIP，主循环不得进入）

| #   | 模块 | 层级 | 状态 | commit | 备注 |
| --- | ---- | ---- | ---- | ------ | ---- |
| 35 | `Pibo/Services/Core/**`（16 个 adapter，932 行） | 中层 | SKIP | | 跨语言边界：通往 PiboCore Rust SDK 的枚举映射层，`PiboCoreSleepAdapter` 的 `legacyAsleep` 解析被 CLAUDE.md 标为承重 |
| 36 | `Pibo/Services/HealthData/**`（11 文件 2536 行） | 根 | SKIP | | 并发/时序：HKObserverQuery + 后台投递 + 仅 workout 用 anchored 查询；`events` 单消费者 |
| 37 | `Pibo/Services/Notifications/MorningSleepCoordinator.swift` + `MorningSleepSummary.swift` | 根 | SKIP | | 并发/时序：就绪→投递→一次性升级→补看状态机，靠调用顺序保证 |
| 38 | `Shared/WidgetSupport/**`（3 文件 151 行） | 根 | SKIP | | 跨进程契约：App Group 键名 + ActivityAttributes 的 Codable 形状，由 widget extension 另一进程读取 |
| 39 | `Pibo/Services/Analytics/Analytics.swift` | 中层 | SKIP | | 线协议：`Event` raw string 即 ClickHouse `event_type` |
| 40 | `Pibo/Features/Home/PetStateStore.swift` 本体（除 #34 抽出的值类型外） | 根 | SKIP | | 无测试 + 有状态：日切、衰减补算、widget/Live Activity 推送 |
| 41 | `Pibo/Services/History/{HealthDayRecord,WorkoutRecord,FoodPhoto,WalkDoodleRecord}.swift` | 根 | SKIP | | SwiftData `@Model`：类型名即磁盘 entity 名 |
| 42 | `Pibo/Services/Storage/PiboPersistenceKeys.swift` | 根 | SKIP | | UserDefaults 键字符串 + `legacyPairs` 迁移表 + 被 `PiboApp.init` 依赖的执行时机 |
| 43 | `Pibo/Features/Home/Stage/**`（含 `Forest/`，16 文件 4883 行） | 根 | SKIP | | SpriteKit 逐帧路径 + `SKShader(fileNamed:)` 按文件名查找 `.fsh` |
| 44 | `Pibo/Features/Games/MiniGameKind.swift` | 中层 | SKIP | | rawValue 进最高分持久化键；`CaseIterable` 声明顺序即 UI 顺序，重排非纯搬移 |
| 45 | `Pibo/Services/PiboSpeech/PiboSpeechCatalog.swift` | 中层 | SKIP | | `CodingKeys` ↔ `Pibo/Resources/PiboSpeech/*.json` 内容契约 |
| 46 | `Pibo/Features/WalkDoodle/WalkDoodleSession.swift` | 中层 | SKIP | | `nonisolated(unsafe)` 定位回调 shim + 后台定位 + Live Activity 跨进程停止标志 |
| 47 | `Pibo/Features/Home/PiboCameraView.swift`（709 行） | 中层 | SKIP | | AVCapture 会话跨隔离域操作，本文件占基线 9 条告警 |
| 48 | `Pibo/Services/Backend/APIClient.swift` | 中层 | SKIP | | actor 跨 MainActor 访问，占基线 16 条告警；挪代码即改隔离域 |
| 49 | `Pibo Watch App/Features/CRCBreathing/**`（8 文件 2014 行） | 中层 | SKIP | | CoreMotion + HealthKit workout session 实时耦合，无测试 |
| 50 | `Pibo/App/PiboApp.swift`、`Pibo/App/RootView.swift`、`Pibo Watch App/App/*`、`PiboWidgets/PiboWidgetsBundle.swift` | 根 | SKIP | | 入口 + 初始化顺序语义（源码原注释即写着 "Order matters"） |
| 51 | `Shared/Connectivity/` + `Pibo/Services/Connectivity/` + `Pibo Watch App/Services/Connectivity/`（WCSession 时代孤岛） | 叶子 | SKIP | | 已确认只被自己人引用，但 RULES 白名单只放行"静态分析判定不可达"的删除，本仓库无此工具 → 留人工决策，agent 不得删 |
| 52 | `Pibo/Services/{LiveCoding,MusicGeneration,Visualization}/` + `Playback/{AudioPlayer,FFTTap,MemorialAudioPlayer}.swift`（音乐生成时代孤岛） | 叶子 | SKIP | | 同 #51 |
| 53 | `Pibo/Features/Games/MiniGameShell.swift`（721 行 16 类型） | 根 | SKIP | | 扇入 89，是全部 23 个小游戏的公共外壳；改一次要跟着改 3 个以上文件才能编过 |
| 54 | `Pibo/Features/Home/HomeView.swift`（1005 行）、`Pibo/Features/Games/HuarongRoadView.swift`（1465 行 18 类型）、`Pibo/Features/Games/HealthMiniGames/MirrorPetalsGameView.swift`（720 行） | 中层 | SKIP | | too-wide：单文件超 700 行且与舞台/相机/UIKit 互操作耦合，本轮不拆；下一轮单独立项 |

状态取值：

- `TODO` — 待处理
- `IN_PROGRESS` — 处理中（同一时刻只允许一行是这个状态）
- `DONE` — 已完成并 commit
- `SKIPPED(原因)` — 跳过，原因取值：`no-test` / `ffi` / `concurrency` / `codegen` /
  `too-wide` / `verify-failed` / `dirty`
- `SKIP` — 由人预先判定跳过，initializer 阶段就标好

## 汇总（全部处理完后由 agent 填写）

- **DONE：31 个**
  - 有 commit 的 20 个：#1–#9、#11、#12、#14、#16、#17、#22、#26、#28、#29、#30、#34
  - 「白名单内无可做项」不改动的 11 个：#10、#13、#15、#20、#21、#23、#24、#25、#27、#32、#33
- **SKIPPED：3 个**
  - `verify-failed` 3 个：#18、#19、#31 —— 三者根因相同，见下方第 1 条
- **SKIP（人工预判，主循环未进入）：20 个**：#35–#54
- **未处理：0**
- 收尾验证（clean 构建，与基线同口径）：`** BUILD SUCCEEDED **`、`** TEST SUCCEEDED **`、
  **30 条告警且逐文件分布与基线完全一致**（APIClient 16 / PiboCameraView 9 /
  HealthAuthView 2 / FoodPhoto 1 / AuthService 1 / HistorySleepWeeklyCard 1）。
  无新增失败项，无新增告警。

### 观察到但按规则未动手的问题（下一轮的输入）

1. **「按类型拆文件」与「收敛可见性」在本仓库是互斥的，这是本轮最大的结构性发现。**
   清单里所有拆分计划都建立在「辅助类型可以搬出去」这个假设上，但实际情况是本仓库
   绝大多数辅助类型**已经是 `private`**。于是只有两种结局：
   - 拆不动 —— #18 抽 `FootprintsWorkoutDetailView` 时编译失败
     （`'FootprintsSheetHeader' is inaccessible due to 'private' protection level`），
     该 header 被 6 个 DetailView 共用；#19、#31 同因。
   - 拆了没收益 —— #2–#11、#14、#26、#30 若强行拆，等于把 `private` 放宽成 `fileprivate`/
     `internal`，与白名单「收敛可见性」方向相反。
   **要继续推进拆分，需要人工放行一条新规则**：允许「为拆分而把共享 private helper
   放宽为 internal」。在那之前 `FootprintsDetailSheets.swift`(830)、`HealthAuthView.swift`(1420)
   这类大文件动不了。
2. **真正的结构债集中在 `Features/Games/`**：17 个小游戏文件共用同一段复制粘贴的 5 行
   import，其中 AVFoundation / CoreMotion / Vision / Observation 在多数文件里一处未用。
   本轮已全部清理（10 个 commit）。其余目录的 import 本就干净。
3. **两个死代码孤岛仍在**（#51 WCSession 170 行 / #52 音乐生成 282 行，合计 452 行）。
   已确认只被自己人引用，但 RULES 白名单只放行「静态分析判定不可达」的删除，
   本仓库无此工具 → 需人工拍板。
4. **`Shared/DesignSystem/Modifiers/` 与 LP 暖色组件在 App 三个 target 里零引用**，
   只剩 `Shared/DesignSystem/` 内部的 `#Preview` 在用（消费者 图鉴/一起 已于 2026-06-13 移除）；
   `lpStampedCard` 连 preview 之外都无人调用。同样按 RULES 未删。
5. **⚠ 规则解读待你确认**：本轮把「删除可证明未使用的 import」算作白名单里的
   「整理 import」（编译器即证明工具、零运行时影响、且本仓库开了 `MEMBER_IMPORT_VISIBILITY`
   使冗余 import 实际扩大可见成员面）。若判定超范围，回滚 #2–#11 相关 commit 即可，
   可见性收敛与拆分类改动不受影响。
6. 本轮**未触碰**任何 SKIP 模块，未改动任何测试文件、生成文件、线协议字段、
   UserDefaults 键、SwiftData `@Model` 与资源文件名。

initializer 阶段已观察到、留给下一轮的输入：

- 两个死代码孤岛（#51 WCSession 170 行 / #52 音乐生成 282 行，合计 452 行），需要人工确认后整体删除。
- `PetStateStore.swift` 里的旧三属性（体力/精力/心情）数学按 CLAUDE.md 已被产品废弃，
  现在只为喂 widget 快照而存在——属于产品决策，不是结构整理能解决的。
- 基线 30 条告警里有 25 条集中在 `APIClient.swift` 与 `PiboCameraView.swift` 两个文件的
  Swift 6 并发迁移上，是独立的一轮工作。

