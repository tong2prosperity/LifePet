#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const harmonyRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const repoRoot = path.resolve(harmonyRoot, '..');
const rootViewPath = path.join(repoRoot, 'LifePulse/App/RootView.swift');
const rootView = fs.readFileSync(rootViewPath, 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

assertSource(rootView.includes('TabView'), 'iOS RootView still uses a three-tab TabView shell');
assertSource(rootView.includes('HealthAuthView(onContinue:'), 'iOS routed surface includes onboarding gate');
assertSource(rootView.includes('HomeView()'), 'iOS routed surface includes HomeView');
assertSource(rootView.includes('CatalogView()'), 'iOS routed surface includes CatalogView');
assertSource(rootView.includes('TogetherView()'), 'iOS routed surface includes TogetherView');
assertSource(rootView.includes('Label("主页"'), 'iOS home tab label remains 主页');
assertSource(rootView.includes('Label("图鉴"'), 'iOS catalog tab label remains 图鉴');
assertSource(rootView.includes('Label("一起"'), 'iOS together tab label remains 一起');

const unroutedPlaceholders = [
  'GenerationView()',
  'PlaybackView()',
  'SessionListView()',
  'SessionDetailView('
];

for (const placeholder of unroutedPlaceholders) {
  assertSource(!rootView.includes(placeholder), `iOS RootView does not route placeholder surface ${placeholder}`);
}

if (failures.length > 0) {
  console.error('iOS routed surface scope checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('iOS routed surface scope checks passed.');
