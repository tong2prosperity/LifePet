#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const checks = [
  ['node', ['tools/check_port.mjs']],
  ['node', ['tools/check_ios_surface_scope.mjs']],
  ['node', ['tools/check_arkts_this_methods.mjs']],
  ['node', ['tools/test_pet_derivation.mjs']],
  ['node', ['tools/test_date_utils.mjs']],
  ['node', ['tools/test_catalog_models.mjs']],
  ['node', ['tools/test_catalog_incense.mjs']],
  ['node', ['tools/test_catalog_trajectory.mjs']],
  ['node', ['tools/test_health_models.mjs']],
  ['node', ['tools/test_huawei_health_mapper.mjs']],
  ['node', ['tools/test_energy_particles.mjs']],
  ['node', ['tools/test_home_components.mjs']],
  ['node', ['tools/test_onboarding_copy.mjs']],
  ['node', ['tools/test_pet_lifecycle.mjs']],
  ['node', ['tools/test_snapshot_store.mjs']],
  ['node', ['tools/test_share_actions.mjs']],
  ['node', ['tools/test_theme_tokens.mjs']],
  ['node', ['tools/test_together_models.mjs']]
];

for (const [command, args] of checks) {
  const label = [command, ...args].join(' ');
  console.log(`\n$ ${label}`);
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit'
  });
  if (result.status !== 0) {
    console.error(`\n${label} failed.`);
    process.exit(result.status ?? 1);
  }
}

console.log('\nAll HarmonyLifePet local checks passed.');
