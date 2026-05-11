#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const service = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/HealthDataService.ets'), 'utf8');
const models = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/HealthModels.ets'), 'utf8');
const mapper = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/HuaweiHealthMapper.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const metricIds = [
  'steps',
  'exerciseMinutes',
  'activeEnergy',
  'standMinutes',
  'heartRate',
  'hrv',
  'restingHR',
  'sleep',
  'mindful',
  'workout'
];

for (const id of metricIds) {
  assertSource(service.includes(`id: '${id}'`), `requiredHealthScopes includes iOS metric: ${id}`);
}

const eventTypes = [
  'Steps',
  'ExerciseMinutes',
  'ActiveEnergy',
  'StandMinutes',
  'HeartRate',
  'Hrv',
  'RestingHR',
  'Sleep',
  'MindfulMinutes',
  'WorkoutFinished'
];

for (const eventType of eventTypes) {
  assertSource(models.includes(`${eventType} =`), `HealthEventType defines ${eventType}`);
  assertSource(service.includes(`HealthEventType.${eventType}`), `MockHealthDataService emits ${eventType}`);
}

assertSource(service.includes('PlatformApprovalRequired'), 'HuaweiHealthDataService keeps explicit platform-approval state');
assertSource(service.includes('readonly scopes: HealthScopeDescriptor[] = requiredHealthScopes'), 'HuaweiHealthDataService exposes the exact approval scope list');
assertSource(service.includes('private emittedWorkoutIds: string[] = []'), 'HuaweiHealthDataService keeps iOS-style workout event dedupe state');
assertSource(mapper.includes('mapDailySnapshot'), 'HuaweiHealthMapper maps approved daily snapshots');
assertSource(mapper.includes('mapSleepSamples'), 'HuaweiHealthMapper maps approved sleep stage samples');
assertSource(mapper.includes('bucketHuaweiWorkoutActivity'), 'HuaweiHealthMapper buckets approved workout samples');
assertSource(mapper.includes('emittedIds.push(id)'), 'HuaweiHealthMapper records emitted workout ids across reconciles');
assertSource(service.includes('mapApprovedSamples'), 'HuaweiHealthDataService keeps provider-to-HealthEvent mapper boundary');

if (failures.length > 0) {
  console.error('Health model parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Health model parity checks passed.');
