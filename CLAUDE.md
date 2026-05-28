# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

The product is **Pibo · Life is Vibe**. The project, schemes, bundle identifiers, and user-facing strings have been migrated to Pibo; old LifePulse names should only appear in historical notes or compatibility migration code. It is an **iOS-only hackathon project** that turns the wearer's daily health data into a tamagotchi:

> 你不是喂宠物，你的身体就是宠物的食物。养得好它陪你更久，养不好它早早走掉。

- **iOS** is the only active surface. It owns the pet UI / step loop / 图鉴 / share, and reads health data **passively** from HealthKit on-device.
- **Apple Watch** has no custom app in this project. The watch the user already wears writes 步数 / HR / HRV / 睡眠 / workouts into HealthKit on its own; iOS reads those samples after the fact.

The original plan had an active watch app streaming live samples over `WCSession`. **That is cut.** No watch session, no `WCSession.sendMessage`, no on-watch UI. New code should treat HealthKit as the sole input. There is dead code from the previous direction (`Shared/Connectivity/`, `Pibo/Services/Connectivity/`, the entire `Pibo Watch App/` target, the `Generation` / `Playback` / `Session` features, `SessionStore`); it can be removed in a cleanup pass and should not be extended.

## Core Product Logic (PRD v0.7 — source of truth)

The full PRD lives at `../lifepulse_md/运动健康的拓麻歌子.md`. The rules below are the parts that drive code; if anything here disagrees with the PRD, the PRD wins and this file should be updated.

### Three stats — the only signals the UI shows

Every screen ultimately reduces to these three numbers in [0, 100]:

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
6. Bottom tab — 主页 · 图鉴
```

What was *removed* in v0.7 and must **not** come back: 21-cell life-pixel grid, 7-day silhouette band, "赛博祭坛" naming, 上香按钮, 致敬计数, 分身replace-you叙事, 收藏按钮, 固定 21 天分母.

### Tone

- ❌ 不卖惨, 不问责, 不悲情 ("分身替你死" / "你没好好活着")
- ✅ Statistical, playful, expectant ("已经陪过 4 只" / "又被你熬死了" / "下一只想养什么类型？")

### Demo defaults (when health data isn't wired up)

For demo / preview, hard-code: pet name **BEAN**, day **D07**, stats **体力 88 / 精力 74 / 心情 82**, state `EXCITED`. The `Shared/` mocks folder (`mocks/`) holds JSONL streams for the watch side.

## Project Layout

Two Xcode targets inside a single project (`Pibo.xcodeproj`):

- `Pibo/` — iOS app (bundle `fun.tiebao.co.Pibo`, SDK `iphoneos`, deployment iOS 26.2). The pet UI / step loop / HealthKit observer pipeline / 图鉴 / share lives here.
- `Pibo Watch App/` — watchOS app target. **Now vestigial.** The pivot to passive HealthKit reads makes the watch app unnecessary. It still builds (the iOS scheme embeds it), but no new feature work should land here. Plan: drop the target in a cleanup pass once the iOS HealthKit story is wired up.

Shared code sits in `Shared/`:

- `Shared/DesignSystem/` — `LP.*` tokens (Colors, Typography, Spacing, Radius, BorderWidth, Shadow, DashPattern) and components (`LPCard`, `LPStatBar`, `LPButton`, `LPPill`, `LPStickyNote`, `LPSpeechBubble`, `LPStamp`, `LPDashedRule`) plus modifiers (`lpCard`, `lpStampedCard`, `lpDashedBorder`, `lpPaper`). **Always reach for these first** before defining one-off colors/fonts/cards. Tokens are platform-aware (watchOS compresses sizes; `lpShadow` is a no-op on watchOS).
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

- **HealthKit** (iOS, read-only): 步数, 运动分钟, kcal, 站立, 睡眠 stages, HRV (SDNN), RHR, 冥想 events, 已完成 workouts. The pipeline is **observer query + anchored object query + background delivery** — see "HealthKit observer architecture (planned)" below for the design. Request `HKHealthStore.requestAuthorization` once at first launch; only the *read* half is needed (we don't write samples). Add `NSHealthShareUsageDescription` to `Pibo/Info.plist` and turn on the HealthKit capability on the iOS target.
- **WatchConnectivity**: ❌ not used. The pivot to HealthKit observers makes WCSession unnecessary.
- **SwiftUI Canvas / SpriteKit / Lottie (TBD)**: pixel pet animation + stat bar transitions. The pet stage animates with bounce + sparkle particles via `TimelineView` + animated transforms; reach for SpriteKit only if particle counts blow up.
- **AVFoundation** (later): only for the *纪念曲* feature in 图鉴 详情 — generate a waveform from a dead pet's lifetime data. **Do not** rebuild a music-generation pipeline; that direction was cut.

## HealthKit observer architecture (planned, not yet implemented)

The home page currently runs off a hard-coded `HomeModel` with sample stats. The plan to wire it to real HealthKit data:

1. **Onboarding** — first-launch screen requests HealthKit read auth for: `HKQuantityType` (stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime, heartRate, heartRateVariabilitySDNN, restingHeartRate), `HKCategoryType` (sleepAnalysis, mindfulSession), `HKWorkoutType.workoutType()`. Store granted-set status in `UserDefaults` so we don't re-prompt.
2. **`HealthDataService`** (new, `Pibo/Services/HealthData/`) — owns one `HKHealthStore`, exposes async streams of typed samples. Each watched type registers two queries:
   - `HKObserverQuery` for *notification only*. The handler fires `HKAnchoredObjectQuery` with the saved anchor to read the delta, then persists the new anchor.
   - `HKHealthStore.enableBackgroundDelivery(for:frequency:)` so iOS wakes the app briefly when the watch syncs new samples — even if the user isn't holding the phone.
3. **`PetStateStore`** (new, replaces hand-set `HomeModel`) — `@Observable @MainActor`. Subscribes to `HealthDataService` streams, maps incoming samples to PRD §3 formulas, mutates the three stats, derives `PetState` per §5 priority order. Owns the `[StepItem]` derivation (auto-tick suggest cards when a matching workout/sleep/mindful session arrives).
4. **Animation feedback on push** — when a sample arrives while the app is foregrounded, `PetStateStore` raises a `lastDelta` event. `HomeView` listens, runs the same `applyGain` / toast / stat-bar animation flow that `markDone` uses today, plus a sparkle burst on the pet stage. Background-delivered updates that land while the app is backgrounded simply update state silently — the next foreground will animate to the new values.
5. **Reconciliation on foreground** — `scenePhase == .active` triggers a one-shot `HKAnchoredObjectQuery` per type to catch anything that slipped through (e.g. permission revoked + restored). Cheap because we still have the anchor.
6. **Demo mode toggle** — keep the hard-coded `BEAN / D07 / 88·74·82` numbers behind a `DemoMode.isEnabled` flag so we can present without HealthKit data on the demo device.

Out of scope for now: the AI-recommended suggestion ranking (currently static cards), the death-trigger evaluation loop, longevity reward bookkeeping. Those build on top of `PetStateStore`'s daily snapshots once the observer layer is in.

## Common Commands

Build / run is normally Xcode (⌘R with the `Pibo` scheme for the phone+watch pair). Command-line equivalents:

```bash
# Build the iOS app (also builds the embedded watch app).
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build

# Build only the watch app.
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build

# List schemes / targets.
xcodebuild -project Pibo.xcodeproj -list

# Clean.
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean
```

There is no test target yet; add one via Xcode before trying `xcodebuild test`.
