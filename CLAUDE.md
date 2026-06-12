# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

The product is **Pibo · Life is Vibe**. The project, schemes, bundle identifiers, and user-facing strings have been migrated to Pibo; old LifePulse names should only appear in historical notes or compatibility migration code. It is an **iOS-only hackathon project** that turns the wearer's daily health data into a tamagotchi:

> 你不是喂宠物，你的身体就是宠物的食物。养得好它陪你更久，养不好它早早走掉。

- **iOS** is the primary surface. It owns the pet UI / 活动区 (拍一拍 · 拔毛) / 上滑数据二楼 (历史数据页) / 拍照 / share, and reads health data **passively** from HealthKit on-device. This is where almost all feature work belongs. (图鉴 / 一起 were cut 2026-06-13.)
- **Apple Watch** no longer streams live samples to the phone. The watch the user already wears writes 步数 / HR / HRV / 睡眠 / workouts into HealthKit on its own; iOS reads those samples after the fact. **However, the watch target is no longer purely dead** — it now hosts a standalone **CRC (cardiorespiratory coupling) breathing trainer** (`Pibo Watch App/Features/CRCBreathing/`), the only active watch feature. Its `RootView` shows `CRCTrainingView()` directly and runs in dark mode.

The original plan had the watch streaming live samples over `WCSession`. **That `WCSession` direction is cut** — no watch session, no `WCSession.sendMessage` feeding the phone; iOS treats HealthKit as the sole input. Genuine dead code from that era still lingers and should not be extended: `Shared/Connectivity/`, `Pibo/Services/Connectivity/`, the `Generation` / `Playback` / `Session` iOS features, `SessionStore`, the `LiveCoding` / `MusicGeneration` / `Visualization` services, and the watch's older `Recording` / `Start` features + `WatchConnectivitySender`. The CRC breathing feature is the exception — it is current. Old `Shared/Models/Vital*` wire-format types are also slated for replacement.

## Core Product Logic (0603 rework + home spec — source of truth)

The product direction is set by two docs under `product-web-prototype/`, both newer than the original PRD:

- **`0603Pibo世界观重构.md`** — the world-view: who Pibo is (异世界种花小精灵), the flower↔energy loop, the three personality stages, the glitch/sickness/death arc.
- **`pibo-home-features-spec.md`** — the concrete home-page feature + copy spec (greeting / activity zone / pull-up Dashboard / camera). **This is the most current home spec; when it disagrees with anything below or in the PRD, it wins.** Note its banner: only the §2 greeting copy is locked; other copy pools are still under review.

The original PRD (`../lifepulse_md/运动健康的拓麻歌子.md`) and the `legacy_docs/` builds (`pibo-mvp-user-journey.md`, `pibo-worldbuilding-bible.md`) are **historical** — keep them for thresholds/lineage, but the worldview, copy, and home IA are superseded by the two docs above.

There is also a sibling `AGENTS.md` (concise repo guidelines) and `README.md` (中文 overview) — keep all three roughly in sync when the architecture shifts.

> **Pivot away from the three-stat model.** The shipped code still computes the old 体力/精力/心情 (`StatKind` vitality/energy/mood) numbers, the `[0,100]` star-light bars (活力星光/静息星光/心绪回声), and the 今日步骤 step cards. **That layer is superseded — do not extend it.** The product no longer surfaces stats or star-light at all; state and the flower are derived **directly from raw HealthKit data + time of day**. Migrate toward the model below; the three-stat / star-light / step-card code (`PetStateStore` stat math, `StatKind`, `LPStatBar` usage, `StepItem`) is prior-pivot scaffolding to be replaced.

### What Pibo is (MVP = 魔丸态)

Pibo is a tsundere flower-growing sprite that fell to Earth. It doesn't like humans, knows nothing about Earth, and only cares about the flower on its head — which needs human energy to bloom. So it leeches off you but never admits it.

> 你不是喂宠物，是 Pibo 为了让头上的花开，不得不从你身上吸能量。养得好它陪你更久，养不好它发疯、生病、离去。

MVP ships the **魔丸 (demon-pill) stage** (Day 1–14): can't understand human speech, talks in garbled-but-readable syllable fragments, mostly ignores you, only cares about the flower. (中期·傲娇 Day 14–60 / 后期·伙伴 Day 60+ soften the personality — out of MVP scope.)

### Energy → flower (no three-stat / no star-light / no nutrient layer)

HealthKit data maps **directly** onto Pibo's state and the head-flower's condition. No 养分 / 经验 / 等级 / 星光 / `[0,100]` stat in between.

| Energy | Source (HealthKit) | Effect on the flower |
|---|---|---|
| 🌙 睡眠能量 | sleep | 精神力 — slept well → flower upright/bright; poorly → droops |
| 🏃 运动能量 | steps / workouts | 活力 — active → vivid color; idle → grey/dim |
| 📸 认知能量 | user photos | unlocks flower 品种 (later) |
| 🎤 声音能量 | calling Pibo's name | flower 亲密度 (later) |

### Home screen IA (home spec §1)

```
1. 首页打招呼文案区 — 时间问候 + 与Pibo相识的第 N 天 + Pibo 日记  (display only)
2. Pibo 活动区     — Pibo 形象 + 拍一拍 (pat) + 拔毛 (pluck seeds)
3. 上滑数据二楼     — grab-bar 上滑 → 数据二楼 (当日/历史健康可视化)
4. 拍照交互        — 露珠相机 → 拍摄 → 预览 + Pibo 弹幕 → 保存
```

The old **能量球 (energy ball) component is removed** — daily/historical health viz now lives behind the **pull-up 数据二楼**. **As of 2026-06-09 the bottom `TabView` is gone** — `RootView` shows `HomeView` directly. The home is a **single floor**; the bottom **grab bar** pulls up the 数据二楼 via an inline coordinated animation (Pibo slides off the top, the 二楼 rises from the bottom) — **not** a `.sheet`. The 二楼's *content* is the **历史数据页 `PiboHistoryView`** — its own feature at `Features/History` (the pull-up animation is home chrome; the page is the content). The pull-up is implemented with an `@Observable FloorModel` (progress) read only by a thin `FloorContainer` shell, so the drag re-renders just the shell, not the stage/chrome/二楼 (see the perf note in the SpriteKit framework bullet). **图鉴 (`Catalog`) / 一起 (`Together`) were removed 2026-06-13** — the new design no longer depends on them. The floating **中/EN language switch button was also removed** (language still follows the stored `appLanguage`).

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

**Implemented (Figma 76:6758):** `pat()` returns a `PatResponse` (`Pat/PatReaction.swift`) — 不理睬 plays the **扭过头 turn-away pose** (`PiboStageScene.playTurnAway`: art themes swap the body to `pibo_body_back`, bottom-aligned; procedural themes swivel). A spoken `PiboSpeechLine` carries a **mood** that picks the bubble style (`Pat/PiboSpeechBubbleView`, the 对话框 set): 正常 = white round outlined bubble, 生气 = black bubble + Pibo also turns away (烦躁/被打扰 states), 呓语 = soft murmur (深眠 + idle mutters). The 仿漫画 render set (生气 jagged / 弹幕飘过) is a later pass. **故事线 (app 叙事):** a spoken pat has a 25% chance of revealing the next clue of the current story chapter instead of pool copy (`Story/PiboStoryline.swift` — authored 第一章·坠落, sequential reveal persisted in `PiboStorylineStore`, accent-ringed ✦ bubble). Chapter gating + the journal surface (`StoryJournalView` stub, not routed) are TODO — most narrative is still 未定.

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

露珠相机 → 拍摄 → 扫描线 → 预览 + **Pibo 弹幕** (no AI recognition yet — time-bucketed copy + a generic pool) → 保存/重拍. Timestamp shown as `YYYY.M.D HH:mm AM/PM` (preview) / `YYYY.M.D HH:mm` (history card). After save: the shot is background-removed (抠图 via `SubjectCutout`, Vision foreground-instance mask) and persisted as a `FoodPhoto` for the day, where it shows up on the 历史数据页's 今日记录 card; 头顶花轻晃 + 50% chance a 拍照 line. Narrative: the user is Pibo's 地球向导 collecting world samples, not "showing Pibo a photo".

### Glitch / sickness / death (0603 §5 — the decline arc)

`正常 → 连续能量不足 → 发疯/glitch → 长期不管 → 生病 → 死亡/离去`. 发疯态 is **glitch 故障艺术** (UI 错位/抖动/像素剥落/Pibo 扭曲), recovered by completing **one** health task (运动 10 min / 睡够 / 拍一张指定照片). Thresholds inherit the original PRD (~3 days low energy → glitch, ~7 → sick, ~30 → death/离去; revival = N days on-target + a 找回仪式, no payment). Lifespan stays **uncapped** and the UI shows only 与Pibo相识的第 N 天 — never a denominator.

### Tone

- ❌ 不卖惨, 不问责, 不悲情, 不直接说「你该运动了」("分身替你死" / "你没好好活着")
- ✅ 傲娇、把健康提醒包进「花的状态」("花今天没精神…不是因为我在乎"), playful, expectant ("已经陪过 4 只" / "又被你熬死了")

### Demo defaults (when health data isn't wired up)

The shipped `PetStateStore.demoMode` still hard-codes the **prior-pivot** values (pet name **BEAN**, day **D07**, 体力 88 / 精力 74 / 心情 82, state `EXCITED`) so the app demos on any device — update these as the 魔丸态 model lands. The `mocks/` folder holds JSONL streams from the earlier watch workflow.

## Project Layout

**Three** Xcode targets / schemes inside a single project (`Pibo.xcodeproj`): `Pibo`, `Pibo Watch App`, `PiboWidgetsExtension`.

- `Pibo/` — iOS app (bundle `fun.tiebao.co.Pibo`, SDK `iphoneos`, deployment iOS 26.2). The pet UI / activity zone / HealthKit observer pipeline / 历史数据页 / share lives here. Active feature folders: `Features/Home` — the 魔丸态 home: a **SpriteKit stage** (`Home/Stage/PiboStageScene` + `PiboStageView`) for the activity zone (themed scene + Pibo + 拍一拍 + 拔毛 + 能量收集 animations), `HomeView` chrome + the grab-bar pull-up shell (`FloorModel` / `FloorContainer`, 打招呼文案 / 主题名 / 与Pibo相识第N天 / 露珠相机 / 发芽 captions + 能量已收集 pop), `Home/Settings` (`SettingsSheet` — theme picker + 重置 + DEBUG flow triggers, behind the header gear), `Home/Pat` (`PatReaction` model + `PiboSpeechBubbleView` mood bubbles), `Home/Energy` (`EnergySproutFlow` — the 发芽 flow phases, animation seam, pop), `Home/Story` (`PiboStoryline` — 拍一拍 story clues + journal stub), `PiboCameraView` (拍照 + 弹幕), the derived `PetStateStore+Mowan` API, and `PetStateStore` (still computes the legacy three stats **only** to feed the widget snapshot — the home no longer shows them). `Features/History` (`PiboHistoryView` + `Components/` — the **历史数据页 = the 二楼 content**, rebuilt 2026-06-13 from Figma `59:342`: 打招呼 header → 日期选择 + 品种(bohair) selector → six modular `HistoryCard`s 活动 / 今日脚步 / 睡眠 / 运动记录 / 体征 / 今日记录, with procedural illustrations (涟漪 / 草坪+萤火虫 / 睡眠云). Today is live from `PetStateStore`, past days from SwiftData; hosted by `HomeView`'s `FloorContainer` drawer, which still owns the `FloorDome` defined in `PiboHistoryView.swift`. The bohair 品种 + "SSR" rarity tag are **display-only** — no 品种 model yet). `Features/Onboarding` (`HealthAuthView`, 魔丸态). (`Features/Catalog` 图鉴 + 纪念波形, `Features/Together` 一起养, and the orphaned SwiftUI sprite stage `Home/PetStageView` / `Home/PixelPet` + `Features/Pet` were all **removed 2026-06-13** — the new design no longer depends on them; the live home stage is SpriteKit `PiboStageScene`.) Active services: `Services/HealthData` (the observer pipeline + `HealthDataService+History` daily backfill + workout-detail fetch), `Services/Identity`, `Services/History` (**SwiftData** `HealthDayRecord` + `WorkoutRecord` (per-workout detail) + `FoodPhoto` (cut-out 拍照 records) via `HealthHistoryStore`; the older file-based `DailySnapshot` is still present), `Services/Vision` (`SubjectCutout` — Vision 主体抠图 for food photos), `Services/Logging`, `Services/Localization` (中 / EN via `AppLanguage` + `AppLocalization`; the in-app switch button was removed, language follows the stored value).
- `Pibo Watch App/` — watchOS target. No longer pure dead weight: its `RootView` is the **CRC breathing trainer** (`Features/CRCBreathing/` — `CRCTrainingViewModel`, `CRCCouplingEngine`, `CRCHapticGuide`, `CRCMotionBreathingDetector`, `CRCTrainingView`, `Models/CRCModels`). The watch's older `Features/Recording`, `Features/Start`, and `Services/Connectivity/WatchConnectivitySender` are the dead WCSession-era code.
- `PiboWidgets/` (`PiboWidgetsExtension` target) — Home Screen widget (`PiboWidgets`) + Live Activity (`PiboWidgetsLiveActivity`), wired through `PiboWidgetsBundle`. Widget/Live-Activity payloads come from `Shared/WidgetSupport/` (`PiboWidgetSnapshot`, `PiboFeedActivityAttributes`); `PetStateStore` pushes updates via WidgetKit / ActivityKit.

Shared code sits in `Shared/`:

- `Shared/DesignSystem/` — `LP.*` tokens (Colors, Typography, Spacing, Radius, BorderWidth, Shadow, DashPattern) and components (`LPCard`, `LPStatBar`, `LPButton`, `LPPill`, `LPStickyNote`, `LPSpeechBubble`, `LPStamp`, `LPDashedRule`) plus modifiers (`lpCard`, `lpStampedCard`, `lpDashedBorder`, `lpPaper`). **Always reach for these first** before defining one-off colors/fonts/cards. Tokens are platform-aware (watchOS compresses sizes; `lpShadow` is a no-op on watchOS).
  - **Figma UI Kit token layer** (mirrors Figma node `57:226`, **synced from the now-published variables via `get_variable_defs` on 2026-06-10** — no longer provisional). Two layers: raw **primitives** in `Tokens/LPPalette.swift` (`LP.Neutral.grey0…grey900` — a *cool blue-grey* ramp, base `#171D22`; `LP.Colorful.{red…pink}50…900`, 10 hues × 10 steps) and the **semantic** slots in `Tokens/LPTokens.swift` composed from them — `LP.Fill.*` (bg incl. `bgSurfaceSecondary`, foundation accent/onAccent/error/warning/success/info, mask muted/modal/deep/blackout), `LP.Content.*` (primary…quarternary + accent + invert ramp; ink @ fixed alpha), `LP.Separator.*`, and the new `LP.Border.*` (primary/secondary/tertiary stroke colors — pure black @ low alpha; distinct from `LP.BorderWidth`). Plus the Figma-named scales on the existing enums — `LP.Spacing.{none,xs,s,m,l,xl,xxl,xxl3…xxl6}`, `LP.Radius.{xxs…xxxl,infinite}`, `LP.Shadow.elevation1…4` (each two stacked drop shadows — `Spec` carries `layers`), and the UI type ramp `LP.Typography.{uiH1…uiH5, b1Medium/Regular…b4, c1/c2}` (PingFang SC Medium/Regular px, exact). **The cool-grey neutral is intentional** — don't "fix" it back to the warm paper palette; `LP.Colors` (paper/coral/sage) stays warm for the LP narrative/legacy aesthetic (its in-app consumers 图鉴 / 一起 were removed 2026-06-13, so the warm palette currently has no live screen — keep the tokens, they're cheap). The serif `h1/h2/h3` stay for the LP narrative aesthetic; the `uiH*` ramp is the product UI. Two values are inferred (Figma label exists, no published var, flagged inline): `Fill.bgSurfaceSecondary` and `Border.secondary`.
  - **`Theme/` — 关于毛的主题** (`PiboTheme` + `PiboThemeScene` / `PiboHeadItemView`, from Figma `74:6101`): token-driven 节气/活动限定 themes. Each `PiboTheme` is pure data (`scene` sky/ground + `headItem` 毛/花 kind). Presets: `.demon` (魔丸 D1 黑洞+?), `.sprout`, `.peachSeason`, `.aranyaSeaBreeze`. Add a theme = add a preset, no view changes. **A `PiboTheme`/`PiboScene` can now carry optional image slots** (`backgroundImage` / `bodyImage` / `bodyBackImage` 扭头背面 / positioned `headSprite` / `sproutedHeadSprite` 发芽后 / `overheadSprite` 黑洞 — head/overhead are `PiboThemeSprite`s carrying their **393×852 design-frame center**, and the body center is per-theme too); when set, the SpriteKit stage (`PiboStageScene`) shows real artwork sprites instead of the procedural geometry. **All three Figma themes are fully image-backed** — 桃花 from Figma `74:5954` (`peach_bg` / `pibo_body` / `peach_branch`), 阿那亚 from Figma `488:1340`+`488:1353` (`aranya_bg` = 沙滩+海湾+贝壳, `aranya_seaweed` = 海草, **reusing `pibo_body`**), and 魔丸 from Figma `74:5917` (`demon_bg` 悬浮平台, `demon_hole` 黑洞, `demon_curl` 「?」卷芽 → `demon_curl_sprouted` 发芽带叶 from `70:4579`, plus the shared `pibo_body_back` turn-away pose from `76:7175`, curl stripped in the SVG), all under `Pibo/Assets.xcassets/themes/`. As of 2026-06-10 **the theme is user-picked from the settings gear** (`SettingsSheet`, persisted as `PetStateStore.selectedThemeID`; `PiboTheme.selectable` = 魔丸默认/桃花时节/阿那亚) with `.demon` as the default — the D1 story state. Themed homes show their `displayName` line in the header. **`PiboGrowthStage`** (mystery ⇄ sprouted, persisted as `PetStateStore.growthStage`) resolves the effective head via `PiboTheme.resolvedHead(for:)` — 发芽 swaps the 卷芽 and drops the 黑洞; 桃花/阿那亚 heads don't change. `PiboStageScene.positionHead` sizes the art head from its **texture's natural points** (not a hardcoded box) so each theme's 毛/花 keeps its own aspect (桃花枝 38×89.5 vs the taller 海草). The Canvas `PiboThemeScene` / `PiboHeadItemView` now stay only for widget/preview. Asset pipeline for adding a theme: Figma node → `get_design_context` asset SVGs → `rsvg-convert` composite → `@3x` PNG in an imageset.
- `Shared/WidgetSupport/` — payload types shared between the iOS app and the widget extension (`PiboWidgetSnapshot`, `PiboFeedActivityAttributes`). **Live**, not dead.
- `Shared/Connectivity/` — *dead*. Holdover from the WatchConnectivity direction; remove in cleanup.
- `Shared/Models/` — `VitalSession`, `VitalSnapshot`, `VitalSample`, `VitalKind`. Were the wire-format for the watch link; will likely be replaced by a leaner local-only state model once the HealthKit layer lands.

Both targets use `PBXFileSystemSynchronizedRootGroup`, so **any `.swift` / asset file dropped into `Pibo/`, `Pibo Watch App/`, or `Shared/` is picked up automatically** — do not hand-edit `project.pbxproj` to register new source files. Only edit the pbxproj when adding frameworks, capabilities, Info.plist keys, or build-phase steps.

## Build Configuration Notes

- Swift 5.0, Xcode 26.2.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set on both targets — new types are `@MainActor`-isolated by default. Mark HealthKit / connectivity / audio work that must run off the main actor explicitly (`nonisolated`, custom actors, or `Task.detached`).
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` is enabled — imports must cover every module whose members you reference (don't rely on transitive imports).
- The LP palette is **light-mode only** — both app entry points pin `.preferredColorScheme(.light)` on the root scene. Don't change that unless the design system grows dark variants.
- `DEVELOPMENT_TEAM = 4626WN8J3B` with automatic code signing.
- No `Package.swift`, no CocoaPods, no Carthage — dependencies, when added, go through Xcode's SwiftPM integration so they land in `project.pbxproj` / `project.xcworkspace`.

## Frameworks This Project Will Need

- **HealthKit** (iOS, read-only): 步数, 运动分钟, kcal, 站立, 睡眠 stages, HRV (SDNN), RHR, 血氧 (SpO2 `oxygenSaturation`), 冥想 events, 已完成 workouts (incl. per-workout detail — type / duration / energy / distance → pace for the 运动记录 card). The pipeline (observer query + background delivery, per-metric read strategy) is **implemented** — see "HealthKit observer architecture (implemented)" below. Read-only auth requested once at first launch; `NSHealthShareUsageDescription` + the HealthKit capability are already configured on the iOS target.
- **WidgetKit + ActivityKit** (iOS): the `PiboWidgetsExtension` target's Home Screen widget + Live Activity. Snapshots/attributes live in `Shared/WidgetSupport/`; `PetStateStore` reloads timelines / updates the activity on state change.
- **SwiftData** (iOS): in-app store of **complete per-day HealthKit history** + derived records — `@Model HealthDayRecord` (one row per day, full metric set), `@Model WorkoutRecord` (one row per HK workout, keyed by uuid — feeds the 运动记录 card), and `@Model FoodPhoto` (cut-out 拍照 records — feeds the 今日记录 card), all via `HealthHistoryStore`, wired in `PiboApp` with one `ModelContainer` (in-memory fallback). Backs the 历史数据页's past-day data. `HealthDataService+History` backfills days via `HKStatisticsCollectionQuery` daily buckets and workouts via an `HKSampleQuery`; a `#if DEBUG` seed (`seedSampleAllIfEmpty`) makes the simulator (no HK data) demonstrable. **Policy: store the complete HK-readable set, display only the subset each screen shows.**
- **CoreMotion + HealthKit workout session** (watch): the CRC breathing trainer reads heart rate via a `WorkoutSessionManager` and breathing via `CRCMotionBreathingDetector`, coupling them in `CRCCouplingEngine` with `CRCHapticGuide` feedback. Self-contained to `Pibo Watch App/Features/CRCBreathing/`.
- **WatchConnectivity**: ❌ not used for the phone↔watch link. WCSession-era code is dead.
- **SpriteKit** (`SpriteView` → `PiboStageScene`): the home **activity-zone stage** — Pibo character, themed sky/ground (meadow/beach/platform), idle bob, 拍一拍 bounce, 能量收集 头顶毛 animation, 拔毛 seed drop, sparkles. This is the live home stage (it grows a lot of 2D-game-like animation); SwiftUI owns only the chrome. The `PiboTheme` data feeds the scene; image-backed themes show real artwork sprites (see Theme above), else procedural geometry. SpriteKit gotchas: (a) an `SKScene()` starts at size `.zero`, so give the scene a non-zero initial size (and a per-frame build fallback) or `didMove`/`didChangeSize` never build; (b) **SwiftUI's `SpriteView` does NOT honor `scaleMode = .resizeFill`** — the scene stays at its initial size and gets non-uniformly stretched (Pibo looked elongated). Fix: drive `scene.size = geo.size` from a `GeometryReader` in `PiboStageView`. (c) Pull-up perf: keep per-frame work off the drag path — the 数据二楼's progress lives in an `@Observable` read only by `FloorContainer`, and `SpriteView(isPaused:)` stops the loop when the stage is fully covered.
- **SwiftUI Canvas / TimelineView**: the `PiboThemeScene` Canvas backdrop for lightweight contexts. (The older pixel-pet sprite stage `PixelPet`/`PetStageView` + the `Features/Pet` sprite machinery were **removed 2026-06-13** along with 图鉴/一起; the live home stage is SpriteKit `PiboStageScene`.)
- **AVFoundation + camera**: the 拍照交互 (露珠相机 → 扫描线 → 预览 + Pibo 弹幕 → 保存). No AI recognition in MVP — 弹幕 are time-bucketed + a generic pool.
- **AVFoundation**: the *纪念曲* memorial waveform lived in 图鉴 详情 (`Catalog/CatalogMemorialWaveform`), which was **removed 2026-06-13** — no waveform surface ships today. **Do not** rebuild a music-generation pipeline regardless; that direction was cut (the `Services/MusicGeneration` + `LiveCoding` code is dead).

## HealthKit observer architecture (implemented)

This pipeline is **built and wired**, not aspirational. The home page runs off `PetStateStore`, fed by `HealthDataService`. Files: `Pibo/Services/HealthData/` (`HealthDataService`, `HealthMetric`, `HealthEvent`) and `Pibo/Features/Home/PetStateStore.swift`. The shape:

1. **Onboarding** — first-launch screen requests HealthKit read auth for: `HKQuantityType` (stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime, heartRate, heartRateVariabilitySDNN, restingHeartRate, oxygenSaturation), `HKCategoryType` (sleepAnalysis, mindfulSession), `HKWorkoutType.workoutType()`. Store granted-set status in `UserDefaults` so we don't re-prompt.
2. **`HealthDataService`** (`@MainActor @Observable`) — owns one `HKHealthStore` and posts typed `HealthEvent`s on an `events` stream. Per metric it registers an `HKObserverQuery` for *notification only* plus `enableBackgroundDelivery(... .immediate)` so iOS wakes the app when the watch syncs — even backgrounded. The **read strategy varies by metric** (don't assume anchored everywhere): aggregates (steps / kcal / stand / exercise / mindful) use `HKStatisticsQuery cumulativeSum` for the day's running total; HRV / RHR / HR use `HKSampleQueryDescriptor limit:1` for the latest value; sleep sums category durations; **only workouts** use an anchored (delta) query so a just-finished run can trigger a 运动 能量收集 card.
3. **`PetStateStore`** (`@Observable @MainActor`) — subscribes to `HealthDataService.events`. The 魔丸态 home reads its **direct-data** derived API in `PetStateStore+Mowan` (greeting pools, the 6-state `PiboActivityState` machine, 拍一拍 `PatResponse` w/ speech caps + moods + 故事线 clues, idle mutter, 22:00–02:00 拔毛 grade, the selection-aware `currentTheme`) off raw metrics + time of day — no stats in between. Stored hooks live on the class: `selectedThemeID` / `growthStage` (+`markSprouted()`) / `story` are UserDefaults-persisted and wiped by `reset()`. The legacy three-stat / `StatKind` / `[StepItem]` math still runs internally but **only feeds the widget snapshot** (`activityState.displayName` is the visible label); the home no longer surfaces it. Day rollover (`checkDayRollover` → reconcile) and widget / Live Activity pushes stay.
4. **Animation feedback on push** — when a sample arrives while foregrounded, `PetStateStore` raises a delta event; `HomeView` plays the 头顶毛动画 (~3s) + slides up the matching 能量卡片. Background-delivered updates apply silently and replay on the next foreground.
5. **Reconciliation on foreground** — `scenePhase == .active` triggers `reconcile()` to catch anything the observer missed (e.g. permission toggled, app force-quit mid-delivery).
6. **Demo mode** — `PetStateStore.demoMode` falls back to the prior-pivot hard-codes (`BEAN / D07 / 88·74·82`, state `EXCITED`) when there's no real HealthKit data, so the app demos on any device — update as the 魔丸态 model lands. Demo still runs the hatch animation (`UserDefaults` key `pibo.hatched.v1`).

Done on top of this layer: the SpriteKit home stage + the direct-data 6-state machine, 拍一拍 (PatResponse moods + 扭头 + 故事线 clues) / 拔毛 / 能量收集 (the 发芽 close-up flow + 能量已收集 pop), the 拍照 flow (with 抠图 → `FoodPhoto` persistence via `SubjectCutout`), the grab-bar pull-up 历史数据页 (the rebuilt six-card `PiboHistoryView`, history-backed via SwiftData — `HealthDataService+History` backfills `HealthDayRecord` days + `WorkoutRecord` workouts; 血氧/SpO2 now in the auth set + 体征 card), three image-backed themes (`.demon`, `.peachSeason`, `.aranyaSeaBreeze`) selectable from the settings gear (which also hosts 重置), and the persisted 魔丸 growth stage. Still TODO: the 品种(bohair) selector + "SSR" tag are display-only (no 品种 model yet), the 本月活动 heat-map / month view was dropped in the 2026-06-13 rebuild (the Figma month frame `183:1212` can re-add it), the designer Lottie for the 发芽 close-up (`SproutAnimationStyle` seam), date-driven 节气/活动 theme-unlock rules (today all three are freely selectable), per-state Pibo art for the 6-state machine, the 仿漫画 speech render set + 故事线 chapter gating/journal, adding distance/flights to the HK auth set (in the `HealthDayRecord` schema but not yet authorized), and the glitch/sickness/death arc.

## Common Commands

Build / run is normally Xcode (⌘R with the `Pibo` scheme for the phone+watch pair). Command-line equivalents:

```bash
# Build the iOS app (also builds the embedded watch app).
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build

# Build only the watch app.
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build

# Build only the widget extension.
xcodebuild -project Pibo.xcodeproj -scheme PiboWidgetsExtension -configuration Debug build

# List schemes / targets.
xcodebuild -project Pibo.xcodeproj -list

# Clean.
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean
```

There is no test target yet; add one via Xcode before trying `xcodebuild test`.
