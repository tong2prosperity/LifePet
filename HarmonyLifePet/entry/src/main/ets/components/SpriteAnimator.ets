import { LPColor } from '../theme/LPTheme';

@Component
export struct SpriteAnimator {
  @Prop sequence: string = 'blob_run';
  @Prop oneShot: boolean = false;
  @Prop size: number = 150;
  @Prop stateTag: string = 'NORMAL';
  onCompleted: () => void = () => {};

  private frameCount(): number {
    switch (this.sequence) {
      case 'egg_hatch':
        return 10;
      case 'blob_run':
      case 'blob_walk':
        return 8;
      case 'blob_lying':
      case 'blob_sleep':
      default:
        return 6;
    }
  }

  private frameMs(): number {
    switch (this.sequence) {
      case 'egg_hatch':
        return 125;
      case 'blob_run':
        return 62;
      case 'blob_walk':
        return 84;
      case 'blob_sleep':
        return 166;
      default:
        return 250;
    }
  }

  private frames(): Array<ImageFrameInfo> {
    const out: Array<ImageFrameInfo> = [];
    const count = this.frameCount();
    for (let i = 0; i < count; i++) {
      const frame = i.toString().padStart(2, '0');
      out.push({
        src: $rawfile(`sprites/${this.sequence}/frame_${frame}.png`),
        duration: this.frameMs()
      });
    }
    return out;
  }

  build() {
    ImageAnimator()
      .images(this.frames())
      .duration(this.frameCount() * this.frameMs())
      .iterations(this.oneShot ? 1 : -1)
      .state(AnimationStatus.Running)
      .fillMode(FillMode.Forwards)
      .width(this.size)
      .height(this.size)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.stateTag)
      .onFinish(() => {
        if (this.oneShot) {
          this.onCompleted();
        }
      })
  }
}

@Component
export struct PixelFallbackPet {
  @Prop size: number = 150;

  build() {
    Stack() {
      Column()
        .width(this.size * 0.46)
        .height(this.size * 0.58)
        .backgroundColor(LPColor.ink)
        .borderRadius(18)
      Row() {
        Column().width(10).height(10).backgroundColor(LPColor.paperCool)
        Blank().width(28)
        Column().width(10).height(10).backgroundColor(LPColor.paperCool)
      }
      .margin({ top: -18 })
      Column()
        .width(34)
        .height(26)
        .backgroundColor(LPColor.coral)
        .borderRadius(8)
        .margin({ top: 38 })
    }
    .width(this.size)
    .height(this.size)
  }
}
