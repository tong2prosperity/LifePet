# Migration Status

Objective: create a new HarmonyOS app directory and move toward feature parity
with the current iOS LifePet app.

## Implemented In This Directory

- HarmonyOS Stage-model project shell targeting API 20:
  - `build-profile.json5`
  - `AppScope/app.json5`
  - `entry/src/main/module.json5`
  - `entry/src/main/ets/entryability/EntryAbility.ets`
  - device targets are phone / tablet / 2in1, keeping the legacy watch surface
    out of this active port
  - no unused network permission is requested while the active Together surface
    remains local/mock
- ArkTS app entry and three-tab shell:
  - `pages/Index.ets`
  - `pages/HomePage.ets`
  - `pages/CatalogPage.ets`
  - `pages/TogetherPage.ets`
  - foreground refresh for rollover, decay catch-up, and health reconcile
  - foreground minute timer with a refresh reentrancy guard for in-foreground
    midnight rollover and long-running sessions
  - startup restore gate prevents onboarding actions before Preferences context
    and persisted state have been restored
  - Health Service Kit approval failure toast uses platform-facing copy and
    does not expose the internal Mock provider label
  - bottom tabs keep iOS-style icon + label semantics for Home, Catalog, and
    Together
- Shared design tokens:
  - `theme/LPTheme.ets` mirrors the iOS LP color palette, spacing scale, radius
    scale, border widths, and draft dash pattern
  - `components/PixelPetSprite.ets` ports the iOS 16x16 `PetSprite` rect
    tables for BEAN / BLOB / NOCT / HUSH static catalog portraits, plus the
    locked-slot pixel placeholder
  - `BreathingPixelPetSprite` ports the iOS 2.6s subtle breathing wrapper for
    live/detail/share catalog portraits
  - page-level transparent colors derived from LP tokens were updated away
    from the earlier approximate palette and are covered by `test_theme_tokens`
  - resource-level colors in `color.json` and `app_icon.svg` use the same
    current LP paper / ink / coral values
  - PetStage LCD colors remain the same iOS screen-local one-off tokens
- Onboarding flow:
  - Health Service Kit connect button
  - requesting and unavailable authorization states matching the iOS first
    launch view
  - Demo mode
  - Later path
  - action buttons now mirror iOS `LPButton` styling: ink primary, paper
    secondary, dashed ghost, 2pt radius, and 1.5pt stroke
  - benefit card now mirrors the iOS stamped-card padding, 1.5pt stroke, and
    2pt offset shadow
  - iOS benefit copy preserved; Health Service Kit permission scopes remain in
    `requiredHealthScopes` and documentation rather than user-facing debug copy
- Home feature parity baseline:
  - pet identity copy
  - two-stage hatch gate: pulsing egg wait state, tap-to-play hatch animation,
    then persist hatched state after sprite completion
  - six-state pet machine
  - pure pet derivation functions in `models/PetDerivation.ets`
  - pure rollover and 4-hour decay helpers in `models/PetLifecycle.ets`
  - one-shot feed particle feedback in `components/EnergyParticleField.ets`,
    using iOS-style 16-dot staggered eased/parabolic flight
  - one-shot pet shake feedback from `feedToken` in `components/PetStage.ets`;
    the LCD inner dash width and 160px sprite frame now match the SwiftUI
    stage geometry
  - vitality / energy / mood stat rows now mirror the current iOS layout:
    emoji label, circular decrement affordance, progress track, `value/100`
    readout, source/supplement copy, value-change bump feedback, and default
    stamped-card fill/padding/1.5pt stroke geometry
  - HealthEvent ingestion
  - workout pending sheet with Harmony `运动健康` source line, timing/kcal
    subtitle, and three gain cells matching the iOS sheet structure
  - workout pending sheet chrome now mirrors iOS top-rule-only treatment,
    handle spacing, 24pt content inset, 48pt bottom safe padding, button
    shadow, and gain-cell 1.5pt LCD cards
  - workout sheet dismissal model now matches iOS: feed button in the sheet,
    backdrop/outside dismiss handled by the root overlay, no extra inline
    "later" button
  - pending workout sheet is held until the hatch gate completes, matching the
    iOS first-launch layering behavior
  - done/suggest step cards with iOS heading/subline spacing, 7pt row spacing,
    exact stamped-card padding, 1.5pt stroke, 2pt offset shadow, auto-sensor
    tag, no extra empty-state copy, and stamped ✅ / ❌ actions
  - iOS quit-toast copy for "下次少推" and repeated-quit preference updates
  - reset confirmation dialog matching the iOS destructive/cancel flow
  - top meta and pet identity sections use iOS-style dashed separators, with
    the low-emphasis 22pt reset affordance and capsule demo shuffle button
    aligned to the current Home view
  - pet identity day label mirrors iOS split styling: muted prefix and bold
    coral day count
  - day rollover and 4h decay catch-up
  - toast and sparkle-burst timing split to match iOS: 2-second toast, 1.6-second
    pet burst, both guarded against stale clears; plain notification toasts do
    not trigger pet sparkle
  - root workout backdrop and toast chrome now mirror iOS opacity, capsule
    padding, 1.5pt stroke, and light shadow treatment
- Persistence baseline:
  - pet identity via Preferences with UUID-shaped pet ids and start-of-day
    birthDate restore semantics matching iOS
  - onboarding / hatch / demo / pending workout flags via Preferences
  - pending workout restore freshness matches iOS: discard cross-day or
    older-than-one-hour workout notifications
  - daily snapshot cache via Preferences
  - snapshot `recent` and inclusive `range` readers matching the iOS history
    store surface, including non-positive day handling and today-bounded
    recent windows
  - HRV baseline refresh from the last seven prior snapshot days, with the
    same three-sample threshold used by the iOS mood formula
  - reset and day-rollover snapshot sealing before a pet/day is cleared
- Resource migration:
  - PNG sprite frames copied to `entry/src/main/resources/rawfile/sprites`
  - memorial MP3s copied to `entry/src/main/resources/rawfile/audio`
- Catalog feature baseline:
  - list-to-detail navigation
  - list header mirrors iOS summary: alive / natural / early / total-days
    chips are computed from the live store overlay plus memorial pets, with
    iOS-style dashed rules above/below the row
  - header and sticky footer summary numbers now mirror iOS split muted/coral
    and sticky/coral styling
  - summary chips now use the iOS stamped-card 1.5pt stroke and 2pt offset
    shadow
  - section headers keep the iOS tag / dashed-rule / optional-count layout
  - live pet overlay from `PetStateStore`
  - live overlay now mirrors iOS semantics: authored sprite, trajectory, and
    moments remain static while name, days, and stats update from the store
  - catalog model sprite identity now uses `PetSpriteName` (`bean`, `blob`,
    `noct`, `hush`) instead of animation sequence names, and list/detail/share
    portraits render through `PixelPetSprite` / `BreathingPixelPetSprite` like
    iOS
  - past pets render in a 3-column grid with locked placeholder slots
  - locked placeholder slots now use the iOS `PixelPetLockedSprite` style
  - past pet cards use the iOS 44pt pixel portrait plus stamped 1.5pt
    stroke/shadow, and locked cards keep the matching dashed stroke
  - pet detail hero / stat row / story note
  - iOS catalog detail tag semantics: `LIVE` / `养育中`, `RARE`,
    `圆满` / `短命`, and muted `已升天`
  - detail back control, death moment marker, incense separator, and share
    button copy now track the current SwiftUI detail view
  - detail stat, trajectory, key-moment, and sticky story blocks now use the
    same iOS stamped-card 1.5pt strokes and offset shadows
  - detail share action now follows iOS `LPButton` typography, border, and 2pt
    radius while keeping the Harmony icon-text label
  - detail hero inner LCD dash, name tracking, memorial duration tracking,
    30pt play control, and stamped incense CTA chrome now mirror the current
    SwiftUI detail view
  - iOS-style life trajectory chart component with 0/50/100 gridlines, 30/85
    thresholds, three stat line series, D-day labels, today marker, and dashed
    death marker
  - iOS catalog mock moments and full bios ported for BEAN / BLOB / NOCT / HUSH
  - memorial waveform panel with Media Kit AVPlayer service and iOS-style
    150ms looping progress cursor; waveform bars are generated from each pet's
    vitality / energy / mood life series like the SwiftUI canvas
  - incense fullscreen overlay with 15-second playback timer, 60x165 iOS pixel
    incense geometry, animated tip, and four staggered smoke particles
  - incense overlay spacing, progress time letter spacing, and `收香` button
    padding/border now mirror the current SwiftUI overlay
  - screenshot-style share card overlay
  - share card faux QR now matches the iOS 21x21 seeded pattern and QR
    subtitle copy
  - share card pet hero size, D-day label width, QR title emphasis, and
    no-explicit-close sheet behavior now mirror current iOS
  - share card spacing, pet hero margins, day-label offset, moments inset,
    full-cell 21x21 QR grid, QR frame, footer faint token, toast chrome, and
    Xiaohongshu action button now follow the current iOS card/LPButton geometry
  - share card stats and QR sections use a reusable dashed rule matching the
    iOS separator style
  - share/save calls centralized in `ShareActionService`
  - system ShareKit share text path for catalog cards
  - SaveButton authorization entry for gallery save
  - component snapshot to PixelMap and `photoAccessHelper` gallery image write
- Together feature baseline:
  - friends sub-tab with 2-column cards
  - top segmented header mirrors the current iOS active coral underline and
    bottom-only 1.5pt ink rule
  - friend detail page with twin stage, dashed health compare rows, messages,
    quick chips, poke, and cheer actions
  - twin stage light band now uses an iOS-style 2.6s phase loop with four
    flowing particles and edge fade instead of a static dot row
  - twin stage, health compare, message input/card, and action buttons now use
    iOS-style 1.5pt strokes and stamped offset shadows where applicable
  - friend detail twin stage now mirrors iOS one-shot poke shake and cheer
    sparkle feedback instead of permanent name highlighting
  - friend detail message thread keeps the iOS 154pt max-height scroll area and
    scrolls to the newest local message
  - friend own-message bubbles use the current iOS coral fill
  - friend-detail and invite back controls keep the iOS coral chevron
  - friend-detail and invite toasts auto-dismiss after the iOS 1.6-second
    interval with stale-toast guards
  - iOS mock copy/emoji parity for friend messages and plaza values
  - Together friend/plaza model sprite identity now uses the same
    `PetSpriteName` enum as iOS, and cards/stage/plaza cells render through
    `PixelPetSprite` instead of live blob animation sequences
  - friends header `+ 添加` action now uses the iOS stamped offset button
  - friends list padding now matches the iOS 16pt horizontal / 12pt top inset
  - friend cards now use the iOS 52pt pet portrait, pet-name tracking, 1.5pt
    outer stroke, and 8pt new-message dot
  - invite page with code card, relation chips, and action toasts
  - relation chips are cosmetic local selection only, matching iOS behavior
  - invite action buttons and relation chips now use iOS-style stamped action
    shadows and natural chip widths
  - invite copy/share calls centralized in `ShareActionService`
  - invite code copy wired to the system pasteboard
  - invite share wired to the system ShareKit panel
  - invite copy/share success toasts mirror the current iOS mock copy while
    using Harmony platform clipboard/share APIs under the hood
  - plaza sticky-note banner rotation, ticking community stats, and pet grid
    with the live user's pet name
- Health data abstraction:
  - `HealthDataProvider`
  - `MockHealthDataService`
  - explicit required health scope list for onboarding and approval planning,
    matched to the iOS HealthMetric set
  - pure Huawei health sample mapper for approved daily snapshots, sleep
    stages, and workout samples
  - workout sample mapping records emitted ids so foreground reconciliation and
    future observer callbacks do not double-feed the same workout
  - `HealthProviderFactory` switch for Mock vs real Health Service Kit
  - `HuaweiHealthDataService` placeholder
- Local verification:
  - `tools/run_all_checks.mjs` runs every local verifier
  - `tools/check_ios_surface_scope.mjs` verifies the iOS routed app surface is
    still Home / Catalog / Together before treating placeholder features as
    out of active parity scope
  - `tools/check_port.mjs` validates project shell, API 20 config, JSON files,
    ArkTS brace balance, required app files, migrated sprite/audio assets, and
    core feature markers including pet derivation functions
  - `tools/check_arkts_this_methods.mjs` catches `this.*` references without a
    local method, getter, field, or callback before DevEco compilation
  - `tools/test_pet_derivation.mjs` executes the `PetDerivation.ets` source
    formulas through a Node VM test harness
  - `tools/test_date_utils.mjs` executes date/relative-time helper tests from
    `DateUtils.ets`
  - `tools/test_catalog_models.mjs` checks iOS catalog data parity, live
    overlay semantics, static pixel sprite identity, and detail tag semantics
  - `tools/test_catalog_trajectory.mjs` checks trajectory chart structure
    against the iOS Canvas behavior
  - `tools/test_health_models.mjs` checks Health scope/event parity with the
    iOS HealthMetric / HealthEvent set
  - `tools/test_huawei_health_mapper.mjs` executes the Huawei health sample
    mapper for daily metric snapshots, sleep sessioning, and workout bucketing
  - `tools/test_energy_particles.mjs` checks feed-particle count, easing,
    lift, and color semantics
  - `tools/test_home_components.mjs` checks Home top separators, reset/demo
    affordances, step-card copy, workout-sheet copy/structure parity, and
    current iOS Home debug/workout behaviors when present in the Swift source
  - `tools/test_onboarding_copy.mjs` checks iOS onboarding copy parity and rejects
    development-only Mock / approval-scope wording in user UI
  - `tools/test_pet_lifecycle.mjs` executes rollover and 4-hour decay helper
    tests from `PetLifecycle.ets` and checks root startup restore / foreground
    refresh timer wiring
  - `tools/test_snapshot_store.mjs` checks DailySnapshot field parity,
    today-bounded recent/range reader surface, HRV baseline wiring, and
    rollover snapshot sealing
  - `tools/test_share_actions.mjs` checks ShareKit, pasteboard, SaveButton,
    and catalog share-card pixel portrait source wiring
  - `tools/test_together_models.mjs` checks Together mock data, plaza parity,
    static pixel sprite identity, and current iOS segmented/friend-card chrome
  - `tools/check_release_ready.mjs` encodes release blockers and is expected to
    fail until real Health Service Kit and DevEco build gates are resolved
- Manual validation plan:
  - `DEVECO_VALIDATION.md` covers DevEco build, device smoke tests, Health
    Service Kit authorization, memorial playback, and share/save gates

## Release Gates Still Open

- `HuaweiHealthDataService` does not yet call Health Service Kit. It is blocked
  on project Client ID / service approval / exact data-scope configuration.
- Catalog memorial playback is wired through `MemorialAudioPlayer`, but has not
  been device-validated in DevEco Studio.
- Catalog and invite share paths call ShareKit, invite copy calls the system
  pasteboard, and catalog save captures the share card then writes a PNG to the
  gallery after SaveButton authorization. These platform paths still need
  DevEco/device validation.
- Together realtime syncing, invite pairing, and backend message delivery remain
  product follow-up work rather than iOS parity blockers: the current iOS
  Together surface is also mock data with scan/code-entry placeholders.
- DevEco / hvigor build validation has not been run because the HarmonyOS
  command-line build tools are unavailable in this environment.

## Verification Run Here

- `node tools/check_port.mjs` passed.
- `node tools/test_pet_derivation.mjs` passed.
- `node tools/test_date_utils.mjs` passed.
- `node tools/test_catalog_models.mjs` passed.
- `node tools/test_together_models.mjs` passed.
- `node tools/test_huawei_health_mapper.mjs` passed.
- `node tools/run_all_checks.mjs` passed.
- `node tools/check_release_ready.mjs` failed as expected with the current
  platform blockers.

## Next Engineering Steps

1. Open `HarmonyLifePet` in DevEco Studio with HarmonyOS 6.0+ SDK and fix any
   ArkTS compiler differences.
2. Replace `MockHealthDataService` with real Health Service Kit authorization
   and aggregate/read queries.
3. Device-test Media Kit / AVPlayer playback, ShareKit, pasteboard, and gallery
   save behavior.
4. Add DevEco/Hypium tests around `PetStateStore` persistence and UI workflows.
