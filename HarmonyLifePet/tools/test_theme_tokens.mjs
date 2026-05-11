#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const theme = fs.readFileSync(path.join(root, 'entry/src/main/ets/theme/LPTheme.ets'), 'utf8');
const etsRoot = path.join(root, 'entry/src/main/ets');
const colorResource = fs.readFileSync(path.join(root, 'entry/src/main/resources/base/element/color.json'), 'utf8');
const appIcon = fs.readFileSync(path.join(root, 'entry/src/main/resources/base/media/app_icon.svg'), 'utf8');
const appScopeIcon = fs.readFileSync(path.join(root, 'AppScope/resources/base/media/app_icon.svg'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walk(file));
    } else if (entry.isFile() && file.endsWith('.ets')) {
      out.push(file);
    }
  }
  return out;
}

const colorTokens = {
  ink: '#1A1A1A',
  ink2: '#3A3A3A',
  muted: '#6E665A',
  faint: '#BBBBBB',
  hairline: '#E7E3D9',
  paper: '#FAF7EF',
  paperCool: '#FAFAF5',
  paperCard: '#FFFEF9',
  paperWarm: '#F4F0E4',
  kraft: '#E7E3D9',
  coral: '#D14B3D',
  coralSoft: '#FDF3F1',
  sage: '#3E7A5F',
  sageSoft: '#F0F6F2',
  sticky: '#FEF4A8',
  stickyInk: '#5A4A2A'
};

for (const [name, value] of Object.entries(colorTokens)) {
  assertSource(
    theme.includes(`static readonly ${name}: string = '${value}'`),
    `LPColor.${name} mirrors the iOS token ${value}`
  );
}

[
  "static readonly lcd: string = '#EBE3CC'",
  "static readonly lcdDash: string = '#BFB89F'",
  "static readonly lcdInk: string = '#7D7657'",
].forEach((needle) => assertSource(theme.includes(needle), `PetStage LCD one-off token kept: ${needle}`));

[
  'static readonly s1: number = 4',
  'static readonly s2: number = 8',
  'static readonly s3: number = 12',
  'static readonly s4: number = 16',
  'static readonly s5: number = 24',
  'static readonly s6: number = 32',
  'static readonly s7: number = 48',
  'static readonly s8: number = 64',
  'static readonly cardPadding: number = LPSpacing.s4',
  'static readonly blockGap: number = LPSpacing.s5',
  'static readonly sectionGap: number = LPSpacing.s7',
  'static readonly screenMargin: number = LPSpacing.s5',
].forEach((needle) => assertSource(theme.includes(needle), `LPSpacing mirrors iOS spacing scale: ${needle}`));

[
  'static readonly sharp: number = 0',
  'static readonly button: number = 2',
  'static readonly card: number = 4',
  'static readonly input: number = 8',
  'static readonly panel: number = 14',
  'static readonly pill: number = 999',
  'static readonly regular: number = 1.5',
  'static readonly hair: number = 1',
  'static readonly heavy: number = 2',
  'static readonly draftDash: number[] = [6, 4]',
].forEach((needle) => assertSource(theme.includes(needle), `LPRadius/LPBorder mirrors iOS token: ${needle}`));

[
  "'#F8F1DF'",
  "'#FFF8E8'",
  "'#EFE8D1'",
  "'#1F1B18'",
  "'#81776C'",
  "'#F05A4F'",
  "'#FFE89A'",
].forEach((oldValue) => assertSource(!theme.includes(oldValue), `LPTheme no longer uses old approximate token ${oldValue}`));

const allSource = walk(etsRoot).map((file) => fs.readFileSync(file, 'utf8')).join('\n');
const resourceSource = `${colorResource}\n${appIcon}\n${appScopeIcon}`;
[
  "'#F8F1DF'",
  "'#FFF8E8",
  "'#EFE8D1'",
  "'#1F1B18'",
  "'#81776C",
  "'#F05A4F",
  "'#FFE89A'",
  "'#4E3A18",
  "'#7A653055'",
  "'#7A653080'",
].forEach((oldValue) => assertSource(!allSource.includes(oldValue), `ArkTS sources no longer use old approximate LP token ${oldValue}`));
[
  '#F8F1DF',
  '#1F1B18',
  '#F05A4F',
].forEach((oldValue) => assertSource(!resourceSource.includes(oldValue), `Harmony resources no longer use old approximate LP token ${oldValue}`));

[
  "'#D14B3D55'",
  "'#D14B3D66'",
  "'#D14B3D14'",
  "'#D14B3D1A'",
  "'#6E665A80'",
  "'#FFFEF9AA'",
  "'#FFFEF999'",
  "'#5A4A2ABF'",
  "'#5A4A2AAA'",
  "'#5A4A2A99'",
  "'#5A4A2A40'",
  "'#6E665A55'",
].forEach((newValue) => assertSource(allSource.includes(newValue), `ArkTS source uses current iOS token-derived transparent color ${newValue}`));

[
  '"value": "#FAF7EF"',
  '"value": "#1A1A1A"',
  '"value": "#D14B3D"',
].forEach((needle) => assertSource(colorResource.includes(needle), `color resource mirrors iOS token: ${needle}`));

[
  'fill="#FAF7EF"',
  'fill="#1A1A1A"',
  'fill="#D14B3D"',
].forEach((needle) => assertSource(appIcon.includes(needle), `app icon uses current iOS token: ${needle}`));
[
  'fill="#FAF7EF"',
  'fill="#1A1A1A"',
  'fill="#D14B3D"',
].forEach((needle) => assertSource(appScopeIcon.includes(needle), `AppScope app icon uses current iOS token: ${needle}`));

if (failures.length > 0) {
  console.error('Theme token parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Theme token parity checks passed.');
