import { PetSpriteName } from '../models/PetSpriteModels';
import { LPColor } from '../theme/LPTheme';

interface PixelRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

@Component
export struct PixelPetSprite {
  @Prop sprite: PetSpriteName = PetSpriteName.Bean;
  @Prop size: number = 60;
  @Prop bodyColor: string = LPColor.ink;

  private unit(): number {
    return this.size / 16;
  }

  private bodyRects(): PixelRect[] {
    switch (this.sprite) {
      case PetSpriteName.Bean:
        return [
          { x: 5, y: 0, w: 6, h: 1 },
          { x: 4, y: 1, w: 8, h: 12 },
          { x: 4, y: 13, w: 2, h: 3 },
          { x: 10, y: 13, w: 2, h: 3 }
        ];
      case PetSpriteName.Blob:
        return [
          { x: 5, y: 1, w: 6, h: 1 },
          { x: 3, y: 2, w: 10, h: 1 },
          { x: 2, y: 3, w: 12, h: 9 },
          { x: 3, y: 12, w: 10, h: 1 },
          { x: 4, y: 13, w: 2, h: 2 },
          { x: 10, y: 13, w: 2, h: 2 }
        ];
      case PetSpriteName.Noct:
        return [
          { x: 3, y: 2, w: 2, h: 2 },
          { x: 11, y: 2, w: 2, h: 2 },
          { x: 5, y: 1, w: 6, h: 1 },
          { x: 3, y: 2, w: 10, h: 1 },
          { x: 2, y: 3, w: 12, h: 10 },
          { x: 3, y: 13, w: 10, h: 1 },
          { x: 4, y: 14, w: 2, h: 2 },
          { x: 10, y: 14, w: 2, h: 2 }
        ];
      case PetSpriteName.Hush:
      default:
        return [
          { x: 7, y: 1, w: 2, h: 1 },
          { x: 6, y: 2, w: 4, h: 1 },
          { x: 5, y: 3, w: 6, h: 1 },
          { x: 4, y: 4, w: 8, h: 8 },
          { x: 5, y: 12, w: 6, h: 1 },
          { x: 6, y: 13, w: 4, h: 1 }
        ];
    }
  }

  private eyeRects(): PixelRect[] {
    switch (this.sprite) {
      case PetSpriteName.Bean:
        return [{ x: 6, y: 5, w: 1, h: 1 }, { x: 9, y: 5, w: 1, h: 1 }];
      case PetSpriteName.Blob:
        return [{ x: 5, y: 6, w: 1, h: 1 }, { x: 10, y: 6, w: 1, h: 1 }];
      case PetSpriteName.Noct:
        return [{ x: 5, y: 7, w: 1, h: 1 }, { x: 10, y: 7, w: 1, h: 1 }];
      case PetSpriteName.Hush:
      default:
        return [{ x: 6, y: 7, w: 1, h: 1 }, { x: 9, y: 7, w: 1, h: 1 }];
    }
  }

  private accentRects(): PixelRect[] {
    switch (this.sprite) {
      case PetSpriteName.Bean:
        return [{ x: 7, y: 7, w: 2, h: 1 }];
      case PetSpriteName.Blob:
        return [{ x: 7, y: 8, w: 2, h: 1 }];
      case PetSpriteName.Noct:
      case PetSpriteName.Hush:
      default:
        return [];
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.bodyRects(), (rect: PixelRect, index: number) => {
        PixelRectBlock({ rect: rect, unit: this.unit(), color: this.bodyColor })
      }, (rect: PixelRect, index: number) => `body-${index}-${rect.x}-${rect.y}-${rect.w}-${rect.h}`)
      ForEach(this.eyeRects(), (rect: PixelRect, index: number) => {
        PixelRectBlock({ rect: rect, unit: this.unit(), color: LPColor.paperCool })
      }, (rect: PixelRect, index: number) => `eye-${index}-${rect.x}-${rect.y}`)
      ForEach(this.accentRects(), (rect: PixelRect, index: number) => {
        PixelRectBlock({ rect: rect, unit: this.unit(), color: LPColor.coral })
      }, (rect: PixelRect, index: number) => `accent-${index}-${rect.x}-${rect.y}`)
    }
    .width(this.size)
    .height(this.size)
    .accessibilityText(this.sprite)
  }
}

@Component
export struct PixelPetLockedSprite {
  @Prop size: number = 44;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(this.size)
        .height(this.size)
        .backgroundColor(LPColor.muted)
        .borderRadius(this.size * 0.1)
      Text('?')
        .fontSize(this.size * 0.45)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(LPColor.paperCool)
    }
    .width(this.size)
    .height(this.size)
    .opacity(0.35)
    .accessibilityText('locked pet')
  }
}

@Component
export struct BreathingPixelPetSprite {
  @Prop sprite: PetSpriteName = PetSpriteName.Bean;
  @Prop size: number = 60;
  @Prop bodyColor: string = LPColor.ink;
  @Prop periodMs: number = 2600;
  @State liftY: number = 0;
  @State scaleY: number = 1;
  private loopTimerId: number = -1;
  private downTimerId: number = -1;

  aboutToAppear(): void {
    this.startBreathing();
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private halfPeriod(): number {
    return Math.max(300, Math.floor(this.periodMs / 2));
  }

  private startBreathing(): void {
    this.clearTimers();
    this.runCycle();
    this.loopTimerId = setInterval(() => {
      this.runCycle();
    }, this.periodMs);
  }

  private runCycle(): void {
    if (this.downTimerId >= 0) {
      clearTimeout(this.downTimerId);
      this.downTimerId = -1;
    }
    animateTo({ duration: this.halfPeriod(), curve: Curve.EaseInOut }, () => {
      this.liftY = -3;
      this.scaleY = 0.985;
    });
    this.downTimerId = setTimeout(() => {
      animateTo({ duration: this.halfPeriod(), curve: Curve.EaseInOut }, () => {
        this.liftY = 0;
        this.scaleY = 1.015;
      });
    }, this.halfPeriod());
  }

  private clearTimers(): void {
    if (this.loopTimerId >= 0) {
      clearInterval(this.loopTimerId);
      this.loopTimerId = -1;
    }
    if (this.downTimerId >= 0) {
      clearTimeout(this.downTimerId);
      this.downTimerId = -1;
    }
  }

  build() {
    PixelPetSprite({ sprite: this.sprite, size: this.size, bodyColor: this.bodyColor })
      .scale({ x: 1, y: this.scaleY })
      .translate({ y: this.liftY })
  }
}

@Component
struct PixelRectBlock {
  @Prop rect: PixelRect = { x: 0, y: 0, w: 1, h: 1 };
  @Prop unit: number = 4;
  @Prop color: string = LPColor.ink;

  build() {
    Column()
      .width(this.rect.w * this.unit)
      .height(this.rect.h * this.unit)
      .backgroundColor(this.color)
      .position({ x: this.rect.x * this.unit, y: this.rect.y * this.unit })
  }
}
