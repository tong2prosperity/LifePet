#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const sourcePath = path.join(root, 'entry/src/main/ets/models/PetLifecycle.ets');
const indexSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
let source = fs.readFileSync(sourcePath, 'utf8');

source = source
  .replace(/^import .*$/mg, '')
  .replace(/export interface DecayCatchup \{[\s\S]*?\n\}/m, '')
  .replace(/export function /g, 'function ')
  .replace(/function (\w+)\(([^)]*)\): [^{]+ \{/g, (_, name, params) => {
    const jsParams = params.replace(/: [^,=)]+/g, '');
    return `function ${name}(${jsParams}) {`;
  });

source = `
function startOfDayMs(value = Date.now()) {
  const d = new Date(value);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}
${source}
globalThis.__petLifecycle = {
  shouldResetForNewDay,
  computeDecayCatchup
};
`;

const context = {
  Date,
  Math,
  globalThis: {}
};

vm.createContext(context);
vm.runInContext(source, context, { filename: sourcePath });

const {
  shouldResetForNewDay,
  computeDecayCatchup
} = context.globalThis.__petLifecycle;

const jan1 = new Date('2026-01-01T09:00:00').getTime();
const jan1Late = new Date('2026-01-01T23:00:00').getTime();
const jan2Early = new Date('2026-01-02T00:01:00').getTime();

assert.equal(shouldResetForNewDay(jan1, jan1Late), false);
assert.equal(shouldResetForNewDay(jan1, jan2Early), true);

const noTick = computeDecayCatchup(new Date('2026-01-01T06:00:00').getTime(), new Date('2026-01-01T09:59:59').getTime());
assert.equal(noTick.ticks, 0);
assert.equal(noTick.vitalityDecay, 0);
assert.equal(noTick.energyDecay, 0);
assert.equal(noTick.nextLastDecayAt, new Date('2026-01-01T06:00:00').getTime());

const daytime = computeDecayCatchup(new Date('2026-01-01T06:00:00').getTime(), new Date('2026-01-01T18:30:00').getTime());
assert.equal(daytime.ticks, 3);
assert.equal(daytime.vitalityDecay, 15);
assert.equal(daytime.moodDecay, 15);
assert.equal(daytime.energyDecay, 15);
assert.equal(daytime.nextLastDecayAt, new Date('2026-01-01T18:00:00').getTime());

const overnight = computeDecayCatchup(new Date('2026-01-01T22:00:00').getTime(), new Date('2026-01-02T10:01:00').getTime());
assert.equal(overnight.ticks, 3);
assert.equal(overnight.vitalityDecay, 15);
assert.equal(overnight.moodDecay, 15);
assert.equal(overnight.energyDecay, 5);
assert.equal(overnight.nextLastDecayAt, new Date('2026-01-02T10:00:00').getTime());

[
  'private foregroundTimerId',
  'private refreshing',
  'private startForegroundRefreshTimer()',
  'setInterval(() =>',
  'void this.restoreAndReconcile()',
  'void this.foregroundRefresh()',
  'private clearForegroundRefreshTimer()',
  'clearInterval(this.foregroundTimerId)',
  'if (!this.restored)',
  'LoadingProgress()',
  'if (this.refreshing || !this.restored || !this.store.onboardingDone)',
  'finally',
  'this.store.checkDayRollover()',
  'this.store.applyDecayCatchup()'
].forEach((needle) => assert.ok(indexSource.includes(needle), `Index keeps foreground lifecycle parity: ${needle}`));

console.log('PetLifecycle rollover/decay tests passed.');
