#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const sourcePath = path.join(root, 'entry/src/main/ets/models/HuaweiHealthMapper.ets');
let source = fs.readFileSync(sourcePath, 'utf8');

source = source
  .replace(/^import .*$/mg, '')
  .replace(/export interface \w+ \{[\s\S]*?\n\}/g, '')
  .replace(/export const /g, 'const ')
  .replace(/export function /g, 'function ')
  .replace(/new Set<[^>]+>/g, 'new Set')
  .replace(/function (\w+)\(([^)]*)\)\s*: [^{]+ \{/g, (_, name, params) => {
    const jsParams = params.replace(/: [^,)=]+/g, '');
    return `function ${name}(${jsParams}) {`;
  })
  .replace(/\b(const|let|var) (\w+): [^=;]+=/g, '$1 $2 =');

source += `
globalThis.__huaweiHealthMapper = {
  HuaweiSleepStage,
  mapDailySnapshot,
  mapSleepSamples,
  bucketHuaweiWorkoutActivity,
  mapWorkoutSamples
};
`;

const context = {
  HealthEventType: {
    Steps: 'steps',
    ExerciseMinutes: 'exerciseMinutes',
    ActiveEnergy: 'activeEnergy',
    StandMinutes: 'standMinutes',
    HeartRate: 'heartRate',
    Hrv: 'hrv',
    RestingHR: 'restingHR',
    Sleep: 'sleep',
    MindfulMinutes: 'mindfulMinutes',
    WorkoutFinished: 'workoutFinished'
  },
  WorkoutKind: {
    Run: 'run',
    Walk: 'walk',
    Cycle: 'cycle',
    Hiit: 'hiit',
    Yoga: 'yoga',
    Other: 'other'
  },
  numericEvent: (type, value) => ({ type, value }),
  Number,
  Math,
  Set,
  globalThis: {}
};

vm.createContext(context);
vm.runInContext(source, context, { filename: sourcePath });

const {
  HuaweiSleepStage,
  mapDailySnapshot,
  mapSleepSamples,
  bucketHuaweiWorkoutActivity,
  mapWorkoutSamples
} = context.globalThis.__huaweiHealthMapper;

const daily = mapDailySnapshot({
  steps: 8123,
  exerciseMinutes: 22,
  activeEnergyKcal: 288,
  standMinutes: 76,
  heartRateBpm: 74,
  hrvMs: 51,
  restingHeartRateBpm: 60,
  mindfulMinutes: 10
});
assert.equal(JSON.stringify(daily.map((event) => event.type)), JSON.stringify([
  'steps',
  'exerciseMinutes',
  'activeEnergy',
  'standMinutes',
  'heartRate',
  'hrv',
  'restingHR',
  'mindfulMinutes'
]));
assert.equal(daily[0].value, 8123);
assert.equal(mapDailySnapshot({ steps: -1, hrvMs: Number.NaN }).length, 0);

const base = Date.UTC(2026, 4, 11, 0, 0, 0);
const oneHour = 3600 * 1000;
const sleep = mapSleepSamples([
  { stage: HuaweiSleepStage.Asleep, start: base - 10 * oneHour, end: base - 2 * oneHour },
  { stage: HuaweiSleepStage.AsleepCore, start: base - 8 * oneHour, end: base - 6 * oneHour },
  { stage: HuaweiSleepStage.AsleepDeep, start: base - 6 * oneHour, end: base - 5 * oneHour },
  { stage: HuaweiSleepStage.Awake, start: base - 5 * oneHour, end: base - 4.5 * oneHour },
  { stage: HuaweiSleepStage.AsleepRem, start: base - 4.5 * oneHour, end: base - 3.5 * oneHour }
]);
assert.equal(sleep.type, 'sleep');
assert.equal(sleep.total, 4 * oneHour);
assert.equal(sleep.deep, oneHour);
assert.equal(sleep.rem, oneHour);
assert.equal(sleep.start, base - 8 * oneHour);

const legacyOnly = mapSleepSamples([
  { stage: HuaweiSleepStage.InBed, start: base - 9 * oneHour, end: base - 8 * oneHour },
  { stage: HuaweiSleepStage.Asleep, start: base - 8 * oneHour, end: base - oneHour }
]);
assert.equal(legacyOnly.total, 7 * oneHour);
assert.equal(legacyOnly.deep, 0);
assert.equal(legacyOnly.rem, 0);

assert.equal(bucketHuaweiWorkoutActivity('running'), 'run');
assert.equal(bucketHuaweiWorkoutActivity('hiking'), 'walk');
assert.equal(bucketHuaweiWorkoutActivity('hand_cycling'), 'cycle');
assert.equal(bucketHuaweiWorkoutActivity('functional_strength_training'), 'hiit');
assert.equal(bucketHuaweiWorkoutActivity('mind and body'), 'yoga');
assert.equal(bucketHuaweiWorkoutActivity('badminton'), 'other');

const workouts = mapWorkoutSamples([
  { id: 'skip-me', activity: 'running', duration: 1800, kcal: 210, end: base + 1 },
  { id: 'run-1', activity: 'running', duration: 1800, kcal: 210, end: base + 2 },
  { id: 'run-1', activity: 'running', duration: 1800, kcal: 210, end: base + 3 },
  { id: 'yoga-1', activity: 'pilates', duration: 1200, end: base + 4 },
  { activity: 'unknown', duration: 600, end: base + 5 }
], ['skip-me']);
assert.equal(JSON.stringify(workouts.map((event) => event.kind)), JSON.stringify(['run', 'yoga', 'other']));
assert.equal(workouts[0].type, 'workoutFinished');
assert.equal(workouts[0].kcal, 210);

const emittedIds = [];
const firstDelta = mapWorkoutSamples([
  { id: 'cycle-1', activity: 'cycling', duration: 900, end: base + 6 }
], emittedIds);
const secondDelta = mapWorkoutSamples([
  { id: 'cycle-1', activity: 'cycling', duration: 900, end: base + 7 },
  { id: 'walk-1', activity: 'walking', duration: 600, end: base + 8 }
], emittedIds);
assert.equal(firstDelta.length, 1);
assert.equal(JSON.stringify(secondDelta.map((event) => event.kind)), JSON.stringify(['walk']));
assert.equal(JSON.stringify(emittedIds), JSON.stringify(['cycle-1', 'walk-1']));

console.log('Huawei health mapper tests passed.');
