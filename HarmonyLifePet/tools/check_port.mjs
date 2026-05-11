#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
let failures = 0;

function pass(message) {
  console.log(`ok  - ${message}`);
}

function fail(message) {
  failures += 1;
  console.error(`bad - ${message}`);
}

function exists(rel) {
  const file = path.join(root, rel);
  if (fs.existsSync(file)) {
    pass(`${rel} exists`);
    return true;
  }
  fail(`${rel} missing`);
  return false;
}

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function walk(dir, predicate) {
  const abs = path.join(root, dir);
  const out = [];
  for (const name of fs.readdirSync(abs)) {
    const file = path.join(abs, name);
    const stat = fs.statSync(file);
    if (stat.isDirectory()) {
      out.push(...walk(path.relative(root, file), predicate));
    } else if (predicate(file)) {
      out.push(path.relative(root, file));
    }
  }
  return out;
}

function checkJson(rel) {
  try {
    JSON.parse(read(rel));
    pass(`${rel} parses as JSON`);
  } catch (err) {
    fail(`${rel} parse failed: ${err.message}`);
  }
}

function checkNeedle(rel, needle, label) {
  if (!exists(rel)) {
    return;
  }
  const text = read(rel);
  if (text.includes(needle)) {
    pass(`${rel} contains ${label}`);
  } else {
    fail(`${rel} missing ${label}`);
  }
}

function checkAbsence(rel, needle, label) {
  if (!exists(rel)) {
    return;
  }
  const text = read(rel);
  if (!text.includes(needle)) {
    pass(`${rel} ${label}`);
  } else {
    fail(`${rel} unexpectedly contains ${needle}`);
  }
}

function checkBraceBalance(rel) {
  const src = read(rel);
  const stack = [];
  let line = 1;
  let col = 0;
  let str = null;
  let esc = false;
  let block = false;
  let lineComment = false;
  for (let i = 0; i < src.length; i += 1) {
    const ch = src[i];
    const next = src[i + 1];
    col += 1;
    if (ch === '\n') {
      line += 1;
      col = 0;
      lineComment = false;
      continue;
    }
    if (lineComment) {
      continue;
    }
    if (block) {
      if (ch === '*' && next === '/') {
        block = false;
        i += 1;
        col += 1;
      }
      continue;
    }
    if (str) {
      if (esc) {
        esc = false;
        continue;
      }
      if (ch === '\\') {
        esc = true;
        continue;
      }
      if (ch === str) {
        str = null;
      }
      continue;
    }
    if (ch === '/' && next === '/') {
      lineComment = true;
      i += 1;
      col += 1;
      continue;
    }
    if (ch === '/' && next === '*') {
      block = true;
      i += 1;
      col += 1;
      continue;
    }
    if (ch === '"' || ch === '\'' || ch === '`') {
      str = ch;
      continue;
    }
    if ('({['.includes(ch)) {
      stack.push([ch, line, col]);
    }
    if (')}]'.includes(ch)) {
      const last = stack.pop();
      const ok = last &&
        ((last[0] === '(' && ch === ')') ||
         (last[0] === '{' && ch === '}') ||
         (last[0] === '[' && ch === ']'));
      if (!ok) {
        fail(`${rel} brace mismatch at ${line}:${col}`);
        return;
      }
    }
  }
  if (stack.length > 0) {
    fail(`${rel} has unclosed bracket near ${stack.at(-1)[1]}:${stack.at(-1)[2]}`);
  } else {
    pass(`${rel} brace balance`);
  }
}

function countFiles(rel) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) {
    return 0;
  }
  return fs.readdirSync(abs).filter((name) => fs.statSync(path.join(abs, name)).isFile()).length;
}

[
  'README.md',
  'MIGRATION_PLAN.md',
  'MIGRATION_STATUS.md',
  'PARITY_AUDIT.md',
  'COMPLETION_AUDIT.md',
  'DEVECO_VALIDATION.md',
  'HEALTH_SERVICE_KIT.md',
  'tools/check_arkts_this_methods.mjs',
  'tools/check_ios_surface_scope.mjs',
  'tools/check_release_ready.mjs',
  'tools/run_all_checks.mjs',
  'tools/test_date_utils.mjs',
  'tools/test_catalog_incense.mjs',
  'tools/test_huawei_health_mapper.mjs',
  'tools/test_pet_derivation.mjs',
  'tools/test_theme_tokens.mjs',
  'build-profile.json5',
  'hvigorfile.ts',
  'AppScope/app.json5',
  'AppScope/resources/base/media/app_icon.svg',
  'entry/build-profile.json5',
  'entry/hvigorfile.ts',
  'entry/oh-package.json5',
  'entry/obfuscation-rules.txt',
  'entry/src/main/module.json5',
  'entry/src/main/ets/entryability/EntryAbility.ets',
  'entry/src/main/ets/pages/Index.ets',
  'entry/src/main/ets/pages/HomePage.ets',
  'entry/src/main/ets/pages/CatalogPage.ets',
  'entry/src/main/ets/pages/TogetherPage.ets',
  'entry/src/main/ets/pages/OnboardingPage.ets',
  'entry/src/main/ets/components/DashedRule.ets',
  'entry/src/main/ets/components/PixelPetSprite.ets',
  'entry/src/main/ets/components/PetStage.ets',
  'entry/src/main/ets/components/EnergyParticleField.ets',
  'entry/src/main/ets/models/PetSpriteModels.ets',
  'entry/src/main/ets/models/PetDerivation.ets',
  'entry/src/main/ets/models/PetLifecycle.ets',
  'entry/src/main/ets/models/HuaweiHealthMapper.ets',
  'entry/src/main/ets/stores/PetStateStore.ets',
  'entry/src/main/ets/services/HealthDataService.ets',
  'entry/src/main/ets/services/HealthProviderFactory.ets',
  'entry/src/main/ets/services/MemorialAudioPlayer.ets',
  'entry/src/main/ets/services/ShareActionService.ets'
].forEach(exists);

checkNeedle('hvigorfile.ts', "export { appTasks } from '@ohos/hvigor-ohos-plugin'", 'root hvigor app tasks');
checkNeedle('entry/hvigorfile.ts', "export { hapTasks } from '@ohos/hvigor-ohos-plugin'", 'entry hvigor hap tasks');
checkNeedle('oh-package.json5', '"check:release": "node tools/check_release_ready.mjs"', 'release readiness script');
checkNeedle('oh-package.json5', '"test:date": "node tools/test_date_utils.mjs"', 'date utility test script');
checkNeedle('oh-package.json5', '"test:catalog:incense": "node tools/test_catalog_incense.mjs"', 'catalog incense test script');
checkNeedle('oh-package.json5', '"test:theme": "node tools/test_theme_tokens.mjs"', 'theme token test script');

walk('.', (file) => /\.json5?$/.test(file)).forEach(checkJson);
const etsFiles = walk('entry/src/main/ets', (file) => file.endsWith('.ets'));
etsFiles.forEach(checkBraceBalance);
const etsSource = etsFiles.map(read).join('\n');
if (!etsSource.includes('APPLE WATCH') && !etsSource.includes('HealthKit')) {
  pass('Harmony ArkTS UI has no iOS-only Apple Watch/HealthKit labels');
} else {
  fail('Harmony ArkTS UI still contains iOS-only Apple Watch/HealthKit labels');
}
if (!etsSource.includes('.onClick(this.')) {
  pass('ArkTS click handlers use explicit lambdas instead of bare this callbacks');
} else {
  fail('ArkTS click handlers still contain bare this callbacks');
}

const rootProfile = JSON.parse(read('build-profile.json5'));
const product = rootProfile.app?.products?.[0];
if (product?.compatibleSdkVersion === '20' && product?.targetSdkVersion === '20') {
  pass('HarmonyOS API 20 target configured');
} else {
  fail('HarmonyOS API 20 target missing');
}

const moduleConfig = JSON.parse(read('entry/src/main/module.json5'));
const deviceTypes = moduleConfig.module?.deviceTypes ?? [];
if (deviceTypes.includes('phone') && deviceTypes.includes('tablet') && deviceTypes.includes('2in1') && !deviceTypes.includes('wearable')) {
  pass('Harmony target devices match the active iOS app surface, excluding legacy wearable');
} else {
  fail(`unexpected deviceTypes: ${JSON.stringify(deviceTypes)}`);
}
const permissions = moduleConfig.module?.requestPermissions ?? [];
const permissionNames = permissions.map((permission) => permission.name);
if (!permissionNames.includes('ohos.permission.INTERNET')) {
  pass('Harmony manifest avoids unused network permission for the current mock parity surface');
} else {
  fail('Harmony manifest still requests unused network permission');
}

const spriteExpectations = {
  'egg_hatch': 10,
  'blob_run': 8,
  'blob_walk': 8,
  'blob_lying': 6,
  'blob_sleep': 6
};
for (const [sprite, expected] of Object.entries(spriteExpectations)) {
  const actual = countFiles(`entry/src/main/resources/rawfile/sprites/${sprite}`);
  if (actual === expected) {
    pass(`${sprite} has ${expected} frames`);
  } else {
    fail(`${sprite} expected ${expected} frames, found ${actual}`);
  }
}

const audioCount = countFiles('entry/src/main/resources/rawfile/audio');
if (audioCount >= 6) {
  pass(`memorial audio files present (${audioCount})`);
} else {
  fail(`expected at least 6 memorial audio files, found ${audioCount}`);
}

checkNeedle('entry/src/main/ets/theme/LPTheme.ets', "static readonly paper: string = '#FAF7EF'", 'iOS paper token');
checkNeedle('entry/src/main/ets/theme/LPTheme.ets', "static readonly coral: string = '#D14B3D'", 'iOS coral token');
checkNeedle('entry/src/main/ets/theme/LPTheme.ets', 'export class LPSpacing', 'iOS spacing scale');
checkNeedle('entry/src/main/resources/base/element/color.json', '"value": "#FAF7EF"', 'iOS paper resource token');
checkNeedle('entry/src/main/resources/base/media/app_icon.svg', 'fill="#D14B3D"', 'iOS coral app icon token');
checkNeedle('AppScope/resources/base/media/app_icon.svg', 'fill="#D14B3D"', 'iOS coral AppScope app icon token');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'CatalogDetail', 'catalog detail');
checkNeedle('entry/src/main/ets/models/CatalogModels.ets', 'PetSpriteName.Bean', 'Catalog iOS bean sprite identity');
checkNeedle('entry/src/main/ets/models/CatalogModels.ets', 'PetSpriteName.Hush', 'Catalog iOS hush sprite identity');
checkAbsence('entry/src/main/ets/models/CatalogModels.ets', 'blob_run', 'Catalog models avoid run sequence identity');
checkAbsence('entry/src/main/ets/models/CatalogModels.ets', 'blob_lying', 'Catalog models avoid lying sequence identity');
checkAbsence('entry/src/main/ets/models/CatalogModels.ets', 'blob_sleep', 'Catalog models avoid sleep sequence identity');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 90 })', 'catalog detail breathing pixel sprite');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 60 })', 'catalog live card breathing pixel sprite');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'PixelPetSprite({ sprite: this.pet.sprite, size: 44 })', 'catalog grid static pixel sprite');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'private livePet(): CatalogPet', 'catalog list live overlay helper');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'pet: this.livePet()', 'catalog living card live overlay');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'series: base.series', 'iOS live overlay static series');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'moments: base.moments', 'iOS live overlay static moments');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'deathBucketLabel', 'iOS catalog tag buckets');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', '已升天', 'iOS catalog dead tag');
checkNeedle('entry/src/main/ets/components/CatalogTrajectoryChart.ets', 'LineSeries', 'iOS-style trajectory line series');
checkNeedle('entry/src/main/ets/components/CatalogTrajectoryChart.ets', 'GridLine({ value: 85', 'trajectory high threshold');
checkNeedle('entry/src/main/ets/components/CatalogTrajectoryChart.ets', 'GridLine({ value: 30', 'trajectory low threshold');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'MemorialPanel', 'memorial panel');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'MemorialWaveform({ pet: this.pet', 'data-driven memorial waveform');
checkNeedle('entry/src/main/ets/components/CatalogShareOverlay.ets', 'FauxQr', 'share QR');
checkNeedle('entry/src/main/ets/components/CatalogIncenseOverlay.ets', 'CatalogIncenseOverlay', 'incense overlay');
checkNeedle('entry/src/main/ets/components/CatalogIncenseOverlay.ets', 'private smokeParticles(): SmokeParticle[]', 'iOS-style incense smoke particles');
checkNeedle('entry/src/main/ets/components/CatalogIncenseOverlay.ets', "PixelRect({ x: 29, y: 34, w: 2, h: 12, color: '#B8B090' })", 'iOS incense pixel geometry');
checkNeedle('entry/src/main/ets/pages/TogetherPage.ets', 'FriendDetailPane', 'friend detail');
checkNeedle('entry/src/main/ets/pages/TogetherPage.ets', 'InvitePane', 'invite flow');
checkNeedle('entry/src/main/ets/pages/TogetherPage.ets', 'PlazaPane', 'plaza flow');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'case PetSpriteName.Bean', 'iOS bean pixel sprite');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'case PetSpriteName.Blob', 'iOS blob pixel sprite');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'case PetSpriteName.Noct', 'iOS noct pixel sprite');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'case PetSpriteName.Hush', 'iOS hush pixel sprite');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'export struct PixelPetLockedSprite', 'iOS locked pixel sprite');
checkNeedle('entry/src/main/ets/components/PixelPetSprite.ets', 'export struct BreathingPixelPetSprite', 'iOS breathing pixel sprite wrapper');
checkNeedle('entry/src/main/ets/pages/CatalogPage.ets', 'PixelPetLockedSprite({ size: 44 })', 'catalog locked card static placeholder sprite');
checkNeedle('entry/src/main/ets/models/TogetherModels.ets', 'PetSpriteName.Blob', 'Together iOS sprite identity enum');
checkAbsence('entry/src/main/ets/models/TogetherModels.ets', 'blob_run', 'Together models avoid animation sequence identity');
checkAbsence('entry/src/main/ets/models/TogetherModels.ets', 'blob_walk', 'Together models avoid walk sequence identity');
checkAbsence('entry/src/main/ets/models/TogetherModels.ets', 'blob_lying', 'Together models avoid lying sequence identity');
checkAbsence('entry/src/main/ets/models/TogetherModels.ets', 'blob_sleep', 'Together models avoid sleep sequence identity');
checkNeedle('entry/src/main/ets/pages/TogetherPage.ets', 'setTimeout(() => {', 'Together auto-dismiss toast timing');
checkNeedle('entry/src/main/ets/pages/TogetherPage.ets', 'if (this.toast === text)', 'Together stale-toast guard');
checkNeedle('entry/src/main/ets/models/TogetherModels.ets', '早安~ 今天慢跑加油 🏃', 'iOS Together message copy');
checkNeedle('entry/src/main/ets/models/TogetherModels.ets', '来！20 点见 💪', 'iOS Together emoji copy');
checkNeedle('entry/src/main/ets/components/EnergyParticleField.ets', 'EnergyParticleField', 'home feed particles');
checkNeedle('entry/src/main/ets/components/EnergyParticleField.ets', 'particleCount: number = 16', 'iOS feed particle count');
checkNeedle('entry/src/main/ets/components/EnergyParticleField.ets', 'const lift = -28 * 4 * t * (1 - t)', 'feed particle parabolic lift');
checkNeedle('entry/src/main/ets/components/PetStage.ets', "@Watch('onFeedTokenChanged')", 'iOS feed shake token');
checkNeedle('entry/src/main/ets/components/PetStage.ets', 'private shakeOffsetX()', 'feed shake offset');
checkNeedle('entry/src/main/ets/components/PetStage.ets', 'hatchPlaying', 'two-stage hatch gate');
checkNeedle('entry/src/main/ets/components/PetStage.ets', 'onCompleted: () => this.finishHatch()', 'hatch completion callback');
checkNeedle('entry/src/main/ets/components/SpriteAnimator.ets', '.onFinish(() =>', 'one-shot sprite completion');
checkNeedle('entry/src/main/ets/pages/HomePage.ets', '重置后会回到首启流程', 'iOS reset confirmation');
checkNeedle('entry/src/main/ets/components/StepsSection.ets', '打 ✅ 它开心', 'iOS steps section copy');
checkNeedle('entry/src/main/ets/components/StepsSection.ets', '⚡ 手表自动', 'automatic sensor step tag');
checkNeedle('entry/src/main/ets/components/WorkoutSheet.ets', '运动健康 · 刚刚同步', 'Harmony workout sheet source copy');
checkNeedle('entry/src/main/ets/components/WorkoutSheet.ets', 'GainCell', 'workout sheet gain cells');
checkNeedle('entry/src/main/ets/models/PetModels.ets', 'stepKindQuitLabel', 'iOS quit label mapping');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', '已跳过 · 下次少推', 'iOS quit skip toast copy');
checkNeedle('entry/src/main/ets/pages/Index.ets', 'foregroundRefresh', 'foreground refresh');
checkNeedle('entry/src/main/ets/pages/Index.ets', "tabBar('⌂ 主页')", 'home tab icon label');
checkNeedle('entry/src/main/ets/pages/Index.ets', "tabBar('▦ 图鉴')", 'catalog tab icon label');
checkNeedle('entry/src/main/ets/pages/Index.ets', "tabBar('👥 一起')", 'together tab icon label');
checkNeedle('entry/src/main/ets/pages/Index.ets', 'if (!this.restored)', 'root restore gate before onboarding');
checkNeedle('entry/src/main/ets/pages/Index.ets', 'void this.restoreAndReconcile()', 'root restore promise is fire-and-forget explicitly');
checkNeedle('entry/src/main/ets/pages/OnboardingPage.ets', '步数 / 运动 / 卡路里', 'iOS onboarding benefit copy');
checkNeedle('entry/src/main/ets/pages/OnboardingPage.ets', 'HealthAuthState.Requesting', 'onboarding requesting state');
checkNeedle('entry/src/main/ets/pages/OnboardingPage.ets', 'HealthAuthState.Unavailable', 'onboarding unavailable state');
checkAbsence('entry/src/main/ets/pages/OnboardingPage.ets', 'Mock 数据', 'onboarding hides internal Mock-provider wording');
checkAbsence('entry/src/main/ets/pages/OnboardingPage.ets', '开发版', 'onboarding hides development-only wording');
checkAbsence('entry/src/main/ets/pages/OnboardingPage.ets', 'Health Service Kit 申请范围', 'onboarding hides developer approval scope summary');
checkNeedle('entry/src/main/ets/pages/Index.ets', 'Health Service Kit 需要开发者平台审批后才能读取真实数据', 'platform approval toast uses user-facing Health Service Kit copy');
checkAbsence('entry/src/main/ets/pages/Index.ets', 'Mock Health', 'root approval toast hides internal Mock provider label');
checkNeedle('entry/src/main/ets/pages/Index.ets', 'healthAuthState: HealthAuthState', 'root health auth state bridge');
checkNeedle('HEALTH_SERVICE_KIT.md', '2026-05-11 核查', 'dated official Health Service Kit research');
checkNeedle('HEALTH_SERVICE_KIT.md', '2026-05-11 二次复核', 'second official Health Service Kit research pass');
checkNeedle('HEALTH_SERVICE_KIT.md', '不能直接复制到\n  HarmonyOS Stage 模型 ArkTS 工程', 'Health Codelab platform limitation documented');
checkNeedle('HEALTH_SERVICE_KIT.md', 'https://developer.huawei.com/consumer/cn/hms/huaweihealth/', 'official Health Service Kit product source');
checkNeedle('HEALTH_SERVICE_KIT.md', 'https://developer.huawei.com/consumer/cn/codelab/HUAWEIHiHealthCore/index.html', 'official Health Kit approval Codelab source');
checkNeedle('HEALTH_SERVICE_KIT.md', 'LifePet 申请时不要请求全部权限', 'least-privilege Health Service Kit application guidance');
checkNeedle('DEVECO_VALIDATION.md', 'Current Local Probe', 'DevEco tooling probe documented');
checkNeedle('DEVECO_VALIDATION.md', '`command -v hvigor` returned no path', 'hvigor absence documented');
checkNeedle('DEVECO_VALIDATION.md', '`command -v ohpm` returned no path', 'ohpm absence documented');
checkNeedle('DEVECO_VALIDATION.md', 'Confirm the approved data permissions match `requiredHealthScopes`', 'Health Service Kit approval validation gate');
checkNeedle('entry/src/main/ets/services/HealthDataService.ets', 'requiredHealthScopes', 'required health scopes');
checkNeedle('entry/src/main/ets/services/HealthDataService.ets', "id: 'exerciseMinutes'", 'exercise minutes health scope');
checkNeedle('entry/src/main/ets/services/HealthDataService.ets', "id: 'standMinutes'", 'stand minutes health scope');
checkNeedle('entry/src/main/ets/services/HealthDataService.ets', "id: 'restingHR'", 'resting heart-rate health scope');
checkNeedle('entry/src/main/ets/models/HuaweiHealthMapper.ets', 'mapDailySnapshot', 'Huawei daily health mapper');
checkNeedle('entry/src/main/ets/models/HuaweiHealthMapper.ets', 'mapSleepSamples', 'Huawei sleep stage mapper');
checkNeedle('entry/src/main/ets/models/HuaweiHealthMapper.ets', 'bucketHuaweiWorkoutActivity', 'Huawei workout bucket mapper');
checkNeedle('entry/src/main/ets/services/HealthDataService.ets', 'mapApprovedSamples', 'Huawei provider mapper boundary');
checkNeedle('entry/src/main/ets/services/HealthProviderFactory.ets', 'createHealthProvider', 'health provider factory');
checkNeedle('entry/src/main/ets/models/PetDerivation.ets', 'deriveStats', 'pet derivation functions');
checkNeedle('entry/src/main/ets/models/PetLifecycle.ets', 'computeDecayCatchup', 'pet lifecycle helpers');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', 'computeDecayCatchup', 'tested decay helper wiring');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', 'shouldResetForNewDay', 'tested rollover helper wiring');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', 'private triggerBurst()', 'iOS 1.6s burst window');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', 'private toastToken', 'toast stale-message guard');
checkNeedle('entry/src/main/ets/stores/PetStateStore.ets', 'age <= 60 * 60 * 1000 && sameDay', 'pending workout restore freshness');
checkNeedle('entry/src/main/ets/services/DailySnapshotStore.ets', 'range(petId: string, from: number, through: number)', 'snapshot range reader');
checkNeedle('entry/src/main/ets/services/MemorialAudioPlayer.ets', 'media.createAVPlayer', 'AVPlayer integration');
checkNeedle('entry/src/main/ets/services/ShareActionService.ets', 'shareCatalogCard', 'share action boundary');
checkNeedle('entry/src/main/ets/services/ShareActionService.ets', 'pasteboard.getSystemPasteboard', 'clipboard integration');
checkNeedle('entry/src/main/ets/services/ShareActionService.ets', 'systemShare.ShareController', 'system share integration');
checkNeedle('entry/src/main/ets/services/ShareActionService.ets', 'photoAccessHelper.getPhotoAccessHelper', 'gallery save integration');
checkNeedle('entry/src/main/ets/services/ShareActionService.ets', 'imagePackerApi.packToFile', 'image packer save integration');
checkNeedle('entry/src/main/ets/components/CatalogShareOverlay.ets', 'SaveButton', 'system save authorization button');
checkNeedle('entry/src/main/ets/components/CatalogShareOverlay.ets', "componentSnapshot.get('catalog-share-card')", 'share card snapshot capture');

if (failures > 0) {
  console.error(`\n${failures} check(s) failed.`);
  process.exit(1);
}

console.log('\nHarmonyLifePet local port checks passed.');
