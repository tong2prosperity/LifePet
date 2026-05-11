#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/EnergyParticleField.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

[
  'particleCount: number = 16',
  'elapsed: number = 0',
  'particleDuration: number = 0.9',
  'particleStagger: number = 0.038',
  'animateTo({ duration: 1508, curve: Curve.Linear }',
  'this.elapsed = this.particleDuration + this.particleStagger * (this.particleCount - 1)',
  'const local = this.elapsed - index * this.particleStagger',
  'if (local < 0 || local > this.particleDuration)',
  'const t = local / this.particleDuration',
  'targetXPercent',
  'targetY',
  'startY',
  'const eased = t * t',
  'const lift = -28 * 4 * t * (1 - t)',
  'Math.sin(index * 2.17)',
  'Math.cos(index * 1.41)',
  'opacity: t < 0.8 ? 1',
  'energyColor(index)',
  '#3EB24E',
  'LPColor.coral',
  '#4A90D9'
].forEach((needle) => assertSource(source.includes(needle), `EnergyParticleField keeps iOS feed-particle behavior: ${needle}`));

assertSource(!source.includes('{ x: 47, y: 176'), 'EnergyParticleField no longer uses the old fixed 8-dot list');

if (failures.length > 0) {
  console.error('Energy particle checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Energy particle checks passed.');
