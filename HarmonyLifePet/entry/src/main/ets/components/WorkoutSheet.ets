import { PendingWorkout } from '../models/PetModels';
import { LPColor } from '../theme/LPTheme';

@Component
export struct WorkoutSheet {
  @Prop workout: PendingWorkout | null = null;
  @Prop petName: string = 'BEAN';
  onFeed: () => void = () => {};
  onDismiss: () => void = () => {};

  private subtitleText(): string {
    if (!this.workout) {
      return '';
    }
    const parts: string[] = [`${this.workout.durationMin} 分钟`];
    if (this.workout.kcal && this.workout.kcal >= 1) {
      parts.push(`${Math.floor(this.workout.kcal)} KCAL`);
    }
    parts.push(this.timeLabel(this.workout.endedAt));
    return parts.join(' · ');
  }

  private timeLabel(value: number): string {
    const d = new Date(value);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  build() {
    if (this.workout) {
      Column({ space: 0 }) {
        Column()
          .width('100%')
          .height(2)
          .backgroundColor(LPColor.ink)
        Column()
          .width(40)
          .height(4)
          .backgroundColor(LPColor.hairline)
          .borderRadius(2)
          .margin({ top: 6, bottom: 12 })
        Column({ space: 0 }) {
          Text('运动健康 · 刚刚同步')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
            .letterSpacing(1)
            .width('100%')
            .margin({ bottom: 2 })
          Text(`${this.workout.label}完成`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
            .width('100%')
          Text(this.subtitleText())
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
            .letterSpacing(0.5)
            .width('100%')
            .margin({ bottom: 16 })
          Row({ space: 8 }) {
            GainCell({ label: '体力', value: `+${this.workout.gainVitality}`, unit: 'PTS' })
            GainCell({ label: '精力', value: `+${this.workout.gainVitality}`, unit: 'PTS' })
            GainCell({ label: '心情', value: `+${this.workout.gainVitality}`, unit: 'PTS' })
          }
          .width('100%')
          .margin({ bottom: 18 })
          Button(`喂养 ${this.petName}`)
            .width('100%')
            .height(50)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(1)
            .backgroundColor(LPColor.ink)
            .fontColor(LPColor.paperCool)
            .borderRadius(12)
            .shadow({ radius: 6, color: '#1A000000', offsetX: 0, offsetY: 4 })
            .onClick(() => this.onFeed())
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        Blank()
          .height(48)
      }
      .width('100%')
      .backgroundColor(LPColor.paperCool)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 12, color: '#1F000000', offsetX: 0, offsetY: 8 })
    }
  }
}

@Component
struct GainCell {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop unit: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(LPColor.muted)
      Text(this.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#3EB24E')
      Text(this.unit)
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
    .backgroundColor(LPColor.lcd)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(10)
    .shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })
  }
}
