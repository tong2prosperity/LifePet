#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/CatalogTrajectoryChart.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

[
  'const CHART_WIDTH = 340',
  'const CHART_HEIGHT = 140',
  'GridLine({ value: 100',
  'GridLine({ value: 50',
  'GridLine({ value: 0',
  'GridLine({ value: 85',
  'GridLine({ value: 30',
  'LineSeries({ values: this.pet.series.energy',
  'LineSeries({ values: this.pet.series.vitality',
  'LineSeries({ values: this.pet.series.mood',
  'LastDots',
  'VerticalDashedLine({ x: this.dx(this.endDay()) })',
  'Column({ space: 2 })',
  '· 今天 ·',
  '✦ 升天',
  'D${day}',
  'LegendChip({ color: LPColor.coral, label: \'心情\'',
  'LegendChip({ color: LPColor.muted, label: \'精力\'',
  'LegendChip({ color: LPColor.ink, label: \'体力\''
].forEach((needle) => assertSource(source.includes(needle), `CatalogTrajectoryChart keeps iOS trajectory behavior: ${needle}`));

assertSource(!source.includes('DayBars'), 'CatalogTrajectoryChart no longer uses the old bar trajectory component');
assertSource(source.includes('.startPoint([') && source.includes('.endPoint(['), 'CatalogTrajectoryChart draws explicit line segments');
assertSource(source.includes('@Prop totalDays'), 'LineSeries positions values against pet totalDays like iOS');

if (failures.length > 0) {
  console.error('Catalog trajectory checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Catalog trajectory checks passed.');
