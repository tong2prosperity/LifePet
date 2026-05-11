import { DashedRule } from './DashedRule';
import { BreathingPixelPetSprite } from './PixelPetSprite';
import { CatalogMoment, CatalogPet } from '../models/CatalogModels';
import { PetSpriteName } from '../models/PetSpriteModels';
import { ShareActionResult, ShareActionService } from '../services/ShareActionService';
import { LPColor } from '../theme/LPTheme';
import { common } from '@kit.AbilityKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

const DEFAULT_SHARE_PET: CatalogPet = {
  id: 'empty',
  name: 'BEAN',
  sprite: PetSpriteName.Bean,
  isAlive: true,
  dates: '今日',
  days: 1,
  totalDays: 1,
  stats: { vitality: 0, energy: 0, mood: 0 },
  series: { vitality: [0], energy: [0], mood: [0] },
  moments: [],
  bio: '',
  isRare: false
};

@Component
export struct CatalogShareOverlay {
  @Prop pet: CatalogPet = DEFAULT_SHARE_PET;
  @State toast: string = '';
  private shareActions: ShareActionService = new ShareActionService();
  onClose: () => void = () => {};

  private daysCopy(): string {
    return this.pet.isAlive ? `已陪伴 · 第 ${this.pet.days} 天` : `陪伴了 ${this.pet.totalDays} 天 · 已升天`;
  }

  private async handleAction(action: Promise<ShareActionResult>): Promise<void> {
    const result = await action;
    this.toast = result.message;
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private async saveShareCard(authorized: boolean): Promise<void> {
    const pixelMap = authorized ? await this.captureShareCard() : undefined;
    await this.handleAction(this.shareActions.saveCatalogCard(this.context(), this.pet, pixelMap, authorized));
  }

  private async captureShareCard(): Promise<image.PixelMap | undefined> {
    try {
      return await componentSnapshot.get('catalog-share-card');
    } catch (error) {
      return undefined;
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .onClick(() => this.onClose())

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 6 }) {
            Text('· LIFEPET ·')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
              .letterSpacing(3)

            BreathingPixelPetSprite({ sprite: this.pet.sprite, size: 70 })
              .margin({ top: 4, bottom: 2 })

            Text(this.pet.name)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.ink)
              .letterSpacing(1)
            Text(this.daysCopy())
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
              .margin({ top: 2 })

            DashedRule({ color: LPColor.lcdDash })
              .margin({ top: 10 })
            Row() {
              ShareStat({ symbol: '💪', value: this.pet.stats.vitality, label: '体力' })
              ShareStat({ symbol: '⚡', value: this.pet.stats.energy, label: '精力' })
              ShareStat({ symbol: '❤️', value: this.pet.stats.mood, label: '心情', coral: true })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            DashedRule({ color: LPColor.lcdDash })

            Column({ space: 2 }) {
              ForEach(this.pet.moments.slice(0, 2), (moment: CatalogMoment) => {
                Row({ space: 6 }) {
                  Text(`D${moment.day.toString().padStart(2, '0')}`)
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(LPColor.coral)
                    .width(26)
                  Text(moment.title)
                    .fontSize(12)
                    .fontColor(LPColor.ink)
                    .layoutWeight(1)
                    .maxLines(2)
                }
                .width('100%')
              }, (moment: CatalogMoment) => `${this.pet.id}-${moment.day}-${moment.title}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10 })

            DashedRule({ color: LPColor.lcdDash })
              .margin({ top: 4, bottom: 8 })

            FauxQr({ seed: `lifepet-${this.pet.id}` })

            Row({ space: 4 }) {
              Text('扫码注册')
                .fontSize(13)
                .fontColor(LPColor.ink)
              Text('LifePet')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.coral)
            }
            Text('养一只属于你自己的')
              .fontSize(13)
              .fontColor(LPColor.ink)
            Text('lifepet.app · via FISH')
              .fontSize(8)
              .fontFamily('monospace')
              .fontColor(LPColor.faint)
              .letterSpacing(1)
          }
          .id('catalog-share-card')
          .width('100%')
          .padding({ left: 14, right: 14, top: 16, bottom: 14 })
          .backgroundColor(LPColor.paperCard)
          .border({ width: 2, color: LPColor.ink })
          .borderRadius(14)
          .shadow({ radius: 0, color: LPColor.ink, offsetX: 4, offsetY: 4 })

          Row({ space: 8 }) {
            SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Normal })
              .layoutWeight(1)
              .height(44)
              .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                void this.saveShareCard(result === SaveButtonOnClickResult.SUCCESS);
              })
            Button('🌹 分享到小红书')
              .layoutWeight(1)
              .height(44)
              .fontSize(11)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .letterSpacing(2.2)
              .backgroundColor(LPColor.coral)
              .fontColor(Color.White)
              .border({ width: 1.5, color: LPColor.coral })
              .borderRadius(2)
              .onClick(() => {
                void this.handleAction(this.shareActions.shareCatalogCard(this.context(), this.pet));
              })
          }
          .width('100%')

        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 52, bottom: 52 })
      }
      .width('100%')
      .height('100%')

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(13)
          .fontColor(LPColor.paperCard)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(LPColor.ink)
          .border({ width: 1.5, color: LPColor.ink })
          .borderRadius(999)
          .shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })
          .margin({ bottom: 24 })
          .onClick(() => this.toast = '')
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct ShareStat {
  @Prop symbol: string = '';
  @Prop value: number = 0;
  @Prop label: string = '';
  @Prop coral: boolean = false;

  build() {
    Column({ space: 2 }) {
      Text(this.symbol)
        .fontSize(13)
      Text(this.value.toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.coral ? LPColor.coral : LPColor.ink)
      Text(this.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .layoutWeight(1)
  }
}

@Component
struct FauxQr {
  @Prop seed: string = '';

  private cells(): boolean[] {
    let state = 0;
    for (let i = 0; i < this.seed.length; i++) {
      state = (state * 31 + this.seed.charCodeAt(i)) % 4294967296;
    }
    const out: boolean[] = [];
    for (let y = 0; y < 21; y++) {
      for (let x = 0; x < 21; x++) {
        const markerArea = this.isMarkerArea(x, y);
        const marker = this.isMarkerCell(x, y);
        state = (state * 1664525 + 1013904223) % 4294967296;
        out.push(markerArea ? marker : state / 4294967295 < 0.48);
      }
    }
    return out;
  }

  private isMarkerArea(x: number, y: number): boolean {
    return this.inMarkerArea(x, y, 0, 0) ||
      this.inMarkerArea(x, y, 14, 0) ||
      this.inMarkerArea(x, y, 0, 14);
  }

  private isMarkerCell(x: number, y: number): boolean {
    return this.markerCell(x, y, 0, 0) ||
      this.markerCell(x, y, 14, 0) ||
      this.markerCell(x, y, 0, 14);
  }

  private inMarkerArea(x: number, y: number, startX: number, startY: number): boolean {
    return x >= startX && x < startX + 7 && y >= startY && y < startY + 7;
  }

  private markerCell(x: number, y: number, startX: number, startY: number): boolean {
    if (!this.inMarkerArea(x, y, startX, startY)) {
      return false;
    }
    const localX = x - startX;
    const localY = y - startY;
    return localX === 0 || localX === 6 || localY === 0 || localY === 6 ||
      (localX >= 2 && localX <= 4 && localY >= 2 && localY <= 4);
  }

  build() {
    Grid() {
      ForEach(this.cells(), (cell: boolean, index: number) => {
        GridItem() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(cell ? LPColor.ink : LPColor.paperCool)
        }
      }, (cell: boolean, index: number) => index.toString())
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .width(86)
    .height(86)
    .padding(4)
    .backgroundColor(LPColor.paperCool)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(4)
  }
}
