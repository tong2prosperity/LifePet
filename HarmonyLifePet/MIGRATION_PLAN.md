# LifePet iOS to HarmonyOS Migration Plan

Target: HarmonyOS 6.0+ / API 20+, Stage model, ArkTS, ArkUI.

## Current iOS Product Logic

- App shell: onboarding, home, catalog, and together tabs.
- Home: `PetStateStore` derives LifePet state from HealthKit-style events,
  daily decay, hatch state, pending workouts, and persisted snapshots.
- Catalog: live pet overlay plus memorial history, detail page, trajectory
  chart, share card, and incense/memorial flow.
- Together: mocked friend spaces, invite flow, health comparison, messages, and
  plaza community view.
- Services: HealthKit abstraction, identity storage, snapshot history, local
  logging, playback, and persistence.

## HarmonyOS Mapping

- Stage model package shell:
  - `AppScope/app.json5`
  - `entry/src/main/module.json5`
  - `entry/src/main/ets/entryability/EntryAbility.ets`
- ArkTS UI:
  - iOS SwiftUI screens become ArkUI components in `entry/src/main/ets/pages`
    and `entry/src/main/ets/components`.
  - LP design tokens are mirrored in `theme/LPTheme.ets`.
- State and persistence:
  - `PetStateStore.ets` ports the iOS pet state machine.
  - `PetIdentityStore.ets` and `DailySnapshotStore.ets` use Preferences.
- Assets:
  - Sprite PNGs and memorial MP3s live under
    `entry/src/main/resources/rawfile`.
- Health data:
  - `HealthDataProvider` keeps UI/business logic independent from Health
    Service Kit.
  - `MockHealthDataService` supports development before approval.
  - `HuaweiHealthDataService` is the replacement point for real Health Service
    Kit authorization and reads.

## Required Platform Work

1. Install DevEco Studio with HarmonyOS 6.0+ SDK and API 20.
2. Create/select a HarmonyOS app in AppGallery Connect using the final bundle
   name and signing identity.
3. Open `HarmonyLifePet` in DevEco Studio and let hvigor sync dependencies.
4. Apply for Health Service Kit access and select only the required data scopes.
5. Add any generated app/service configuration files that Huawei requires for
   the approved app identity.
6. Switch `ACTIVE_HEALTH_PROVIDER` in `HealthProviderFactory.ets` to
   `HealthProviderMode.Huawei`, then replace `HuaweiHealthDataService`
   placeholder with real authorization, aggregate/read queries, revocation
   handling, and error mapping.
7. Device-test Media Kit playback for memorial MP3 files.
8. Replace `ShareActionService` local feedback with platform save-to-gallery,
   clipboard, and system share intents for catalog share cards and invite cards.
9. Validate on a real HarmonyOS 6.0+ device with a Huawei account and Health
   Service Kit data source.

## Health Service Kit Approval Boundary

You can develop the app before service approval. The approval blocks only real
access to Huawei health data. UI, pet formulas, storage, mock data, catalog,
together flows, and most local integration can be completed first.

The app still needs runtime user authorization after platform access is
approved. Treat these as two separate states:

- platform not approved / not configured
- approved but user denied or revoked runtime authorization

Both should keep the app usable through demo/later modes.
