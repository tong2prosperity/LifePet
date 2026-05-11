# Parity Audit

Objective: create a new HarmonyOS app directory and implement the Harmony app
until it matches the current iOS app's active product surface.

Current iOS root route: onboarding first, then three tabs: Home, Catalog,
Together.
`tools/check_ios_surface_scope.mjs` verifies this routed surface and fails if
Generation, Playback, or Session placeholders are promoted into the iOS app
shell.

## Evidence Checklist

| Requirement | HarmonyOS evidence | Status |
| --- | --- | --- |
| New HarmonyOS app directory | `HarmonyLifePet/` | Implemented |
| iOS routed-surface guard | `tools/check_ios_surface_scope.mjs` | Active parity scope is guarded against untracked iOS route changes |
| HarmonyOS 6.0+ target | `build-profile.json5` uses API 20 | Implemented |
| Stage model app shell | `AppScope/app.json5`, `entry/src/main/module.json5`, `EntryAbility.ets` | Implemented, not DevEco-built; device targets are phone/tablet/2in1, exclude the legacy watch/wearable surface, and do not request unused network permission while the active Together surface is local/mock |
| Shared design tokens | `theme/LPTheme.ets`, `resources/base/element/color.json`, entry/AppScope app icons, `tools/test_theme_tokens.mjs` | iOS LP colors, spacing, radius, border widths, draft dash pattern, app icon/resource colors, and PetStage LCD one-off colors are source-verified; ArkTS/resources are scanned to reject old approximate token literals |
| Root shell and tabs | `pages/Index.ets` | Onboarding gate, three-tab shell, icon+label tab semantics, and foreground refresh implemented |
| Startup and foreground lifecycle | `restored` gate, `onPageShow`, foreground minute timer, and refresh reentrancy guard in `pages/Index.ets` | Implemented baseline for startup restore before onboarding actions, return-to-foreground, in-foreground midnight rollover, decay catch-up, and health reconcile |
| Onboarding | `pages/OnboardingPage.ets`, Health scopes from `requiredHealthScopes`, `tools/test_onboarding_copy.mjs` | iOS benefit copy preserved; requesting/unavailable auth states mirrored; Health Service Kit naming replaces HealthKit; LPButton-style ink/secondary/dashed-ghost actions and stamped benefit card chrome are source-verified; development-only Mock/approval-scope wording is kept out of the user UI |
| Home tab | `pages/HomePage.ets`, `stores/PetStateStore.ets`, `models/PetModels.ets`, Home components, `tools/test_home_components.mjs` | Implemented; two-stage hatch flow with pulsing egg wait state, 160px sprite frame, 1.5pt LCD inner dash, top dashed separators, split muted/coral day label, 22pt reset affordance, capsule demo shuffle button, current iOS vertical stat rows with source/supplement copy, stamped geometry, and value bump feedback, iOS-spaced/stamped step cards, quit-toast, and workout-sheet top-rule/chrome/dismissal structure now aligned with iOS; the workout source line is localized to Harmony `运动健康` instead of leaking Apple Watch |
| Home feed feedback | `components/EnergyParticleField.ets`, `components/PetStage.ets`, `stores/PetStateStore.ets`, `feedToken` wiring in `HomePage.ets`, root toast in `Index.ets`, `tools/test_energy_particles.mjs`, `tools/test_home_components.mjs` | 16-dot staggered eased/parabolic particle flight, one-shot pet shake, 1.6s burst timing, 2s toast timing, and iOS-style toast/backdrop chrome are source-wired; not device-animated validated |
| Pet state machine | `stores/PetStateStore.ets`, `models/PetDerivation.ets`, `models/PetLifecycle.ets`, `tools/test_pet_derivation.mjs`, `tools/test_pet_lifecycle.mjs`, workout handling | Formula and pure lifecycle tests added; persistence/UI workflows still need DevEco test target |
| Persistence | `PetIdentityStore.ets`, `DailySnapshotStore.ets`, Preferences use, `PetStateStore.ets`, `tools/test_snapshot_store.mjs`, `tools/test_home_components.mjs` | Implemented baseline; identity IDs and birthDate restore semantics match iOS shape; DailySnapshot fields and recent/range readers match iOS storage surface, including today-bounded recent windows; pending workout restore freshness matches iOS; HRV baseline refresh and reset/day-rollover snapshot sealing are wired |
| Health data abstraction | `HealthDataProvider`, `MockHealthDataService`, `HealthProviderFactory`, `HuaweiHealthDataService`, `models/HuaweiHealthMapper.ets`, `tools/test_health_models.mjs`, `tools/test_huawei_health_mapper.mjs` | Scope/event set matches iOS HealthMetric/HealthEvent; approved daily/sleep/workout sample mapping is locally tested; workout emitted-id dedupe mirrors the iOS process-level guard; real SDK authorization/read adapter pending |
| Catalog tab list | `pages/CatalogPage.ets`, `models/CatalogModels.ets`, `components/DashedRule.ets`, `components/PixelPetSprite.ets`, `tools/test_catalog_models.mjs` | Implemented with iOS split-color header/footer summaries, stamped summary chips, dashed stats/section rules, live card with breathing pixel portrait and inner LCD dash, 3-column past grid, 44pt past-pet portraits, `PixelPetLockedSprite` locked placeholders, sticky footer copy, and static `PetSpriteName` pixel portraits |
| Catalog detail | `CatalogDetail` in `CatalogPage.ets`, `models/CatalogModels.ets`, `components/PixelPetSprite.ets`, `tools/test_catalog_models.mjs`, `tools/test_catalog_incense.mjs` | iOS mock moments/full bios ported; live overlay keeps authored sprite/series/moments like iOS; catalog portraits use the iOS 16x16 BEAN/BLOB/NOCT/HUSH rect tables and breathing wrapper instead of blob animation sequence names; detail tags now use iOS `LIVE`/`养育中`/`RARE`/`圆满`/`短命`/muted `已升天` semantics; detail stat/trajectory/moment/story blocks use iOS stamped-card strokes/shadows; back control, hero LCD dash/name tracking, death moment marker, memorial duration/play control, incense separator/CTA chrome, and LPButton-style share label mirror current iOS; memorial progress advances every 150ms and wraps like iOS while playing; waveform bars are derived from the pet life-series instead of a fixed mock list |
| Catalog trajectory chart | `components/CatalogTrajectoryChart.ets`, `tools/test_catalog_trajectory.mjs` | Reworked from bar trajectory to iOS-style three-line chart with threshold lines, today marker, and dashed death marker; still needs DevEco visual validation |
| Catalog share card | `components/CatalogShareOverlay.ets`, `components/DashedRule.ets`, `services/ShareActionService.ets`, `tools/test_share_actions.mjs` | Visual card, iOS-style pet hero/D-day/QR title/no-close behavior, iOS card spacing/pet hero margins/day-label offset/moments inset/QR frame/footer token/toast chrome, LPButton-style Xiaohongshu action, dashed separators, full-cell 21x21 seeded faux QR, ShareKit text share, SaveButton authorization, component snapshot, and gallery PNG write source-wired; DevEco/device validation pending |
| Catalog incense overlay | `components/CatalogIncenseOverlay.ets`, `tools/test_catalog_incense.mjs` | iOS 60x165 pixel incense geometry, glowing tip, four-particle smoke drift/envelope, overlay spacing, progress time letter spacing, `收香` button chrome, 15s progress, and data-driven memorial waveform are source-verified; device animation/audio validation pending |
| Memorial audio | `services/MemorialAudioPlayer.ets`, raw MP3 files | Wired, not device-validated |
| Together friends | `pages/TogetherPage.ets`, `models/TogetherModels.ets`, `components/DashedRule.ets`, `components/PixelPetSprite.ets`, `tools/test_together_models.mjs` | Implemented baseline with iOS segmented active underline and bottom-only 1.5pt rule, stamped `+ 添加` action, iOS list inset, 52pt friend pet portraits, pet-name tracking, 1.5pt card strokes, 8pt new-message dots, static BEAN/BLOB/NOCT/HUSH pixel portraits, back chevrons, twin-stage 2.6s flowing light band, 1.5pt LCD/message/compare strokes, stamped action buttons, poke shake and cheer sparkle feedback, message bubble/toast copy, max-height auto-scrolling message thread, dashed compare rows, mock copy/emoji, plaza sticky banner rotation, and auto-dismiss toast behavior |
| Friend detail | `FriendDetailPane` in `TogetherPage.ets` | Implemented baseline |
| Invite page | `InvitePane` in `TogetherPage.ets`, `services/ShareActionService.ets`, `tools/test_share_actions.mjs` | Implemented baseline; clipboard and ShareKit share are wired while success toasts mirror the current iOS mock copy; real pairing pending |
| Plaza page | `PlazaPane` in `TogetherPage.ets` | Implemented baseline with local ticker |
| Sprite/audio assets | `resources/rawfile/sprites`, `resources/rawfile/audio` | Copied |
| Local structural verification | `node tools/check_port.mjs`, `node tools/check_arkts_this_methods.mjs`, `node tools/test_catalog_models.mjs`, `node tools/test_catalog_incense.mjs`, `node tools/test_catalog_trajectory.mjs`, `node tools/test_health_models.mjs`, `node tools/test_huawei_health_mapper.mjs`, `node tools/test_energy_particles.mjs`, `node tools/test_home_components.mjs`, `node tools/test_onboarding_copy.mjs`, `node tools/test_pet_derivation.mjs`, `node tools/test_date_utils.mjs`, `node tools/test_pet_lifecycle.mjs`, `node tools/test_snapshot_store.mjs`, `node tools/test_share_actions.mjs`, `node tools/test_theme_tokens.mjs`, `node tools/test_together_models.mjs`, `node tools/run_all_checks.mjs` | Passed |
| Release readiness gate | `node tools/check_release_ready.mjs` | Expected failure until platform blockers are resolved |
| DevEco/device checklist | `DEVECO_VALIDATION.md` | Written; not executed |
| Build validation | `hvigor` / `hvigorw` unavailable in current environment | Not verified |

## Remaining Gaps

- Real `HuaweiHealthDataService` cannot be completed without approved app
  identity, Health Service Kit service access, data scopes, and a real device.
- Media Kit playback is wired but not validated with DevEco Studio or a device.
- Catalog and invite system share are source-wired through ShareKit; invite
  copy is source-wired through the system pasteboard; catalog save-to-gallery
  is source-wired through SaveButton, component snapshot, ImagePacker, and
  `photoAccessHelper`. These flows are not yet DevEco/device validated.
- Together backend syncing, invite pairing, and message delivery remain product
  follow-up work, not current iOS parity blockers; the routed iOS Together
  surface is also mock data with scan/code-entry placeholders.
- Pet formulas are extracted to `PetDerivation.ets`; rollover and decay are
  extracted to `PetLifecycle.ets`; both have local Node source harnesses.
  Persistence lifecycle wiring now covers pending-workout freshness, HRV
  baseline refresh, and reset/day-rollover snapshot sealing. Full UI workflows
  still need DevEco-compatible tests.

## Completion Decision

Do not mark the migration complete yet. The current directory is a functional
porting baseline, but real Health Service Kit integration and DevEco/device
validation are still open gates.
