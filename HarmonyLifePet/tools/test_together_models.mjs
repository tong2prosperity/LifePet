#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/TogetherModels.ets'), 'utf8');
const page = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/TogetherPage.ets'), 'utf8');
const pixelSprite = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/PixelPetSprite.ets'), 'utf8');
const failures = [];

function assertSource(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

const needles = [
  "id: 'nova'",
  "id: 'mom'",
  "id: 'aj'",
  '早安~ 今天慢跑加油 🏃',
  '太棒了 ✨',
  '记得吃早饭 🥣',
  '来！20 点见 💪',
  '全社区累计步行 1,000,000 步',
  "myRank: '#84'",
  "exerciseCount: '1,024'"
];

for (const needle of needles) {
  assertSource(source.includes(needle), `TogetherModels keeps iOS mock data: ${needle}`);
}

assertSource((source.match(/id: 'p\d+'/g) ?? []).length === 12, 'Together plaza keeps 12 community members');
assertSource(source.includes("import { PetSpriteName } from './PetSpriteModels';"), 'Together models use the shared PetSpriteName identity enum');
assertSource(source.includes('sprite: PetSpriteName.Blob') && source.includes('sprite: PetSpriteName.Noct') && source.includes('sprite: PetSpriteName.Hush'), 'Together friends keep iOS PetSprite identities');
assertSource(source.includes('sprite: PetSpriteName.Bean') && source.includes("name: '老王'") && source.includes("name: '小满'"), 'Together plaza keeps iOS bean members');
assertSource(!/blob_(run|walk|lying|sleep)/.test(source), 'Together models no longer store animation sequence names as pet identity');
assertSource(source.includes('return Math.min(1, snapshot.goalCurrent / snapshot.goalTotal)'), 'Together goal percent clamps at 100%');
assertSource(page.includes('TogetherTabButton'), 'Together root uses a custom segmented tab button');
assertSource(page.includes("import { PixelPetSprite } from '../components/PixelPetSprite';"), 'Together page renders catalog-style static pixel sprites');
assertSource(!page.includes("import { SpriteAnimator } from '../components/SpriteAnimator';"), 'Together page no longer uses live animation sequences for catalog pets');
assertSource(page.includes('PixelPetSprite({ sprite: this.friend.sprite, size: 52 })'), 'Friend cards render the iOS 52pt PixelPetSprite portrait');
assertSource(page.includes('PixelPetSprite({ sprite: this.sprite, size: 62 })'), 'Twin stage renders iOS PixelPetSprite portraits');
assertSource(page.includes('PlazaPetCell({ name: this.store.petName, sprite: PetSpriteName.Bean, isMe: true })'), 'Plaza inserts the user as the iOS bean sprite');
assertSource(pixelSprite.includes('case PetSpriteName.Bean') && pixelSprite.includes('{ x: 4, y: 1, w: 8, h: 12 }'), 'PixelPetSprite ports the iOS bean rect table');
assertSource(pixelSprite.includes('case PetSpriteName.Noct') && pixelSprite.includes('{ x: 11, y: 2, w: 2, h: 2 }'), 'PixelPetSprite ports the iOS noct ear rects');
assertSource(pixelSprite.includes('case PetSpriteName.Hush') && pixelSprite.includes('{ x: 4, y: 4, w: 8, h: 8 }'), 'PixelPetSprite ports the iOS hush rect table');
assertSource(page.includes('.width(30)') && page.includes('.height(3)') && page.includes('this.active ? LPColor.coral : Color.Transparent'), 'Together segmented header keeps iOS active coral underline');
assertSource(page.includes('.height(1.5)') && page.includes('.backgroundColor(LPColor.ink)'), 'Together segmented header keeps the iOS bottom-only ink rule');
assertSource(page.includes("import { DashedRule } from '../components/DashedRule';"), 'Together uses the shared dashed rule for iOS separators');
assertSource((page.match(/Text\('‹'\)/g) ?? []).length >= 2 && page.includes('fontColor(LPColor.coral)'), 'Together detail/invite back controls keep the iOS coral chevron');
assertSource(!page.includes("Button('‹ 返回')"), 'Together no longer renders a single-color back button');
assertSource(page.includes('struct AddFriendButton') && page.includes('AddFriendButton({'), 'Friends header add action uses the iOS stamped offset button');
assertSource(page.includes("Text('+ 添加')") && page.includes('.width(64)') && page.includes('.height(34)'), 'Friends header add action keeps the iOS compact add-button size');
assertSource(page.includes('.padding({ left: 16, right: 16, top: 12, bottom: 34 })'), 'Friends list padding matches the iOS 16pt horizontal and 12pt top inset');
assertSource(page.includes('Text(this.friend.petName)') && page.includes('.letterSpacing(0.5)'), 'Friend cards keep iOS pet-name tracking');
assertSource(page.includes('.border({ width: 1.5, color: LPColor.ink })'), 'Friend cards keep the iOS 1.5pt ink outer stroke');
assertSource(page.includes('.width(8)') && page.includes('.height(8)') && page.includes('.borderRadius(4)'), 'Friend cards keep the iOS 8pt new-message dot');
assertSource(page.includes("TextInput({ placeholder: '说点什么…'"), 'Friend detail input keeps the iOS ellipsis placeholder');
assertSource(page.includes("QuickChip({ label: '记得喝水 💧'"), 'Friend detail quick chips keep the iOS water reminder copy');
assertSource(page.includes('一下 👋') && page.includes('加油 ✨'), 'Friend detail action toasts keep iOS emoji feedback');
assertSource(page.includes('private messageScroller: Scroller = new Scroller()'), 'Friend detail message thread has a dedicated scroller like iOS ScrollViewReader');
assertSource(page.includes('Scroll(this.messageScroller)') && page.includes('.constraintSize({ maxHeight: 154 })'), 'Friend detail message thread keeps iOS max-height scroll area');
assertSource(page.includes('this.messageScroller.scrollEdge(Edge.Bottom)'), 'Friend detail scrolls new local messages to the bottom like iOS');
assertSource(page.includes("TextInput({ placeholder: '说点什么…', text: this.draft })") && page.includes('.border({ width: 1.5, color: LPColor.ink })'), 'Friend detail input and message card keep iOS 1.5pt ink strokes');
assertSource(page.includes("Button(`戳一下 ${this.friend.petName}`)") && page.includes("Button('给 TA 加油')") && page.includes('.shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })'), 'Friend detail action buttons keep iOS stamped offset shadow');
assertSource(page.includes("@Prop @Watch('onPokeNonceChanged') pokeNonce") && page.includes('private runPokeShake()'), 'Twin stage pet column replays iOS poke shake on nonce changes');
assertSource(page.includes("@Prop @Watch('onCheerNonceChanged') cheerNonce") && page.includes('private runCheerFloat()'), 'Twin stage pet column replays iOS cheer float on nonce changes');
assertSource(page.includes("Text('✨')") && page.includes('this.cheerOpacity') && page.includes('this.cheerY'), 'Twin stage renders the iOS cheer sparkle overlay');
assertSource(page.includes('.translate({ x: this.shakeX, y: this.shakeY })'), 'Twin stage translates the friend pet during poke shake');
assertSource(!page.includes('highlight: this.pokeNonce > 0 || this.cheerNonce > 0'), 'Twin stage no longer uses non-iOS permanent name highlighting');
assertSource(page.includes('struct LightBand') && page.includes('@State phase: number = 0') && page.includes('setInterval(() => {') && page.includes('this.phase = (this.phase + 1 / 78) % 1'), 'Twin stage light band animates on a 2.6s iOS-style phase loop');
assertSource(page.includes('private dotIndexes(): number[]') && page.includes('return [0, 1, 2, 3]') && page.includes('private dotOpacity(index: number): number'), 'Twin stage light band keeps the iOS four flowing particles with edge fade');
assertSource(page.includes(".border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })"), 'Twin stage keeps the iOS 1.5pt inner LCD dashed frame');
assertSource(page.includes('backgroundColor(this.message.who === MessageSender.Me ? LPColor.coral : LPColor.paperCool)'), 'Friend detail own message bubble uses the iOS coral fill');
assertSource(page.includes('DashedRule({ color: LPColor.lcdDash })'), 'Friend health compare rows use iOS-style dashed separators');
assertSource(page.includes('.rotate({ angle: -0.3 })'), 'Plaza banner keeps the iOS slight sticky-note rotation');
assertSource((page.match(/setTimeout\(\(\) => \{/g) ?? []).length >= 2, 'Together toasts auto-dismiss like iOS friend detail and invite views');
assertSource((page.match(/if \(this.toast === text\)/g) ?? []).length >= 2, 'Together toast auto-dismiss keeps iOS stale-toast guard');
assertSource(page.includes('this.toastWith(result.message)'), 'Invite share/copy result uses the auto-dismiss toast path');
assertSource(page.includes("copyInviteCode('FISH-7K2')"), 'Invite copy action uses the iOS static invite code');
assertSource(page.includes("shareInviteCode(this.context(), 'FISH-7K2')"), 'Invite share action uses the iOS static invite code');
assertSource(page.includes('struct InviteFullAction') && page.includes('InviteFullAction({'), 'Invite scan/code actions use the shared iOS-style full-width action button');
assertSource(page.includes('.translate({ x: 2, y: 2 })'), 'Invite action buttons keep the iOS stamped offset shadow');
assertSource(page.includes('.padding({ left: 12, right: 12 })') && !page.includes('Button(this.label)\n      .layoutWeight(1)'), 'Invite relation chips use natural chip width like iOS FlowLayout');
assertSource(page.includes('扫码功能即将上线'), 'Invite scan placeholder matches iOS copy');
assertSource(page.includes('输入对方邀请码 · 即将上线'), 'Invite code-entry placeholder matches iOS copy');
assertSource(!page.includes('已选择 ') && !page.includes('已清除关系昵称'), 'Invite relation chips stay cosmetic like iOS');

if (failures.length > 0) {
  console.error('Together model parity checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Together model parity checks passed.');
