# Repository Guidelines

## Project Structure & Module Organization

`Pibo.xcodeproj` contains the iOS app, watch app, and widget extension targets. The primary product surface is the iOS app in `Pibo/`; the watch app is active only for the standalone CRC breathing trainer.

- `Pibo/App/`: app entry point, root view, environment wiring, scene phase hooks.
- `Pibo/Features/`: SwiftUI/SpriteKit feature surfaces. `Home` is the fixed portrait SpriteKit forest (`PiboStageView` / `PiboStageScene`) with Pibo、由真实健康数据驱动的 `bo` 生长、共同物件直接投入和 SwiftUI chrome；旧 Studio/Gym 分区、横向漫游与独立拔取流程已经删除。`History` is the full-screen history page; `WalkDoodle` is the released independent「散步涂鸦」activity-creation loop, not a mini-game or gated item capability; `Games` contains unreleased engineering inventory and is not a current Gym page; `Onboarding` handles HealthKit auth. `Catalog` / `Together` were removed 2026-06-13.
- `Pibo/Services/`: HealthKit, SwiftData history, identity/auth/backend, membership, analytics, Vision, localization, and app services. Do not extend the old connectivity/playback/session/music-generation direction.
- `Shared/Logging/LPLog.swift`: the one logging entry point for app + watch + widget. Add a category to the table; never construct an `os.Logger` at a call site.
- `Pibo/Services/Core/`: thin iOS adapters over the shared Rust `pibo-core` SDK. Keep type mapping and platform presentation here; shared thresholds and deterministic rules belong in the SDK.
- `Pibo Watch App/Features/CRCBreathing/`: the only current watch feature. Older `Recording`, `Start`, and watch connectivity code are WCSession-era leftovers.
- `PiboWidgets/`: Home Screen widget and Live Activity extension. Shared payloads live in `Shared/WidgetSupport/` and are live, not legacy.
- `Shared/DesignSystem/`: LP tokens, Figma UI Kit tokens, reusable components, modifiers, and theme data. Use these before adding one-off UI styling.
- `Shared/Connectivity/` and old `Shared/Models/Vital*`: WatchConnectivity wire-format leftovers; avoid extending them.
- `Pibo/Assets.xcassets/` and `Pibo/Resources/`: sprites, app assets, audio, and theme artwork.
- `/Users/trevorlink/Project/PiboWorld/pibo-media`: source of truth for production-approved images, SVG, audio, video, character media, and platform exports. Its generated `manifest.json` carries hashes and stable collection IDs; `platform/ios/` and `platform/harmony/` contain runtime derivatives. App builds vendor selected files and never depend on this absolute path.
- `docs/product-strategy-202608/`: current MVP mechanics and implementation source of truth. Read `05-P0-Implementation-Status.md` for the latest cross-platform checkpoint. `product-web-prototype/pibo-home-features-spec.md`, `legacy_docs/`, and `mocks/` are historical and must not override approved decisions or current code.
- `docs/narrative-rebuild/`: current narrative and product-decision source of truth. Use `decisions/README.md` to locate approved decisions, especially 033/034 for contextual pat speech and 043 for Shadow Pibo. `HANDOFF.md` is a dated context index: its newest checkpoint wins and older dated TODOs are historical, not current implementation status.
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

Use Xcode with the `Pibo` scheme for normal run/debug. `PiboTests` is the unit/integration test target. There is no app-level `Package.swift`, CocoaPods, or Carthage setup. Dependencies go through Xcode Swift Package Manager, all three as exact-version remote packages: `PiboCore` from the private `git@github.com:PiboWorld/pibo-core.git` (needs an SSH key), `PiboChessUI` and `DataSneaker` (`https://github.com/all2prosperity/ds-swift-sdk.git`) public over HTTPS. Commit `Package.resolved` whenever a remote package version changes.

## Coding Style & Naming Conventions

Use SwiftUI-first patterns and keep views, view models, and services in the matching feature or service folder. The live home scene is SpriteKit-backed, with SwiftUI owning chrome and presentation. Follow four-space indentation, `PascalCase` types, `camelCase` properties/functions, and filenames such as `HealthDataService.swift`.

Both app targets default to `MainActor` isolation with approachable concurrency enabled. Mark background HealthKit, CoreMotion, location, audio, networking, or long-running work with `nonisolated`, a custom actor, or detached tasks where appropriate. Member import visibility is enabled, so import every module whose members are referenced.

Keep the LP design system light-only unless dark-mode tokens are intentionally added. Do not reintroduce TabView home navigation, the old pull-up floor, per-frame opacity fades on heavy history content, or one-off visual systems where LP tokens/components already fit.

Info.plist keys are usually generated from `INFOPLIST_KEY_*` build settings. Keys with no build-setting form, such as `UIBackgroundModes`, belong in the root `Pibo-Info.plist`, which must stay outside the synchronized `Pibo/` group to avoid double-bundling.

## Testing Guidelines

`PiboTests` (swift-testing) is wired into the `Pibo` scheme; run it with `xcodebuild test -project Pibo.xcodeproj -scheme Pibo -destination 'platform=iOS Simulator,name=iPhone 17'`. Mirror source paths where practical and name files `TypeNameTests.swift`. Suites that touch app-wide singletons (e.g. `StressNotifier.shared`) must be `@Suite(.serialized)`. Prioritize direct-data state derivation (6-state machine), double-tap gesture acceptance, contextual speech/microchapter/cooldown lifecycle, direct `bo` investment and idempotency, morning-sleep readiness/delivery, HealthKit event mapping/backfill, food-camera validation/history, Walk Doodle scoring/reward/history, Shadow friendship/snapshot/privacy behavior, widget snapshots, membership entitlement handling, and CRC coupling logic.

The suite is green; treat any failure as a regression. Sleep ingestion in particular is pinned by `PiboTests/PiboCoreSleepIntegrationTests.swift`, which encodes why HealthKit's ambiguous asleep value (`.asleep` == `.asleepUnspecified`) must resolve conservatively — see `CLAUDE.md` before changing that mapping.

For UI changes, include simulator screenshots or recordings where practical, especially for home SpriteKit, history, widgets/Live Activities, camera, and watch CRC surfaces.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style prefixes, especially `feat:` and `fix:`. Prefer concise imperative messages, for example `feat: add daily decay tracking`.

PRs should include a behavior summary, screenshots or recordings for UI changes, build/test notes, and any HealthKit, StoreKit, widget, location, signing, backend, or Info.plist/capability changes.

## Product & Architecture Notes

### Shared Rust domain SDK

`pibo-core` is the source of truth for deterministic rules shared with HarmonyPibo. It owns environment/time/weather mixing, the six-state activity machine, greetings, accepted-pat context/content/cooldown policy, sleep/workout policy, stress scoring and alert decisions, soundscape profiles, `bo` growth/investment rules, Walk Doodle tasks/geometry/rewards, and retained mini-game domain inventory. Legacy pluck/grading and unreleased mini-game APIs may remain for compatibility, but they are not authorization to restore those product flows. iOS consumes its `PiboCore` Swift product and maps results through `Pibo/Services/Core/`.

Do not copy SDK-owned thresholds or algorithms into Swift. Cross-platform animation selection, semantic transition intent, speech/bubble trigger policy, cooldowns, and deterministic content-key selection belong in Core. Platform acquisition and effects—HealthKit, time/weather fetching, permissions, persistence, SwiftUI/SpriteKit playback, localized strings, asset decoding, audio, haptics, notifications, networking, analytics, and StoreKit—remain in this repository. New cross-platform pure logic must be implemented and released in `PiboWorld/pibo-core` first.

Core release order is strict: update and verify Core → publish a SemVer tag such as `0.1.1` → update this project's exact Swift Package version and `Package.resolved` → update HarmonyPibo's pinned submodule → build both Apps. Never point the app at Core `main` or an unpublished local revision. The SDK's own `AGENTS.md`/`CLAUDE.md` define ABI and release requirements.

The app name is `Pibo`. All user-facing copy, App display names, share-card branding, onboarding copy, screenshots, manuals, analytics naming, and public docs should say `Pibo`/`PIBO`, not `LifePet` or `LifePulse`.

Keep migrated engineering identifiers stable unless the task is explicitly another bundle/project migration: `Pibo.xcodeproj`, the `Pibo` schemes, target names, Swift app types such as `PiboApp`, bundle identifiers, entitlements paths, and source folder names remain `Pibo`. New persistence keys use `pibo.*`; legacy `lifepet.*` references should stay isolated to compatibility migration code.

New narrative and copy work follows the approved decisions in `docs/narrative-rebuild/`; `docs/narrative/` remains shipped lineage until the rebuild is formally migrated. The product archetype is a virtual pet raised by real health data, while Pibo's narrative identity is an amnesiac young firebringer on its first independent journey—not a domesticated subordinate, a child, or the user's health coach. Its constant traits are serious, curious, direct, procedural, and self-respecting. It speaks briefly and plainly; garbling comes from damaged memory/translation and may decrease, while its voice stays restrained and unsweetened. Show care through remembered details, changed plans, and consequential choices; do not use denial-of-care lines such as “才不是关心你”. Personality stays constant while judgment and action change. See decisions 005 and 034.

The absolute “Pibo cannot suffer” boundary in decision 027 was reopened by the user on 2026-08-13. Pibo may experience negative conditions, and positive health-driven change must visibly land on Pibo so the same state can later support Shadow Pibo. The triggers, severity, recovery, missing-data behavior, and anti-coercion boundary are not yet frozen. Until a replacement decision is approved, do not invent death, irreversible loss, guilt notifications, permission punishment, or a direct “you moved too little, therefore Pibo is harmed” rule.

Common items are persistent behavior/capability entitlements defined by `pibo-core`, not cosmetic flags. Platform stores persist ownership and derive capabilities through Core. Raw health collection, health authorization, `bo` formation, the base food camera, Walk Doodle, and Shadow friendship must remain outside item gates. The next unowned common item appears directly in the forest as one grey target; a ripe `bo` stays on Pibo's head until the user confirms direct investment from that item's Half Sheet. Do not restore a backpack, separate unlock-reward window, or pluck gesture. Hammock ownership changes sleep review/wake behavior; the dream-mending chime's replacement value and later item costs remain explicitly unresolved. Decision 043 supersedes decision 032 for Shadow eligibility.

Future monetization follows `docs/narrative-rebuild/decisions/028-养成社交战斗与商业化边界.md`. Commercial shops, battle, and advanced social tools remain outside the current MVP. Shadow Pibo's free one-friend flow is implemented on both platforms as a local engineering closure, but production domains, deep linking/App Linking, deployed backend verification, and two-device synchronization remain release gates. `bo`, story progress, relationship depth, memory recovery, and return readiness cannot be purchased or accelerated with money. Paid entitlements are separate and may later cover ongoing meal-camera services, cosmetics, space expression, and advanced social tools. Basic social viewing/visiting remains free. Physical return ends the Earth cohabitation and main storyline but transitions the App to a low-frequency remote connection; never strand purchased cosmetics, social identity, or game assets after story completion.

Core state derives directly from raw HealthKit data plus time of day. Do not extend the old 三状态/星光/养分 layer (`StatKind`, stat bars, 活力星光/静息星光/心绪回声, 今日步骤 cards); it is prior-pivot scaffolding. The only current Core states are `dataUnknown`, `sleeping`, `waking`, `stable`, `energetic`, and `tired`. Resting, comforted, playing, and similar presentation variants are behavior substates; the old irritated/disturbed state is retired. Physical pat input is a double tap on Pibo's body on both platforms; one tap must not advance text.

Food capture succeeds only after the backend confirms `is_food`. A successful meal produces the approved sticker projection beside Pibo, one LLM-authored observation, restrained observe behavior, and a persisted history item with calorie/nutrition detail. Do not create meal records, projections, or rewards for non-food, recognition failure, or synthetic fallback. Shadow Pibo is a mutually accepted single-friend relationship that synchronizes only public semantic Pibo state, preserves the latest valid snapshot when offline, and never exposes raw health metrics or implies online presence. “Send a light” carries no text, score, streak, or reward.

The current home IA is one fixed portrait SpriteKit forest; there is no Studio page, Gym page, horizontal camera pan, snap, or inertia. SwiftUI owns feature chrome and presentation around the scene. The old 上滑数据二楼 / `FloorModel` / `FloorContainer` / `FloorDome` navigation is retired; history opens as `HistoryScreen`. Do not reconstruct Studio/Gym from stale narrative documents.

New iOS feature work should read from `HealthDataService`, `HealthHistoryStore`, and `PetStateStore`, not WatchConnectivity. iOS passively reads on-device HealthKit samples written by the user's watch; the phone/watch WCSession streaming direction is cut. The watch app's current CRC breathing trainer is self-contained and does not feed the phone.

The sibling HarmonyOS app lives at `/Users/trevorlink/Project/hackathon/HarmonyPibo`, the production media source repository at `/Users/trevorlink/Project/PiboWorld/pibo-media`, and the sibling backend at `/Users/trevorlink/Project/hackathon/pibo-server`; none live inside this repo. Media binaries never belong in `pibo-core`: keep approved masters under `pibo-media/source/`, publish iOS-ready derivatives under `pibo-media/platform/ios/`, and copy/version selected runtime files into this App with the repository's sync tool. Core returns stable semantic IDs, not filenames or absolute paths. iOS backend clients are under `Pibo/Services/Backend/`. Membership uses StoreKit 2 in `MembershipService` with products `fun.tiebao.co.Pibo.membership.monthly` and `.yearly`; local simulator testing uses the root `PiboStore.storekit`.

Analytics goes through `Pibo/Services/Analytics/Analytics.swift` only. Call sites should use `Analytics.track(...)` and never import DataSneaker directly. Event names are snake_case data contracts; treat renames as migrations. If `PIBO_ANALYTICS_URL` in `Pibo-Info.plist` is empty, analytics is disabled. Instrument discrete user actions only, never per-frame SpriteKit/drag/update paths. The SDK itself is the pinned remote package `all2prosperity/ds-swift-sdk` (extracted 2026-07-26 from the DataSneaker monorepo, which .gitignores `sdk/`): `track()` is non-blocking with all work on an `EventPipeline` actor, it writes to disk only on flush failure and backgrounding, and it no-ops entirely until configured. Its wire format mirrors the Go server's `internal/models/event.go`, so key changes ship on both sides together; bump it by tagging a plain SemVer release there, then updating the exact pin and `Package.resolved` here.
