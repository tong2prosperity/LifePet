# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

The product is **Pibo · Life is Vibe**. The project, schemes, bundle identifiers, and user-facing strings have been migrated to Pibo; old LifePulse names should only appear in historical notes or compatibility migration code. This repository is the iOS implementation of a health product that makes daily sleep, walking, and exercise visible through Pibo and practical tools:

> Pibo 是共同经历者，不是宠物或被照顾者。低活动、缺席或拒绝授权不会伤害 Pibo；较少的健康积累只会延后其高耗能行动、使命准备和部分故事节点。

- **iOS** is the primary surface. It owns the pet UI / 活动区 (拍一拍 · 拔毛) / 上滑数据二楼 (历史数据页) / 拍照 / share, and reads health data **passively** from HealthKit on-device. This is where almost all feature work belongs. (图鉴 / 一起 were cut 2026-06-13.)
- **Apple Watch** no longer streams live samples to the phone. The watch the user already wears writes 步数 / HR / HRV / 睡眠 / workouts into HealthKit on its own; iOS reads those samples after the fact. **However, the watch target is no longer purely dead** — it now hosts a standalone **CRC (cardiorespiratory coupling) breathing trainer** (`Pibo Watch App/Features/CRCBreathing/`), the only active watch feature. Its `RootView` shows `CRCTrainingView()` directly and runs in dark mode.

The original plan had the watch streaming live samples over `WCSession`. **That `WCSession` direction is cut** — no watch session, no `WCSession.sendMessage` feeding the phone; iOS treats HealthKit as the sole input. Genuine dead code from that era still lingers and should not be extended: `Shared/Connectivity/`, `Pibo/Services/Connectivity/`, the `Generation` / `Playback` / `Session` iOS features, `SessionStore`, the `LiveCoding` / `MusicGeneration` / `Visualization` services, and the watch's older `Recording` / `Start` features + `WatchConnectivitySender`. The CRC breathing feature is the exception — it is current. Old `Shared/Models/Vital*` wire-format types are also slated for replacement.

### Backend (pibo-server)

The Pibo backend lives in a **separate local git repo at `/Users/trevorlink/Project/hackathon/pibo-server`** (sibling of this iOS repo, NOT a subfolder). One Go binary embeds the auth service + a bo-economy module + an Apple-IAP membership module on one Chi router + one PostgreSQL; it consumes `auth_service` (`/Users/trevorlink/Project/interesting/modules/auth_service/srv`) via a `go.mod` replace. The iOS client layer that talks to it is `Pibo/Services/Backend/`. See the `pibo-server-backend` memory for the full architecture, local-dev setup, and verification notes.

**Apple 内购 / Pibo 会员 (StoreKit 2)**: `Pibo/Services/Membership/MembershipService.swift` (@MainActor @Observable) owns the auto-renewable subscription pair `fun.tiebao.co.Pibo.membership.monthly` / `.yearly` — loads products, purchases, listens to `Transaction.updates`, derives the local entitlement from `currentEntitlements` (StoreKit is the on-device source of truth, works logged-out), and best-effort POSTs every verified transaction's `jwsRepresentation` to `POST /api/v1/membership/verify` when logged in (`MembershipDTOs.swift` in `Services/Backend/`). UI: `Features/Home/Settings/MembershipSheet.swift` (月/年 plans + 恢复购买), entered from the `SettingsSheet`「Pibo 会员」row. Local testing rides `PiboStore.storekit` at the repo root (kept OUTSIDE the synced `Pibo/` group, like `Pibo-Info.plist`), wired into the shared `Pibo` scheme's LaunchAction — purchases work in the simulator via Xcode ⌘R with no App Store Connect setup. Server side: `internal/membership/` in pibo-server verifies the JWS x5c chain against an embedded Apple Root CA G3, but accepts Xcode-test transactions unverified by default (set `APPLE_IAP_REQUIRE_SIGNATURE=true` in production).

### Shared domain engine (pibo-core)

Cross-platform deterministic rules live in the private Rust SDK at `git@github.com:PiboWorld/pibo-core.git`. The Xcode project consumes the `PiboCore` Swift Package product at an **exact SemVer tag**; `Package.resolved` is committed. Safe app-facing mappings live under `Pibo/Services/Core/`. The same Rust source is pinned by HarmonyPibo and linked through its Node-API bridge.

Core owns time/environment mixing, the six-state activity machine, greeting selection, 拍一拍/拔毛 policy, sleep/workout policy, stress scoring/alerts, soundscape profiles, Walk Doodle geometry, mini-game rewards and shared pure game engines. Do not duplicate its thresholds, scoring, state transitions, time windows, or algorithms in Swift. HealthKit and other platform data collection, SwiftUI/SpriteKit, storage, copy/localization, audio/haptics, notifications, networking, analytics, and StoreKit stay native.

For shared-rule work, update and verify `pibo-core` first, publish a new plain SemVer tag (`0.1.1`, no `v`), then update this project's exact package pin and HarmonyPibo's submodule pointer. Never use Core `main` or a local relative path for an App commit. Read the SDK's `AGENTS.md` and `CLAUDE.md` before changing its ABI or capability boundary.

### 角色动画 · 12 状态路径变形 (2026-07-29)

Pibo 的角色表现正在从「两张贴图 + SKAction」换成**矢量 12 状态变形**，源自设计交付包 `pibo_context`(lulu-design)。本轮落了 6 个状态：`default` / `muscle` / `pigu` / `sleep-1` / `sleep-2` / `awake`。**默认关着**，`PiboVectorCharacterFlag` 控制（`-PiboVectorCharacter` / `-PiboLegacyCharacter`），旧的双 sprite 路径原样保留可并排比较。

运行时在 `Pibo/Features/Home/Stage/Character/`：`PiboCharacterData`(解码) / `PiboCharacterGeometry`(路径与插值) / `PiboVectorCharacter`(元素树) / `PiboStateTransition`(节奏) / `PiboIdleAnimator`(待机编排) / `PiboCharacterPlaybook`(剧本) / `PiboCharacterLighting` / `PiboAnimationStateMap`。验证台是 `Features/CharacterLab`（`-PiboCharacterLab`）。

几条不显然但会反复咬人的约束：

- **只有 `body` / `bo` / `boline` 三条路径跨状态变形**，其余一律按状态淡入淡出。这是数据事实不是偷懒 —— `angry`/`dive` 没有脸，五官无法跨状态对应。
- **对应关系在构建期解决。** 生成器 `pibo-assets/tools/prematch/` 把全部状态重采样到同一套拓扑，运行时只剩逐点 lerp，N 个状态的 N² 种切换全部自动可用。**不要在运行时引入 morph 库。**
- **芽（bo+boline）放在一个 `SKEffectNode` 里**，现有的 6 段骨骼弹簧 rig 原样驱动它。warp 作用在渲染网格上、不碰路径数据，所以 rig 与 morph 互不知道对方存在。代价是离屏栅格化会赔掉抗锯齿 —— **必须按 3 倍尺度建路径再把宿主缩回 1/3**（`sproutSupersample`）。
- **时段光照走 CPU 颜色变换**（`PiboCharacterLighting`，数学与 `ForestMaterial.fsh` 逐行一致），不给矢量角色挂 shader：那会强制一次离屏，赔掉的正是抗锯齿。
- **水面倒影靠隐藏的 `reflectionSource` 快照代理**（`ForestReflectionProxy` 的 `treatsSourceAsInvisibleProxy` 模式）。快照只跟几何变化走，不跟待机走。
- **舞台定位按区一份**（地面 / 巢），不是按状态 —— 同区状态的相对位置已经烘在各自的 300×300 画板里。地面沿用 `piboFootPoint`，巢区是 `piboNestAnchor`。
- **每帧顺序**：重建基准路径 → 归位上一帧待机 → 叠加这一帧待机。路径原语因此永远从干净基准出发，不需要自己缓存「静止形状」；SPEC §7 第 6、7 条那两个 Web 引擎的坑在这个结构下不成立。
- **动画态的选择在 `pibo-core`**（`src/animation.rs`），不在 Swift。`dive` / `coolhide` 是同一条压力 z-score 的两端（焦虑 / 放松），所以没有独立的「开心度」输入。Core 已经会返回全部 12 态，App 用 `PiboAnimationStateMap.available` 白名单挡着降级。

进度与决策记录见 `docs/character-animation-port.md`，待验证清单见 `docs/character-animation-verification.md`。

### Shared animation assets (pibo-assets)

The sibling HarmonyOS app is `/Users/trevorlink/Project/hackathon/HarmonyPibo`; the shared animation source repository is `/Users/trevorlink/Project/hackathon/pibo-assets`. Cross-platform animation selection, semantic transitions, speech/bubble triggers, cooldowns, and deterministic content-key selection belong in `pibo-core`. MOV, image sequences, Rive files, audio, and localized strings do not: Core returns stable semantic IDs rather than filenames or absolute paths.

In `pibo-assets`, keep immutable source art and ProRes 4444 alpha MOV masters under `source/`, iOS runtime derivatives under `ios/`, HarmonyOS derivatives under `harmony/`, and cross-platform mappings in `manifest.json`. MOV is only a container, so validate codec, alpha mode, color space, loop seam, startup latency, and hardware decoding per platform. Copy and version selected iOS runtime files inside this App; production builds must not depend on the sibling repository's absolute local path.

### 打点 / Analytics (DataSneaker)

Event tracking rides the **DataSneaker Swift SDK** — an **exact-version remote SwiftPM package**, `https://github.com/all2prosperity/ds-swift-sdk.git` pinned at `0.1.0` (public, HTTPS, so a fresh clone resolves it with no credentials). It was extracted from the DataSneaker monorepo on 2026-07-26: the sources had lived at `sdk/swift/` there, under a `sdk/` .gitignore rule that keeps the react and rust SDKs in their own repos (`ds-react-sdk` / `ds-rust-sdk`) — so the Swift one was tracked nowhere at all, and the old `XCLocalSwiftPackageReference` also forced every checkout into a fixed sibling-directory layout. Bump it the same way as PiboCore: change the SDK repo, tag a plain SemVer release, update the exact pin here, commit `Package.resolved`. The app-side seam is **`Pibo/Services/Analytics/Analytics.swift`**: all event names (`Analytics.Event`, snake_case strings — ClickHouse `event_type`s, treat renames as data migrations) + the endpoint config live there; call sites do `Analytics.track(.pat, screen: "home", ["reaction": .string(...)])` and never import DataSneaker (properties use the in-module `AnalyticsValue` because member-import-visibility would otherwise force the import). The 统一后台打点 URL is the **`PIBO_ANALYTICS_URL`** key in the partial `Pibo-Info.plist` — **currently empty = analytics fully disabled** (the SDK is never configured; every call no-ops); fill it once the DataSneaker server is deployed (`http://localhost:8080` hits a locally-run one in the simulator, but note pibo-server also defaults to 8080). Instrumented paths: app lifecycle (`PiboApp`), onboarding health auth, 拍一拍/拔毛/能量收集/photo/doodle/games/history/settings/theme/reset (`HomeView` + `SettingsSheet` + `WalkDoodleView`), meal 识别 result (`FoodRecognitionService`), IAP purchase/restore (`MembershipService`), login/logout (`AuthService`, which also calls `Analytics.setUser` → device→user identity alias). **Performance rule: only instrument discrete user actions — never per-frame paths (drag/pan/SpriteKit update).** SDK 行为契约 (`ds-swift-sdk`) — the parts that constrain call sites: `track()` is non-blocking and allocation-light (one lock read + an `AsyncStream` yield — no Task spawn, no encoding, no I/O), with all real work on a single `EventPipeline` actor; disk persistence happens only on flush failure and on backgrounding, never per-enqueue; a 4xx drops the batch (validation errors never succeed on retry) while network errors / 5xx re-queue with exponential backoff capped at 5 min; an unconfigured SDK makes every API a silent no-op, which is exactly what an empty `PIBO_ANALYTICS_URL` relies on. The wire format mirrors the Go server's `internal/models/event.go` (snake_case, ms timestamps, `event_type` + `device_id` always present), so a key rename breaks the server contract and has to land on both sides together. Full internals: `CLAUDE.md` in the ds-swift-sdk repo.

## Core Product Logic (implementation lineage + narrative rebuild)

**Narrative/worldview is split from home mechanics.** `docs/narrative/` describes the currently shipped lineage, but all new narrative, character, and copy work follows approved decisions under **`docs/narrative-rebuild/`**. In particular, [`docs/narrative-rebuild/decisions/005-Pibo人物基础.md`](docs/narrative-rebuild/decisions/005-Pibo%E4%BA%BA%E7%89%A9%E5%9F%BA%E7%A1%80.md) supersedes every older tsundere or pet-like personality instruction.

- **`docs/narrative-rebuild/decisions/`** — approved story, character, ethical, progression, and product-narrative rules. These win over conflicting older narrative text.
- **`docs/narrative/`** — shipped lineage to preserve until an explicit migration; do not use its tsundere, coercive pact, or low-health-harms-Pibo framing for new work.

The home-mechanics + copy spec is set by **`product-web-prototype/pibo-home-features-spec.md`** (still current for IA/features/greeting):

- **`0603Pibo世界观重构.md`** — the flower↔energy loop + glitch/sickness/death thresholds are still valid lineage; **its worldview/personality framing is superseded by `docs/narrative/`**.
- **`pibo-home-features-spec.md`** — the concrete home-page feature + copy spec (greeting / activity zone / pull-up Dashboard / camera). **This is the most current home spec; when it disagrees with anything below or in the PRD, it wins.** Note its banner: only the §2 greeting copy is locked; other copy pools are still under review.

The original PRD (`../lifepulse_md/运动健康的拓麻歌子.md`) and the `legacy_docs/` builds (`pibo-mvp-user-journey.md`, `pibo-worldbuilding-bible.md`) are **historical** — keep them for thresholds/lineage, but the worldview, copy, and home IA are superseded by the two docs above.

There is also a sibling `AGENTS.md` (concise repo guidelines) and `README.md` (中文 overview) — keep all three roughly in sync when the architecture shifts.

> **Pivot away from the three-stat model.** The shipped code still computes the old 体力/精力/心情 (`StatKind` vitality/energy/mood) numbers, the `[0,100]` star-light bars (活力星光/静息星光/心绪回声), and the 今日步骤 step cards. **That layer is superseded — do not extend it.** The product no longer surfaces stats or star-light at all; state and the flower are derived **directly from raw HealthKit data + time of day**. Migrate toward the model below; the three-stat / star-light / step-card code (`PetStateStore` stat math, `StatKind`, `LPStatBar` usage, `StepItem`) is prior-pivot scaffolding to be replaced.

### What Pibo is (see `docs/narrative-rebuild/decisions/005-Pibo人物基础.md`)

Pibo is a real alien life form and a young firebringer on its first independent journey. It lost episodic memory and mission context but retained training, language habits, personality, and the procedural instinct to gather `bo` and return home. Its accidental App connection with the user becomes a temporary, revocable cooperation and eventually a relationship built through shared time.

Pibo is serious, curious, direct, procedural, and self-respecting. It likes measurement, classification, naming, and records; dislikes being treated as a pet or child; is poor at verbal comfort but remembers details and acts on them; and does not flee important responsibility. It is an organic person with its own work, errors, concealments, desires, and choices—not a robot or health coach.

**Personality is constant, but judgment and action change.** Pibo does not move through a cold/tsundere/gentle personality arc. It begins by measuring everything for mission utility, later preserves things with no measurable return, and eventually accepts responsibility for rewriting its mission. Garbling and missing words come from memory/translation damage and can decrease; brief, direct, restrained, unsweetened expression remains. Never write stock tsundere denial such as “才不是关心你” or “不是因为担心”. Let care appear through remembered details, altered plans, waiting, and costly choices.

### Energy → flower (no three-stat / no star-light / no nutrient layer)

HealthKit data maps **directly** onto Pibo's state and the head-flower's condition. No 养分 / 经验 / 等级 / 星光 / `[0,100]` stat in between.

| Energy | Source (HealthKit) | Effect on the flower |
|---|---|---|
| 🌙 睡眠能量 | sleep | 精神力 — slept well → flower upright/bright; poorly → droops |
| 🏃 运动能量 | steps / workouts | 活力 — active → vivid color; idle → grey/dim |
| 📸 认知能量 | user photos | unlocks flower 品种 (later) |
| 🎤 声音能量 | calling Pibo's name | flower 亲密度 (later) |

### Home screen IA (home spec §1)

> **超越上滑二楼 — 横向逛场景 (2026-06-27 重构, source of truth for navigation).** The home is no longer a single vertical floor with a 上滑数据二楼. It is now a **horizontally-pannable SpriteKit world** (旅行青蛙-style diorama): the user **drags left/right inside the main scene** to roam between three zones, and **taps a zone to enter its feature**. The 上滑 pull-up (`FloorModel` / `FloorContainer` / `FloorDome`) is **retired and deleted**; feature entries are now in-world.
>
> ```
> 照相馆 (studio)  ←   Pibo 的栖息地 (home, 默认居中)   →   游戏场 (gym)
>   tap → 露珠相机        拍一拍 / 拔毛 / 能量收集            tap → 健康小游戏列表
> ```
> The three zones are `StageZone { studio=0, home=1, gym=2 }` laid out along x in **one large continuous scene** (worldWidth = `zoneCount · width`); a `SKCameraNode` free-pans over it like dragging a map — **no snap, no inertia**. The drag follows the finger 1:1, **hard-clamped** to the map bounds (`clampCamX`, no overscroll), and the camera **stops dead wherever the finger releases** (can rest between zones, split-screen). "Current zone" (for chrome greeting/dots) is judged **continuously** from the camera center (`updateZoneFromCamera`), not a discrete snap event. (A release-inertia glide was built then removed per product direction 2026-06-27 — the camera does not coast.) Touch arbitration (one SpriteKit touch system, no SwiftUI/SpriteView gesture war): a touch on the 毛 (home only) → 拖毛 drag; a horizontal drag dominant over vertical → **world pan** (translation tracked in **view** coords, camera-independent — scene coords move with the camera and would feed back); a tap routes by zone (home body → 拍一拍, studio → `onEnterCamera`, gym → `onEnterGames`). `HomeView` is now full-screen `PiboStageView` + overlay chrome only: greeting (shown on home zone, hidden off-home), the **hand-drawn 「足迹」 icon** (tilted paper card, top-right) → `HistoryScreen` (the 历史数据页 as a `fullScreenCover`, 数据/自定义 tabs intact), the settings gear, a contextual 拔毛 button (home + window-open), and **zone dots**. Health 小游戏 live in `Features/Games/GameListView` (`fullScreenCover`) — every game is 健康相关 (the worldview demands it); the first is **地图涂鸦 (walk doodle)** = 运动能量, plus a 敬请期待 placeholder. The retired pull-up's `floorIsOpen` env value now lives in `Features/History/HistoryEnvironment.swift` (defaults `true` — the history `WaterSurface` / `HistoryStepsCard` animate whenever the cover is on screen). **No game engine runtime** — SpriteKit covers the diorama, camera pan, hit-testing, and (future) 2D minigames; minigames are separate `SKScene`s / SwiftUI screens.

The original (superseded) spec text, kept for lineage:

```
1. 首页打招呼文案区 — 时间问候 + 与Pibo相识的第 N 天 + Pibo 日记  (display only)
2. Pibo 活动区     — Pibo 形象 + 拍一拍 (pat) + 拔毛 (pluck seeds)
3. 上滑数据二楼     — grab-bar 上滑 → 数据二楼 (当日/历史健康可视化)   ← 已被横向逛场景取代
4. 拍照交互        — 露珠相机 → 拍摄 → 预览 + Pibo 弹幕 → 保存
```

The old **能量球 (energy ball) component is removed**. **As of 2026-06-09 the bottom `TabView` is gone** — `RootView` shows `HomeView` directly. **图鉴 (`Catalog`) / 一起 (`Together`) were removed 2026-06-13**. The floating **中/EN language switch button was also removed** (language still follows the stored `appLanguage`). The 历史数据页 `PiboHistoryView` (its own feature at `Features/History`) is unchanged as *content* — only its entry moved from the pull-up drawer to the 足迹 icon's cover.

### Greeting copy (home spec §2 — the only locked copy)

Format `{称呼}，[文案]`. 称呼: Day 1–14 always `人`; Day 15+ the user nickname (fallback `人`). Day line is fixed: **`与Pibo相识的第 N 天`**. The greeting pool maps **by time band only** (7 bands, 4–6 lines each, drawn once per day) — see spec §2.1 for the full pool. No data-state overrides the greeting.

### Pibo activity zone — 6-state machine (home spec §3.1)

Driven by **time rhythm + raw HealthKit data**. Priority: **深眠 > 初醒(·睡够 / ·没睡够) > 活跃 / 烦躁 > 发呆** (被打扰 is optional 🅿️; if built it outranks all).

| State | Trigger |
|---|---|
| **深眠** SLEEPING | 22:00–06:00, or within 5 min after 拔毛 |
| **初醒** WAKING | 06:00–10:00 first app open — 🅿️ ·睡够 if 昨日睡眠 ≥7h / ·没睡够 if <7h |
| **活跃** ACTIVE | 步数 ≥10000 or has an active workout |
| **烦躁** IRRITATED | 步数 <3000 且无运动, or 睡眠 <5h |
| **发呆** IDLE | default — 数据普通, most common state |
| **被打扰** 🅿️ | ≥3 pats within 10 min |

🅿️ = optional if design resources are tight (初醒 need not split; 被打扰 may be skipped). Each state has its own copy pool (spec §3.3): garbled-but-readable syllable fragments with a subject (Pibo / 花) and the odd 啵/呢/啊 — e.g. `...花...睡了...` / `...发芽了啵！`. The background also shifts per state (spec §3.6): 深眠 dark + stars/moon, 初醒 white sky + sunrise/晨雾, 活跃 brighter + faster clouds, 烦躁 grey + wilted flowers.

### 拍一拍 / pat (home spec §3.2)

Two reactions: **不理睬** (back/side to user, no text) or **说一句话** (current-state copy). Hard speech caps: **≤3 lines / 10 min** and **≤9 lines / 24h**. Logic: at the day cap → always ignore; at the 10-min cap → always ignore; else **30% speak / 70% ignore**. Idle 15–30s → 20% chance of a self-mutter (发呆 pool). Pibo is stingy with words, never fully silent.

**Implemented (Figma 76:6758):** `pat()` returns a `PatResponse` (`Pat/PatReaction.swift`) — 不理睬 plays the **扭过头 turn-away pose** (`PiboStageScene.playTurnAway`: themes with a `bodyBackImage` swap the body to the 背面 art, bottom-aligned; themes without one — including the current `.forest` — swivel the root node instead). A spoken `PiboSpeechLine` carries a **mood** that picks the bubble style (`Pat/PiboSpeechBubbleView`, the 对话框 set): 正常 = white round outlined bubble, 生气 = black bubble + Pibo also turns away (烦躁/被打扰 states), 呓语 = soft murmur (深眠 + idle mutters). The 仿漫画 render set (生气 jagged / 弹幕飘过) is a later pass. **故事线 (app 叙事):** a spoken pat has a 25% chance of revealing story content instead of pool copy (`Story/PiboStoryline.swift`, accent-ringed ✦ bubble). **Current code is the old linear model** (authored 第一章·坠落, sequential reveal in `PiboStorylineStore`) and is **to be migrated** to the new **碎片叙事** design in `docs/narrative/` — i.e. the 25% pat should drop a **记忆碎片** or **显影一条约定 (pact clause)** *乱序*, gated by 记忆恢复度 (cumulative energy depth) rather than linear chapters, and the journal surface (`StoryJournalView` stub) becomes a **记忆馆/碎片图鉴**. See [docs/narrative/pibo-storyline-fragments.md](docs/narrative/pibo-storyline-fragments.md) §4 (carrier→mechanic map) + §8 (落地优先级).

### 能量收集 / energy collection (home spec §3.4)

HK background delivery detects an event → 头顶毛动画 (~3s, designer-delivered) → slide-up 能量卡片 auto-positioned to its data block. Backgrounded → mark + replay on next foreground.

| Event | Detection | Card 定位 · 系统提示 |
|---|---|---|
| 运动 | new `HKWorkout` | 运动区块 · 收集到你的运动能量！ |
| 睡眠 | yesterday `sleepAnalysis` filled | 睡眠区块 · 睡眠能量已更新 |
| 拍照 | camera save | 今日记录区块 · 记录已保存 |

**Implemented — the 发芽 flow (Figma《识别到用户的活动》74:6102):** opening the app with a fresh workout (`pendingWorkout`) auto-plays a head close-up — the SpriteKit camera zooms onto the 毛, it 抖动→发力, the 「?」卷芽 swaps to `demon_curl_sprouted` (黑洞 fades), captions sync via `SproutCloseupPhase` ("收集到你的运动能量！" → "Pibo...发芽了啵！"), the camera pulls back and the **能量已收集 pop** (Figma `pop` 76:6725, `Energy/EnergySproutFlow.swift`) closes the loop; dismissing consumes the workout. The first collection persists `growthStage = .sprouted` (pibo头顶发生变化); later collections (or non-sproutable themes / parked on the 二楼) play the small in-place `playEnergyGain` shake + pop. **Animation seam:** the close-up is a placeholder built from current assets — the designer's Lottie plugs in at `SproutAnimationStyle` (`EnergySproutFlow.swift`); rehearse the flow via the settings sheet's DEBUG「模拟运动完成」.

### 拔毛 / pluck seeds (home spec §3.5)

Window **22:00–02:00**, triggered on first app open. Uncollected past 02:00 → **cleared, no next-day makeup**. Grade from sleep + exercise: **好** (睡眠≥7h 且 有运动) / **中** (睡眠≥6h) / **坏** (睡眠<6h or 步数<3000) → drives seed visual + Pibo copy. After plucking, Pibo enters a **5-min 深眠** (won't respond to pats). Seeds drop into the 花田 (历史页). Next-day uncollected state shows a dashed placeholder + `...昨天...带走了...`-style copy.

### 拍照交互 / camera (home spec §4)

露珠相机 → 拍摄 → 扫描线 → 预览 + **Pibo 弹幕** (弹幕 copy stays time-bucketed + a generic pool) → 保存/重拍. Timestamp shown as `YYYY.M.D HH:mm AM/PM` (preview) / `YYYY.M.D HH:mm` (history card). **识图 (added 2026-06-13):** after the shutter, `SubjectClassifier` (Vision `VNClassifyImageRequest`, on-device taxonomy) best-effort names the main subject — 中文 via a built-in mapping, English identifier fallback, nil OK ("识别错了也没有大碍") — shown as a tag on the polaroid preview and stored on the record. After save: the shot is background-removed (抠图 via `SubjectCutout`, Vision foreground-instance mask), **镶嵌白色贴纸边框** (silhouette-hugging white border + hairline grey die-cut rim, `SubjectCutout.stickerize`) and persisted as a `FoodPhoto` (incl. `subjectLabel`) for the day, where it shows up on the 历史数据页's 今日记录 card with the label as a caption; 头顶花轻晃 + 50% chance a 拍照 line. Narrative: the user is Pibo's 地球向导 collecting world samples, not "showing Pibo a photo".

### Low accumulation consequences (rebuild rule)

The old `低能量 → glitch → sickness → death/离去` punishment arc is superseded and must not drive new narrative or copy. Low health accumulation may slow `bo` formation, delay high-energy actions, postpone mission preparation, and move some story nodes later. It never harms Pibo, degrades the relationship, erases memory, removes earned `bo`, or makes absence and permission refusal a moral failure. Pibo may state that an operation lacks sufficient accumulation, but cannot blame, plead, suffer, or threaten departure. See `docs/narrative-rebuild/decisions/027-低健康积累对Pibo的影响.md`.

### Tone

- ❌ 不卖惨、不问责、不用死亡威胁、不写标签式傲娇、不把低活动解释成 Pibo 受苦，也不直接命令“你该运动了”
- ✅ 轻松、愉快、坦然、从容；简短、直接、克制、不甜腻；需要沉重时也保持坦然，通过观察、行动、选择和留白表达关系

### Demo defaults (when health data isn't wired up)

The shipped `PetStateStore.demoMode` still hard-codes the **prior-pivot** values (pet name **BEAN**, day **D07**, 体力 88 / 精力 74 / 心情 82, state `EXCITED`) so the app demos on any device — update these as the 魔丸态 model lands. The `mocks/` folder holds JSONL streams from the earlier watch workflow.

## Project Layout

**Three** Xcode targets / schemes inside a single project (`Pibo.xcodeproj`): `Pibo`, `Pibo Watch App`, `PiboWidgetsExtension`.

- `Pibo/` — iOS app (bundle `fun.tiebao.co.Pibo`, SDK `iphoneos`, deployment iOS 26.2). The pet UI / activity zone / HealthKit observer pipeline / 历史数据页 / share lives here. Active feature folders: `Features/Home` — the 魔丸态 home: a **SpriteKit stage** (`Home/Stage/PiboStageScene` + `PiboStageView`) for the activity zone (themed scene + Pibo + 拍一拍 + 拔毛 + 能量收集 animations), `HomeView` chrome + the grab-bar pull-up shell (`FloorModel` / `FloorContainer`, 打招呼文案 / 主题名 / 与Pibo相识第N天 / 露珠相机 / 发芽 captions + 能量已收集 pop), `Home/Settings` (`SettingsSheet` — 重置 + `debugForestHour` time-of-day + DEBUG flow triggers, behind the header gear), `Home/Pat` (`PatReaction` model + `PiboSpeechBubbleView` mood bubbles), `Home/Energy` (`EnergySproutFlow` — the 发芽 flow phases, animation seam, pop), `Home/Story` (`PiboStoryline` — 拍一拍 story clues + journal stub), `PiboCameraView` (拍照 + 弹幕), the derived `PetStateStore+Mowan` API, and `PetStateStore` (still computes the legacy three stats **only** to feed the widget snapshot — the home no longer shows them). `Features/History` (`PiboHistoryView` + `Components/` — the **历史数据页 = the 二楼 content**, rebuilt 2026-06-13 from Figma `59:342`: 打招呼 header → 日期选择 + 品种(bohair) selector → six modular `HistoryCard`s 活动 / 今日脚步 / 睡眠 / 运动记录 / 体征 / 今日记录, with procedural illustrations (涟漪 / 草坪+萤火虫 / 睡眠云). As of 2026-06-14 the 草坪 is a **data-true plant landscape** (方案C, Figma `walk number` 1496:1416): `HealthDayRecord.hourlySteps` (24h) drives a landscape over the **waking window 06:00–22:00** = 16 hourly columns, each growing a plant whose growth stage maps that hour's step volume on a fixed scale (石头 <150 → 嫩芽 → 松树 → 高株 ≥1500 步/h), today's future hours dimmed. Below it a **time ruler** (`TickRuler` — tall tick every 32pt, short between, `LP.Content.quarternary`) + a `06:00 · {峰值时段}{峰值步}步 · 22:00` label row; the peak callout is the busiest hour (real data only). The four plants **and** the mint `Group 117` hills are the **real exported Figma artwork** — vector **PDF** imagesets (`preserves-vector-representation`) in `Assets.xcassets/plants/` (`walk_rock` / `walk_sprout` / `walk_pine` / `walk_tall` / `walk_hills`), rendered via `Image(...).resizable()` sized off the variant frames (48×{20,36,64,96}); the base also scatters small 石头 pebbles (碎石地面) + `#FFDF51` fireflies. Asset pipeline: `download_assets` SVG → strip the frame/section/selection chrome (keep only `<g id="variant=N">`; replace `var(--…)` fills with literals) → `rsvg-convert -f pdf` → imageset. The 睡眠云 render real `sleepSegments` (x = time in the night, y = 眼动/浅睡/深睡 band, size = duration; capped at 10 clouds with ≥2 kept per stage); 运动记录 and 体征 hide entirely on no-data days. Today is live from `PetStateStore` except hourly/segments which read today's record (refreshed on foreground via `fetchTodayHourlySteps`), past days from SwiftData; hosted by `HomeView`'s `FloorContainer` as a **single rising drawer** (refactored 2026-06-18: a single #E8EEF1 `FloorDome` surface — convex-up domed top, fills down — with this content on top, translating as one unit by `(1−p)·travel`), so the domed leading edge travels continuously from the closed bottom peek to the open ceiling. **One shape + one colour** (the page bg IS the #E8EEF1 surface) → no two-dome handoff, no `TabView`-occluded crown, and crucially no two-tone boundary / floating "lens" mid-drag (the earlier `FloorCap` band+lip surfaced one during a slow close). A single always-visible grab chevron lerps from the closed bottom dome to the open ceiling (content tops pad 88). The bohair 品种 + "SSR" rarity tag are **display-only** — no 品种 model yet). `Features/WalkDoodle` (the **地图涂鸦 / walk-doodle** feature, added 2026-06-17 — Pibo's first 主界面布置的任务: a `WalkDoodleTaskCard` in the home bottom controls ("出门走一幅画 · 圈一块花田") opens `WalkDoodleView` full-screen, mirroring the 露珠相机 cover; `WalkDoodleSession` — an `@Observable` `CLLocationManager` wrapper + a standalone `CLLocationManagerDelegate` shim, the same split as `HealthDataService` — records the live GPS trail (accuracy + min-spacing filtered) and the view draws it as a thick Pibo-green `MapPolyline` stroke over MapKit with live 距离/圈地(面积)/用时; 完成 fits the camera to the stroke, Pibo says a 魔丸 line, 保存 persists. The doodle is 运动能量 — saving nudges the head 毛 (`energyToken`). Pure path math + the `WalkDoodleShape` offline re-render + 魔丸 copy pools + the `WalkDoodleChallenge` scaffold (target shapes for the future 布置涂鸦 完成度 / 比拼面积) live in `WalkDoodleGeometry.swift`; area is shoelace on a local equirectangular projection. Saved doodles persist as `WalkDoodleRecord` → the 二楼's 足迹涂鸦 `HistoryDoodleCard`. **Background recording**: the walk keeps recording GPS while backgrounded / locked (`allowsBackgroundLocationUpdates`, gated on the `location` background mode) and mirrors progress to a **Live Activity** (`WalkDoodleActivityAttributes` — Dynamic Island + Lock Screen「正在画涂鸦」with live 距离/圈地 + a self-counting timer) carrying a 结束 button (`StopWalkDoodleIntent`, a `LiveActivityIntent` that raises an App-Group stop flag the session's 1s ticker polls → `stopRequested` → the view finalizes). Location auth is `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`; the `location` background mode rides a partial `Pibo-Info.plist` merged into the generated plist — see Build Config). `Features/Onboarding` (`HealthAuthView`, 魔丸态). (`Features/Catalog` 图鉴 + 纪念波形, `Features/Together` 一起养, and the orphaned SwiftUI sprite stage `Home/PetStageView` / `Home/PixelPet` + `Features/Pet` were all **removed 2026-06-13** — the new design no longer depends on them; the live home stage is SpriteKit `PiboStageScene`.) Active services: `Services/HealthData` (the observer pipeline + `HealthDataService+History` daily backfill + workout-detail fetch), `Services/Identity`, `Services/History` (**SwiftData** `HealthDayRecord` + `WorkoutRecord` (per-workout detail) + `FoodPhoto` (cut-out 拍照 records) + `WalkDoodleRecord` (足迹涂鸦 GPS strokes) via `HealthHistoryStore`; the older file-based `DailySnapshot` is still present), `Services/Vision` (`SubjectCutout` — Vision 主体抠图 + 贴纸边框 for food photos; `SubjectClassifier` — `VNClassifyImageRequest` 识图 labels), `Services/Localization` (中 / EN via `AppLanguage` + `AppLocalization`; the in-app switch button was removed, language follows the stored value).
- `Pibo Watch App/` — watchOS target. No longer pure dead weight: its `RootView` is the **CRC breathing trainer** (`Features/CRCBreathing/` — `CRCTrainingViewModel`, `CRCCouplingEngine`, `CRCHapticGuide`, `CRCMotionBreathingDetector`, `CRCTrainingView`, `Models/CRCModels`). The watch's older `Features/Recording`, `Features/Start`, and `Services/Connectivity/WatchConnectivitySender` are the dead WCSession-era code.
- `PiboWidgets/` (`PiboWidgetsExtension` target) — Home Screen widget (`PiboWidgets`) + Live Activity (`PiboWidgetsLiveActivity`), wired through `PiboWidgetsBundle`. Widget/Live-Activity payloads come from `Shared/WidgetSupport/` (`PiboWidgetSnapshot`, `PiboFeedActivityAttributes`); `PetStateStore` pushes updates via WidgetKit / ActivityKit.

Shared code sits in `Shared/`:

- `Shared/DesignSystem/` — `LP.*` tokens (Colors, Typography, Spacing, Radius, BorderWidth, Shadow, DashPattern) and components (`LPCard`, `LPStatBar`, `LPButton`, `LPPill`, `LPStickyNote`, `LPSpeechBubble`, `LPStamp`, `LPDashedRule`) plus modifiers (`lpCard`, `lpStampedCard`, `lpDashedBorder`, `lpPaper`). **Always reach for these first** before defining one-off colors/fonts/cards. Tokens are platform-aware (watchOS compresses sizes; `lpShadow` is a no-op on watchOS).
  - **Figma UI Kit token layer** (mirrors Figma node `57:226`, **synced from the now-published variables via `get_variable_defs` on 2026-06-10** — no longer provisional). Two layers: raw **primitives** in `Tokens/LPPalette.swift` (`LP.Neutral.grey0…grey900` — a *cool blue-grey* ramp, base `#171D22`; `LP.Colorful.{red…pink}50…900`, 10 hues × 10 steps) and the **semantic** slots in `Tokens/LPTokens.swift` composed from them — `LP.Fill.*` (bg incl. `bgSurfaceSecondary`, foundation accent/onAccent/error/warning/success/info, mask muted/modal/deep/blackout), `LP.Content.*` (primary…quarternary + accent + invert ramp; ink @ fixed alpha), `LP.Separator.*`, and the new `LP.Border.*` (primary/secondary/tertiary stroke colors — pure black @ low alpha; distinct from `LP.BorderWidth`). Plus the Figma-named scales on the existing enums — `LP.Spacing.{none,xs,s,m,l,xl,xxl,xxl3…xxl6}`, `LP.Radius.{xxs…xxxl,infinite}`, `LP.Shadow.elevation1…4` (each two stacked drop shadows — `Spec` carries `layers`), and the UI type ramp `LP.Typography.{uiH1…uiH5, b1Medium/Regular…b4, c1/c2}` (PingFang SC Medium/Regular px, exact). **The cool-grey neutral is intentional** — don't "fix" it back to the warm paper palette; `LP.Colors` (paper/coral/sage) stays warm for the LP narrative/legacy aesthetic (its in-app consumers 图鉴 / 一起 were removed 2026-06-13, so the warm palette currently has no live screen — keep the tokens, they're cheap). The serif `h1/h2/h3` stay for the LP narrative aesthetic; the `uiH*` ramp is the product UI. Two values are inferred (Figma label exists, no published var, flagged inline): `Fill.bgSurfaceSecondary` and `Border.secondary`.
  - **`Theme/` — home appearance tokens** (`PiboTheme` + the SwiftUI preview renderer `PiboThemeScene` / `PiboHeadItemView`): `PiboTheme` is pure data — a `PiboScene` (sky/ground colors + `terrain` meadow/beach/platform + optional `backgroundImage`) plus head decoration (`headItem` and optional image slots `bodyImage` / `bodyBackImage` 扭头背面 / positioned `headSprite` / `sproutedHeadSprite` 发芽后 / `overheadSprite`, each `PiboThemeSprite` carrying its **393×852 design-frame center**). When image slots are set the SpriteKit stage renders real artwork sprites instead of the procedural egg/face geometry. **As of the 2026-07 rework there is exactly ONE runtime theme: `.forest`** — defined in `Shared/DesignSystem/Theme/PiboTheme.swift` and the sole registration in `PiboThemeCatalog` (`Features/Home/Stage/PiboStageArchitecture.swift`; `defaultTheme` + `resolvedThemeID(_:)` both fall back to it, so any stale persisted id resolves to forest). The earlier **multi-theme picker is retired**: the `.demon` 魔丸 / `.peachSeason` 桃花 / `.aranyaSeaBreeze` 阿那亚 presets and the `SettingsSheet` theme selector are **gone** (the settings gear now hosts a `debugForestHour` time-of-day slider instead). Their old imagesets still sit **orphaned** under `Pibo/Assets.xcassets/themes/` (`demon_*` / `peach_*` / `aranya_*` / `pibo_body*`) — dead art, don't wire them back. The forest is **not** one sprite: it's assembled from layered Figma artwork by **`ForestSceneManifest`** (all of `Features/Home/Stage/Forest/`) — depth-sorted `Layer`s (trees / stones / grass / water) bucketed into far/midground/foreground **lighting groups**, wind-sway **`ForestFoliageNode`** leaves/grass with per-node stiffness + touch interaction, water/reflection/stream **`.fsh` shaders** (`ForestReflectionProjection`), and a **time-of-day lighting** system (`PiboStageEnvironment*` + `forest_light_*` overlays, debuggable via `debugForestHour`). Forest artwork lives in **`Pibo/Resources/Forest/`** (SVG + `@3x` PNG), NOT the `themes/` imageset folder. Pibo itself is `forest_pibo_body` + `forest_pibo_head`; forest sets **no `bodyBackImage`**, so 拍一拍 扭头 takes `playTurnAway`'s procedural root-rotation branch, and its `headSprite` == `sproutedHeadSprite` (发芽 is now expressed via scale/rotation, not a texture swap). **`PiboGrowthStage`** (mystery ⇄ sprouted, persisted as `PetStateStore.growthStage`, resolved through `PiboTheme.resolvedHead(for:)`) and `PetStateStore.selectedThemeID` / `currentTheme` still exist but only ever resolve to forest. Adding a production theme = extend the `PiboThemeCatalog` registration table (theme data + a `PiboThemeRenderer`), no view changes. `PiboStageScene.positionHead` sizes the art head from its **texture's natural points** (not a hardcoded box) so each theme's 毛/花 keeps its own aspect. The Canvas `PiboThemeScene` / `PiboHeadItemView` stay only for widget/preview.
- `Shared/WidgetSupport/` — payload types shared between the iOS app and the widget extension (`PiboWidgetSnapshot`, `PiboFeedActivityAttributes`, and `WalkDoodleActivityAttributes` + its `StopWalkDoodleIntent` `LiveActivityIntent` / `WalkDoodleStopSignal` App-Group flag). **Live**, not dead.
- `Shared/Connectivity/` — *dead*. Holdover from the WatchConnectivity direction; remove in cleanup.
- `Shared/Logging/` — **`LPLog`**, the single logging entry point for all three targets (moved out of `Pibo/Services/` on 2026-07-26 so the watch could stop using `print`). One `os.Logger` per area, named on a dotted scheme (`HealthKit.Sleep`, `Vision.Cutout`, `Backend.Auth`, `Watch.Breathing`) so a Console.app predicate can pull a whole family or one noisy leaf. `subsystem` reads the *running* bundle id, so the app / watch / widget stay separable while sharing one category vocabulary. **Add to the table rather than constructing a `Logger` at a call site** — an ad-hoc logger re-declares the subsystem and drifts off the scheme, which is exactly what makes a log unfilterable. HarmonyPibo mirrors the same category names in its own `PiboLog` (per module, since `entry/` and `wearable/` share no code); keep the two vocabularies in step. Logging is deliberately **not** in `pibo-core` — it's a platform side effect, same class as analytics. When a Core decision needs explaining, encode the reason in its return value and let each platform log it; do not add a logging callback to the C ABI.
- `Shared/Models/` — `VitalSession`, `VitalSnapshot`, `VitalSample`, `VitalKind`. Were the wire-format for the watch link; will likely be replaced by a leaner local-only state model once the HealthKit layer lands.
- `Shared/Health/` — **`HRVAnalysis`**, the one implementation of RR intervals → **RMSSD** (added 2026-07-27). Both the phone's periodic stress reading (`HeartbeatSeriesReader`) and the watch's post-session breathing report (`CRCHeartbeatSeriesReader`) delegate to it, because they compute the *same measurement from the same kind of data* (a complete `HKHeartbeatSeriesSample`) and must not disagree — a breathing session and the next background reading would otherwise report two different HRVs minutes apart. Foundation-only on purpose, so the widget extension doesn't drag in HealthKit; each target keeps its own HealthKit enumeration. Artifact rejection is **local-median + absolute threshold** (Kubios-style, 250 ms), never a fraction of the successive difference — filtering on the quantity being measured can only bias RMSSD downward, and worse the higher the true HRV. Deliberately **not** in `pibo-core`: HarmonyOS has no raw beat-series type (Health Service Kit hands over an already-computed HRV, which it defines as RMSSD), so there is no second platform to share RR→RMSSD with; Core takes `rmssd` as an input and that boundary is correct — same reasoning as logging. Note **RMSSD ≠ Apple's `heartRateVariabilitySDNN`**: SDNN reads systematically higher and the gap widens as HRV rises, so the two numbers are not comparable.

Both targets use `PBXFileSystemSynchronizedRootGroup`, so **any `.swift` / asset file dropped into `Pibo/`, `Pibo Watch App/`, or `Shared/` is picked up automatically** — do not hand-edit `project.pbxproj` to register new source files. Only edit the pbxproj when adding frameworks, capabilities, Info.plist keys, or build-phase steps. **Info.plist keys** are normally set via `INFOPLIST_KEY_*` build settings (generated plist) — but keys with no build-setting form (e.g. `UIBackgroundModes`) go in the partial **`Pibo-Info.plist`** at repo root, wired as the iOS target's `INFOPLIST_FILE` and **merged** with the generated keys (`GENERATE_INFOPLIST_FILE` stays YES). Keep that file at the repo root, **outside** the synchronized `Pibo/` group, or it gets double-bundled (`Multiple commands produce Info.plist`).

## Build Configuration Notes

- Swift 5.0, Xcode 26.2.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set on both targets — new types are `@MainActor`-isolated by default. Mark HealthKit / connectivity / audio work that must run off the main actor explicitly (`nonisolated`, custom actors, or `Task.detached`).
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` is enabled — imports must cover every module whose members you reference (don't rely on transitive imports).
- The LP palette is **light-mode only** — both app entry points pin `.preferredColorScheme(.light)` on the root scene. Don't change that unless the design system grows dark variants.
- `DEVELOPMENT_TEAM = 4626WN8J3B` with automatic code signing.
- Dependencies go through Xcode's SwiftPM integration (no CocoaPods/Carthage). **PiboCore**, **PiboChessUI**, and **DataSneaker** are all exact-version remote packages — there is no local package reference left, so a fresh clone resolves without any sibling-repo layout. Only PiboCore is private, and it is pinned by SSH URL (`git@github.com:`), so a new contributor needs an SSH key on their GitHub account; the other two are public over HTTPS.

## Frameworks This Project Will Need

- **HealthKit** (iOS, read-only): 步数, 运动分钟, kcal, 站立, 睡眠 stages, HRV (SDNN), RHR, 血氧 (SpO2 `oxygenSaturation`), 冥想 events, 已完成 workouts (incl. per-workout detail — type / duration / energy / distance → pace for the 运动记录 card). The pipeline (observer query + background delivery, per-metric read strategy) is **implemented** — see "HealthKit observer architecture (implemented)" below. Read-only auth requested once at first launch; `NSHealthShareUsageDescription` + the HealthKit capability are already configured on the iOS target.
- **WidgetKit + ActivityKit** (iOS): the `PiboWidgetsExtension` target's Home Screen widget + Live Activity. Snapshots/attributes live in `Shared/WidgetSupport/`; `PetStateStore` reloads timelines / updates the activity on state change.
- **SwiftData** (iOS): in-app store of **complete per-day HealthKit history** + derived records — `@Model HealthDayRecord` (one row per day, full metric set incl. `hourlySteps: [Int]` 24-hour buckets + `sleepSegments: [SleepSegmentValue]` per-night stage segments), `@Model WorkoutRecord` (one row per HK workout, keyed by uuid — feeds the 运动记录 card), `@Model FoodPhoto` (cut-out 拍照 records — feeds the 今日记录 card), and `@Model WalkDoodleRecord` (a walk doodle's GPS stroke + distance/area/duration — feeds the 足迹涂鸦 card), all via `HealthHistoryStore`, wired in `PiboApp` with one `ModelContainer` (in-memory fallback). Backs the 历史数据页's past-day data. `HealthDataService+History` backfills days via `HKStatisticsCollectionQuery` daily buckets (steps additionally hour-bucketed; sleep keeps its stage segments, adjacent same-stage merged) and workouts via an `HKSampleQuery`; `fetchTodayHourlySteps` re-runs on foreground so today's grass stays fresh. A `#if DEBUG` seed (`seedSampleAllIfEmpty`, incl. an upgrade pass that fills the new fields on old seeded rows) makes the simulator (no HK data) demonstrable. **Policy: store the complete HK-readable set, display only the subset each screen shows.**
- **CoreMotion + HealthKit workout session** (watch): the CRC breathing trainer reads heart rate via a `WorkoutSessionManager` and breathing via `CRCMotionBreathingDetector`, coupling them in `CRCCouplingEngine` with `CRCHapticGuide` feedback. Self-contained to `Pibo Watch App/Features/CRCBreathing/`.
- **CoreLocation + MapKit** (iOS): the 地图涂鸦 / walk-doodle feature (`Features/WalkDoodle`). `WalkDoodleSession` wraps a `CLLocationManager` (when-in-use auth, `kCLLocationAccuracyBestForNavigation`, `activityType = .fitness`) and the view draws the trail as a SwiftUI `Map` (POI labels on) + `MapPolyline` stroke. Recording continues in the background (`location` background mode + `allowsBackgroundLocationUpdates`; when-in-use auth + the blue status indicator is enough — no Always) and drives a **Live Activity** (`WalkDoodleActivityAttributes`, rendered by `WalkDoodleLiveActivity` in the widget bundle) with a 结束 button. Auth is `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`; the `location` background mode lives in the partial `Pibo-Info.plist` (see Build Config). Test on the simulator via **Features ▸ Location ▸ City Run / Freeway Drive** to feed a moving route.
- **WatchConnectivity**: ❌ not used for the phone↔watch link. WCSession-era code is dead.
- **SpriteKit** (`SpriteView` → `PiboStageScene`): the home **activity-zone stage** — Pibo character, the layered forest scene, idle bob, 拍一拍 bounce, 能量收集 头顶毛 animation, 拔毛 seed drop, sparkles. This is the live home stage (it grows a lot of 2D-game-like animation); SwiftUI owns only the chrome. The single `.forest` `PiboTheme` feeds the scene, assembled as layered Figma artwork by `ForestSceneManifest` (see Theme above); the procedural sky/ground geometry now survives only as a fallback. SpriteKit gotchas: (a) an `SKScene()` starts at size `.zero`, so give the scene a non-zero initial size (and a per-frame build fallback) or `didMove`/`didChangeSize` never build; (b) **SwiftUI's `SpriteView` does NOT honor `scaleMode = .resizeFill`** — the scene stays at its initial size and gets non-uniformly stretched (Pibo looked elongated). Fix: drive `scene.size = geo.size` from a `GeometryReader` in `PiboStageView`. (c) Pull-up perf (hardened 2026-06-18): keep per-frame work off the drag path — the 数据二楼's progress lives in an `@Observable` read **only** by `FloorContainer` (`HomeView.body` never reads it, so the stage/chrome/二楼 closures aren't re-evaluated per frame); the rising drawer + content + chrome ride **opaque** (NO per-frame `.opacity` cross-fade — that offscreen-composited the whole heavy history page every frame; the opaque drawer just covers/reveals as it slides); the settle spring is **`CADisplayLink`-driven** (vsync-aligned, no `Task.sleep` drift / wake-up jitter, while still letting a finger catch it mid-flight); and `SpriteView(isPaused:)` is driven by a single `p > 0.98` threshold (`onChange`), so the stage also pauses when the floor is drag-*held* open, not only on a settle landing. Don't reintroduce `.opacity` fades on the content/chrome during the drag.
- **SwiftUI Canvas / TimelineView**: the `PiboThemeScene` Canvas backdrop for lightweight contexts. (The older pixel-pet sprite stage `PixelPet`/`PetStageView` + the `Features/Pet` sprite machinery were **removed 2026-06-13** along with 图鉴/一起; the live home stage is SpriteKit `PiboStageScene`.)
- **AVFoundation + camera**: the 拍照交互 (露珠相机 → 扫描线 → 预览 + Pibo 弹幕 → 保存). 弹幕 are time-bucketed + a generic pool; the only "AI" is on-device Vision — `SubjectClassifier` 识图 (subject label) + `SubjectCutout` 抠图/贴纸边框. No network models.
- **AVFoundation**: the *纪念曲* memorial waveform lived in 图鉴 详情 (`Catalog/CatalogMemorialWaveform`), which was **removed 2026-06-13** — no waveform surface ships today. **Do not** rebuild a music-generation pipeline regardless; that direction was cut (the `Services/MusicGeneration` + `LiveCoding` code is dead).

## HealthKit observer architecture (implemented)

This pipeline is **built and wired**, not aspirational. The home page runs off `PetStateStore`, fed by `HealthDataService`. Files: `Pibo/Services/HealthData/` (`HealthDataService`, `HealthMetric`, `HealthEvent`) and `Pibo/Features/Home/PetStateStore.swift`. The shape:

1. **Onboarding** — first-launch screen requests HealthKit read auth for: `HKQuantityType` (stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime, heartRate, heartRateVariabilitySDNN, restingHeartRate, oxygenSaturation), `HKCategoryType` (sleepAnalysis, mindfulSession), `HKWorkoutType.workoutType()`. Store granted-set status in `UserDefaults` so we don't re-prompt.
2. **`HealthDataService`** (`@MainActor @Observable`) — owns one `HKHealthStore` and posts typed `HealthEvent`s on an `events` stream. Per metric it registers an `HKObserverQuery` for *notification only* plus `enableBackgroundDelivery(... .immediate)` so iOS wakes the app when the watch syncs — even backgrounded. The **read strategy varies by metric** (don't assume anchored everywhere): aggregates (steps / kcal / stand / exercise / mindful) use `HKStatisticsQuery cumulativeSum` for the day's running total; HRV / RHR / HR use `HKSampleQueryDescriptor limit:1` for the latest value; sleep sums category durations; **only workouts** use an anchored (delta) query so a just-finished run can trigger a 运动 能量收集 card.
3. **`PetStateStore`** (`@Observable @MainActor`) — subscribes to `HealthDataService.events`. The 魔丸态 home reads its **direct-data** derived API in `PetStateStore+Mowan` (greeting pools, the 6-state `PiboActivityState` machine, 拍一拍 `PatResponse` w/ speech caps + moods + 故事线 clues, idle mutter, 22:00–02:00 拔毛 grade, the selection-aware `currentTheme`) off raw metrics + time of day — no stats in between. Stored hooks live on the class: `selectedThemeID` / `growthStage` (+`markSprouted()`) / `story` are UserDefaults-persisted and wiped by `reset()`. The legacy three-stat / `StatKind` / `[StepItem]` math still runs internally but **only feeds the widget snapshot** (`activityState.displayName` is the visible label); the home no longer surfaces it. Day rollover (`checkDayRollover` → reconcile) and widget / Live Activity pushes stay.
4. **Animation feedback on push** — when a sample arrives while foregrounded, `PetStateStore` raises a delta event; `HomeView` plays the 头顶毛动画 (~3s) + slides up the matching 能量卡片. Background-delivered updates apply silently and replay on the next foreground.
5. **Reconciliation on foreground** — `scenePhase == .active` triggers `reconcile()` to catch anything the observer missed (e.g. permission toggled, app force-quit mid-delivery).
6. **Demo mode** — `PetStateStore.demoMode` falls back to the prior-pivot hard-codes (`BEAN / D07 / 88·74·82`, state `EXCITED`) when there's no real HealthKit data, so the app demos on any device — update as the 魔丸态 model lands. Demo still runs the hatch animation (`UserDefaults` key `pibo.hatched.v1`).

Done on top of this layer: the SpriteKit home stage + the direct-data 6-state machine, 拍一拍 (PatResponse moods + 扭头 + 故事线 clues) / 拔毛 / 能量收集 (the 发芽 close-up flow + 能量已收集 pop), the 拍照 flow (识图 label via `SubjectClassifier` + 抠图/贴纸边框 → `FoodPhoto` persistence via `SubjectCutout`), the grab-bar pull-up 历史数据页 (the rebuilt six-card `PiboHistoryView`, history-backed via SwiftData — `HealthDataService+History` backfills `HealthDayRecord` days + `WorkoutRecord` workouts; 血氧/SpO2 now in the auth set + 体征 card), the single `.forest` theme (layered Figma artwork via `ForestSceneManifest` + time-of-day lighting; the old `.demon`/`.peachSeason`/`.aranyaSeaBreeze` multi-theme picker was retired — the settings gear now hosts 重置 + a `debugForestHour` slider), and the persisted growth stage. Still TODO: the 品种(bohair) selector + "SSR" tag are display-only (no 品种 model yet), the 本月活动 heat-map / month view was dropped in the 2026-06-13 rebuild (the Figma month frame `183:1212` can re-add it), the designer Lottie for the 发芽 close-up (`SproutAnimationStyle` seam), per-state Pibo art for the 6-state machine, the 仿漫画 speech render set + 故事线 chapter gating/journal, adding distance/flights to the HK auth set (in the `HealthDayRecord` schema but not yet authorized), and the glitch/sickness/death arc.

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
