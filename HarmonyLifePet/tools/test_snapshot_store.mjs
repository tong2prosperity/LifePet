#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/DailySnapshotStore.ets'), 'utf8');
const identity = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/PetIdentityStore.ets'), 'utf8');
const store = fs.readFileSync(path.join(root, 'entry/src/main/ets/stores/PetStateStore.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const fields = [
  'petId',
  'date',
  'vitality',
  'energy',
  'mood',
  'stateTag',
  'steps',
  'exerciseMinutes',
  'activeEnergy',
  'standMinutes',
  'hrv',
  'restingHR',
  'sleepTotal',
  'sleepDeep',
  'sleepREM',
  'mindfulMinutes',
  'completedStepKinds',
  'updatedAt'
];

for (const field of fields) {
  assertSource(source.includes(`${field}:`), `DailySnapshot keeps iOS field: ${field}`);
}

assertSource(source.includes('this.cache = this.cache.filter'), 'DailySnapshotStore overwrites one snapshot per pet/day before writing');
assertSource(source.includes('recent(petId: string, days: number)'), 'DailySnapshotStore keeps recent-day reader');
assertSource(source.includes('if (days <= 0)') && source.includes('return [];'), 'DailySnapshotStore recent matches iOS empty result for non-positive day counts');
assertSource(source.includes('const today = startOfDayMs()'), 'DailySnapshotStore recent anchors its window on today like iOS');
assertSource(source.includes('item.date >= cutoff && item.date <= today'), 'DailySnapshotStore recent excludes future snapshots like iOS');
assertSource(source.includes('range(petId: string, from: number, through: number)'), 'DailySnapshotStore keeps iOS range reader');
assertSource(source.includes('start > end'), 'DailySnapshotStore range handles inverted date bounds');
assertSource(source.includes('item.date >= start && item.date <= end'), 'DailySnapshotStore range is inclusive');
assertSource(source.includes('.sort((a: DailySnapshot, b: DailySnapshot) => a.date - b.date)'), 'DailySnapshotStore readers return ascending dates');

assertSource(identity.includes('startOfDayMs(restoredBirthDate)'), 'PetIdentityStore normalizes restored birthDate to start of day like iOS');
assertSource(identity.includes('bytes[6] = (bytes[6] & 0x0f) | 0x40') && identity.includes('bytes[8] = (bytes[8] & 0x3f) | 0x80'), 'PetIdentityStore mints UUID-v4 shaped pet ids like iOS');
assertSource(identity.includes("hex.slice(0, 4).join('')") && identity.includes("hex.slice(10, 16).join('')"), 'PetIdentityStore formats persisted pet ids with UUID sections');

[
  'private refreshBaseline()',
  'this.snapshots.recent(this.identity.currentPetId, 8)',
  'startOfDayMs(item.date) < today && item.hrv > 0',
  'priorHRVs.length >= 3',
  'this.raw.hrvBaseline = baseline',
  'this.recordSnapshot(this.lastSeenDate)',
  'private recordSnapshot(date: number = startOfDayMs())'
].forEach((needle) => assertSource(store.includes(needle), `PetStateStore keeps iOS snapshot/baseline lifecycle: ${needle}`));

if (failures.length > 0) {
  console.error('Snapshot store parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Snapshot store parity checks passed.');
