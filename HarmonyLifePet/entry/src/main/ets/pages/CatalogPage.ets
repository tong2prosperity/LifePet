import { CatalogIncenseOverlay, MemorialWaveform } from '../components/CatalogIncenseOverlay';
import { CatalogShareOverlay } from '../components/CatalogShareOverlay';
import { CatalogTrajectoryChart, CatalogTrajectoryLegend } from '../components/CatalogTrajectoryChart';
import { DashedRule } from '../components/DashedRule';
import { BreathingPixelPetSprite, PixelPetLockedSprite, PixelPetSprite } from '../components/PixelPetSprite';
import { CatalogMoment, CatalogPet, DeathType, demoCatalogPets } from '../models/CatalogModels';
import { StatKind } from '../models/PetModels';
import { MemorialAudioPlayer, memorialAudioForPet } from '../services/MemorialAudioPlayer';
import { PetStateStore } from '../stores/PetStateStore';
import { LPColor } from '../theme/LPTheme';
import { common } from '@kit.AbilityKit';

const LIVE_PET_ID = 'live';
const DEFAULT_CATALOG_PET: CatalogPet = demoCatalogPets[0];

@Component
export struct CatalogPage {
  @ObjectLink store: PetStateStore;
  @State selectedPetId: string = '';
  @State showingShareCard: boolean = false;
  @State showingIncense: boolean = false;
  @State memorialPlaying: boolean = false;
  @State memorialProgress: number = 0.18;
  private memorialAudio: MemorialAudioPlayer = new MemorialAudioPlayer();
  private memorialTimerId: number = -1;

  private liveStat(kind: StatKind): number {
    const found = this.store.stats.find((item) => item.kind === kind);
    return found ? found.value : 0;
  }

  private deadPets(): CatalogPet[] {
    return demoCatalogPets.filter((pet: CatalogPet) => !pet.isAlive);
  }

  private totalCount(): number {
    return demoCatalogPets.length;
  }

  private totalDays(): number {
    return this.store.dayCount + this.deadPets().reduce((sum: number, pet: CatalogPet) => sum + pet.totalDays, 0);
  }

  private naturalCount(): number {
    return this.deadPets().filter((pet: CatalogPet) => pet.deathType === DeathType.Natural).length;
  }

  private earlyCount(): number {
    return this.deadPets().length - this.naturalCount();
  }

  private lockedSlots(): number {
    const dead = this.deadPets().length;
    const target = Math.max(6, dead + ((3 - dead % 3) % 3) + 3);
    return Math.max(0, target - dead);
  }

  private lockedSlotItems(): number[] {
    const out: number[] = [];
    for (let index = 0; index < this.lockedSlots(); index++) {
      out.push(index);
    }
    return out;
  }

  private livePet(): CatalogPet {
    const base = demoCatalogPets[0];
    const vitality = this.liveStat(StatKind.Vitality);
    const energy = this.liveStat(StatKind.Energy);
    const mood = this.liveStat(StatKind.Mood);
    return {
      id: LIVE_PET_ID,
      name: this.store.petName,
      sprite: base.sprite,
      isAlive: true,
      dates: base.dates,
      days: this.store.dayCount,
      totalDays: this.store.dayCount,
      stats: { vitality, energy, mood },
      series: base.series,
      moments: base.moments,
      bio: base.bio,
      isRare: false
    };
  }

  private currentPet(): CatalogPet {
    if (this.selectedPetId === LIVE_PET_ID) {
      return this.livePet();
    }
    const found = demoCatalogPets.find((pet: CatalogPet) => pet.id === this.selectedPetId);
    return found ? found : this.livePet();
  }

  aboutToDisappear(): void {
    this.stopMemorialPlayback();
  }

  private toggleMemorial(): void {
    const shouldPlay = !this.memorialPlaying;
    if (shouldPlay) {
      this.memorialPlaying = true;
      this.startMemorialProgressTimer();
      void this.syncMemorialAudio(true);
      return;
    }
    this.pauseMemorialPlayback();
  }

  private startMemorialProgressTimer(): void {
    this.clearMemorialTimer();
    this.memorialTimerId = setInterval(() => {
      this.memorialProgress = (this.memorialProgress + 0.008) % 1;
    }, 150);
  }

  private clearMemorialTimer(): void {
    if (this.memorialTimerId >= 0) {
      clearInterval(this.memorialTimerId);
      this.memorialTimerId = -1;
    }
  }

  private pauseMemorialPlayback(): void {
    this.clearMemorialTimer();
    this.memorialPlaying = false;
    void this.memorialAudio.pause();
  }

  private stopMemorialPlayback(): void {
    this.clearMemorialTimer();
    this.memorialPlaying = false;
    void this.memorialAudio.stop();
  }

  private async syncMemorialAudio(shouldPlay: boolean): Promise<void> {
    if (!shouldPlay) {
      await this.memorialAudio.pause();
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    await this.memorialAudio.play(context, memorialAudioForPet(this.currentPet()));
  }

  build() {
    Stack() {
      if (this.selectedPetId === '') {
        CatalogList({
          store: this.store,
          onSelect: (id: string) => {
            this.stopMemorialPlayback();
            this.selectedPetId = id;
            this.memorialProgress = 0.18;
          }
        })
      } else {
        CatalogDetail({
          pet: this.currentPet(),
          memorialPlaying: this.memorialPlaying,
          memorialProgress: this.memorialProgress,
          onBack: () => {
            this.stopMemorialPlayback();
            this.selectedPetId = '';
            this.showingShareCard = false;
            this.showingIncense = false;
          },
          onShare: () => {
            this.showingShareCard = true;
          },
          onToggleMemorial: () => this.toggleMemorial(),
          onIncense: () => {
            this.stopMemorialPlayback();
            this.showingIncense = true;
          }
        })
      }

      if (this.showingShareCard) {
        CatalogShareOverlay({
          pet: this.currentPet(),
          onClose: () => {
            this.showingShareCard = false;
          }
        })
      }

      if (this.showingIncense) {
        CatalogIncenseOverlay({
          pet: this.currentPet(),
          onClose: () => {
            this.showingIncense = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}

@Component
struct CatalogList {
  @ObjectLink store: PetStateStore;
  onSelect: (id: string) => void = () => {};

  private liveStat(kind: StatKind): number {
    const found = this.store.stats.find((item) => item.kind === kind);
    return found ? found.value : 0;
  }

  private deadPets(): CatalogPet[] {
    return demoCatalogPets.filter((pet: CatalogPet) => !pet.isAlive);
  }

  private aliveCount(): number {
    return demoCatalogPets.filter((pet: CatalogPet) => pet.isAlive).length;
  }

  private totalCount(): number {
    return demoCatalogPets.length;
  }

  private totalDays(): number {
    return this.store.dayCount + this.deadPets().reduce((sum: number, pet: CatalogPet) => sum + pet.totalDays, 0);
  }

  private naturalCount(): number {
    return this.deadPets().filter((pet: CatalogPet) => pet.deathType === DeathType.Natural).length;
  }

  private earlyCount(): number {
    return this.deadPets().length - this.naturalCount();
  }

  private lockedSlots(): number {
    const dead = this.deadPets().length;
    const target = Math.max(6, dead + ((3 - dead % 3) % 3) + 3);
    return Math.max(0, target - dead);
  }

  private lockedSlotItems(): number[] {
    const out: number[] = [];
    for (let index = 0; index < this.lockedSlots(); index++) {
      out.push(index);
    }
    return out;
  }

  private livePet(): CatalogPet {
    const base = demoCatalogPets[0];
    return {
      id: LIVE_PET_ID,
      name: this.store.petName,
      sprite: base.sprite,
      isAlive: true,
      dates: base.dates,
      days: this.store.dayCount,
      totalDays: this.store.dayCount,
      stats: {
        vitality: this.liveStat(StatKind.Vitality),
        energy: this.liveStat(StatKind.Energy),
        mood: this.liveStat(StatKind.Mood)
      },
      series: base.series,
      moments: base.moments,
      bio: base.bio,
      isRare: false
    };
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 2 }) {
          Row({ space: 0 }) {
            Text('图鉴')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.ink)
            Text('.')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
          }
          Row({ space: 0 }) {
            Text('陪伴过 ')
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
              .letterSpacing(1)
            Text(this.totalCount().toString())
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(LPColor.coral)
              .letterSpacing(1)
            Text(' 只 · 累计 ')
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
              .letterSpacing(1)
            Text(this.totalDays().toString())
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(LPColor.coral)
              .letterSpacing(1)
            Text(' 天')
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
              .letterSpacing(1)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 0 }) {
          DashedRule({ color: LPColor.lcdDash })
          Row({ space: 6 }) {
            CatalogStatChip({ value: this.aliveCount(), label: '养育中', live: true })
            CatalogStatChip({ value: this.naturalCount(), label: '圆满' })
            CatalogStatChip({ value: this.earlyCount(), label: '短命' })
            CatalogStatChip({ value: this.totalDays(), label: '总天数' })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          DashedRule({ color: LPColor.lcdDash })
        }
        .width('100%')

        SectionHeader({ tag: '养育中' })
          .width('100%')

        LiveCatalogCard({
          pet: this.livePet(),
          onOpen: () => this.onSelect(LIVE_PET_ID)
        })

        SectionHeader({ tag: '已升天', count: this.deadPets().length })
          .width('100%')

        Grid() {
          ForEach(this.deadPets(), (pet: CatalogPet) => {
            GridItem() {
              DeadCatalogCard({
                pet,
                onOpen: () => this.onSelect(pet.id)
              })
            }
          }, (pet: CatalogPet) => pet.id)

          ForEach(this.lockedSlotItems(), (slot: number) => {
            GridItem() {
              LockedCatalogCard()
            }
          }, (slot: number) => `locked-${slot}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')

        Column({ space: 3 }) {
          Row({ space: 0 }) {
            Text('陪伴过 ')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.stickyInk)
            Text(this.totalCount().toString())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
            Text(' 只 · 养活 ')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.stickyInk)
            Text((this.aliveCount() + this.naturalCount()).toString())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
            Text(' 只 · 送走 ')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.stickyInk)
            Text(this.earlyCount().toString())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
            Text(' 只')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.stickyInk)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          Text('养死了也别难过，下一只会更好。')
            .fontSize(12)
            .fontStyle(FontStyle.Italic)
            .fontColor('#5A4A2ABF')
            .textAlign(TextAlign.Center)
        }
          .width('100%')
          .padding(12)
          .backgroundColor(LPColor.sticky)
          .border({ width: 1.5, color: LPColor.ink, style: BorderStyle.Dashed })
          .borderRadius(10)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 34 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}

@Component
struct CatalogStatChip {
  @Prop value: number = 0;
  @Prop label: string = '';
  @Prop live: boolean = false;

  build() {
    Column({ space: 3 }) {
      Text(this.value.toString())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.live ? LPColor.coral : LPColor.ink)
      Text(this.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(LPColor.paperCool)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(8)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct SectionHeader {
  @Prop tag: string = '';
  @Prop count: number = -1;

  build() {
    Row({ space: 10 }) {
      Text(this.tag)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(LPColor.ink)
      DashedRule({ color: LPColor.lcdDash })
        .layoutWeight(1)
      if (this.count >= 0) {
        Text(`${this.count} 只`)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
      }
    }
    .width('100%')
  }
}

@Component
struct CatalogDetail {
  @Prop pet: CatalogPet = DEFAULT_CATALOG_PET;
  @Prop memorialPlaying: boolean = false;
  @Prop memorialProgress: number = 0.18;
  onBack: () => void = () => {};
  onShare: () => void = () => {};
  onToggleMemorial: () => void = () => {};
  onIncense: () => void = () => {};

  private daysNumber(): number {
    return this.pet.isAlive ? this.pet.days : this.pet.totalDays;
  }

  private heroDates(): string {
    return this.pet.isAlive ? `${this.pet.dates} · 已陪伴 ${this.pet.days} 天` : `${this.pet.dates} · ${this.pet.totalDays} 天`;
  }

  private trajectoryTitle(): string {
    return this.pet.isAlive ? `生命轨迹 · 至今 ${this.pet.days} 天` : `生命轨迹 · ${this.pet.totalDays} 天`;
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Row({ space: 2 }) {
            Text('‹')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
            Text('返回图鉴')
              .fontSize(15)
              .fontColor(LPColor.ink)
          }
            .height(34)
            .onClick(() => this.onBack())
          Blank()
        }
        .width('100%')

        DetailHero({ pet: this.pet, heroDates: this.heroDates() })

        Row({ space: 6 }) {
          DetailStatCell({ symbol: '💪', value: this.pet.stats.vitality, label: '体力' })
          DetailStatCell({ symbol: '⚡', value: this.pet.stats.energy, label: '精力' })
          DetailStatCell({ symbol: '❤️', value: this.pet.stats.mood, label: '心情', coral: true })
          DetailStatCell({ symbol: '📅', value: this.daysNumber(), label: this.pet.isAlive ? '陪伴中' : '共陪伴' })
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text(this.trajectoryTitle())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.ink)
            Blank()
            CatalogTrajectoryLegend()
          }
          .width('100%')
          CatalogTrajectoryChart({ pet: this.pet })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(LPColor.paperCool)
        .border({ width: 1.5, color: LPColor.ink })
        .borderRadius(10)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })

        Column({ space: 0 }) {
          Text('关键时刻')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
            .width('100%')
            .margin({ bottom: 6 })

          ForEach(this.pet.moments, (moment: CatalogMoment, index: number) => {
            MomentRow({ moment, showRule: index > 0 })
          }, (moment: CatalogMoment) => `${moment.day}-${moment.title}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(LPColor.paperCool)
        .border({ width: 1.5, color: LPColor.ink })
        .borderRadius(10)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })

        Column({ space: 6 }) {
          Text(this.pet.isAlive ? '它的故事' : '— 它的故事 —')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.stickyInk)
          Text(this.pet.bio)
            .fontSize(15)
            .fontColor(LPColor.stickyInk)
            .lineHeight(22)
          Text('— via LifePet')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor('#5A4A2A99')
            .width('100%')
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .backgroundColor(LPColor.sticky)
        .border({ width: 1.5, color: LPColor.ink })
        .borderRadius(10)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
        .rotate({ angle: -0.3 })

        if (!this.pet.isAlive) {
          MemorialPanel({
            pet: this.pet,
            playing: this.memorialPlaying,
            progress: this.memorialProgress,
            onToggle: () => this.onToggleMemorial(),
            onIncense: () => this.onIncense()
          })
        }

        Button('↗ 分享')
          .width('100%')
          .height(44)
          .fontSize(11)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .letterSpacing(2.2)
          .backgroundColor(LPColor.ink)
          .fontColor(LPColor.paper)
          .border({ width: 1.5, color: LPColor.ink })
          .borderRadius(2)
          .onClick(() => this.onShare())
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 34 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}

@Component
struct DetailHero {
  @Prop pet: CatalogPet = DEFAULT_CATALOG_PET;
  @Prop heroDates: string = '';

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(238)
        .backgroundColor(LPColor.lcd)
        .border({ width: 2, color: LPColor.ink })
        .borderRadius(14)
      Column()
        .width('96%')
        .height(226)
        .border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })
        .borderRadius(10)
      Column({ space: 4 }) {
        BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 90 })
          .height(100)
        Text(this.pet.name)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.ink)
          .letterSpacing(1.5)
        Text(this.heroDates)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(LPColor.lcdInk)
        Row({ space: 6 }) {
          if (this.pet.isAlive) {
            DetailTag({ label: 'LIVE', coral: false })
            DetailTag({ label: '养育中', coral: false })
          } else {
            if (this.pet.isRare) {
              DetailTag({ label: 'RARE', coral: true })
            }
            DetailTag({ label: deathBucketLabel(this.pet.deathType), coral: false })
            DetailTag({ label: '已升天', dead: true })
          }
        }
        .margin({ top: 4 })
      }
      .width('100%')
      .padding(14)
    }
    .width('100%')
    .height(238)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
  }
}

@Component
struct DetailTag {
  @Prop label: string = '';
  @Prop coral: boolean = false;
  @Prop dead: boolean = false;

  build() {
    Text(this.label)
      .fontSize(9)
      .fontFamily('monospace')
      .fontColor(this.coral || this.dead ? Color.White : LPColor.ink)
      .letterSpacing(1)
      .padding({ left: 8, right: 8, top: 1, bottom: 1 })
      .backgroundColor(this.coral ? LPColor.coral : this.dead ? LPColor.muted : LPColor.paperCool)
      .border({ width: 1.5, color: this.coral ? LPColor.coral : this.dead ? LPColor.muted : LPColor.ink })
      .borderRadius(8)
  }
}

@Component
struct DetailStatCell {
  @Prop symbol: string = '';
  @Prop value: number = 0;
  @Prop label: string = '';
  @Prop coral: boolean = false;

  build() {
    Column({ space: 3 }) {
      Text(this.symbol)
        .fontSize(14)
      Text(this.value.toString())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.coral ? LPColor.coral : LPColor.ink)
      Text(this.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(LPColor.paperCool)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(8)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct MomentRow {
  @Prop moment: CatalogMoment = { day: 1, title: '', isDeath: false };
  @Prop showRule: boolean = false;

  build() {
    Column({ space: 0 }) {
      if (this.showRule) {
        DashedRule({ color: LPColor.lcdDash })
          .margin({ top: 5, bottom: 5 })
      }
      Row({ space: 10 }) {
        Text(`D${this.moment.day.toString().padStart(2, '0')}`)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(this.moment.isDeath ? LPColor.muted : LPColor.coral)
          .width(34)
        Text(this.moment.isDeath ? `${this.moment.title} 🕊️` : this.moment.title)
          .fontSize(14)
          .fontColor(this.moment.isDeath ? LPColor.muted : LPColor.ink)
          .fontStyle(this.moment.isDeath ? FontStyle.Italic : FontStyle.Normal)
          .layoutWeight(1)
          .maxLines(2)
        if (this.moment.value) {
          Text(this.moment.value)
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
        }
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Component
struct MemorialPanel {
  @Prop pet: CatalogPet = DEFAULT_CATALOG_PET;
  @Prop playing: boolean = false;
  @Prop progress: number = 0.18;
  onToggle: () => void = () => {};
  onIncense: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('♪')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.coral)
        Text(this.pet.memorialTitle ?? '《纪念曲》')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.stickyInk)
        Blank()
        Text(this.pet.memorialDuration ?? '0:00')
          .fontSize(9)
          .fontFamily('monospace')
          .letterSpacing(0.5)
          .fontColor('#5A4A2AAA')
      }
      .width('100%')

      MemorialWaveform({ pet: this.pet, progress: this.progress, muted: false })

      Row({ space: 8 }) {
        Button(this.playing ? 'Ⅱ' : '▶')
          .width(30)
          .height(30)
          .fontSize(10)
          .fontColor(LPColor.paperCard)
          .backgroundColor(this.playing ? LPColor.coral : LPColor.stickyInk)
          .borderRadius(15)
          .onClick(() => this.onToggle())
        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width('100%')
            .height(2)
            .backgroundColor('#5A4A2A40')
            .borderRadius(1)
          Column()
            .width(`${Math.floor(this.progress * 100)}%`)
            .height(2)
            .backgroundColor(LPColor.stickyInk)
            .borderRadius(1)
        }
        .layoutWeight(1)
        .height(12)
      }
      .width('100%')

      Text('由 TA 一生的健康数据生成 · 时长 15 秒')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor('#5A4A2AAA')
        .width('100%')
        .textAlign(TextAlign.Center)

      DashedRule({ color: '#C8A860' })
        .margin({ top: 3, bottom: 4 })

      Button('🕯 上香')
        .width('100%')
        .height(38)
        .fontSize(15)
        .fontColor('#F0D8A0')
        .backgroundColor('#4A3820')
        .border({ width: 1.5, color: '#3A2810' })
        .borderRadius(8)
        .shadow({ radius: 0, color: '#3A2810', offsetX: 2, offsetY: 2 })
        .onClick(() => this.onIncense())
      Text('点燃一炷香 · 聆听 TA 的 15 秒纪念曲')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor('#5A4A2A99')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F5EDE0')
    .border({ width: 1.5, color: LPColor.stickyInk })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.stickyInk, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct LiveCatalogCard {
  @Prop pet: CatalogPet = DEFAULT_CATALOG_PET;
  onOpen: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('96%')
        .height(98)
        .border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })
        .borderRadius(10)
        .margin({ left: 5, top: 5 })
      Row({ space: 14 }) {
        BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 60 })
          .width(80)
          .height(80)
        Column({ space: 4 }) {
          Text(this.pet.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
            .letterSpacing(1)
          Text(this.pet.dates)
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
          Text(`已陪伴 · 第 ${this.pet.days} 天`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor(LPColor.coral)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      Text('LIVE')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(Color.White)
        .letterSpacing(1)
        .padding({ left: 10, right: 10, top: 2, bottom: 2 })
        .backgroundColor(LPColor.coral)
        .borderRadius(4)
        .margin({ left: 14 })
    }
    .width('100%')
    .height(108)
    .padding(14)
    .backgroundColor(LPColor.lcd)
    .border({ width: 2, color: LPColor.ink })
    .borderRadius(14)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
    .onClick(() => this.onOpen())
  }
}

@Component
struct DeadCatalogCard {
  @Prop pet: CatalogPet = DEFAULT_CATALOG_PET;
  onOpen: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 4 }) {
        PixelPetSprite({ sprite: this.pet.sprite, size: 44 })
        Text(this.pet.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.ink)
        Text(this.pet.dates)
          .fontSize(8)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
        Text(deathBucketLabel(this.pet.deathType))
          .fontSize(8)
          .fontFamily('monospace')
          .fontColor(this.pet.deathType === DeathType.Natural ? '#7D6B3A' : '#A13528')
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor(this.pet.deathType === DeathType.Natural ? '#F3EBD8' : '#FADAD6')
          .borderRadius(3)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      if (this.pet.isRare) {
        Text('RARE')
          .fontSize(8)
          .fontFamily('monospace')
          .fontColor(Color.White)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor(LPColor.coral)
          .borderRadius(3)
          .margin({ top: -4, right: -4 })
      }
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 10, bottom: 9 })
    .backgroundColor(LPColor.paperCard)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
    .onClick(() => this.onOpen())
  }
}

@Component
struct LockedCatalogCard {
  build() {
    Column({ space: 4 }) {
      PixelPetLockedSprite({ size: 44 })
        .height(52)
      Text('???')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(LPColor.muted)
      Text('UNLOCK')
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 10, bottom: 9 })
    .opacity(0.45)
    .backgroundColor(LPColor.paperCool)
    .border({ width: 1.5, color: LPColor.ink, style: BorderStyle.Dashed })
    .borderRadius(10)
  }
}

function deathBucketLabel(type?: DeathType): string {
  switch (type) {
    case DeathType.Natural:
      return '圆满';
    case DeathType.Chronic:
    case DeathType.Acute:
    case DeathType.Starve:
    case DeathType.Illness:
      return '短命';
    default:
      return '短命';
  }
}
