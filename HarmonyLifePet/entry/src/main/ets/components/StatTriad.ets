import {
  Stat,
  StatKind,
  statEmoji,
  statLabel,
  statSourceCopy,
  statSupplementCopy
} from '../models/PetModels';
import { LPColor } from '../theme/LPTheme';

@Component
export struct StatTriad {
  @Prop stats: Stat[] = [];
  onDecrement: (kind: StatKind) => void = () => {};

  build() {
    Column({ space: 12 }) {
      ForEach(this.stats, (stat: Stat) => {
        StatRow({ stat, onDecrement: (kind: StatKind) => this.onDecrement(kind) })
      }, (stat: Stat) => stat.kind)
    }
    .width('100%')
  }
}

@Component
struct StatRow {
  @Prop @Watch('onStatChanged') stat: Stat = { kind: StatKind.Vitality, value: 0 };
  @State bumpScale: number = 1;
  @State bumpColor: string = LPColor.ink;
  onDecrement: (kind: StatKind) => void = () => {};
  private lastValue: number = -1;
  private bumpTimerId: number = -1;

  aboutToAppear(): void {
    this.lastValue = this.stat.value;
  }

  aboutToDisappear(): void {
    this.clearBumpTimer();
  }

  private onStatChanged(): void {
    if (this.lastValue < 0) {
      this.lastValue = this.stat.value;
      return;
    }
    if (this.stat.value === this.lastValue) {
      return;
    }
    this.lastValue = this.stat.value;
    this.clearBumpTimer();
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bumpScale = 1.3;
      this.bumpColor = '#3EB24E';
    });
    this.bumpTimerId = setTimeout(() => {
      animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
        this.bumpScale = 1;
        this.bumpColor = LPColor.ink;
      });
      this.bumpTimerId = -1;
    }, 200);
  }

  private clearBumpTimer(): void {
    if (this.bumpTimerId >= 0) {
      clearTimeout(this.bumpTimerId);
      this.bumpTimerId = -1;
    }
  }

  private clampedValue(): number {
    return Math.max(0, Math.min(100, this.stat.value));
  }

  private accentColor(): string {
    return this.stat.kind === StatKind.Mood ? LPColor.coral : LPColor.ink;
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(`${statEmoji(this.stat.kind)} ${statLabel(this.stat.kind)}`)
          .fontSize(16)
          .fontColor(LPColor.ink)
          .width(60)
        Button('−')
          .width(18)
          .height(18)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(Color.Transparent)
          .fontColor(LPColor.muted)
          .border({ width: 1, color: '#6E665A80' })
          .borderRadius(9)
          .onClick(() => this.onDecrement(this.stat.kind))
        Progress({ value: this.clampedValue(), total: 100, type: ProgressType.Linear })
          .layoutWeight(1)
          .height(12)
          .color(this.accentColor())
          .backgroundColor('#F0EADB')
          .border({ width: 1.5, color: LPColor.ink })
          .borderRadius(4)
        Row({ space: 0 }) {
          Text(this.stat.value.toString())
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor(this.bumpColor)
            .scale({ x: this.bumpScale, y: this.bumpScale })
          Text('/100')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.faint)
        }
        .width(42)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')

      Column({ space: 2 }) {
        Text(`来自手表 · ${statSourceCopy(this.stat.kind)}`)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
          .width('100%')
        Row({ space: 0 }) {
          Text('↑ 补充 · ')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
          Text(statSupplementCopy(this.stat.kind))
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.coral)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 2 })
    }
    .width('100%')
    .padding({ top: 9, left: 11, bottom: 8, right: 11 })
    .backgroundColor(LPColor.paperCool)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}
