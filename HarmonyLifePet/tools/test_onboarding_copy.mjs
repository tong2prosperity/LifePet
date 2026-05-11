#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/OnboardingPage.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const needles = [
  '先把你身体里的小生物\\n接进来。',
  '你不是喂宠物，你的身体就是宠物的食物。',
  'LifePet 会读取（不写入）',
  '步数 / 运动 / 卡路里',
  '睡眠 · 深睡 · REM',
  'HRV / 心率 / 冥想',
  '已完成的运动',
  '→ 体力',
  '→ 精力',
  '→ 心情',
  '→ 自动打勾今日卡片',
  '连接 Health Service Kit',
  '当前设备不支持 Health Service Kit · 仅 Demo 模式可用',
  '等你授权…',
  '用 Demo 数据继续',
  '以后再说'
];

for (const needle of needles) {
  assertSource(source.includes(needle), `Onboarding keeps iOS/Harmony copy: ${needle}`);
}

assertSource(source.includes('authState: HealthAuthState'), 'Onboarding receives Health Service Kit auth state');
assertSource(source.includes('HealthAuthState.Unavailable'), 'Onboarding mirrors the iOS unavailable state');
assertSource(source.includes('HealthAuthState.Requesting'), 'Onboarding mirrors the iOS requesting state');
assertSource(source.includes('LoadingProgress()'), 'Onboarding shows a progress indicator while requesting authorization');
assertSource(source.includes('enum OnboardingActionVariant'), 'Onboarding uses explicit LPButton-style action variants');
assertSource(source.includes('OnboardingActionButton({') && source.includes('variant: OnboardingActionVariant.Primary'), 'Onboarding actions render through the shared LPButton-style component');
assertSource(source.includes('.backgroundColor(this.isPrimary() ? LPColor.ink') && source.includes('.fontColor(this.isPrimary() ? LPColor.paper : LPColor.ink)'), 'Onboarding primary action uses the iOS ink fill and paper label');
assertSource(source.includes('style: this.isGhost() ? BorderStyle.Dashed : BorderStyle.Solid'), 'Onboarding ghost action keeps the iOS dashed LPButton border');
assertSource(source.includes(".padding({ left: 11, right: 11, top: 9, bottom: 8 })") && source.includes('.border({ width: 1.5, color: LPColor.ink })') && source.includes('offsetX: 2, offsetY: 2'), 'Onboarding benefit card mirrors iOS stamped-card padding/stroke/offset');
assertSource(!source.includes('.onClick(this.on'), 'Onboarding button callbacks use explicit ArkTS lambdas');
assertSource(!source.includes('Health Service Kit 申请范围'), 'Onboarding does not expose developer approval scope summary in user UI');
assertSource(!source.includes('Mock 数据'), 'Onboarding does not expose internal Mock-provider wording in user UI');
assertSource(!source.includes('开发版'), 'Onboarding does not expose development-only wording in user UI');
assertSource(!source.includes('.backgroundColor(LPColor.coral)\n              .fontColor(Color.White)'), 'Onboarding primary action no longer uses non-iOS coral button styling');

if (failures.length > 0) {
  console.error('Onboarding copy checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Onboarding copy checks passed.');
