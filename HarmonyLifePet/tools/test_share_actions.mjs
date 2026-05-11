#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const failures = [];

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const service = read('entry/src/main/ets/services/ShareActionService.ets');
const catalogOverlay = read('entry/src/main/ets/components/CatalogShareOverlay.ets');
const dashedRule = read('entry/src/main/ets/components/DashedRule.ets');
const togetherPage = read('entry/src/main/ets/pages/TogetherPage.ets');

assertSource(service.includes("import { pasteboard } from '@kit.BasicServicesKit'"), 'ShareActionService imports pasteboard');
assertSource(service.includes("import { fileIo } from '@kit.CoreFileKit'"), 'ShareActionService imports file I/O');
assertSource(service.includes("import { image } from '@kit.ImageKit'"), 'ShareActionService imports Image Kit');
assertSource(service.includes("import { photoAccessHelper } from '@kit.MediaLibraryKit'"), 'ShareActionService imports Media Library Kit');
assertSource(service.includes("import { systemShare } from '@kit.ShareKit'"), 'ShareActionService imports ShareKit');
assertSource(service.includes('pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN'), 'ShareActionService creates plain-text pasteboard data');
assertSource(service.includes('pasteboard.getSystemPasteboard().setData'), 'ShareActionService writes to the system pasteboard');
assertSource(service.includes('new systemShare.SharedData'), 'ShareActionService creates SharedData');
assertSource(service.includes('new systemShare.ShareController'), 'ShareActionService creates ShareController');
assertSource(service.includes('await controller.show(context)'), 'ShareActionService opens the system share panel');
assertSource(service.includes('message: `已复制 ${code}`'), 'Invite copy success toast mirrors iOS copy');
assertSource(service.includes("message: '已生成分享卡'"), 'Invite share success toast mirrors iOS copy');
assertSource(service.includes('photoAccessHelper.getPhotoAccessHelper(context)'), 'ShareActionService gets PhotoAccessHelper');
assertSource(service.includes("helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png')"), 'ShareActionService creates a gallery image asset');
assertSource(service.includes('fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)'), 'ShareActionService opens gallery asset URI for writing');
assertSource(service.includes('imagePackerApi.packToFile(pixelMap, file.fd'), 'ShareActionService encodes PixelMap to the gallery file');
assertSource(service.includes('imagePackerApi.release()'), 'ShareActionService releases the ImagePacker');

assertSource(catalogOverlay.includes('SaveButton'), 'Catalog share overlay uses SaveButton for gallery authorization');
assertSource(catalogOverlay.includes('SaveButtonOnClickResult.SUCCESS'), 'Catalog share overlay handles SaveButton authorization result');
assertSource(catalogOverlay.includes("componentSnapshot.get('catalog-share-card')"), 'Catalog share overlay captures the share card component');
assertSource(catalogOverlay.includes(".id('catalog-share-card')"), 'Catalog share overlay marks the share card for snapshot capture');
assertSource(catalogOverlay.includes('shareCatalogCard(this.context(), this.pet)'), 'Catalog share overlay passes UIAbilityContext to system share');
assertSource(catalogOverlay.includes("FauxQr({ seed: `lifepet-${this.pet.id}` })"), 'Catalog share QR uses the same seeded prefix as iOS');
assertSource(catalogOverlay.includes('for (let y = 0; y < 21; y++)') && catalogOverlay.includes('for (let x = 0; x < 21; x++)'), 'Catalog share QR uses the iOS 21x21 grid');
assertSource(catalogOverlay.includes('this.markerCell(x, y, 14, 0)') && catalogOverlay.includes('this.markerCell(x, y, 0, 14)'), 'Catalog share QR keeps the three iOS marker positions');
assertSource(catalogOverlay.includes('markerArea ? marker : state / 4294967295 < 0.48'), 'Catalog share QR preserves the iOS empty ring inside marker areas');
assertSource(catalogOverlay.includes("import { BreathingPixelPetSprite } from './PixelPetSprite';"), 'Catalog share overlay imports the shared breathing pixel sprite renderer');
assertSource(catalogOverlay.includes('BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 70 })'), 'Catalog share card uses the iOS 70pt breathing pet hero');
assertSource(catalogOverlay.includes('.margin({ top: 4, bottom: 2 })'), 'Catalog share pet hero keeps iOS top/bottom spacing');
assertSource(catalogOverlay.includes('.margin({ top: 2 })'), 'Catalog share day copy keeps iOS top spacing');
assertSource(catalogOverlay.includes('.width(26)'), 'Catalog share card keeps the narrower iOS D-day moment label');
assertSource(catalogOverlay.includes('Column({ space: 6 })') && catalogOverlay.includes('.padding({ left: 14, right: 14, top: 16, bottom: 14 })'), 'Catalog share card keeps iOS card spacing and padding');
assertSource(catalogOverlay.includes('Column({ space: 2 })') && catalogOverlay.includes('.padding({ left: 10, right: 10 })'), 'Catalog share moments keep iOS compact row spacing and inset');
assertSource(catalogOverlay.includes('.padding({ top: 10, bottom: 10 })'), 'Catalog share stats strip keeps iOS vertical padding');
assertSource(catalogOverlay.includes('.margin({ top: 10 })'), 'Catalog share stats block keeps iOS 10pt top offset');
assertSource(catalogOverlay.includes('.margin({ top: 4, bottom: 8 })'), 'Catalog share QR block keeps iOS dashed-rule-to-QR spacing');
assertSource(catalogOverlay.includes("Text('扫码注册')") && catalogOverlay.includes("Text('LifePet')") && catalogOverlay.includes('fontColor(LPColor.coral)'), 'Catalog share QR title highlights LifePet like iOS');
assertSource(catalogOverlay.includes('养一只属于你自己的'), 'Catalog share card keeps the iOS QR subtitle');
assertSource(catalogOverlay.includes("Text('lifepet.app · via FISH')") && catalogOverlay.includes('fontColor(LPColor.faint)'), 'Catalog share footer uses the iOS faint token');
assertSource(catalogOverlay.includes("ShareStat({ symbol: '❤️'"), 'Catalog share card keeps the iOS mood emoji');
assertSource(catalogOverlay.includes("Button('🌹 分享到小红书')"), 'Catalog share actions keep the iOS Xiaohongshu label');
assertSource(catalogOverlay.includes("Button('🌹 分享到小红书')") && catalogOverlay.includes('.height(44)') && catalogOverlay.includes(".fontFamily('monospace')") && catalogOverlay.includes('.letterSpacing(2.2)') && catalogOverlay.includes('.borderRadius(2)'), 'Catalog share Xiaohongshu action keeps iOS LPButton coral geometry');
assertSource(!catalogOverlay.includes("Button('关闭')"), 'Catalog share overlay matches iOS sheet with no explicit close button');
assertSource(catalogOverlay.includes("import { DashedRule } from './DashedRule'"), 'Catalog share overlay imports the dashed rule component');
assertSource((catalogOverlay.match(/DashedRule\(/g) ?? []).length >= 3, 'Catalog share card uses dashed rules around stats and QR blocks');
assertSource(dashedRule.includes('Row({ space: 3 })') && dashedRule.includes('segments: number = 32'), 'DashedRule mirrors the iOS short dash separator');
assertSource(catalogOverlay.includes('.padding(4)') && catalogOverlay.includes('.border({ width: 1.5, color: LPColor.ink })'), 'Catalog share QR frame keeps iOS padding and 1.5pt border');
assertSource(catalogOverlay.includes(".width('100%')") && catalogOverlay.includes(".height('100%')"), 'Catalog share QR cells fill the iOS 21x21 grid units');
assertSource(!catalogOverlay.includes('.width(3)\n            .height(3)'), 'Catalog share QR cells are not fixed undersized dots');
assertSource(catalogOverlay.includes('.borderRadius(999)') && catalogOverlay.includes(".shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })"), 'Catalog share toast uses iOS capsule stroke/shadow treatment');

assertSource(togetherPage.includes('copyInviteCode'), 'Together invite keeps copy action');
assertSource(togetherPage.includes('shareInviteCode(this.context()'), 'Together invite passes UIAbilityContext to system share');

if (failures.length > 0) {
  console.error('Share action source checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Share action source checks passed.');
