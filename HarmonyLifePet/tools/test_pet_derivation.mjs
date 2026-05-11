#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const sourcePath = path.join(root, 'entry/src/main/ets/models/PetDerivation.ets');
let source = fs.readFileSync(sourcePath, 'utf8');

source = source
  .replace(/^import .*$/mg, '')
  .replace(/export interface StatDecay \{[\s\S]*?\n\}/m, '')
  .replace(/export function /g, 'function ')
  .replace(/function (\w+)\(([^)]*)\): [^{]+ \{/g, (_, name, params) => {
    const jsParams = params.replace(/: [^,]+/g, '');
    return `function ${name}(${jsParams}) {`;
  });

source += `
globalThis.__petDerivation = {
  clampScore,
  computeVitality,
  computeSleepScore,
  computeEnergy,
  computeMood,
  derivePetState,
  deriveStats
};
`;

const context = {
  PetState: {
    Sick: 'SICK',
    Sleeping: 'SLEEPING',
    Tired: 'TIRED',
    Normal: 'NORMAL',
    Excited: 'EXCITED',
    Blissful: 'BLISSFUL'
  },
  StatKind: {
    Vitality: 'vitality',
    Energy: 'energy',
    Mood: 'mood'
  },
  Math,
  globalThis: {}
};

vm.createContext(context);
vm.runInContext(source, context, { filename: sourcePath });

const {
  clampScore,
  computeVitality,
  computeSleepScore,
  computeEnergy,
  computeMood,
  derivePetState,
  deriveStats
} = context.globalThis.__petDerivation;

function raw(overrides = {}) {
  return {
    steps: 0,
    exerciseMinutes: 0,
    activeEnergy: 0,
    standMinutes: 0,
    heartRate: 0,
    hrv: 0,
    restingHR: 0,
    sleepTotal: 0,
    sleepDeep: 0,
    sleepREM: 0,
    mindfulMinutes: 0,
    ...overrides
  };
}

assert.equal(clampScore(-1), 0);
assert.equal(clampScore(101), 100);
assert.equal(clampScore(42), 42);

assert.equal(computeVitality(raw()), 20);
assert.equal(computeVitality(raw({ steps: 10000, exerciseMinutes: 30, activeEnergy: 300 })), 100);

assert.equal(computeSleepScore(raw()), 0);
assert.equal(computeSleepScore(raw({ sleepTotal: 8 * 3600, sleepDeep: 1.5 * 3600, sleepREM: 1.5 * 3600 })), 100);
assert.equal(computeEnergy(raw()), 0);
assert.equal(computeEnergy(raw({ sleepTotal: 8 * 3600, sleepDeep: 1.5 * 3600, sleepREM: 1.5 * 3600 })), 100);

assert.equal(computeMood(raw()), 50);
assert.equal(computeMood(raw({ hrv: 60, hrvBaseline: 50 })), 58);
assert.equal(computeMood(raw({ hrv: 40, hrvBaseline: 60 })), 34);

assert.equal(derivePetState(100, 100, 20), 'SICK');
assert.equal(derivePetState(100, 20, 100), 'SLEEPING');
assert.equal(derivePetState(20, 100, 100), 'TIRED');
assert.equal(derivePetState(70, 70, 90), 'BLISSFUL');
assert.equal(derivePetState(90, 70, 70), 'EXCITED');
assert.equal(derivePetState(70, 70, 70), 'NORMAL');

assert.equal(
  JSON.stringify(deriveStats(
    raw({ steps: 10000, exerciseMinutes: 30, activeEnergy: 300, sleepTotal: 8 * 3600, sleepDeep: 1.5 * 3600, sleepREM: 1.5 * 3600, hrv: 60, hrvBaseline: 50 }),
    { vitality: 95, energy: 0, mood: 0 }
  )),
  JSON.stringify([
    { kind: 'vitality', value: 10 },
    { kind: 'energy', value: 100 },
    { kind: 'mood', value: 58 }
  ])
);

console.log('PetDerivation formula tests passed.');
