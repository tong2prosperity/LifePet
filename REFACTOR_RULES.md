# 重构规则

> 已针对本仓库（Pibo，iOS / Xcode / SwiftPM）填写完毕，无待填占位符。
> 本次任务只做结构整理，不改变任何运行时行为。每轮开始前重读本文件。

## 允许的操作（白名单，只做这些）

- 文件拆分/合并：整块搬移代码，函数体内容一个字符都不改
- 把类型、常量、私有函数移动到更合适的模块
- 收敛可见性：public → 包内可见 → 私有
- 整理 import / use 顺序
- 删除静态分析工具报告为不可达的代码

不在这个列表里的操作一律超出范围。想做但没列出来的，记在 ledger 备注列里，不要动手。

## 禁止

- 修改函数签名、参数顺序、返回类型
- 增删改结构体 / 类 / 枚举的字段
- 修改错误处理策略（吞异常、改 Result/Option、新增 panic 或 throw）
- 修改日志级别或日志内容
- 引入新接口、新抽象层、泛型化
- 同步改异步，或移动 await 的位置
- 修改任何测试文件
- 新增 / 升级依赖，或修改依赖锁定与 patch 配置
- 手改自动生成文件：
  - `Pibo.xcodeproj/project.pbxproj` — Xcode 管理。`Pibo/`、`Pibo Watch App/`、`Shared/`、
    `PiboWidgets/`、`PiboTests/` 都是 `PBXFileSystemSynchronizedRootGroup`，**新增/移动
    `.swift` 会自动注册，绝不要手动改 pbxproj 去登记文件**。
  - `Pibo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — SwiftPM 生成，
    只能由 `xcodebuild -resolvePackageDependencies` 重写
  - `Pibo.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
  - `Pibo.xcodeproj/xcshareddata/xcschemes/*.xcscheme`
  - `**/Assets.xcassets/**/Contents.json`（78 个，资源目录编辑器生成）
  - `Pibo/Resources/Localizable.xcstrings`、`Pibo/Resources/InfoPlist.xcstrings` — String Catalog，
    key 在构建时从源码抽取
  - `PiboStore.storekit` — Xcode StoreKit 配置编辑器
  - `Pibo/Assets.xcassets/plants/*.imageset/*.pdf` — Figma SVG → `rsvg-convert` 的派生产物
  - `Tools/PiboLeafRigGodot/leaf_rig.gd.uid` — Godot 生成
  - 构建期合成的 `Info.plist`（`GENERATE_INFOPLIST_FILE=YES` + 根目录部分 plist `Pibo-Info.plist`
    合并）。合并结果是构建产物；根目录那份部分 plist 才是源文件，且必须留在同步组 `Pibo/` 之外
  - 仓库外但被消费：`pibo-core` 的 `include/pibo_core.h` 与 `PiboCoreFFI.xcframework`
    （Rust 侧生成，本仓库只按 tag 消费）
- 删除国际化翻译 key

## 必须跳过的模块（命中即 SKIPPED，不要"小心地改"）

通用判据：

- 该模块无测试覆盖，且改动不是纯搬移
- 跨语言边界：FFI、unsafe、extern、native bridge、C header
- 并发相关：锁的作用域、事件发送时序、channel 消费顺序、状态机流转
- 代码生成的输入或输出：宏展开签名、注解驱动的注册、IDL / proto
- 需要同时修改 3 个以上其他文件才能编译通过
- 该模块存在未提交的改动

本仓库特有：

**跨语言边界（Rust FFI）**

- `Pibo/Services/Core/**`（16 个 `PiboCore*Adapter.swift`）——本仓库通往 `PiboCore` Rust SDK
  （`PiboCoreFFI.xcframework` + C header `pibo_core.h`）的唯一映射层。里面全是
  Swift enum ↔ Core enum 的 switch 映射：调换一个 case、合并一个分支，编译照过、行为静默改变。
  `PiboCoreSleepAdapter.coreSampleKind` 把 HealthKit 的歧义 `asleep` 解析成 `legacyAsleep`，
  CLAUDE.md 明确标注该选择"两半都是承重的"。整个目录不碰。

**并发 / 时序（靠单线程、单消费者、调用顺序保证正确性）**

- `Pibo/Services/HealthData/HealthDataService.swift` 及 `+History` / `+MorningSleep`
  ——`HKObserverQuery` + `enableBackgroundDelivery(.immediate)`；每个 metric 的读取策略不同
  （聚合用 `HKStatisticsQuery`、最新值用 `limit:1`、**只有 workout 用 anchored 增量查询**）。
  `events` 是无界 `AsyncStream`，**全 App 只有 `PetStateStore` 一个消费者**——多一个消费者就丢事件。
- `Pibo/Services/Notifications/MorningSleepCoordinator.swift`（+ `HealthData/MorningSleepSummary.swift`、
  `HealthData/HealthDataService+MorningSleep.swift`）——就绪/投递/一次性升级/补看四段状态机，
  "已展示的卡片只允许被 settled 版本替换一次"靠调用顺序保证。
- `Pibo/Features/WalkDoodle/WalkDoodleSession.swift` — `WalkLocationDelegate` 是
  `nonisolated(unsafe)` 回调 shim（254–268 行），配合后台定位 + Live Activity 跨进程停止标志。
- `Pibo/Services/Backend/APIClient.swift` — actor 内跨 MainActor 访问，基线里 16 条并发告警集中在此；
  挪动代码会改变隔离域，告警集合随之变化。
- `Pibo/Features/Home/PiboCameraView.swift` — AVCapture 会话在 nonisolated 上下文操作，基线 9 条告警。
- `Pibo Watch App/Features/CRCBreathing/**` — CoreMotion + HealthKit workout session 实时耦合，无测试。

**有初始化顺序语义的入口文件**

- `Pibo/App/PiboApp.swift` — `init()` 的顺序是语义：`PiboPersistenceMigrator.runIfNeeded()` 必须最先；
  `AppNotificationRouter.shared.onMorningSleepOpened` 必须在 `.install()` **之前**赋值；
  `HealthDataService` 先于 `PetStateStore(events:)` 构造。`.onChange(of: scenePhase)` 里
  源码原注释写着 "Order matters"：rollover → decay catchup → reconcile。
- `Pibo/App/RootView.swift`、`Pibo Watch App/App/PiboWatchApp.swift`、
  `Pibo Watch App/App/RootView.swift`、`PiboWidgets/PiboWidgetsBundle.swift`（`@main` / WidgetBundle 注册）

**跨进程 / 跨端契约（改了编译照过，运行时静默失效）**

- `Shared/WidgetSupport/**` — App Group `group.fun.tiebao.co.Pibo` 的键名、
  `PiboWidgetSnapshot` / `PiboFeedActivityAttributes` / `WalkDoodleActivityAttributes` 的 `Codable`
  形状、`StopWalkDoodleIntent`。由 widget extension **另一个进程**读取。
- `Pibo/Services/Analytics/Analytics.swift` — `Analytics.Event` 的 raw string 就是 ClickHouse 的
  `event_type`，与 Go 服务端 `internal/models/event.go` 对齐，改名等于数据迁移。
- `Pibo/Services/History/{HealthDayRecord,WorkoutRecord,FoodPhoto,WalkDoodleRecord}.swift` —
  SwiftData `@Model`，**类型名即磁盘 entity 名**，改名/换类型会让老库打不开。
- `Pibo/Services/Storage/PiboPersistenceKeys.swift` — UserDefaults 键字符串 + 旧键迁移表
  `legacyPairs`；`PiboPersistenceMigrator` 的执行时机被 `PiboApp.init` 依赖。
- `Pibo/Features/Games/MiniGameKind.swift` — `String` rawValue 被拼进最高分持久化键
  （`pibo.games.bestScore.v1.<rawValue>`）；且 `CaseIterable` 的**声明顺序就是游戏列表 UI 顺序**，
  重排 case 不是纯搬移。

**按文件名字符串查找的资源（改名编译照过、运行时崩）**

- `SKShader(fileNamed:)` → `Pibo/Features/Home/Stage/Forest/{ForestStream,ForestWaterBase,ForestMaterial,ForestReflection}.fsh`
  （调用点在 `ForestThemeRenderer.swift`、`ForestReflectionProjection.swift`）
- `Pibo/Services/PiboSpeech/PiboSpeechCatalog.swift` 的 `CodingKeys` ↔
  `Pibo/Resources/PiboSpeech/*.json` 五个内容文件；属性改名 = 内容文件失效
- `Pibo/Services/Playback/MemorialAudioPlayer.swift` 的 `Bundle.main.url(forResource:)`

**每帧路径（性能语义）**

- `Pibo/Features/Home/Stage/**`（含 `Forest/`）——SpriteKit 场景、相机平移、逐帧
  `update`、着色器。CLAUDE.md 有明确性能约定（不得在拖拽/平移/update 上加打点或透明度合成）。

**判定纠正（别照抄 CLAUDE.md 的"死代码"清单）**

- `Shared/Models/Vital*` 被 CLAUDE.md 列为"待替换的旧线格式"，但 `VitalSample` 仍被**在用的**
  手表 CRC 功能引用（`CRCTrainingViewModel.swift`、`VitalsStream.swift`）——不是死码。
- `Pibo/Services/History/DailySnapshotStore.swift` 被 `PiboApp` 与 `PetStateStore` 实际引用，在用。
- 真正自闭环、只被自己人引用的孤岛：`Shared/Connectivity/` + `Pibo/Services/Connectivity/` +
  `Pibo Watch App/Services/Connectivity/`（WCSession 时代）、
  `Pibo/Services/{LiveCoding,MusicGeneration,Visualization}/` + `Playback/{AudioPlayer,FFTTap}.swift`
  （音乐生成时代）。**即便如此也不许在本轮删除**——见下方判定标准。

## 验证（每个模块改完必须全跑）

```bash
# 工作目录：仓库根 /Users/trevorlink/Project/hackathon/Pibo（以下所有命令都在这里跑）

# ① 构建 —— 一条命令覆盖全部三个 target（Pibo / Pibo Watch App / PiboWidgetsExtension）
#    以及三个 SwiftPM 包（PiboCore / PiboChessUI / DataSneaker）。
#    Shared/ 会同时编进三个 target，只验 iOS 会漏掉手表和 widget 的编译错误。
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# ② 静态检查 —— 本仓库没有 SwiftLint / SwiftFormat / 任何 linter（已确认未安装、无配置文件）。
#    编译器告警就是唯一的静态检查。按 file:line:col 去重后计数：
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 \
  | grep -oE '/[^ ]+\.swift:[0-9]+:[0-9]+: warning: ' | sort -u | wc -l

# ③ 测试 —— PiboTests，swift-testing 与 XCTest 混用，已挂在 Pibo scheme 上
xcodebuild test -project Pibo.xcodeproj -scheme Pibo \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

关于这三条命令，本仓库实测出来的三个坑（不读会误判）：

1. **增量构建的告警数不可与基线直接比。** 增量构建只对重新编译的文件重新发告警——
   一次什么都没重编的构建会报 0 条，看起来像"告警清零了"。
   要么在计数前先 `xcodebuild -project Pibo.xcodeproj -scheme Pibo clean`（干净构建约 3–4 分钟），
   要么**只比对本模块碰过的文件**的告警条目。基线 30 条的分布见 ledger。
2. **不要用测试条数当判据。** 实测连跑三次，执行到的用例并集是 56 条，但每次控制台
   都会少打 1 行（每次少的还不是同一条：run1 少 `settledAtTracksTheEvidenceLevel`，
   run2 少 `sleepTimelineKeepsBriefIntervalsVisibleWithoutMovingTheirMidpoint`，run3 齐）。
   这是 xcodebuild 文本 reporter 的丢行，不是测试被跳过——三次都 0 失败、都 `** TEST SUCCEEDED **`。
   **判据用退出码 + `** TEST SUCCEEDED **`，不要用条数。**
3. **丢弃改动不能只用 `git checkout .`。** 本轮会拆文件、产生新文件，而 `git checkout .`
   不删未跟踪文件——残留的半个新文件会带进下一个模块。而直接 `git clean -fd` 会误删
   仓库里现有的未跟踪目录（`artifacts/`、`design/`、`docs/narrative-rebuild/`、`output/`、
   `outputs/` 都没被 .gitignore 忽略）。**只能限定范围清理：**

   ```bash
   git checkout . && git clean -fd Pibo "Pibo Watch App" Shared PiboWidgets PiboTests
   ```

一次完整验证（增量构建 + 全部测试）实测约 51 秒，可以每个模块都跑。

判定标准：

- 不得出现基线中没有的失败项
- 静态检查 warning 数不得高于基线
- **不允许删除死代码。** 白名单只放行"静态分析工具报告为不可达的代码"，而本仓库没有这类工具；
  引用计数是人工数的，不算证据。已知的两个孤岛（WCSession 时代、音乐生成时代）在 ledger 里
  已标 SKIP，留给人工决策，agent 不得自行删除。
- 失败最多修 2 次；仍失败则丢弃全部改动（用上面的限定范围清理命令），
  在 ledger 标记 `SKIPPED(verify-failed)`，进入下一个模块
- 绝不通过修改测试来让验证通过

## Commit

一个模块一个 commit：`refactor(<module>): <一句话>`

diff 超过 400 行说明范围划大了——丢弃改动，把该模块在 ledger 里拆成两行再来。

## 对 ledger 的写入权限

只允许修改「状态 / commit / 备注」三列。**禁止增删模块行**，禁止改动基线一节。
