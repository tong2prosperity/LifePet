#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const failures = [];

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function assertGate(condition, message) {
  if (!condition) {
    failures.push(message);
  } else {
    console.log(`ok  - ${message}`);
  }
}

function commandExists(command) {
  const result = spawnSync('sh', ['-lc', `command -v ${command}`], {
    cwd: root,
    stdio: 'ignore'
  });
  return result.status === 0;
}

const factory = read('entry/src/main/ets/services/HealthProviderFactory.ets');
const health = read('entry/src/main/ets/services/HealthDataService.ets');
const share = read('entry/src/main/ets/services/ShareActionService.ets');
const status = read('MIGRATION_STATUS.md');

assertGate(
  factory.includes('ACTIVE_HEALTH_PROVIDER: HealthProviderMode = HealthProviderMode.Huawei'),
  'release build uses HealthProviderMode.Huawei'
);
assertGate(
  !health.includes('PlatformApprovalRequired') && !health.includes('return []'),
  'HuaweiHealthDataService contains real authorization/read implementation'
);
assertGate(
  share.includes("import { pasteboard } from '@kit.BasicServicesKit'") &&
    share.includes("import { systemShare } from '@kit.ShareKit'") &&
    share.includes('pasteboard.getSystemPasteboard().setData') &&
    share.includes('new systemShare.ShareController'),
  'ShareActionService has platform clipboard/share API integration'
);
assertGate(
  share.includes("import { photoAccessHelper } from '@kit.MediaLibraryKit'") &&
    share.includes("import { image } from '@kit.ImageKit'") &&
    share.includes("import { fileIo } from '@kit.CoreFileKit'") &&
    share.includes('photoAccessHelper.getPhotoAccessHelper(context)') &&
    share.includes('imagePackerApi.packToFile(pixelMap, file.fd') &&
    !share.includes('还需接入截图写入相册'),
  'Catalog share card image save writes to the gallery'
);
assertGate(
  commandExists('hvigor') || commandExists('hvigorw') || fs.existsSync(path.join(root, 'hvigorw')),
  'DevEco/hvigor build tool is available'
);
assertGate(
  !status.includes('Not Yet At iOS Parity') && !status.includes('not wired yet') && !status.includes('not installed'),
  'migration status has no remaining parity blockers'
);

if (failures.length > 0) {
  console.error('\nRelease readiness failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('\nHarmonyLifePet release readiness checks passed.');
