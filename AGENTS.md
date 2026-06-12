# Repository Guidelines

## Project Structure & Module Organization

`Pibo.xcodeproj` contains `Pibo` and `Pibo Watch App` schemes. The active product is the iOS app in `Pibo/`; treat the watch target as legacy unless doing cleanup.

- `Pibo/App/`: app entry point, root view, environment wiring.
- `Pibo/Features/`: SwiftUI screens such as `Home` (Pibo 活动区 / 拍一拍 / 拔毛 / 上滑数据二楼 / 拍照), `History` (历史数据页 — the 二楼 content, `PiboHistoryView`), `Onboarding`, `Pet`. (`Catalog` / `Together` were removed 2026-06-13 — the new design no longer depends on them.)
- `Pibo/Services/`: HealthKit, history, identity, storage, logging, playback, and app services.
- `Shared/DesignSystem/`: LP tokens, reusable components, and modifiers. Use these before adding one-off UI styles.
- `Shared/Models/` and `Shared/Connectivity/`: older watch-streaming models; avoid extending them for new iOS work.
- `Pibo/Assets.xcassets/` and `Pibo/Resources/`: sprites, app assets, and audio.
- `product-web-prototype/`: the current source-of-truth product docs — `0603Pibo世界观重构.md` (world-view) and `pibo-home-features-spec.md` (home-page feature + copy spec) — plus HTML mockups. `legacy_docs/` holds the older PRD-era builds (`pibo-mvp-user-journey.md`, `pibo-worldbuilding-bible.md`), kept for lineage only.
- `mocks/`: JSONL sample streams from the earlier watch workflow.

The project uses file-system synchronized Xcode groups. Adding Swift or asset files under target folders is usually enough; do not edit `project.pbxproj` just to register files.

## Build, Test, and Development Commands

```bash
xcodebuild -project Pibo.xcodeproj -list
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build
xcodebuild -project Pibo.xcodeproj -scheme "Pibo Watch App" -configuration Debug build
xcodebuild -project Pibo.xcodeproj -scheme Pibo clean
```

Use Xcode with the `Pibo` scheme for normal run/debug. There is no `Package.swift`, CocoaPods, or Carthage setup; add dependencies through Xcode Swift Package Manager.

## Coding Style & Naming Conventions

Use SwiftUI-first patterns and keep views, view models, and services in the matching feature or service folder. Follow four-space indentation, `PascalCase` types, `camelCase` properties/functions, and filenames such as `HealthDataService.swift`.

Both targets default to `MainActor` isolation. Mark background HealthKit, audio, or long-running work with `nonisolated`, a custom actor, or detached tasks where appropriate.

## Testing Guidelines

No test target exists yet. When adding tests, create an XCTest target such as `PiboTests`, mirror source paths where practical, and name files `TypeNameTests.swift`. Prioritize the direct-data state derivation (6-state machine), 拍一拍 speech caps, 拔毛 grading, HealthKit event mapping, and snapshot persistence.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style prefixes, especially `feat:` and `fix:`. Prefer concise imperative messages, for example `feat: add daily decay tracking`.

PRs should include a behavior summary, screenshots or recordings for UI changes, build/test notes, and any HealthKit capability or signing changes.

## Product & Architecture Notes

The app name is `Pibo`. All user-facing copy, App display names, share-card branding, onboarding copy, screenshots, manuals, and public docs should say `Pibo`/`PIBO`, not `LifePet` or `LifePulse`.

Keep migrated engineering identifiers stable unless the task is explicitly another bundle/project migration: `Pibo.xcodeproj`, the `Pibo` schemes, target names, Swift app types such as `PiboApp`, bundle identifiers, entitlements paths, and source folder names remain `Pibo`. New persistence keys use `pibo.*`; legacy `lifepet.*` references should stay isolated to compatibility migration code.

The active product surface is the iOS app in `Pibo/`. New feature work should read from iOS HealthKit and `PetStateStore`, not WatchConnectivity. The watch target and older connectivity/playback/session code are legacy unless doing cleanup.

Keep the LP light-only design system intact unless dark-mode tokens are added intentionally. For Pibo narrative/UI work, follow the **魔丸态** model in `product-web-prototype/` (`0603Pibo世界观重构.md` + `pibo-home-features-spec.md`): Pibo is a tsundere flower-sprite that only cares about the flower on its head, and state is derived **directly from raw HealthKit data + time of day**. The old 三状态/星光 framing (体力/精力/心情, 活力星光/静息星光/心绪回声) and the 今日步骤 step cards are **superseded — do not extend them**; the shipped `StatKind`/stat-bar/`StepItem` code is prior-pivot scaffolding. Exercise and sleep energy now drive the head-flower's 活力/精神力 and the 6-state activity zone; decline states (发呆/烦躁 → glitch/生病) stay low-pressure and never accusatory.
