import { PetState, showsSparkles } from '../models/PetModels';
import { LPColor } from '../theme/LPTheme';
import { SpriteAnimator } from './SpriteAnimator';

@Component
export struct PetStage {
  @Prop petName: string = 'BEAN';
  @Prop dayCount: number = 1;
  @Prop state: PetState = PetState.Normal;
  @Prop hatched: boolean = false;
  @Prop bursting: boolean = false;
  @Prop @Watch('onFeedTokenChanged') feedToken: number = 0;
  @Prop lastWorkoutEndedAt: number = 0;
  @State hatchPlaying: boolean = false;
  @State shakePhase: number = 0;
  @State eggPulsePhase: number = 0;
  onHatch: () => void = () => {};
  private lastFeedToken: number = 0;
  private shakeTimerId: number = -1;
  private eggPulseTimerId: number = -1;

  aboutToAppear(): void {
    this.startEggPulse();
  }

  aboutToDisappear(): void {
    this.clearShakeTimer();
    this.clearEggPulseTimer();
  }

  private idleSequence(): string {
    if (this.state === PetState.Excited || this.state === PetState.Blissful) {
      return 'blob_run';
    }
    if (this.state === PetState.Sleeping) {
      return 'blob_sleep';
    }
    if (this.state === PetState.Tired) {
      return 'blob_walk';
    }
    if (this.state === PetState.Sick) {
      return 'blob_lying';
    }
    if (this.lastWorkoutEndedAt > 0 && Date.now() - this.lastWorkoutEndedAt < 30 * 60000) {
      return 'blob_run';
    }
    const hour = new Date().getHours();
    return hour >= 9 ? 'blob_walk' : 'blob_lying';
  }

  private onFeedTokenChanged(): void {
    if (this.feedToken <= 0 || this.feedToken === this.lastFeedToken) {
      return;
    }
    this.lastFeedToken = this.feedToken;
    this.clearShakeTimer();
    this.shakePhase = 0;
    animateTo({ duration: 450, curve: Curve.EaseInOut }, () => {
      this.shakePhase = 1;
    });
    this.shakeTimerId = setTimeout(() => {
      this.shakePhase = 0;
      this.shakeTimerId = -1;
    }, 470);
  }

  private clearShakeTimer(): void {
    if (this.shakeTimerId >= 0) {
      clearTimeout(this.shakeTimerId);
      this.shakeTimerId = -1;
    }
  }

  private startEggPulse(): void {
    if (this.hatched || this.eggPulseTimerId >= 0) {
      return;
    }
    this.eggPulseTimerId = setInterval(() => {
      if (this.hatched || this.hatchPlaying) {
        return;
      }
      animateTo({ duration: 900, curve: Curve.EaseInOut }, () => {
        this.eggPulsePhase = this.eggPulsePhase === 0 ? 1 : 0;
      });
    }, 900);
  }

  private clearEggPulseTimer(): void {
    if (this.eggPulseTimerId >= 0) {
      clearInterval(this.eggPulseTimerId);
      this.eggPulseTimerId = -1;
    }
  }

  private shakeEnvelope(): number {
    return Math.max(0, Math.sin(this.shakePhase * Math.PI));
  }

  private shakeOffsetX(): number {
    return Math.sin(this.shakePhase * Math.PI * 4) * 3 * this.shakeEnvelope();
  }

  private shakeRotation(): number {
    return Math.cos(this.shakePhase * Math.PI * 4) * 4 * this.shakeEnvelope();
  }

  private shakeScale(): number {
    return 1 + 0.06 * this.shakeEnvelope();
  }

  private eggScale(): number {
    return 0.96 + 0.08 * this.eggPulsePhase;
  }

  private eggTilt(): number {
    return -3 + 6 * this.eggPulsePhase;
  }

  private hintOpacity(): number {
    return 0.55 + 0.45 * this.eggPulsePhase;
  }

  private finishHatch(): void {
    if (!this.hatched) {
      this.onHatch();
    }
    this.hatchPlaying = false;
    this.clearEggPulseTimer();
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(208)
        .backgroundColor(LPColor.lcd)
        .borderRadius(18)
        .border({ width: 2, color: LPColor.ink })

      Column()
        .width('96%')
        .height(196)
        .borderRadius(12)
        .border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })

      Text(`${this.petName} ○`)
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
        .position({ x: 14, y: 12 })

      Text(`D${this.dayCount.toString().padStart(2, '0')}`)
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
        .position({ x: '82%', y: 12 })

      Text(this.hatched ? this.state : 'EGG')
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
        .position({ x: 14, y: 184 })

      Text('♪ ♫ ♪')
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
        .position({ x: '80%', y: 184 })

      Stack() {
        if (!this.hatched && !this.hatchPlaying) {
          Image($rawfile('sprites/egg_hatch/frame_00.png'))
            .interpolation(ImageInterpolation.None)
            .objectFit(ImageFit.Contain)
            .width(96)
            .height(96)
            .scale({ x: this.eggScale(), y: this.eggScale() })
            .rotate({ angle: this.eggTilt() })
        } else if (!this.hatched && this.hatchPlaying) {
          SpriteAnimator({
            sequence: 'egg_hatch',
            oneShot: true,
            stateTag: 'EGG',
            size: 160,
            onCompleted: () => this.finishHatch()
          })
        } else {
          SpriteAnimator({
            sequence: this.idleSequence(),
            oneShot: false,
            stateTag: this.state,
            size: 160
          })
        }
        if (!this.hatched && !this.hatchPlaying) {
          Text('戳一下 →')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor(LPColor.lcdInk)
            .opacity(this.hintOpacity())
            .margin({ top: 136 })
        }
        if (this.hatched && (showsSparkles(this.state) || this.bursting)) {
          Text('★')
            .fontSize(18)
            .fontColor(LPColor.coral)
            .position({ x: 20, y: 20 })
          Text('✦')
            .fontSize(16)
            .fontColor(LPColor.coral)
            .position({ x: 118, y: 38 })
          Text('✧')
            .fontSize(14)
            .fontColor(LPColor.coral)
            .position({ x: 78, y: 8 })
        }
      }
      .width(160)
      .height(160)
      .scale({ x: this.shakeScale(), y: this.shakeScale() })
      .rotate({ angle: this.shakeRotation() })
      .translate({ x: this.shakeOffsetX(), y: 0 })
      .onClick(() => {
        if (!this.hatched && !this.hatchPlaying) {
          this.hatchPlaying = true;
        }
      })
    }
    .width('100%')
    .height(208)
  }
}
