#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const catalog = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/CatalogModels.ets'), 'utf8');
const page = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/CatalogPage.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const expectedNeedles = [
  "'bean'",
  "'blob'",
  "'noct'",
  "'hush'",
  '全生命期最巅峰',
  'SICK 突变',
  '你开始冥想 → 好起来',
  '它活成了你那段时间的样子',
  '破壳',
  '体力跌破 15',
  '饱食度 0',
  '被你熬死的第 3 只',
  '稳定开端',
  '最长连续睡眠',
  '慢慢过完了 21 天'
];

for (const needle of expectedNeedles) {
  assertSource(catalog.includes(needle), `CatalogModels keeps iOS catalog data: ${needle}`);
}

assertSource((catalog.match(/title:/g) ?? []).length >= 19, 'CatalogModels keeps the full iOS moment count');
assertSource(catalog.includes("import { PetSpriteName } from './PetSpriteModels';"), 'Catalog models use the shared PetSpriteName identity enum');
assertSource(catalog.includes('sprite: PetSpriteName.Bean') && catalog.includes('sprite: PetSpriteName.Blob') && catalog.includes('sprite: PetSpriteName.Noct') && catalog.includes('sprite: PetSpriteName.Hush'), 'Catalog models keep iOS PetSprite identities');
assertSource(!/blob_(run|walk|lying|sleep)/.test(catalog), 'Catalog models no longer store animation sequence names as pet identity');
assertSource(page.includes('sprite: base.sprite'), 'Catalog live overlay keeps the authored iOS sprite');
assertSource(page.includes('series: base.series'), 'Catalog live overlay keeps the authored iOS series');
assertSource(page.includes('moments: base.moments'), 'Catalog live overlay keeps the authored iOS moments');
assertSource(!page.includes('patchedSeries'), 'Catalog live overlay does not patch series locally');
assertSource(page.includes('private aliveCount()'), 'Catalog list owns the alive summary helper it renders');
assertSource(page.includes('private livePet(): CatalogPet'), 'Catalog list builds its own live overlay for the living card');
assertSource(page.includes('pet: this.livePet()'), 'Catalog living card receives the live overlay object');
assertSource(page.includes("import { BreathingPixelPetSprite, PixelPetLockedSprite, PixelPetSprite } from '../components/PixelPetSprite';"), 'Catalog page imports the shared static/breathing pixel sprite renderers');
assertSource(!page.includes("import { SpriteAnimator } from '../components/SpriteAnimator';"), 'Catalog page no longer uses live animation sequences for catalog portraits');
assertSource(page.includes('BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 60 })'), 'Catalog living card renders the authored iOS breathing pixel sprite');
assertSource(page.includes('BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 90 })'), 'Catalog detail hero renders the authored iOS breathing pixel sprite');
assertSource(page.includes('PixelPetSprite({ sprite: this.pet.sprite, size: 44 })'), 'Catalog past grid renders the authored iOS 44pt pixel sprite');
assertSource(page.includes('Text(this.pet.dates)'), 'Catalog living card keeps the iOS date line');
assertSource(page.includes('struct CatalogStatChip'), 'Catalog list keeps iOS summary stat chips');
assertSource(page.includes("label: '养育中', live: true"), 'Catalog summary keeps live chip');
assertSource(page.includes("label: '圆满'"), 'Catalog summary keeps natural chip');
assertSource(page.includes("label: '短命'"), 'Catalog summary keeps early chip');
assertSource(page.includes("label: '总天数'"), 'Catalog summary keeps total-days chip');
assertSource(page.includes("Text('陪伴过 ')") && page.includes('Text(this.totalCount().toString())') && page.includes('Text(this.totalDays().toString())'), 'Catalog header summary uses iOS split muted/coral number styling');
assertSource(page.includes('Text((this.aliveCount() + this.naturalCount()).toString())') && page.includes('Text(this.earlyCount().toString())'), 'Catalog footer note uses iOS split sticky/coral number styling');
assertSource(page.includes('.border({ width: 1.5, color: LPColor.ink })') && page.includes('.shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })'), 'Catalog summary chips keep iOS stamped-card stroke and offset shadow');
assertSource(page.includes(".border({ width: 1.5, color: LPColor.ink, style: BorderStyle.Dashed })"), 'Catalog sticky footer keeps iOS dashed 1.5pt border');
assertSource(page.includes("import { DashedRule } from '../components/DashedRule';"), 'Catalog list imports the shared dashed rule');
assertSource((page.match(/DashedRule\(\{ color: LPColor\.lcdDash \}\)/g) ?? []).length >= 3, 'Catalog list uses iOS dashed rules around stats and section headers');
assertSource(page.includes("DashedRule({ color: LPColor.lcdDash })\n          Row({ space: 6 })"), 'Catalog stats row has an iOS-style top dashed rule instead of a full box border');
assertSource(page.includes("DashedRule({ color: LPColor.lcdDash })\n        .layoutWeight(1)"), 'Catalog section headers keep the iOS dashed rule between tag and count');
assertSource(page.includes('private lockedSlots()'), 'Catalog list pads the past grid with locked slots');
assertSource(page.includes("Grid()"), 'Catalog past section uses a grid');
assertSource(page.includes(".columnsTemplate('1fr 1fr 1fr')"), 'Catalog past section uses iOS 3-column grid');
assertSource(page.includes('struct LockedCatalogCard'), 'Catalog list keeps iOS locked placeholders');
assertSource(page.includes('PixelPetLockedSprite({ size: 44 })'), 'Catalog locked placeholders render the iOS pixel locked sprite');
assertSource(page.includes('UNLOCK'), 'Catalog locked placeholders keep iOS copy');
assertSource(page.includes('养死了也别难过，下一只会更好。'), 'Catalog footer keeps iOS sticky note copy');
assertSource(page.includes("DetailTag({ label: 'LIVE'"), 'Catalog detail keeps iOS LIVE tag');
assertSource(page.includes("DetailTag({ label: '养育中'"), 'Catalog detail keeps iOS alive tag');
assertSource(page.includes("DetailTag({ label: 'RARE'"), 'Catalog detail keeps iOS rare tag');
assertSource(page.includes("DetailTag({ label: '已升天', dead: true })"), 'Catalog detail keeps iOS muted dead tag');
assertSource(page.includes("DetailStatCell({ symbol: '❤️'"), 'Catalog detail keeps the iOS mood emoji');
assertSource(page.includes("Text('‹')") && page.includes('fontColor(LPColor.coral)') && page.includes("Text('返回图鉴')"), 'Catalog detail back control keeps the iOS coral chevron and label');
assertSource(page.includes("`${this.moment.title} 🕊️`") && page.includes('FontStyle.Italic'), 'Catalog detail death moments keep the iOS dove marker and italic style');
assertSource(page.includes("Text(this.pet.memorialDuration ?? '0:00')"), 'Catalog memorial duration fallback matches iOS');
assertSource(page.includes("Text(this.pet.memorialDuration ?? '0:00')") && page.includes('.letterSpacing(0.5)'), 'Catalog memorial duration keeps iOS mono tracking');
assertSource(page.includes("DashedRule({ color: '#C8A860' })"), 'Catalog incense CTA uses the iOS dashed separator color');
assertSource(page.includes(".border({ width: 1.5, color: '#3A2810' })") && page.includes(".shadow({ radius: 0, color: '#3A2810', offsetX: 2, offsetY: 2 })"), 'Catalog incense CTA keeps iOS stamped dark-brown button chrome');
assertSource(page.includes("Button('↗ 分享')"), 'Catalog detail keeps an icon+share button label');
assertSource(page.includes(".fontFamily('monospace')") && page.includes('.letterSpacing(2.2)') && page.includes('.borderRadius(2)'), 'Catalog detail share button keeps iOS LPButton typography and radius');
assertSource(page.includes('struct DetailStatCell') && page.includes('.shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })'), 'Catalog detail stat cells keep iOS stamped-card shadow');
assertSource(page.includes('BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 90 })') && page.includes('.letterSpacing(1.5)'), 'Catalog detail hero keeps iOS sprite size and name tracking');
assertSource(page.includes('struct DetailHero') && page.includes(".border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })"), 'Catalog detail hero keeps iOS 1.5pt dashed inner LCD frame');
assertSource(page.includes(".width(30)\n          .height(30)\n          .fontSize(10)") && page.includes('.borderRadius(15)'), 'Catalog memorial play button keeps iOS 30pt control size');
assertSource(page.includes('struct LiveCatalogCard') && page.includes(".border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })"), 'Catalog live card keeps the iOS inner LCD dashed frame');
assertSource(page.includes('struct DetailTag') && page.includes('.letterSpacing(1)') && page.includes('.padding({ left: 8, right: 8, top: 1, bottom: 1 })'), 'Catalog detail tags keep iOS mono chip spacing');
assertSource(page.includes('struct DeadCatalogCard') && page.includes('PixelPetSprite({ sprite: this.pet.sprite, size: 44 })') && page.includes('.border({ width: 1.5, color: LPColor.ink })'), 'Catalog dead cards keep iOS 44pt sprite and 1.5pt stroke');
assertSource(page.includes("struct LockedCatalogCard") && page.includes(".border({ width: 1.5, color: LPColor.ink, style: BorderStyle.Dashed })"), 'Catalog locked cards keep iOS dashed 1.5pt stroke');
assertSource(page.includes('function deathBucketLabel'), 'Catalog detail uses iOS death bucket labels');
assertSource(page.includes("return '圆满'"), 'Catalog detail maps natural death to 圆满');
assertSource(page.includes("return '短命'"), 'Catalog detail maps early death buckets to 短命');
assertSource(page.includes('private memorialTimerId: number = -1'), 'Catalog detail owns a single memorial progress timer');
assertSource(page.includes('this.memorialTimerId = setInterval(() => {') && page.includes('}, 150);'), 'Catalog detail advances memorial progress every 150ms like iOS');
assertSource(page.includes('this.memorialProgress = (this.memorialProgress + 0.008) % 1'), 'Catalog detail wraps memorial progress like iOS');
assertSource(page.includes('private clearMemorialTimer()'), 'Catalog detail clears memorial timer on pause/navigation');

if (failures.length > 0) {
  console.error('Catalog model parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Catalog model parity checks passed.');
