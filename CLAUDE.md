# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

The product is **Pibo · Life is Vibe**. The project, schemes, bundle identifiers, and user-facing strings have been migrated to Pibo; old LifePulse names should only appear in historical notes or compatibility migration code. It is an **iOS-only hackathon project** that turns the wearer's daily health data into a tamagotchi:

> 你不是喂宠物，你的身体就是宠物的食物。养得好它陪你更久，养不好它早早走掉。

- **iOS** is the primary surface. It owns the pet UI / step loop / 图鉴 / 一起 / share, and reads health data **passively** from HealthKit on-device. This is where almost all feature work belongs.
- **Apple Watch** no longer streams live samples to the phone. The watch the user already wears writes 步数 / HR / HRV / 睡眠 / workouts into HealthKit on its own; iOS reads those samples after the fact. **However, the watch target is no longer purely dead** — it now hosts a standalone **CRC (cardiorespiratory coupling) breathing trainer** (`Pibo Watch App/Features/CRCBreathing/`), the only active watch feature. Its `RootView` shows `CRCTrainingView()` directly and runs in dark mode.

The original plan had the watch streaming live samples over `WCSession`. **That `WCSession` direction is cut** — no watch session, no `WCSession.sendMessage` feeding the phone; iOS treats HealthKit as the sole input. Genuine dead code from that era still lingers and should not be extended: `Shared/Connectivity/`, `Pibo/Services/Connectivity/`, the `Generation` / `Playback` / `Session` iOS features, `SessionStore`, the `LiveCoding` / `MusicGeneration` / `Visualization` services, and the watch's older `Recording` / `Start` features + `WatchConnectivitySender`. The CRC breathing feature is the exception — it is current. Old `Shared/Models/Vital*` wire-format types are also slated for replacement.

## Core Product Logic (PRD v0.7 — source of truth)

The full PRD lives at `../lifepulse_md/运动健康的拓麻歌子.md`. In-repo product docs also live under `legacy_docs/` (`pibo-mvp-user-journey.md`, `pibo-worldbuilding-bible.md`, the rendered manual/worldbuilding builds) and the newest world-view rework + HTML mockups under `product-web-prototype/` (`0603Pibo世界观重构.md`, `prototype-v0603-*.html`). The rules below are the parts that drive code; if anything here disagrees with the PRD, the PRD wins and this file should be updated.

There is also a sibling `AGENTS.md` (concise repo guidelines) and `README.md` (current 中文 overview with a feature checklist) — keep all three roughly in sync when the architecture shifts.

### Three stats — the only signals the UI shows

Every screen ultimately reduces to these three numbers in [0, 100]. **Note the UI copy has been reframed to a "star-light" (星光) theme** while the underlying `StatKind` cases stay `vitality` / `energy` / `mood`: 体力 → **活力星光** (`✦`), 精力 → **静息星光** (`☾`), 心情 → **心绪回声** (`❤️`). Use the reframed copy in new UI; keep the formulas below.

| Stat | Sources (HealthKit) | Formula | Supplement (`+N`) |
|---|---|---|---|
| 💪 **体力** (vitality) | 步数 · 运动分钟 · 活动卡路里 · 站立时长 | `20 + (步数/10000)·40 + (运动分钟/30)·30 + (kcal/300)·10` | 走 1000 步 +4 / 运动 10 分钟 +10 / 站立 1 小时 +6 |
| ⚡ **精力** (energy)   | 总睡眠 · 深睡 · REM | `(总睡眠h/8)·50 + (深睡h/2)·30 + (REMh/1.5)·20` | 每睡 1 小时 +6 / 深睡多 30 分钟 +15 |
| ❤️ **心情** (mood)     | HRV · 心率稳定度 · 压力峰值 | `50 + (HRV_今 - HRV_基线)·0.8 − 压力峰值·5` | 冥想 5 分钟 +15 / 深呼吸 1 次 +3 |

**Decay:** every 4h, each stat naturally drops 5 (floor 10). 精力 does **not** decay during sleep.

There is **no intermediate "nutrient" layer** — HealthKit data maps directly onto these three stats. Don't introduce养分 / 经验 / 等级 systems.

### Pet visual state machine (priority order)

The pet has 6 states, evaluated in this priority. MVP / demo only animates `NORMAL` and `EXCITED`; the other four are ID-only placeholders for V1.

| Priority | Condition | State | Visual |
|---|---|---|---|
| 1 | 心情 < 30        | `SICK`     | 红晕 + 蹙眉 |
| 2 | 精力 < 30        | `SLEEPING` | 闭眼 + Zzz |
| 3 | 体力 < 30        | `TIRED`    | 半闭眼 + 微垂 |
| 4 | 心情 > 85        | `BLISSFUL` | 爱心飘出 |
| 5 | 体力 > 85        | `EXCITED`  | 举手 + 火花 |
| 6 | otherwise        | `NORMAL`   | 睁眼 + 红舌 |

### Dynamic life cycle (no fixed 21 days)

Lifespan is **not** capped. UI shows only **"已陪伴第 N 天"** — never `N / 21` or any denominator.

Death triggers (轻量化 copy, never accusatory):

| Type | Trigger | Tag |
|---|---|---|
| 急性死 | 心情 < 30 连续 7 天 | "TA 没撑过压力" |
| 慢性死 | 10 天零运动 | "TA 懒得再动了" |
| 饿死 | 基础能量 7 天不补 | "TA 被忘在了角落" |
| 急病死 | 任一状态 = 0 超 48h | "TA 就这么没了" |

Longevity rewards: 3 状态均 > 60 → 每满 7 天自动续命; 连续早起 / 冥想 7 天 → 奖励天数. Visual stages (egg → 幼体 → 青年 → 成体 → 长老) are loose, day-driven, **not** strictly enforced.

### Step cards (今日步骤) — the input loop

Two card kinds:

- **✅ 已完成卡** — what already happened today (auto-generated from HealthKit *or* manually checked).
- **🎯 建议卡** — AI-recommended next step, with two buttons:
  - `✅ 完成` → stat +N, card flips to 已完成
  - `❌ Quit` → **does not deduct**; backend记录 a preference signal. After 3 quits of the same kind → reduce that kind's推送 weight.

Auto-tick comes in two flavors and both must be supported:
- **Manual** — user taps ✅.
- **System auto** — HealthKit detects 跑步 / 睡眠 / 冥想 → 建议卡 auto-flips to 已完成 + a small toast. Auto-completed cards show a `手表自动` tag.

Subheading copy under "今日步骤" is fixed: **"打 ✅ 它开心，打 ❌ 不扣分 —— 但它会记住，下次少推。"** Don't rephrase.

### Home screen IA (v0.7)

```
1. Top meta — greeting + date
2. Pet identity — large pet name + 已陪伴第 N 天 + 当前 state tag
3. LCD stage — pixel pet (state-driven), corner labels, sparkle FX
4. 3 stat bars — 体力 / 精力 / 心情 with data source + supplement copy
5. 今日步骤 — 已完成 (with 手表自动 tag) + 建议 (with ✅ / ❌)
6. Bottom tab — 主页 · 图鉴 · 一起
```

(The shipped `MainTabs` in `Pibo/App/RootView.swift` has three tabs — 主页 `HomeView`, 图鉴 `CatalogView`, 一起 `TogetherView` — plus a floating language menu (中 / EN) in the top-right.)

What was *removed* in v0.7 and must **not** come back: 21-cell life-pixel grid, 7-day silhouette band, "赛博祭坛" naming, 上香按钮, 致敬计数, 分身replace-you叙事, 收藏按钮, 固定 21 天分母.

### Tone

- ❌ 不卖惨, 不问责, 不悲情 ("分身替你死" / "你没好好活着")
- ✅ Statistical, playful, expectant ("已经陪过 4 只" / "又被你熬死了" / "下一只想养什么类型？")

### Demo defaults (when health data isn't wired up)

For demo / preview, hard-code: pet name **BEAN**, day **D07**, stats **体力 88 / 精力 74 / 心情 82**, state `EXCITED`. The `Shared/` mocks folder (`mocks/`) holds JSONL streams for the watch side.

## Project Layout

**Three** Xcode targets / schemes inside a single project (`Pibo.xcodeproj`): `Pibo`, `Pibo Watch App`, `PiboWidgetsExtension`.

- `Pibo/` — iOS app (bundle `fun.tiebao.co.Pibo`, SDK `iphoneos`, deployment iOS 26.2). The pet UI / step loop / HealthKit observer pipeline / 图鉴 / 一起 / share lives here. Active feature folders: `Features/Home` (pet stage, stat triad, step cards, `PetStateStore`), `Features/Catalog` (图鉴 + 纪念波形), `Features/Together` (一起养 — friends / invite / plaza), `Features/Pet` (sprite sequences), `Features/Onboarding` (`HealthAuthView`). Active services: `Services/HealthData` (the observer pipeline), `Services/Identity`, `Services/History` (`DailySnapshot`), `Services/Logging`, `Services/Localization` (中 / EN via `AppLanguage` + `AppLocalization`).
- `Pibo Watch App/` — watchOS target. No longer pure dead weight: its `RootView` is the **CRC breathing trainer** (`Features/CRCBreathing/` — `CRCTrainingViewModel`, `CRCCouplingEngine`, `CRCHapticGuide`, `CRCMotionBreathingDetector`, `CRCTrainingView`, `Models/CRCModels`). The watch's older `Features/Recording`, `Features/Start`, and `Services/Connectivity/WatchConnectivitySender` are the dead WCSession-era code.
- `PiboWidgets/` (`PiboWidgetsExtension` target) — Home Screen widget (`PiboWidgets`) + Live Activity (`PiboWidgetsLiveActivity`), wired through `PiboWidgetsBundle`. Widget/Live-Activity payloads come from `Shared/WidgetSupport/` (`PiboWidgetSnapshot`, `PiboFeedActivityAttributes`); `PetStateStore` pushes updates via WidgetKit / ActivityKit.

Shared code sits in `Shared/`:

- `Shared/DesignSystem/` — `LP.*` tokens (Colors, Typography, Spacing, Radius, BorderWidth, Shadow, DashPattern) and components (`LPCard`, `LPStatBar`, `LPButton`, `LPPill`, `LPStickyNote`, `LPSpeechBubble`, `LPStamp`, `LPDashedRule`) plus modifiers (`lpCard`, `lpStampedCard`, `lpDashedBorder`, `lpPaper`). **Always reach for these first** before defining one-off colors/fonts/cards. Tokens are platform-aware (watchOS compresses sizes; `lpShadow` is a no-op on watchOS).
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

- **HealthKit** (iOS, read-only): 步数, 运动分钟, kcal, 站立, 睡眠 stages, HRV (SDNN), RHR, 冥想 events, 已完成 workouts. The pipeline (observer query + background delivery, per-metric read strategy) is **implemented** — see "HealthKit observer architecture (implemented)" below. Read-only auth requested once at first launch; `NSHealthShareUsageDescription` + the HealthKit capability are already configured on the iOS target.
- **WidgetKit + ActivityKit** (iOS): the `PiboWidgetsExtension` target's Home Screen widget + Live Activity. Snapshots/attributes live in `Shared/WidgetSupport/`; `PetStateStore` reloads timelines / updates the activity on state change.
- **CoreMotion + HealthKit workout session** (watch): the CRC breathing trainer reads heart rate via a `WorkoutSessionManager` and breathing via `CRCMotionBreathingDetector`, coupling them in `CRCCouplingEngine` with `CRCHapticGuide` feedback. Self-contained to `Pibo Watch App/Features/CRCBreathing/`.
- **WatchConnectivity**: ❌ not used for the phone↔watch link. WCSession-era code is dead.
- **SwiftUI Canvas / TimelineView**: pixel pet animation + stat bar transitions. The pet stage animates with bounce + sparkle particles via `TimelineView` + animated transforms; reach for SpriteKit only if particle counts blow up.
- **AVFoundation**: only for the *纪念曲* memorial waveform in 图鉴 详情 (`Catalog/CatalogMemorialWaveform`) — a waveform from a dead pet's lifetime data. **Do not** rebuild a music-generation pipeline; that direction was cut (the `Services/MusicGeneration` + `LiveCoding` code is dead).

## HealthKit observer architecture (implemented)

This pipeline is **built and wired**, not aspirational. The home page runs off `PetStateStore`, fed by `HealthDataService`. Files: `Pibo/Services/HealthData/` (`HealthDataService`, `HealthMetric`, `HealthEvent`) and `Pibo/Features/Home/PetStateStore.swift`. The shape:

1. **Onboarding** — first-launch screen requests HealthKit read auth for: `HKQuantityType` (stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime, heartRate, heartRateVariabilitySDNN, restingHeartRate), `HKCategoryType` (sleepAnalysis, mindfulSession), `HKWorkoutType.workoutType()`. Store granted-set status in `UserDefaults` so we don't re-prompt.
2. **`HealthDataService`** (`@MainActor @Observable`) — owns one `HKHealthStore` and posts typed `HealthEvent`s on an `events` stream. Per metric it registers an `HKObserverQuery` for *notification only* plus `enableBackgroundDelivery(... .immediate)` so iOS wakes the app when the watch syncs — even backgrounded. The **read strategy varies by metric** (don't assume anchored everywhere): aggregates (steps / kcal / stand / exercise / mindful) use `HKStatisticsQuery cumulativeSum` for the day's running total; HRV / RHR / HR use `HKSampleQueryDescriptor limit:1` for the latest value; sleep sums category durations; **only workouts** use an anchored (delta) query so a just-finished run can flip a matching suggest card.
3. **`PetStateStore`** (`@Observable @MainActor`) — subscribes to `HealthDataService.events`, maps samples to PRD §3 formulas, mutates the three stats, derives `PetState` per §5 priority order, and owns the `[StepItem]` derivation (auto-tick suggest cards on a matching workout/sleep/mindful sample). Also handles day rollover (`checkDayRollover` → `applyDecayCatchup` → reconcile) and pushes widget / Live Activity snapshots.
4. **Animation feedback on push** — when a sample arrives while foregrounded, `PetStateStore` raises a delta event; `HomeView` runs the same `applyGain` / toast / stat-bar flow as a manual ✅, plus a sparkle burst. Background-delivered updates apply silently and animate on the next foreground.
5. **Reconciliation on foreground** — `scenePhase == .active` triggers `reconcile()` to catch anything the observer missed (e.g. permission toggled, app force-quit mid-delivery).
6. **Demo mode** — `PetStateStore.demoMode` falls back to hard-coded `BEAN / D07 / 88·74·82` (state `EXCITED`) when there's no real HealthKit data, so the app demos on any device. Demo still runs the hatch animation (`UserDefaults` key `pibo.hatched.v1`).

Still TODO on top of this layer: AI-recommended suggestion ranking (cards are static today), the death-trigger evaluation loop, and longevity reward bookkeeping — all build on `PetStateStore`'s daily snapshots (`Services/History/DailySnapshot`).

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
