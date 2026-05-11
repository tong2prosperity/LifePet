import { DashedRule } from './DashedRule';
import { StatKind, StepItem, StepKind, StepStatus, statEmoji, statLabel } from '../models/PetModels';
import { PetStateStore } from '../stores/PetStateStore';
import { LPColor } from '../theme/LPTheme';

const DEFAULT_STEP: StepItem = {
  id: 'default',
  status: StepStatus.Suggest,
  kind: StepKind.Walk,
  actionLabel: '',
  titleValue: '',
  affects: StatKind.Vitality,
  gain: 0,
  time: '',
  fromAutoSensor: false
};

@Component
export struct StepsSection {
  @ObjectLink store: PetStateStore;

  private doneCount(): number {
    return this.store.steps.filter((item: StepItem) => item.status === StepStatus.Done).length;
  }

  private suggestCount(): number {
    return this.store.steps.filter((item: StepItem) => item.status === StepStatus.Suggest).length;
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Text('今日步骤')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.ink)
        Text(`${this.doneCount()} 已完成 · ${this.suggestCount()} 建议`)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
        DashedRule({ color: LPColor.lcdDash })
          .layoutWeight(1)
      }
      .width('100%')

      Text('打 ✅ 它开心，打 ❌ 不扣分 —— 但它会记住，下次少推。')
        .fontSize(12)
        .fontColor(LPColor.muted)
        .width('100%')
        .margin({ left: 2, top: 4, bottom: 10 })

      Column({ space: 7 }) {
        ForEach(this.store.steps, (item: StepItem) => {
          StepCard({ item, store: this.store })
        }, (item: StepItem) => item.id)
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Component
struct StepCard {
  @Prop item: StepItem = DEFAULT_STEP;
  @ObjectLink store: PetStateStore;

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row({ space: 10 }) {
        Text(this.item.status === StepStatus.Done ? '✅' : '🎯')
          .fontSize(16)
          .width(26)
          .textAlign(TextAlign.Center)

        Column({ space: 2 }) {
          Row({ space: 0 }) {
            Text(this.item.status === StepStatus.Suggest ? `建议: ${this.item.actionLabel}` : this.item.actionLabel)
              .fontSize(15)
              .fontColor(LPColor.ink)
            Text(' ')
              .fontSize(15)
            Text(this.item.titleValue)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
          }
          Row({ space: 0 }) {
            Text(this.item.status === StepStatus.Done ? '→ ' : '可获得 ')
              .fontSize(9)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
            Text(`+${this.item.gain}`)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(this.item.status === StepStatus.Done ? LPColor.ink : '#7A6530')
            Text(` ${statEmoji(this.item.affects)} ${statLabel(this.item.affects)}`)
              .fontSize(9)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
          }
        }
        .layoutWeight(1)

        if (this.item.status === StepStatus.Done) {
          Text(this.item.time)
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.faint)
        } else {
          Row({ space: 5 }) {
            MiniActionButton({ symbol: '✅', fill: '#D3EBD5', onTap: () => this.store.markDone(this.item.id) })
            MiniActionButton({ symbol: '❌', fill: '#EBEBEB', onTap: () => this.store.quit(this.item.id) })
          }
        }
      }
      .width('100%')

      if (this.item.status === StepStatus.Done && this.item.fromAutoSensor) {
        Text('⚡ 手表自动')
          .fontSize(7.5)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .backgroundColor(LPColor.paperCool)
          .border({ width: 1, color: LPColor.hairline })
          .borderRadius(3)
          .margin({ top: -4, right: 8 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.item.status === StepStatus.Done ? '#EEF5E8' : '#FEF4E6')
    .border({ width: 1.5, color: LPColor.ink, style: this.item.status === StepStatus.Suggest ? BorderStyle.Dashed : BorderStyle.Solid })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct MiniActionButton {
  @Prop symbol: string = '';
  @Prop fill: string = '#FFFFFF';
  onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(32)
        .height(32)
        .backgroundColor(LPColor.ink)
        .borderRadius(7)
        .translate({ x: 2, y: 2 })
      Column()
        .width(32)
        .height(32)
        .backgroundColor(this.fill)
        .border({ width: 1.5, color: LPColor.ink })
        .borderRadius(7)
      Text(this.symbol)
        .fontSize(12)
    }
      .width(34)
      .height(34)
      .onClick(() => this.onTap())
  }
}
