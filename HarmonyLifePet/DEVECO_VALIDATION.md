# DevEco / Device Validation Checklist

Use this after opening `HarmonyLifePet` in DevEco Studio with HarmonyOS 6.0+
SDK / API 20.

## Current Local Probe

Checked on 2026-05-11 from the repository shell:

- `command -v hvigor` returned no path.
- `command -v hvigorw` returned no path.
- `command -v ohpm` returned no path.

So this workspace can run source-level Node checks, but cannot perform a real
DevEco/hvigor build until DevEco Studio or the HarmonyOS command-line tooling
is installed and added to `PATH`.

## Build Gates

1. Open the `HarmonyLifePet` directory as a HarmonyOS project.
2. Confirm SDK selection:
   - compatible SDK: API 20
   - target SDK: API 20
   - runtime OS: HarmonyOS
3. Sync hvigor.
4. Build the `entry` module.
5. Fix ArkTS compiler differences found by DevEco.
6. Run on a HarmonyOS 6.0+ device.

## Smoke Test Gates

1. First launch shows onboarding.
2. Onboarding lists Health Service Kit read scopes.
3. "用 Demo 数据继续" enters the app.
4. Home tab:
   - pet hatches
   - stats render
   - state can cycle in demo mode
   - suggestions and pending workout sheet render
5. Catalog tab:
   - live pet card opens detail
   - dead pet card opens detail
   - trajectory chart renders
   - share card overlay opens and closes
   - incense overlay opens and closes
   - memorial audio plays and stops
6. Together tab:
   - friends/plaza segmented switch works
   - friend detail opens and returns
   - message input appends a local bubble
   - invite page opens and relation chips toggle
   - plaza grid includes the current pet name

## Health Service Kit Gates

Do this only after AppGallery Connect service access is approved.

1. Configure the approved app identity, Client ID, signing certificate, and
   any generated service config required by Huawei.
2. Confirm the approved data permissions match `requiredHealthScopes`; do not
   request broad sample/Codelab-only scopes that are not tied to a visible
   LifePet feature.
3. Switch `ACTIVE_HEALTH_PROVIDER` in `HealthProviderFactory.ets` from
   `HealthProviderMode.Mock` to `HealthProviderMode.Huawei`.
4. Initialize Health Service Kit from the UIAbility context.
5. Request runtime authorization for the scopes listed in
   `requiredHealthScopes`.
6. Verify denied / revoked / unavailable states keep Demo and Later paths
   usable.
7. Verify real data reconciliation maps to `HealthEvent`:
   - steps
   - exercise minutes
   - active energy
   - heart rate
   - HRV
   - resting heart rate
   - sleep total/deep/REM/start
   - mindful minutes
   - workout finished

## Release-Blocking Items

- DevEco build must pass.
- Device smoke tests must pass.
- Health Service Kit real authorization and read queries must pass.
- Memorial AVPlayer playback must be validated on device.
- Share-to-system and save-to-gallery behavior must be wired or removed from
  release UI.
