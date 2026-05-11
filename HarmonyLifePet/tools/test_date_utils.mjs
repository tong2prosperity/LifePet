#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const sourcePath = path.join(root, 'entry/src/main/ets/utils/DateUtils.ets');
let source = fs.readFileSync(sourcePath, 'utf8');

source = source
  .replace(/export function /g, 'function ')
  .replace(/value: number = Date\.now\(\)/g, 'value = Date.now()')
  .replace(/nowMs: number = Date\.now\(\)/g, 'nowMs = Date.now()')
  .replace(/birthMs: number/g, 'birthMs')
  .replace(/valueMs: number/g, 'valueMs')
  .replace(/prefix: string/g, 'prefix')
  .replace(/\): string/g, ')')
  .replace(/\): number/g, ')')
  .replace(/: string\[\]/g, '');

source += `
globalThis.__dateUtils = {
  startOfDayMs,
  daysSinceBirth,
  timeLabel,
  relativeTimeLabel,
  dateLabel,
  greeting,
  makeId
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
  startOfDayMs,
  daysSinceBirth,
  timeLabel,
  relativeTimeLabel,
  dateLabel,
  greeting,
  makeId
} = context.globalThis.__dateUtils;

const may10 = new Date(2026, 4, 10, 22, 45).getTime();
const may11Morning = new Date(2026, 4, 11, 9, 5).getTime();
const may11Noon = new Date(2026, 4, 11, 12, 15).getTime();
const may9 = new Date(2026, 4, 9, 8, 20).getTime();

assert.equal(startOfDayMs(may11Morning), new Date(2026, 4, 11, 0, 0, 0, 0).getTime());
assert.equal(daysSinceBirth(may10, may11Morning), 2);
assert.equal(daysSinceBirth(may11Morning, may10), 1);
assert.equal(timeLabel(may11Morning), '09:05');
assert.equal(relativeTimeLabel(may11Morning, may11Noon), '今 09:05');
assert.equal(relativeTimeLabel(may10, may11Noon), '昨 22:45');
assert.equal(relativeTimeLabel(may9, may11Noon), '5/9 08:20');
assert.equal(dateLabel(may11Morning), 'MON · 5/11');

assert.equal(greeting(new Date(2026, 4, 11, 4, 59).getTime()), '深夜');
assert.equal(greeting(new Date(2026, 4, 11, 5, 0).getTime()), '早上好');
assert.equal(greeting(new Date(2026, 4, 11, 11, 0).getTime()), '午安');
assert.equal(greeting(new Date(2026, 4, 11, 13, 0).getTime()), '下午好');
assert.equal(greeting(new Date(2026, 4, 11, 18, 0).getTime()), '晚上好');
assert.equal(greeting(new Date(2026, 4, 11, 22, 0).getTime()), '夜深了');

assert.match(makeId('step'), /^step_\d+_\d+$/);

console.log('DateUtils tests passed.');
