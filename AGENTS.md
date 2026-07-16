# Repository Guidelines

## Project Structure & Module Organization

`Pibo.xcodeproj` contains the iOS app, watch app, and widget extension targets. The primary product surface is the iOS app in `Pibo/`; the watch app is active only for the standalone CRC breathing trainer.

- `Pibo/App/`: app entry point, root view, environment wiring, scene phase hooks.
- `Pibo/Features/`: SwiftUI/SpriteKit feature surfaces. `Home` is the full-screen horizontally pannable SpriteKit world (`PiboStageView` / `PiboStageScene`) with 拍一拍 / 拔毛 / 能量收集 / 露珠相机 entry; `History` is the 足迹 full-screen history page; `Games` hosts health mini-games; `WalkDoodle` is the map doodle recorder; `Onboarding` handles HealthKit auth. `Catalog` / `Together` were removed 2026-06-13.
- `Pibo/Services/`: HealthKit, SwiftData history, identity/auth/backend, membership, analytics, Vision, localization, logging, and app services. Do not extend the old connectivity/playback/session/music-generation direction.
- `Pibo/Services/Core/`: thin iOS adapters over the shared Rust `pibo-core` SDK. Keep type mapping and platform presentation here; shared thresholds and deterministic rules belong in the SDK.
- `Pibo Watch App/Features/CRCBreathing/`: the only current watch feature. Older `Recording`, `Start`, and watch connectivity code are WCSession-era leftovers.
- `PiboWidgets/`: Home Screen widget and Live Activity extension. Shared payloads live in `Shared/WidgetSupport/` and are live, not legacy.
- `Shared/DesignSystem/`: LP tokens, Figma UI Kit tokens, reusable components, modifiers, and theme data. Use these before adding one-off UI styling.
- `Shared/Connectivity/` and old `Shared/Models/Vital*`: WatchConnectivity wire-format leftovers; avoid extending them.
- `Pibo/Assets.xcassets/` and `Pibo/Resources/`: sprites, app assets, audio, and theme artwork.
- `docs/narrative/`: current narrative source of truth. `product-web-prototype/pibo-home-features-spec.md` remains the current home mechanics/copy spec. `product-web-prototype/0603Pibo世界观重构.md` is lineage for the flower/energy loop only; its worldview/personality framing is superseded. `legacy_docs/` and `mocks/` are historical.
- Root config/support files include `Pibo-Info.plist` for plist keys without build-setting forms and `PiboStore.storekit` for local StoreKit testing.

The project uses file-system synchronized Xcode groups. Adding Swift or asset files under target folders is usually enough; do not edit `project.pbxproj` just to register files. Only edit the pbxproj for frameworks, capabilities, Info.plist wiring, build phases, package references, or similar project settings.

## Build, Test, and Development Commands

```bash
xcodebuild -project Pibo.xcodeproj -list
xcodebuild -resolvePackageDependencies -project Pibo.xcodeproj -scheme Pibo
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build
xcodebuild -project Pibo.xcodeproj -scheme PiboWidgetsExtension -configuration Debug build
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean
```

Use Xcode with the `Pibo` scheme for normal run/debug. `PiboTests` is the unit/integration test target. There is no app-level `Package.swift`, CocoaPods, or Carthage setup. Dependencies go through Xcode Swift Package Manager. `PiboCore` is pinned to an exact release of the private `git@github.com:PiboWorld/pibo-core.git` package; DataSneaker remains a local package at `../../tiebao/utils/DataSneaker/sdk/swift`. Commit `Package.resolved` whenever a remote package version changes.

## Coding Style & Naming Conventions

Use SwiftUI-first patterns and keep views, view models, and services in the matching feature or service folder. The live home scene is SpriteKit-backed, with SwiftUI owning chrome and presentation. Follow four-space indentation, `PascalCase` types, `camelCase` properties/functions, and filenames such as `HealthDataService.swift`.

Both app targets default to `MainActor` isolation with approachable concurrency enabled. Mark background HealthKit, CoreMotion, location, audio, networking, or long-running work with `nonisolated`, a custom actor, or detached tasks where appropriate. Member import visibility is enabled, so import every module whose members are referenced.

Keep the LP design system light-only unless dark-mode tokens are intentionally added. Do not reintroduce TabView home navigation, the old pull-up floor, per-frame opacity fades on heavy history content, or one-off visual systems where LP tokens/components already fit.

Info.plist keys are usually generated from `INFOPLIST_KEY_*` build settings. Keys with no build-setting form, such as `UIBackgroundModes`, belong in the root `Pibo-Info.plist`, which must stay outside the synchronized `Pibo/` group to avoid double-bundling.

## Testing Guidelines

No XCTest target exists yet. When adding tests, create `PiboTests`, mirror source paths where practical, and name files `TypeNameTests.swift`. Prioritize direct-data state derivation (6-state machine), 拍一拍 speech caps, 拔毛 grading, HealthKit event mapping/backfill, SwiftData history persistence, widget snapshots, membership entitlement handling, and CRC coupling logic.

Until tests exist, run the relevant `xcodebuild ... build` command after implementation. For UI changes, include simulator screenshots or recordings where practical, especially for home SpriteKit, history, widgets/Live Activities, camera, and watch CRC surfaces.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style prefixes, especially `feat:` and `fix:`. Prefer concise imperative messages, for example `feat: add daily decay tracking`.

PRs should include a behavior summary, screenshots or recordings for UI changes, build/test notes, and any HealthKit, StoreKit, widget, location, signing, backend, or Info.plist/capability changes.

## Product & Architecture Notes

### Shared Rust domain SDK

`pibo-core` is the source of truth for deterministic rules shared with HarmonyPibo. It owns environment/time/weather mixing, the six-state activity machine, greetings, 拍一拍/拔毛, sleep/workout policy, stress scoring and alert decisions, soundscape profiles, Walk Doodle geometry, mini-game rewards, 华容道, Pet Detective, 叠花盆, and Rhythm Tap. iOS consumes its `PiboCore` Swift product and maps results through `Pibo/Services/Core/`.

Do not copy SDK-owned thresholds or algorithms into Swift. Platform acquisition and effects—HealthKit, time/weather fetching, permissions, persistence, SwiftUI/SpriteKit, localized copy, audio, haptics, notifications, networking, analytics, and StoreKit—remain in this repository. New cross-platform pure logic must be implemented and released in `PiboWorld/pibo-core` first.

Core release order is strict: update and verify Core → publish a SemVer tag such as `0.1.1` → update this project's exact Swift Package version and `Package.resolved` → update HarmonyPibo's pinned submodule → build both Apps. Never point the app at Core `main` or an unpublished local revision. The SDK's own `AGENTS.md`/`CLAUDE.md` define ABI and release requirements.

The app name is `Pibo`. All user-facing copy, App display names, share-card branding, onboarding copy, screenshots, manuals, analytics naming, and public docs should say `Pibo`/`PIBO`, not `LifePet` or `LifePulse`.

Keep migrated engineering identifiers stable unless the task is explicitly another bundle/project migration: `Pibo.xcodeproj`, the `Pibo` schemes, target names, Swift app types such as `PiboApp`, bundle identifiers, entitlements paths, and source folder names remain `Pibo`. New persistence keys use `pibo.*`; legacy `lifepet.*` references should stay isolated to compatibility migration code.

Narrative now follows `docs/narrative/`: Pibo is an amnesiac, constant-personality tsundere creature bound by a 约定, with fragmented Souls-style storytelling and memory recovery tied to cumulative health-behaviour depth. Do not revive the old 魔丸→傲娇→伙伴 personality-stage arc or the explicit future/AI timeline. The shipped 魔丸 look, garbled voice, flower/energy loop, glitch/sickness/离去 arc, and low-pressure tone remain.

Core state derives directly from raw HealthKit data plus time of day. Do not extend the old 三状态/星光/养分 layer (`StatKind`, stat bars, 活力星光/静息星光/心绪回声, 今日步骤 cards); it is prior-pivot scaffolding. Exercise and sleep energy drive the head-flower's 活力/精神力 and the 6-state activity zone: 深眠, 初醒, 活跃, 烦躁, 发呆, optional 被打扰.

The current home IA is the 2026-06-27 horizontal world: `studio ← home ← gym`, panned by dragging inside the SpriteKit scene with a hard-clamped camera, no snap and no inertia. Studio enters 露珠相机, home handles 拍一拍 / 拔毛 / 能量收集, and gym opens health mini-games. The old 上滑数据二楼 / `FloorModel` / `FloorContainer` / `FloorDome` navigation is retired; history now opens from the hand-drawn 足迹 icon as `HistoryScreen`.

New iOS feature work should read from `HealthDataService`, `HealthHistoryStore`, and `PetStateStore`, not WatchConnectivity. iOS passively reads on-device HealthKit samples written by the user's watch; the phone/watch WCSession streaming direction is cut. The watch app's current CRC breathing trainer is self-contained and does not feed the phone.

The sibling backend lives at `/Users/trevorlink/Project/hackathon/pibo-server`, not inside this repo. iOS backend clients are under `Pibo/Services/Backend/`. Membership uses StoreKit 2 in `MembershipService` with products `fun.tiebao.co.Pibo.membership.monthly` and `.yearly`; local simulator testing uses the root `PiboStore.storekit`.

Analytics goes through `Pibo/Services/Analytics/Analytics.swift` only. Call sites should use `Analytics.track(...)` and never import DataSneaker directly. Event names are snake_case data contracts; treat renames as migrations. If `PIBO_ANALYTICS_URL` in `Pibo-Info.plist` is empty, analytics is disabled. Instrument discrete user actions only, never per-frame SpriteKit/drag/update paths.
