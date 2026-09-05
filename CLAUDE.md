# CLAUDE.md

产品定义统一见 [docs/PRODUCT.md](docs/PRODUCT.md)，工程目录与规则见 [AGENTS.md](AGENTS.md)，交付状态见 [05](docs/product-strategy-202608/05-P0-Implementation-Status.md)。本文件仅补充独有技术约束，不维护另一套角色定义。

### Backend (pibo-server)

The Pibo backend lives in a **separate local git repo at `/Users/trevorlink/Project/hackathon/pibo-server`** (sibling of this iOS repo, NOT a subfolder). One Go binary embeds the auth service + a bo-economy module + an Apple-IAP membership module on one Chi router + one PostgreSQL; it consumes `auth_service` (`/Users/trevorlink/Project/interesting/modules/auth_service/srv`) via a `go.mod` replace. The iOS client layer that talks to it is `Pibo/Services/Backend/`. See the `pibo-server-backend` memory for the full architecture, local-dev setup, and verification notes.

**Apple 内购 / Pibo 会员 (StoreKit 2)**: `Pibo/Services/Membership/MembershipService.swift` (@MainActor @Observable) owns the auto-renewable subscription pair `fun.tiebao.co.Pibo.membership.monthly` / `.yearly` — loads products, purchases, listens to `Transaction.updates`, derives the local entitlement from `currentEntitlements` (StoreKit is the on-device source of truth, works logged-out), and best-effort POSTs every verified transaction's `jwsRepresentation` to `POST /api/v1/membership/verify` when logged in (`MembershipDTOs.swift` in `Services/Backend/`). UI: `Features/Home/Settings/MembershipSheet.swift` (月/年 plans + 恢复购买), entered from the `SettingsSheet`「Pibo 会员」row. Local testing rides `PiboStore.storekit` at the repo root (kept OUTSIDE the synced `Pibo/` group, like `Pibo-Info.plist`), wired into the shared `Pibo` scheme's LaunchAction — purchases work in the simulator via Xcode ⌘R with no App Store Connect setup. Server side: `internal/membership/` in pibo-server verifies the JWS x5c chain against an embedded Apple Root CA G3, but accepts Xcode-test transactions unverified by default (set `APPLE_IAP_REQUIRE_SIGNATURE=true` in production).

### Shared domain engine (pibo-core)

Cross-platform deterministic rules live in the private Rust SDK at `git@github.com:PiboWorld/pibo-core.git`. The Xcode project consumes the `PiboCore` Swift Package product at an **exact SemVer tag**; `Package.resolved` is committed. Safe app-facing mappings live under `Pibo/Services/Core/`. The same Rust source is pinned by HarmonyPibo and linked through its Node-API bridge.

Core owns time/environment mixing, the six-state activity machine, greeting selection, 拍一拍与直接 bo 投入 policy, sleep/workout policy, stress scoring/alerts, soundscape profiles, Walk Doodle geometry, mini-game rewards and shared pure game engines. Do not duplicate its thresholds, scoring, state transitions, time windows, or algorithms in Swift. HealthKit and other platform data collection, SwiftUI/SpriteKit, storage, copy/localization, audio/haptics, notifications, networking, analytics, and StoreKit stay native.

For shared-rule work, update and verify `pibo-core` first, publish a new plain SemVer tag (`0.1.1`, no `v`), then update this project's exact package pin and HarmonyPibo's submodule pointer. Never use Core `main` or a local relative path for an App commit. Read the SDK's `AGENTS.md` and `CLAUDE.md` before changing its ABI or capability boundary.

### 矢量角色渲染约束（技术沿革）

当前角色表现与已交付动画见工程状态；下列记录保留路径、坐标和渲染约束，不定义当前业务状态集合。

运行时在 `Pibo/Features/Home/Stage/Character/`：`PiboCharacterData`(解码) / `PiboCharacterGeometry`(路径与插值) / `PiboVectorCharacter`(元素树) / `PiboStateTransition`(节奏) / `PiboIdleAnimator`(待机编排) / `PiboCharacterPlaybook`(剧本) / `PiboCharacterLighting` / `PiboAnimationStateMap`。验证台是 `Features/CharacterLab`（`-PiboCharacterLab`）。

几条不显然但会反复咬人的约束：

- **只有 `body` / `bo` / `boline` 三条路径跨状态变形**，其余一律按状态淡入淡出。这是数据事实不是偷懒 —— `angry`/`dive` 没有脸，五官无法跨状态对应。
- **对应关系在构建期解决。** 生成器与正式状态母版归档在 `/Users/trevorlink/Project/PiboWorld/pibo-media`；平台运行时只读取已生成的 `PiboCharacterData.json`，逐点 lerp 完成 N 个状态的 N² 种切换。**不要在运行时引入 morph 库。**
- **芽（bo+boline）放在一个 `SKEffectNode` 里**，现有的 6 段骨骼弹簧 rig 原样驱动它。warp 作用在渲染网格上、不碰路径数据，所以 rig 与 morph 互不知道对方存在。代价是离屏栅格化会赔掉抗锯齿 —— **必须按 3 倍尺度建路径再把宿主缩回 1/3**（`sproutSupersample`）。
- **时段光照走 CPU 颜色变换**（`PiboCharacterLighting`，数学与 `ForestMaterial.fsh` 逐行一致），不给矢量角色挂 shader：那会强制一次离屏，赔掉的正是抗锯齿。
- **水面倒影靠隐藏的 `reflectionSource` 快照代理**（`ForestReflectionProxy` 的 `treatsSourceAsInvisibleProxy` 模式）。快照只跟几何变化走，不跟待机走。
- **舞台定位按区一份**（地面 / 巢），不是按状态 —— 同区状态的相对位置已经烘在各自的 300×300 画板里。地面沿用 `piboFootPoint`，巢区是 `piboNestAnchor`。
- **每帧顺序**：重建基准路径 → 归位上一帧待机 → 叠加这一帧待机。路径原语因此永远从干净基准出发，不需要自己缓存「静止形状」；SPEC §7 第 6、7 条那两个 Web 引擎的坑在这个结构下不成立。
- **芽宿主的 z 必须和元素下标同一把尺子。** `bodyLayer` 里每个元素都带
  `zPosition = 元素下标`，而整个芽是一个 `SKEffectNode`、只有一个 z。给它写 0 或 1
  的后果不是"芽不见了"——而是**只有埋在头里的那截草根被身体盖掉**，草看起来像浮在
  头顶上方而不是长在头里（0801 走查截到的就是这一处）。在前还是在后按每个状态自己的
  元素顺序判（`syncSproutLayer`）：设计包里 11 个状态 bo/boline 排在 body 之后，只有
  `sleep-2` 反过来。
- **动画态的选择在 `pibo-core`**（`src/animation.rs`），不在 Swift。`dive` / `coolhide` 是同一条压力 z-score 的两端（焦虑 / 放松），所以没有独立的「开心度」输入。Core 已经会返回全部 12 态，App 用 `PiboAnimationStateMap.available` 白名单挡着降级。

进度与决策记录见 `docs/character-animation-port.md`，待验证清单见 `docs/character-animation-verification.md`。

### Shared production media (pibo-media)

The sibling HarmonyOS app is `/Users/trevorlink/Project/hackathon/HarmonyPibo`; the production media source repository is `/Users/trevorlink/Project/PiboWorld/pibo-media`. Cross-platform animation selection, semantic transitions, speech/bubble triggers, cooldowns, and deterministic content-key selection belong in `pibo-core`. MOV, image sequences, Rive files, audio, and localized strings do not: Core returns stable semantic IDs rather than filenames or absolute paths.

In `pibo-media`, keep approved source art and ProRes 4444 alpha MOV masters under `source/`, iOS runtime derivatives under `platform/ios/`, HarmonyOS derivatives under `platform/harmony/`, and generated hashes/mappings in `manifest.json`. MOV is only a container, so validate codec, alpha mode, color space, loop seam, startup latency, and hardware decoding per platform. Copy and version selected iOS runtime files inside this App; production builds must not depend on the media repository's absolute local path.

### 打点 / Analytics (DataSneaker)

Event tracking rides the **DataSneaker Swift SDK** — an **exact-version remote SwiftPM package**, `https://github.com/all2prosperity/ds-swift-sdk.git` pinned at `0.1.0` (public, HTTPS, so a fresh clone resolves it with no credentials). It was extracted from the DataSneaker monorepo on 2026-07-26: the sources had lived at `sdk/swift/` there, under a `sdk/` .gitignore rule that keeps the react and rust SDKs in their own repos (`ds-react-sdk` / `ds-rust-sdk`) — so the Swift one was tracked nowhere at all, and the old `XCLocalSwiftPackageReference` also forced every checkout into a fixed sibling-directory layout. Bump it the same way as PiboCore: change the SDK repo, tag a plain SemVer release, update the exact pin here, commit `Package.resolved`. The app-side seam is **`Pibo/Services/Analytics/Analytics.swift`**: all event names (`Analytics.Event`, snake_case strings — ClickHouse `event_type`s, treat renames as data migrations) + the endpoint config live there; call sites do `Analytics.track(.pat, screen: "home", ["reaction": .string(...)])` and never import DataSneaker (properties use the in-module `AnalyticsValue` because member-import-visibility would otherwise force the import). The 统一后台打点 URL is the **`PIBO_ANALYTICS_URL`** key in the partial `Pibo-Info.plist` — **currently empty = analytics fully disabled** (the SDK is never configured; every call no-ops); fill it once the DataSneaker server is deployed (`http://localhost:8080` hits a locally-run one in the simulator, but note pibo-server also defaults to 8080). Instrumented paths: app lifecycle (`PiboApp`), onboarding health auth, 拍一拍/拔毛/能量收集/photo/doodle/games/history/settings/theme/reset (`HomeView` + `SettingsSheet` + `WalkDoodleView`), meal 识别 result (`FoodRecognitionService`), IAP purchase/restore (`MembershipService`), login/logout (`AuthService`, which also calls `Analytics.setUser` → device→user identity alias). **Performance rule: only instrument discrete user actions — never per-frame paths (drag/pan/SpriteKit update).** SDK 行为契约 (`ds-swift-sdk`) — the parts that constrain call sites: `track()` is non-blocking and allocation-light (one lock read + an `AsyncStream` yield — no Task spawn, no encoding, no I/O), with all real work on a single `EventPipeline` actor; disk persistence happens only on flush failure and on backgrounding, never per-enqueue; a 4xx drops the batch (validation errors never succeed on retry) while network errors / 5xx re-queue with exponential backoff capped at 5 min; an unconfigured SDK makes every API a silent no-op, which is exactly what an empty `PIBO_ANALYTICS_URL` relies on. The wire format mirrors the Go server's `internal/models/event.go` (snake_case, ms timestamps, `event_type` + `device_id` always present), so a key rename breaks the server contract and has to land on both sides together. Full internals: `CLAUDE.md` in the ds-swift-sdk repo.

## Build Configuration Notes

- Swift 5.0, Xcode 26.2.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set on both targets — new types are `@MainActor`-isolated by default. Mark HealthKit / connectivity / audio work that must run off the main actor explicitly (`nonisolated`, custom actors, or `Task.detached`).
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` is enabled — imports must cover every module whose members you reference (don't rely on transitive imports).
- The LP palette is **light-mode only** — both app entry points pin `.preferredColorScheme(.light)` on the root scene. Don't change that unless the design system grows dark variants.
- `DEVELOPMENT_TEAM = 4626WN8J3B` with automatic code signing.
- Dependencies go through Xcode's SwiftPM integration (no CocoaPods/Carthage). **PiboCore**, **PiboChessUI**, and **DataSneaker** are all exact-version remote packages — there is no local package reference left, so a fresh clone resolves without any sibling-repo layout. Only PiboCore is private, and it is pinned by SSH URL (`git@github.com:`), so a new contributor needs an SSH key on their GitHub account; the other two are public over HTTPS.

## Frameworks This Project Will Need

现有框架、目录与职责见 [AGENTS.md](AGENTS.md)。HealthKit / SwiftData / SwiftUI / SpriteKit 的平台职责不变；旧数据二楼、拔取和 WatchConnectivity 流程不再作为实现依据。

## HealthKit observer architecture (implemented)

This pipeline is **built and wired**, not aspirational. The home page runs off `PetStateStore`, fed by `HealthDataService`. Files: `Pibo/Services/HealthData/` (`HealthDataService`, `HealthMetric`, `HealthEvent`) and `Pibo/Features/Home/PetStateStore.swift`. The shape:

1. **Onboarding** — first-launch screen requests HealthKit read auth for: `HKQuantityType` (stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime, heartRate, heartRateVariabilitySDNN, restingHeartRate, oxygenSaturation), `HKCategoryType` (sleepAnalysis, mindfulSession), `HKWorkoutType.workoutType()`. Persist the request lifecycle separately from observed data; HealthKit read authorization does not reveal a reliable per-type granted set.
2. **`HealthDataService`** (`@MainActor @Observable`) — owns one `HKHealthStore` and posts typed `HealthEvent`s on an `events` stream. Per metric it registers an `HKObserverQuery` for *notification only* plus `enableBackgroundDelivery(... .immediate)` so iOS wakes the app when the watch syncs — even backgrounded. The **read strategy varies by metric** (don't assume anchored everywhere): aggregates (steps / kcal / stand / exercise / mindful) use `HKStatisticsQuery cumulativeSum` for the day's running total; HRV / RHR / HR use `HKSampleQueryDescriptor limit:1` for the latest value; sleep sums category durations; **only workouts** use an anchored (delta) query so a just-finished run can trigger a 运动 能量收集 card.
3. **`PetStateStore`** receives health facts and maps the published Core six-state result through thin adapters. Widget and Live Activity snapshots use current semantic state; do not restore the old stat layer or speech caps.
4. **Animation feedback** follows Core semantic intent and current presentation contracts. Current authored clips and food projection progress are recorded in 05; no legacy sprout close-up or energy-card flow is implied.
5. **Reconciliation on foreground** — `scenePhase == .active` triggers `reconcile()` to catch anything the observer missed (e.g. permission toggled, app force-quit mid-delivery).
6. **Demo provenance** must remain separate from real health facts. Synthetic records must not mint bo or advance real-data story events; dataUnknown is the honest fallback for missing real data.

Current features, incomplete work and verification limits are maintained only in 05, not in this technical pipeline description.

## Common Commands

Build / run is normally Xcode (⌘R with the `Pibo` scheme for the phone+watch pair). Command-line equivalents:

```bash
# Build the iOS app (also builds the embedded watch app).
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build

# Resolve the exact remote SDK pins on a clean checkout.
xcodebuild -resolvePackageDependencies -project Pibo.xcodeproj -scheme Pibo

# Build only the watch app.
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build

# Build only the widget extension.
xcodebuild -project Pibo.xcodeproj -scheme PiboWidgetsExtension -configuration Debug build

# List schemes / targets.
xcodebuild -project Pibo.xcodeproj -list

# Clean.
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean

# Unit tests (`PiboTests`, swift-testing; already wired into the `Pibo` scheme).
xcodebuild test -project Pibo.xcodeproj -scheme Pibo \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**HealthKit's ambiguous asleep value.** `HKCategoryValueSleepAnalysis.asleep` and
`.asleepUnspecified` are the same value (rawValue 1; iOS 16 only renamed it), so
`PiboCoreSleepAdapter.coreSampleKind` cannot tell "modern API, stage unknown"
from a pre-iOS-16 block that envelopes the real stages. It resolves that
ambiguity to Core's `legacyAsleep`, and **both halves of that choice are
load-bearing**: it keeps `hasDetailedStages` false for a phone-only sleep
schedule (otherwise the card renders a fake 100%-浅睡 breakdown), and it makes
`resolveSample` drop the span on a source that *does* carry stages — otherwise
the enveloping block clips every interior stage away in
`MorningSleepSessionBuilder.normalize` (a segment fully contained in the previous
one is discarded). Core's `unspecified` kind stays reachable for platforms whose
API separates the two. `PiboTests/PiboCoreSleepIntegrationTests.swift` pins both
halves, including a characterization test for the clipping hazard.

## Morning sleep summary (notification + card)

`HealthDataService.postSleep` → `MorningSleepCoordinator.receive` → local
notification / `pendingPresentation` → `HomeView.presentMorningSleepIfPossible` →
`MorningSleepCard.onAppear → markPresented`. Reworked 2026-07-26; the rules that
decide **when** a summary may reach the user live in `pibo-core` (`src/sleep.rs`,
surfaced through `PiboCoreSleepAdapter`) — do not re-derive them in Swift:

- **Readiness** (`morning_sleep_readiness`) — duration decides eligibility
  (in-bed envelope, else ≥2h); *quiet time* decides finality (30 min, or 10 min
  when the platform marked a terminal awake stage). A wearable writes a night in
  batches, so a freshly synced batch is never proof the night is over. The app
  being open shortens the terminal-awake wait to zero — the user holding the
  phone is direct proof they are awake — but that shortcut does **not** count as
  "settled" (see below).
- **Delivery** (`morning_sleep_delivery`) — a finished night landing in the local
  quiet band `[00:00, 05:00)` is deferred to 07:00 instead of pushed. The
  deferred request stays *pending*, so a more complete summary simply replaces
  it; that is what makes a partial overnight sync self-heal by morning. The same
  decision gates the in-app card, so the two can never disagree.
- **Upgrade** (`morning_sleep_supersedes`) — a card shown while the watch was
  still syncing (final-by-interaction, i.e. `isSettled == false`) may be replaced
  exactly once by a settled summary that adds ≥30 min. A settled night closes the
  wake-day for good.
- **Catch-up** (`morning_sleep_within_catchup_window`) — a summary stays
  reachable for 36h from the start of its wake-day, so a notification tapped
  after midnight still resolves. The coordinator keeps the last three nights in
  `pibo.sleep.morning.summaries.v2`; `MorningSleepCard` switches to a dated title
  when `isCatchUp`.

Only a *settled* night feeds the 28-day baseline behind the card's
「比平时多睡/少睡」 line. `presentMorningSleepIfPossible` asks the coordinator for a
freshly validated `consumablePresentation()` rather than trusting the queued one,
and every cover/sheet resumes queued flows from `onDismiss` — reacting to the
presentation binding instead would present while the previous modal is still
animating out, which SwiftUI silently drops.

Rehearse without moving the device clock: the DEV settings row 「睡眠投递时刻」
(`MorningSleepCoordinator.debugLocalHourOverride`) plus 「模拟睡眠通知」, or launch
with `-PiboShowMorningSleep`.
