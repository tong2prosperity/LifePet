#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const repoRoot = path.resolve(root, '..');
const home = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/HomePage.ets'), 'utf8');
const index = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
const petStage = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/PetStage.ets'), 'utf8');
const store = fs.readFileSync(path.join(root, 'entry/src/main/ets/stores/PetStateStore.ets'), 'utf8');
const steps = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/StepsSection.ets'), 'utf8');
const workout = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/WorkoutSheet.ets'), 'utf8');
const statTriad = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/StatTriad.ets'), 'utf8');
const petModels = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/PetModels.ets'), 'utf8');
const iosHome = fs.readFileSync(path.join(repoRoot, 'LifePulse/Features/Home/HomeView.swift'), 'utf8');
const iosStore = fs.readFileSync(path.join(repoRoot, 'LifePulse/Features/Home/PetStateStore.swift'), 'utf8');
const iosStatsTriad = fs.readFileSync(path.join(repoRoot, 'LifePulse/Features/Home/StatsTriadView.swift'), 'utf8');
const iosWorkout = fs.readFileSync(path.join(repoRoot, 'LifePulse/Features/Home/WorkoutAlertSheet.swift'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function assertWhenIos(conditionInIos, conditionInHarmony, message) {
  if (conditionInIos) {
    assertSource(conditionInHarmony, message);
  }
}

assertWhenIos(
  iosHome.includes('onDecrement: { kind in store.debugDecrement(kind) }'),
  home.includes('onDecrement: (kind: StatKind) => this.store.debugDecrement(kind)'),
  'HomePage mirrors current iOS debug decrement wiring when present'
);
assertWhenIos(
  iosStatsTriad.includes('DecrementButton') && iosStatsTriad.includes('onDecrement?(stat.kind)'),
  statTriad.includes("Button('−')") && statTriad.includes('this.onDecrement(this.stat.kind)'),
  'StatTriad mirrors current iOS decrement control when present'
);
assertWhenIos(
  iosStore.includes('func debugDecrement') && iosStore.includes('decayPending[kind, default: 0] += amount'),
  store.includes('debugDecrement(kind: StatKind)') && store.includes('this.addDecay(kind, 5)'),
  'PetStateStore mirrors current iOS debug decrement decay persistence when present'
);
assertWhenIos(
  iosWorkout.includes('GainCell(label: "精力", value: "+\\(workout.gainVitality)", unit: "PTS", isPositive: true)') &&
    iosWorkout.includes('GainCell(label: "心情", value: "+\\(workout.gainVitality)", unit: "PTS", isPositive: true)'),
  workout.includes("GainCell({ label: '精力', value: `+${this.workout.gainVitality}`, unit: 'PTS' })") &&
    workout.includes("GainCell({ label: '心情', value: `+${this.workout.gainVitality}`, unit: 'PTS' })"),
  'WorkoutSheet mirrors current iOS all-stat workout gains when present'
);

[
  '今日步骤',
  '已完成 ·',
  '建议',
  '打 ✅ 它开心，打 ❌ 不扣分 —— 但它会记住，下次少推。',
  '✅',
  '🎯',
  '可获得',
  '⚡ 手表自动',
  'MiniActionButton'
].forEach((needle) => assertSource(steps.includes(needle), `StepsSection keeps iOS home copy/structure: ${needle}`));
[
  "import { DashedRule } from './DashedRule';",
  'DashedRule({ color: LPColor.lcdDash })',
  '.fontSize(17)',
  '.fontColor(LPColor.faint)',
  'Column({ space: 0 })',
  '.margin({ left: 2, top: 4, bottom: 10 })',
  'Column({ space: 7 })',
  '.padding({ left: 12, right: 12, top: 8, bottom: 8 })',
  '.border({ width: 1.5, color: LPColor.ink, style: this.item.status === StepStatus.Suggest ? BorderStyle.Dashed : BorderStyle.Solid })',
  '.borderRadius(10)',
  '.shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })',
  '.fontSize(7.5)',
  '.border({ width: 1, color: LPColor.hairline })',
  '.margin({ top: -4, right: 8 })',
  '.translate({ x: 2, y: 2 })',
  '.border({ width: 1.5, color: LPColor.ink })'
].forEach((needle) => assertSource(steps.includes(needle), `StepsSection mirrors current iOS heading/time treatment: ${needle}`));
assertSource(!steps.includes('等待健康数据同步，或先用 Demo 数据继续。'), 'StepsSection does not add a non-iOS empty-state card');

[
  "import { DashedRule } from '../components/DashedRule'",
  'showResetConfirm',
  '重置后会回到首启流程',
  '当前所有 stats、卡片和孵化记录都会清掉。',
  '重新开始',
  'this.store.reset()',
  'Button(\'↻\')',
  '.width(22)',
  '.height(22)',
  '.borderRadius(11)',
  'Button(\'⇄ 换一换\')',
  '.borderRadius(16)',
  ".shadow({ radius: 3, color: '#33000000', offsetY: 2 })",
  'feedToken: this.store.feedToken',
  'onDecrement: (kind: StatKind) => this.store.debugDecrement(kind)',
  '.opacity(this.store.hatched ? 1 : 0.3)',
  '.enabled(this.store.hatched)',
  'if (this.store.hatched)',
  "Text('已陪伴 ')",
  'Text(`第 ${this.store.dayCount} 天`)',
  '.letterSpacing(1)',
  '.letterSpacing(0.5)'
].forEach((needle) => assertSource(home.includes(needle), `HomePage keeps iOS reset/feed wiring: ${needle}`));
assertSource((home.match(/DashedRule\(\{ color: LPColor\.lcdDash \}\)/g) ?? []).length >= 2, 'HomePage mirrors iOS dashed separators below top meta and pet identity');
assertSource(home.includes("Text('已陪伴 ')\n                    .fontSize(10)") && home.includes('Text(`第 ${this.store.dayCount} 天`)\n                    .fontSize(11)\n                    .fontWeight(FontWeight.Bold)'), 'HomePage mirrors iOS split muted day-prefix and bold coral day-count');

[
  'StatRow({ stat, onDecrement',
  'Text(`${statEmoji(this.stat.kind)} ${statLabel(this.stat.kind)}`)',
  "Button('−')",
  'Progress({ value: this.clampedValue(), total: 100, type: ProgressType.Linear })',
  "Text('/100')",
  "@Watch('onStatChanged')",
  'this.bumpScale = 1.3',
  "this.bumpColor = '#3EB24E'",
  '}, 200);',
  ".border({ width: 1, color: '#6E665A80' })",
  '.scale({ x: this.bumpScale, y: this.bumpScale })',
  '.fontColor(LPColor.faint)',
  ".padding({ top: 9, left: 11, bottom: 8, right: 11 })",
  '.backgroundColor(LPColor.paperCool)',
  '.border({ width: 1.5, color: LPColor.ink })',
  '.borderRadius(10)',
  '来自手表 · ${statSourceCopy(this.stat.kind)}',
  "Text('↑ 补充 · ')",
  'statSupplementCopy(this.stat.kind)',
  'this.stat.kind === StatKind.Mood ? LPColor.coral : LPColor.ink'
].forEach((needle) => assertSource(statTriad.includes(needle), `StatTriad mirrors current iOS vertical stat row: ${needle}`));
assertSource(statTriad.includes('statEmoji'), 'StatTriad labels match current iOS StatKind.label emoji prefixes');

[
  '步数 · 运动分钟 · 活动卡路里',
  '总睡眠 · 深睡 · REM',
  'HRV · 心率稳定度',
  '走 1000 步 +4 / 运动 10 分钟 +10',
  '每睡 1 小时 +6 / 深睡多 30 分钟 +15',
  '冥想 5 分钟 +15 / 深呼吸 1 次 +3'
].forEach((needle) => assertSource(petModels.includes(needle), `PetModels keeps iOS stat copy: ${needle}`));

[
  'this.store.hatched && this.store.pendingWorkout',
  ".backgroundColor('#73000000')",
  'WorkoutSheet({',
  'onFeed: () => this.store.consumePendingWorkout()',
  'onDismiss: () => this.store.dismissPendingWorkout()',
  '.padding({ left: 16, right: 16, top: 8, bottom: 8 })',
  '.border({ width: 1.5, color: LPColor.ink })',
  '.borderRadius(999)',
  ".shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })"
].forEach((needle) => assertSource(index.includes(needle), `Index keeps iOS pending workout sheet gate: ${needle}`));

[
  'hatchPlaying',
  'eggPulsePhase',
  'private startEggPulse()',
  'setInterval(() =>',
  'private eggScale()',
  'private eggTilt()',
  'private hintOpacity()',
  "Image($rawfile('sprites/egg_hatch/frame_00.png'))",
  "sequence: 'egg_hatch'",
  'onCompleted: () => this.finishHatch()',
  'private finishHatch()',
  'this.hatchPlaying = true',
  '.border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })',
  'size: 160',
  "@Watch('onFeedTokenChanged')",
  'private onFeedTokenChanged()',
  'animateTo({ duration: 450',
  'private shakeOffsetX()',
  'private shakeRotation()',
  'private shakeScale()',
  '.translate({ x: this.shakeOffsetX(), y: 0 })'
].forEach((needle) => assertSource(petStage.includes(needle), `PetStage keeps iOS feed shake behavior: ${needle}`));

[
  'private triggerBurst()',
  '}, 1600);',
  'private toastToken',
  'if (this.toastToken === token)',
  'this.lastDeltaToken = 0',
  'debugDecrement(kind: StatKind)',
  'this.applyGain(kind, -5)',
  'this.addDecay(kind, 5)',
  'private clearBurstTimer()',
  'let changed = false',
  'if (!changed)',
  'return;'
].forEach((needle) => assertSource(store.includes(needle), `PetStateStore keeps iOS toast/burst timing: ${needle}`));
assertSource((store.match(/triggerBurst\(\)/g) ?? []).length === 3, 'PetStateStore only triggers burst from stat changes, not plain toasts');

[
  'stepKindQuitLabel',
  '已跳过 · 下次少推${label}',
  '📍 ${label} 已被 quit ${count} 次，偏好已更新'
].forEach((needle) => assertSource(store.includes(needle), `PetStateStore keeps iOS quit toast copy: ${needle}`));

[
  'let shouldClearPendingWorkout = false',
  'const age = now - restoredPending.endedAt',
  'const sameDay = startOfDayMs(restoredPending.endedAt) === startOfDayMs(now)',
  'if (age <= 60 * 60 * 1000 && sameDay)',
  'shouldClearPendingWorkout = true',
  "await pref.put('pendingWorkout', '')",
  'await pref.flush()'
].forEach((needle) => assertSource(store.includes(needle), `PetStateStore keeps iOS pending workout restore freshness: ${needle}`));

[
  '运动健康 · 刚刚同步',
  'KCAL',
  'GainCell',
  "GainCell({ label: '体力', value: `+${this.workout.gainVitality}`, unit: 'PTS' })",
  "GainCell({ label: '精力', value: `+${this.workout.gainVitality}`, unit: 'PTS' })",
  "GainCell({ label: '心情', value: `+${this.workout.gainVitality}`, unit: 'PTS' })",
  'PTS',
  '喂养 ${this.petName}',
  '.height(2)',
  '.backgroundColor(LPColor.ink)',
  '.backgroundColor(LPColor.hairline)',
  '.margin({ top: 6, bottom: 12 })',
  '.margin({ bottom: 16 })',
  '.margin({ bottom: 18 })',
  '.padding({ left: 24, right: 24 })',
  '.height(48)',
  ".shadow({ radius: 12, color: '#1F000000', offsetX: 0, offsetY: 8 })",
  ".shadow({ radius: 6, color: '#1A000000', offsetX: 0, offsetY: 4 })",
  ".shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })",
  '.onClick(() => this.onFeed())'
].forEach((needle) => assertSource(workout.includes(needle), `WorkoutSheet keeps Harmony sheet copy/structure: ${needle}`));
assertSource(!workout.includes('APPLE WATCH'), 'WorkoutSheet does not leak the iOS-only Apple Watch source label');
assertSource(!workout.includes('.onClick(this.onFeed)'), 'WorkoutSheet uses an explicit ArkTS click lambda for the feed callback');
assertSource(!workout.includes("Button('稍后')"), 'WorkoutSheet matches iOS dismissal model without an extra inline later button');
assertSource(!workout.includes(".border({ width: 2, color: LPColor.ink })"), 'WorkoutSheet uses iOS top-rule treatment instead of a full sheet border');

if (failures.length > 0) {
  console.error('Home component parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Home component parity checks passed.');
