# Repository Guidelines

## Project Structure & Module Organization

`LifePulse.xcodeproj` contains `LifePulse` and `LifePulse Watch App` schemes. The active product is the iOS app in `LifePulse/`; treat the watch target as legacy unless doing cleanup.

- `LifePulse/App/`: app entry point, root view, environment wiring.
- `LifePulse/Features/`: SwiftUI screens such as `Home`, `Catalog`, `Together`, `Onboarding`, `Pet`.
- `LifePulse/Services/`: HealthKit, history, identity, storage, logging, playback, and app services.
- `Shared/DesignSystem/`: LP tokens, reusable components, and modifiers. Use these before adding one-off UI styles.
- `Shared/Models/` and `Shared/Connectivity/`: older watch-streaming models; avoid extending them for new iOS work.
- `LifePulse/Assets.xcassets/` and `LifePulse/Resources/`: sprites, app assets, and audio.
- `docs/`: product and submission docs. Current public docs should use the `pibo` name/prefix, for example `docs/pibo-mvp-user-journey.md` and `docs/pibo_manual_build/`.
- `mocks/`: JSONL sample streams from the earlier watch workflow.

The project uses file-system synchronized Xcode groups. Adding Swift or asset files under target folders is usually enough; do not edit `project.pbxproj` just to register files.

## Build, Test, and Development Commands

```bash
xcodebuild -project LifePulse.xcodeproj -list
xcodebuild -project LifePulse.xcodeproj -scheme LifePulse -configuration Debug build
xcodebuild -project LifePulse.xcodeproj -scheme "LifePulse Watch App" -configuration Debug build
xcodebuild -project LifePulse.xcodeproj -scheme LifePulse clean
```

Use Xcode with the `LifePulse` scheme for normal run/debug. There is no `Package.swift`, CocoaPods, or Carthage setup; add dependencies through Xcode Swift Package Manager.

## Coding Style & Naming Conventions

Use SwiftUI-first patterns and keep views, view models, and services in the matching feature or service folder. Follow four-space indentation, `PascalCase` types, `camelCase` properties/functions, and filenames such as `HealthDataService.swift`.

Both targets default to `MainActor` isolation. Mark background HealthKit, audio, or long-running work with `nonisolated`, a custom actor, or detached tasks where appropriate.

## Testing Guidelines

No test target exists yet. When adding tests, create an XCTest target such as `LifePulseTests`, mirror source paths where practical, and name files `TypeNameTests.swift`. Prioritize pet state derivation, daily decay, HealthKit event mapping, and snapshot persistence.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style prefixes, especially `feat:` and `fix:`. Prefer concise imperative messages, for example `feat: add daily decay tracking`.

PRs should include a behavior summary, screenshots or recordings for UI changes, build/test notes, and any HealthKit capability or signing changes.

## Product & Architecture Notes

The app name is `Pibo`. All user-facing copy, App display names, share-card branding, onboarding copy, screenshots, manuals, and public docs should say `Pibo`/`PIBO`, not `LifePet` or `LifePulse`.

Keep historical engineering identifiers stable unless the task is explicitly a bundle/project migration: `LifePulse.xcodeproj`, the `LifePulse` scheme, target names, Swift app types such as `LifePulseApp`, bundle identifiers, entitlements paths, and source folder names remain `LifePulse`. Existing persistence keys such as `lifepet.*` should also remain stable unless a migration plan is added, because renaming them can reset old user state.

The active product surface is the iOS app in `LifePulse/`. New feature work should read from iOS HealthKit and `PetStateStore`, not WatchConnectivity. The watch target and older connectivity/playback/session code are legacy unless doing cleanup.

Keep the LP light-only design system intact unless dark-mode tokens are added intentionally. For Pibo narrative/UI work, prefer the current contract-life and star-light framing: exercise maps to `活力星光`, sleep maps to `静息星光`, and decline states should stay low-pressure rather than punitive.
