# HarmonyLifePet

HarmonyOS 6.0+ / API 20+ ArkTS port of the iOS LifePet app.

This directory is intentionally independent from `LifePulse.xcodeproj`. The
first milestone mirrors the current iOS app's product surface:

- onboarding with Health Service Kit / demo / later choices
- home tab with LifePet state machine, health-derived stats, hatch flow,
  sprite animation, suggestions, pending workout ritual, and reset
- catalog tab with the current static memorial dataset overlaid by live pet
  values and iOS-style static pixel pet portraits
- together tab with mocked friends/plaza data and iOS-style static pixel pet
  portraits
- resources copied from the iOS asset catalog into `resources/rawfile`

Health Service Kit access is wrapped behind `HealthDataProvider`. Real health
reads require Huawei developer-console service approval and runtime user
authorization; until then `MockHealthDataService` keeps the app usable. See
`HEALTH_SERVICE_KIT.md` for the approval/runtime authorization split.

## Open In DevEco Studio

Open this `HarmonyLifePet` directory as a HarmonyOS project. The project is
scaffolded for a Stage model entry module:

```text
AppScope/
build-profile.json5
hvigorfile.ts
entry/
  build-profile.json5
  hvigorfile.ts
  src/main/ets/
  src/main/resources/
```

Use a HarmonyOS 6.0+ SDK. `compatibleSdkVersion` and `targetSdkVersion` are set
to `20` to match HarmonyOS 6.0.0(20) API 20.
The active port targets phone, tablet, and 2-in-1 devices. Wearable/watch
surfaces are intentionally out of scope for this directory, matching the
current iOS app rather than the legacy watch target.

See `MIGRATION_PLAN.md` for the iOS-to-HarmonyOS mapping and remaining platform
integration steps. See `PARITY_AUDIT.md` and `COMPLETION_AUDIT.md` for the
current evidence checklists against the iOS app surface. See
`DEVECO_VALIDATION.md` for the DevEco Studio and real-device gates that cannot
be verified in this repository environment.

## Local Checks

This repository environment does not include DevEco Studio or `hvigor`, but the
port includes a repeatable local verifier for structure, resources, JSON, and
feature coverage:

```bash
node tools/check_port.mjs
```

Pet derivation formulas can also be checked locally:

```bash
node tools/test_pet_derivation.mjs
```

Date/rollover helpers can be checked locally:

```bash
node tools/test_date_utils.mjs
```

Pet lifecycle rollover and 4-hour decay helpers can be checked locally:

```bash
node tools/test_pet_lifecycle.mjs
```

Catalog mock data and live-overlay parity with the iOS app can be checked
locally:

```bash
node tools/test_catalog_models.mjs
```

Catalog incense and memorial waveform parity can be checked locally:

```bash
node tools/test_catalog_incense.mjs
```

Catalog trajectory chart structure can be checked locally:

```bash
node tools/test_catalog_trajectory.mjs
```

Health scope/event parity with the iOS app can be checked locally:

```bash
node tools/test_health_models.mjs
```

Huawei health sample mapping can be checked locally:

```bash
node tools/test_huawei_health_mapper.mjs
```

Home step cards and workout sheet parity can be checked locally:

```bash
node tools/test_home_components.mjs
```

Home feed particle behavior can be checked locally:

```bash
node tools/test_energy_particles.mjs
```

Onboarding copy parity can be checked locally:

```bash
node tools/test_onboarding_copy.mjs
```

Snapshot storage shape and readers can be checked locally:

```bash
node tools/test_snapshot_store.mjs
```

Share, clipboard, and SaveButton wiring can be checked locally:

```bash
node tools/test_share_actions.mjs
```

Shared design token parity can be checked locally:

```bash
node tools/test_theme_tokens.mjs
```

Together mock data parity with the iOS app can be checked locally:

```bash
node tools/test_together_models.mjs
```

Or run every local check with:

```bash
node tools/run_all_checks.mjs
```

`tools/check_arkts_this_methods.mjs` is included in the full check suite and
catches `this.*` references that do not have a local method, getter, field, or
callback in the same ArkTS struct/class.

`tools/check_ios_surface_scope.mjs` verifies the current iOS `RootView` routed
surface is still Home / Catalog / Together. Experimental Generation,
Playback, and Session placeholders are not treated as active parity scope until
they are routed by the iOS app shell.

The same commands are also exposed from `oh-package.json5` as `check`,
`check:port`, `check:release`, `check:ios-scope`, `check:arkts`, `test:catalog`,
`test:catalog:incense`, `test:trajectory`, `test:date`, `test:derivation`,
`test:particles`, `test:lifecycle`, `test:health`, `test:health:mapper`,
`test:home`, `test:onboarding`, `test:snapshot`, `test:share`, `test:theme`,
and `test:together`.

There is also a release-readiness gate. It is expected to fail until real
Health Service Kit and DevEco build validation are resolved. System clipboard,
system share, and gallery image save are source-wired but still need DevEco
device validation:

```bash
node tools/check_release_ready.mjs
```
