# 移植 `pibo-server` 计算模型到 `pibo-core`：Coding Agent Prompt

> 日期：2026-07-30  
> 用途：将下方“可直接复制的 Prompt”完整交给 Coding Agent。  
> 范围：第一阶段只做现有 Go 纯计算模型到 Rust Core 的等价迁移、跨语言边界和验证；不切换 App、后端生产链路，也不重新设计数值。

## 可直接复制的 Prompt

```text
你要完成一项跨仓库的领域模型迁移：把 `pibo-server` 中现有的 `bo` 纯计算模型，等价移植到共享 Rust SDK `pibo-core`，使 `pibo-core` 成为后续 iOS、HarmonyOS 和服务端共同使用的唯一确定性规则源。

这不是重写产品数值，也不是立即替换线上后端。第一阶段目标是：

1. 现有 Go 纯算法在 Rust 中有一份 no_std 兼容、可测试、可通过 C ABI/Swift 使用的等价实现；
2. Go 与 Rust 对同一组 golden fixtures 产生一致结果；
3. Core 的 Rust API、C ABI、Swift wrapper、Swift 边界测试和 Apple XCFramework 同步完成；
4. 不修改 iOS/HarmonyOS 的业务接线，不删除 Go 实现，不发布 tag、不 push，先提交验证结果等待用户批准发布。

你可以读取和修改以下仓库，但必须遵守每个仓库自己的 `AGENTS.md` / `CLAUDE.md`：

- iOS/产品文档仓库：
  `/Users/trevorlink/Project/hackathon/Pibo`
- Go 后端（迁移源）：
  `/Users/trevorlink/Project/hackathon/pibo-server`
- Rust 共享 SDK（主要修改目标）：
  `/Users/trevorlink/Project/hackathon/pibo-core`
- HarmonyOS 消费端（本阶段只读，用于核对 ABI 接法）：
  `/Users/trevorlink/Project/hackathon/HarmonyPibo`

一、开始前必须阅读

1. `/Users/trevorlink/Project/hackathon/Pibo/AGENTS.md`
2. `/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/HANDOFF.md`
3. `/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/031-bo本地优先与Core单一规则源.md`
4. `/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/25-pibo-server现有bo算法复核.md`
5. `/Users/trevorlink/Project/hackathon/pibo-core/AGENTS.md`
6. `/Users/trevorlink/Project/hackathon/pibo-core/CLAUDE.md`
7. `/Users/trevorlink/Project/hackathon/pibo-server/CLAUDE.md`

不要依赖聊天记忆推断规则。上述文档和当前代码是事实来源。

二、先处理 Core checkout 版本，禁止在旧分支上直接开发

当前已知状态：

- 独立 checkout `/Users/trevorlink/Project/hackathon/pibo-core` 当前可能停在旧的 `feat/rain-reaction` / `0.2.0` 附近；
- iOS `Pibo.xcodeproj` 当前 exact pin 是 `0.4.0`；
- iOS `Package.resolved` 和 HarmonyOS `vendor/pibo-core` 当前都指向 `ee191c800923caabbde603d6573133e10e8621d7`，即 tag `0.4.0`；
- 远端 canonical repository 是 `git@github.com:PiboWorld/pibo-core.git`。

执行前：

1. 分别运行 `git status --short`，确认三个仓库的现有改动；任何已有改动都属于用户，不能覆盖、reset、stash 或 checkout 丢弃；
2. 在 `pibo-core` 执行只读核对：当前分支、HEAD、远端、tag；必要时 `git fetch origin --tags`；
3. 必须从包含 `0.4.0` 全部能力的最新 `origin/main` 建立新的工作分支，例如：
   `feat/bo-economy-core`
4. 如果工作树不干净或无法安全切换，停止并报告，不要使用 `git reset --hard`、`git checkout -- .` 或其他破坏命令；
5. 不能从当前旧 `0.2.0` 分支直接开始实现，也不能让 0.3/0.4 已有模块倒退。

三、迁移源：必须逐文件核对

Go 纯计算源文件：

- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/service/curve.go`
  - 分段线性插值、端点 clamp；
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/service/config.go`
  - `EconomyConfig`、`SleepConfig`、默认曲线、权重、阈值、来源系数、行为能量；
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/service/sleep.go`
  - `SleepMetrics`、`ScoreSleep`、质量指标重归一化、architecture bonus；
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/service/scoring.go`
  - `DailyMetrics`、`DailyEnergyBreakdown`、`ScoreDay`、`ApplyEnergy`、`ApplyDailyCap`；
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/service/economy_test.go`
  - 当前行为的可执行测试基线。

必须理解但本阶段不要搬进 Core 的服务端编排/持久化文件：

- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/core/core.go`
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/repo/repo.go`
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/models/models.go`
- `/Users/trevorlink/Project/hackathon/pibo-server/internal/economy/transport/rest/`

设计依据：

- `/Users/trevorlink/Project/hackathon/pibo-server/docs/数值系统-依据.md`
- `/Users/trevorlink/Project/hackathon/pibo-server/docs/数值系统-睡眠评分.md`
- `/Users/trevorlink/Project/hackathon/pibo-server/docs/数值系统-计算示例.md`

四、严格的范围边界

迁入 `pibo-core`：

- Curve/Point 与分段线性插值；
- 默认 Economy/Sleep 配置；
- 睡眠评分；
- 每日健康能量评分；
- 恢复乘数和数据来源系数；
- 每日健康能量封顶；
- 能量池跨阈值铸造结果；
- 通用 daily-cap 纯函数；
- 解释性 breakdown；
- 默认配置版本号/规则版本号。

不要迁入 `pibo-core`：

- GORM、PostgreSQL、HTTP、JSON transport、JWT、匿名账号、手机号登录；
- 数据库存储、`bo_ledger` 持久化、事务和锁；
- HealthKit / Health Service Kit 类型；
- 系统时区读取、系统当前时间、权限、网络、后台任务；
- SwiftData、Preferences、通知、动画、文案；
- 服务端 request idempotency 表和 sample dedup 数据库实现。

Core 只接受调用方已经收集并聚合好的 primitive input，返回 presentation-neutral result。存储和副作用继续由平台/服务端负责。

五、第一阶段必须是“等价迁移”，禁止顺手重设计

必须保持 Go 当前默认模型的数值行为，包括：

- `EnergyPerBo = 75`
- `DailyHealthCap = 110`
- 权重：sleep `0.45`、steps `0.30`、MVPA `0.25`
- 所有 sleep/steps/MVPA/recovery curve 断点；
- source：unknown/missing → `1.0`，watch `1.0`，phone `0.8`，app `0.55`；
- 睡眠质量字段缺失时的重归一化/中性降级；
- `ApplyEnergy` 可一次铸造多枚并保留 remainder；
- daily cap 行为；
- Go 当前 `MVPA=0` 映射到 `0.2` 的行为也必须先作为 parity fixture 保留，不能在迁移时静默修正。

以下已知产品冲突本阶段只记录，不自行改变：

- 新故事已确认站立也能形成 `bo`，但当前 Go 模型没有站立柱；不要在 parity migration 中擅自加权；
- Go 当前不能区分 MVPA 缺失与明确为零；不要自行改变结果；
- photo/game 行为能量与新叙事冲突；不要把它接入新的 Core `bo` 主流程；
- HRV/recovery 是否应负向扣减、source coefficient 是否保留，尚未逐项拍板；先等价迁移；
- 跨午夜睡眠归属和历史补录是调用方的日聚合问题，本阶段不要在纯评分函数里猜日期。

对于 App 行为能量：

- 可以迁移 `ActionEnergy` 的映射作为明确标注的 legacy/compatibility 纯函数，便于 golden parity；
- 但不要在新的默认 `score_day` 或 `apply_health_energy` 中自动加入 photo/game；
- 不要在 iOS/HarmonyOS 中接线；
- 如果为了避免把冲突规则公开成新 API而选择只在 fixture/迁移说明中保留，也可以，但必须说明取舍。

六、建议的 Rust 结构

遵循 `pibo-core` 现有扁平、no_std、小型纯模块风格。推荐：

- 新建 `/Users/trevorlink/Project/hackathon/pibo-core/src/bo_curve.rs`
  - `Point`
  - `Curve<'a>` 或不分配内存的等价结构
  - `eval`
  - `clamp` / `clamp01`
- 新建 `/Users/trevorlink/Project/hackathon/pibo-core/src/bo.rs`
  - 配置、输入、输出、默认曲线静态数组；
  - `score_sleep`
  - `score_day`
  - `apply_energy`
  - `apply_daily_cap`
  - 规则版本常量。
- 修改 `/Users/trevorlink/Project/hackathon/pibo-core/src/lib.rs`
  - 注册 module；
  - re-export Rust API；
  - 增加 C ABI entry points。

可以根据代码清晰度调整模块名，但不要把全部业务塞进 `lib.rs`。

必须保持：

- `#![cfg_attr(not(feature = "std"), no_std)]`
- 生产依赖只使用 `core` 和已有 `libm`；
- 不引入 `Vec`、`HashMap`、字符串分配作为核心计算依赖；
- 静态曲线用 `const`/`static` slice；
- `ApplyEnergy` 返回 `minted_count + new_energy_pool`，不需要返回动态数组；
- 所有输入先检查 NaN/Infinity/负值，FFI 不 panic；
- 有效有限输入必须与 Go 保持误差容忍内一致。

七、建议的 Rust 领域类型

公共 Rust API 至少需要表达：

1. `BoDataSource`
   - `Unknown`
   - `Watch`
   - `Phone`
   - `App`

2. `BoSleepMetrics`
   - `tst_seconds`
   - `in_bed_seconds`
   - `deep_seconds`
   - `rem_seconds`
   - `latency_seconds`
   - `awakenings`
   - 对可选字段必须能表达缺失；Rust API 可使用 `Option`，C ABI 使用 `has_*: int32_t`。

3. `BoDailyMetrics`
   - sleep
   - steps
   - mvpa_minutes
   - optional recovery level
   - source

4. `BoDailyEnergyBreakdown`
   - sleep_score
   - steps_score
   - mvpa_score
   - weighted_base
   - recovery_multiplier
   - source_coefficient
   - raw_energy
   - energy

5. `BoMintResult`
   - new_energy_pool
   - minted_count

6. `BoDailyCapResult`
   - granted
   - new_energy_today

配置类型要支持 Rust 单元测试和未来服务端调用；C ABI 第一版可以只暴露 versioned default configuration 的评分函数，不必通过 FFI 传整组动态曲线。禁止为了远程配置在 C ABI 中暴露 Rust 所有权或不稳定指针。

八、C ABI 设计要求

修改：

- `/Users/trevorlink/Project/hackathon/pibo-core/src/lib.rs`
- `/Users/trevorlink/Project/hackathon/pibo-core/include/pibo_core.h`

建议新增、命名可按现有风格微调：

- `uint32_t pibo_bo_scoring_version(void);`
- `double pibo_bo_energy_per_bo(void);`
- `double pibo_bo_daily_health_cap(void);`
- `PiboCoreBoDailyEnergyBreakdown pibo_bo_score_day(PiboCoreBoDailyMetrics input);`
- `double pibo_bo_score_sleep(PiboCoreBoSleepMetrics input);`
- `PiboCoreBoMintResult pibo_bo_apply_energy(double energy_pool, double granted_energy);`
- `PiboCoreBoDailyCapResult pibo_bo_apply_daily_cap(double cap, double energy_today, double raw_energy);`

C structs：

- 一律 `#[repr(C)]` / C typedef struct；
- bool/Option 使用 `int32_t` flag；
- enum crossing ABI 使用固定 `int32_t` raw value；
- Rust/C 字段顺序完全一致；
- unknown enum 输入回退到安全、确定性的 `Unknown`；
- invalid numeric input 返回安全确定值，不 panic、不产生 NaN 输出；
- 这是 additive ABI，若没有破坏旧签名，`pibo_core_abi_version()` 保持 1；不要只因新增函数就 bump ABI。

九、Swift wrapper 与边界测试

新增：

- `/Users/trevorlink/Project/hackathon/pibo-core/Sources/PiboCore/PiboBoEconomy.swift`
- `/Users/trevorlink/Project/hackathon/pibo-core/Tests/PiboCoreTests/PiboBoEconomyTests.swift`

Swift wrapper 要：

- 提供 Sendable、Equatable 的 Swift value types；
- 使用可选值表达睡眠质量和 recovery 缺失；
- 隐藏 `has_*` FFI 细节；
- 使用 `Int32(clamping:)`；
- 对未知 enum 安全回退；
- 不引入 HealthKit、SwiftData、网络或 UI；
- 命名与现有 `PiboCoreStress` / `PiboCoreWorkout` wrapper 风格一致。

Swift 测试至少验证：

- C ABI 字段映射正确；
- 7.5h duration-only sleep；
- fragmented sleep；
- balanced day；
- source coefficient；
- recovery/cap；
- multi-mint + remainder；
- invalid numeric input 不产生 crash/NaN。

十、Golden fixtures 与 parity

不要只“照着 Go 代码翻译”。建立一组 canonical golden fixtures，至少覆盖 Go 现有测试：

Curve：

- clamp low/high；
- midpoint interpolation；
- plateau；
- exact breakpoint。

Sleep：

- 7.5h、无质量数据 → `1.0`；
- 11h → `< 0.5`，同时记录精确输出；
- 无睡眠 → `0`；
- clean sleep → `1.0`；
- fragmented sleep → 约 `0.47`，使用与 Go 相同 tolerance。

Day：

- 7.5h + 10,000 steps + 45 MVPA，neutral recovery/source → `100`；
- perfect + recovery 4 → raw 超过 cap，energy `110`；
- recovery 0 → `85`；
- watch/phone/app → `100/80/55`；
- 全部输入零时保留当前 Go 行为，明确记录 MVPA 0 baseline 所产生的结果；
- 缺失 recovery → neutral 1.0；
- unknown source → 1.0。

Wallet：

- pool 60 + grant 100 → mint 2，remainder 10；
- pool 10 + grant 30 → mint 0，remainder 40；
- cap 10, already 8, raw 5 → grant 2, today 10；
- cap <= 0 → uncapped。

建议在 `pibo-core/fixtures/bo_economy_v1.json` 保存语言无关 fixture，并：

- Rust 测试读取或等价硬编码同一 fixture；
- 在 `pibo-server` 增加一个只验证 fixture 的 Go parity test，调用原有 Go service；
- 如果给 Rust tests 增加 `serde/serde_json` dev-dependency，必须保证 `cargo build --release --no-default-features` 不引入 std 生产依赖；
- 若不引入解析依赖，则 fixture 文件与 Rust/Go 测试值必须有清晰注释和一一对应关系。

浮点比较采用明确 tolerance（建议 `1e-9` 用于简单插值/池计算，`1e-6` 或 Go 原测试 tolerance 用于综合评分），不要直接对所有 f64 使用 bitwise equality。

十一、服务端修改范围

第一阶段允许在 `pibo-server` 做的修改仅限：

- 增加/整理 golden parity test；
- 修复与本任务直接相关的纯算法测试；
- 增加迁移说明。

不要：

- 删除 `internal/economy/service` Go 实现；
- 让生产 `/sync` 改为调用未发布的本地 Core；
- 修改数据库 schema；
- 修改 HTTP contract；
- 顺便修复匿名登录、拔取、历史回填或客户端上传；
- 顺便改变数值。

已知 `go test ./internal/economy/...` 当前会因 identity logger 类型漂移在集成测试编译阶段失败；`go test ./internal/economy/service/...` 当前通过。不要把这个既有集成测试装配问题误报为本次 Rust 数值迁移造成的回归。可以在结果中记录；除非修复非常局部且不扩大任务，否则不要顺手处理。

十二、文档

在 `pibo-core` 增加一份简洁的模型说明，例如：

- `/Users/trevorlink/Project/hackathon/pibo-core/docs/bo-economy.md`

内容包括：

- Go 源文件路径与迁移日期；
- 规则版本；
- 公式与默认参数；
- missing-value 兼容行为；
- 哪些问题刻意未在 parity phase 修改；
- Core 与平台/服务端责任边界；
- future migration checklist。

不要把用户故事文案写进 SDK。

十三、验证命令

在 `pibo-core` 必须运行：

```bash
cargo fmt --check
cargo test
cargo build --release --no-default-features
./scripts/build-apple.sh
swift test
git diff --check
```

还要核对：

- `include/pibo_core.h` 与 XCFramework 内复制的 header 一致；
- rebuilt `apple/PiboCoreFFI.xcframework` 的 artifact diff 合理；
- 旧 Core 测试全部继续通过；
- ABI version 没有无故变化。

在 `pibo-server` 运行：

```bash
go test ./internal/economy/service/...
```

如果增加了独立 fixture test，再单独运行它。完整 `go test ./internal/economy/...` 可以运行并记录已知 logger 编译阻塞，但不能声称通过。

十四、版本和发布边界

当前消费者使用 `pibo-core 0.4.0`。这是一个新增重要领域能力，预期下一版本可为 `0.5.0`，但本任务不要自行：

- 创建 tag；
- push main/tag；
- 更新 iOS exact package pin；
- 更新 HarmonyOS submodule；
- 提交 App 接线。

先完成实现、测试、XCFramework 重建和变更报告。报告中列出建议版本 `0.5.0`，等待用户明确批准后再执行严格发布顺序：

1. Core commit；
2. push main；
3. tag/push `0.5.0`；
4. iOS 更新 exact pin 和 `Package.resolved`，构建测试；
5. HarmonyOS 更新 `vendor/pibo-core` submodule、NAPI/ArkTS adapter，构建 HAP；
6. 后端另开任务切换到同一 Core 产物。

十五、验收标准

只有同时满足以下条件才算完成：

- 从正确的 0.4.0+ 基线开发，没有丢失已有能力；
- Rust 默认模型与 Go 默认模型 golden parity；
- no_std release build 通过；
- Rust API、C ABI、header、Swift wrapper、Swift tests 同步；
- Apple XCFramework 已重建；
- invalid FFI 输入安全；
- 未把数据库/平台能力搬入 Core；
- 未改变产品数值、未新增站立权重、未修正 zero-vs-missing 行为；
- 未接入 App、未删除 Go、未 tag/push；
- 清楚报告现有测试结果、已知阻塞和下一阶段工作。

十六、最终交付格式

最终回复必须先给结果，再列证据：

1. 修改了哪些仓库和文件；
2. 迁移了哪些函数和默认参数；
3. Golden parity 结果；
4. Rust/C/Swift API 摘要；
5. 每条验证命令的结果；
6. 未解决且刻意未扩大范围的问题；
7. 是否建议发布 `0.5.0`；
8. 明确说明没有执行 tag、push、消费者升级和生产切换。

工作期间保持已有用户改动，使用 `apply_patch` 编辑文本文件，不使用破坏性 Git 命令，不要把无关格式化或重构混入变更。
```

## 使用建议

这份 Prompt 刻意把工作拆成“等价迁移与验证”而不是“一次性改完三端”。这样可以先回答最重要的问题：Rust 与现有 Go 模型是否一致。只有完成这一基线，下一轮才适合讨论站立、行为能量、缺失值、设备系数、恢复乘数，以及后端如何运行同一 Core 产物。
