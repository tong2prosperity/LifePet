#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const overlay = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/CatalogIncenseOverlay.ets'), 'utf8');
const page = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/CatalogPage.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

[
  'interface MemorialBar',
  'interface SmokeParticle',
  'private barCount(): number',
  'this.pet.series.vitality.length',
  'this.pet.series.energy.length',
  'this.pet.series.mood.length',
  'const avg = (vitality + energy + mood) / 3',
  'mood >= vitality && mood >= energy',
  'energy >= vitality',
  'LPColor.coral',
  'LPColor.muted',
  'LPColor.ink',
  'Column()\n        .width(1)\n        .height(this.waveformHeight())\n        .backgroundColor(LPColor.coral)',
].forEach((needle) => assertSource(overlay.includes(needle), `MemorialWaveform mirrors iOS data-driven bars: ${needle}`));

[
  "MemorialWaveform({ pet: this.pet, progress: this.progress, muted: false })",
  "MemorialWaveform({ pet: this.pet, progress: this.progress(), muted: true })",
].forEach((needle) => assertSource((page + overlay).includes(needle), `MemorialWaveform receives the current pet series: ${needle}`));

[
  "Text('— 上 香 —')",
  '.letterSpacing(4)',
  ".margin({ bottom: 6 })",
  'Text(`为 ${this.pet.name}`)',
  ".margin({ bottom: 20 })",
  'Column({ space: 8 })',
  '.padding({ left: 24, right: 24, bottom: 22 })',
  '.letterSpacing(1)',
  "Button('收香')",
  '.height(38)',
  '.padding({ left: 32, right: 32 })',
  ".border({ width: 1.5, color: '#9A784080' })",
].forEach((needle) => assertSource(overlay.includes(needle), `Incense overlay mirrors iOS spacing/chrome: ${needle}`));

[
  '.width(60)',
  '.height(165)',
  "PixelRect({ x: 29, y: 34, w: 2, h: 12, color: '#B8B090' })",
  "PixelRect({ x: 29, y: 46, w: 2, h: 60, color: '#8B6840' })",
  "PixelRect({ x: 17, y: 106, w: 26, h: 2, color: '#7A6040' })",
  "PixelRect({ x: 20, y: 110, w: 20, h: 12, color: '#6B5030' })",
  "PixelRect({ x: 17, y: 122, w: 26, h: 3, color: '#4A3020' })",
  "PixelRect({ x: 20, y: 125, w: 5, h: 4, color: '#3A2010' })",
  "PixelRect({ x: 35, y: 125, w: 5, h: 4, color: '#3A2010' })",
  "PixelRect({ x: 21, y: 114, w: 18, h: 1, color: '#9A8060B3' })",
  "PixelRect({ x: 27, y: 108, w: 6, h: 4, color: '#C8B88899' })",
  ".width(4)\n        .height(5)\n        .backgroundColor('#C83828')\n        .position({ x: 28, y: 26 })",
  ".width(2)\n        .height(4)\n        .backgroundColor('#FF8028')\n        .position({ x: 29, y: 23 })",
].forEach((needle) => assertSource(overlay.includes(needle), `IncenseSprite keeps iOS pixel geometry: ${needle}`));

[
  'private smokeParticles(): SmokeParticle[]',
  '[30, 18, 2.5, 0.7, 0.0]',
  '[27, 16, 3.5, 0.5, 0.9]',
  '[33, 20, 2.0, 0.6, 1.8]',
  '[29, 14, 3.0, 0.4, 2.5]',
  'return 4 * (t / 0.3)',
  'return 4 - 7 * ((t - 0.3) / 0.35)',
  'return -3 + 4 * ((t - 0.65) / 0.35)',
  'return this.lerp(0.8, 0.5, t / 0.3)',
  'return this.lerp(0.5, 0.2, (t - 0.3) / 0.35)',
  'return this.lerp(0.2, 0, (t - 0.65) / 0.35)',
].forEach((needle) => assertSource(overlay.includes(needle), `Incense smoke mirrors iOS drift/envelope: ${needle}`));

assertSource(!overlay.includes("Text('∿')"), 'IncenseSprite no longer uses text glyph smoke');
assertSource(!overlay.includes('return [0.28, 0.55'), 'MemorialWaveform no longer uses a fixed fake bar list');

if (failures.length > 0) {
  console.error('Catalog incense parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Catalog incense parity checks passed.');
