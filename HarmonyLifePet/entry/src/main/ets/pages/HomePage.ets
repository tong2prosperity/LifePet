import { DashedRule } from '../components/DashedRule';
import { EnergyParticleField } from '../components/EnergyParticleField';
import { PetStage } from '../components/PetStage';
import { StatTriad } from '../components/StatTriad';
import { StepsSection } from '../components/StepsSection';
import { PetState, StatKind } from '../models/PetModels';
import { PetStateStore } from '../stores/PetStateStore';
import { LPColor } from '../theme/LPTheme';

@Component
export struct HomePage {
  @ObjectLink store: PetStateStore;
  @State demoStateIndex: number = 0;
  @State showResetConfirm: boolean = false;
  private demoStates: PetState[] = [
    PetState.Normal,
    PetState.Excited,
    PetState.Tired,
    PetState.Sleeping,
    PetState.Sick,
    PetState.Blissful
  ];

  private cycleDemoState(): void {
    this.demoStateIndex = (this.demoStateIndex + 1) % this.demoStates.length;
    this.store.state = this.demoStates[this.demoStateIndex];
  }

  private performReset(): void {
    this.showResetConfirm = false;
    this.store.reset();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Row() {
              Text(`${this.store.greetingText}, `)
                .fontSize(17)
                .fontColor(LPColor.ink)
              Text(this.store.ownerName)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.coral)
              Blank()
              Text(this.store.dateText)
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor(LPColor.muted)
              Button('↻')
                .width(22)
                .height(22)
                .fontSize(10)
                .backgroundColor(Color.Transparent)
                .fontColor(LPColor.muted)
                .border({ width: 1, color: '#6E665A66' })
                .borderRadius(11)
                .onClick(() => this.showResetConfirm = true)
            }
            .width('100%')

            DashedRule({ color: LPColor.lcdDash })
          }
          .width('100%')

          Column({ space: 10 }) {
            Column({ space: 6 }) {
              Row({ space: 0 }) {
                Text(this.store.petName)
                  .fontSize(44)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(LPColor.ink)
                Text('.')
                  .fontSize(44)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(LPColor.coral)
              }
              Row({ space: 8 }) {
                Row({ space: 0 }) {
                  Text('已陪伴 ')
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor(LPColor.muted)
                    .letterSpacing(1)
                  Text(`第 ${this.store.dayCount} 天`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(LPColor.coral)
                    .letterSpacing(1)
                }
                Text(this.store.state)
                  .fontSize(10)
                  .fontFamily('monospace')
                  .fontColor(Color.White)
                  .letterSpacing(0.5)
                  .padding({ left: 8, right: 8, top: 1, bottom: 1 })
                  .backgroundColor(LPColor.coral)
                  .borderRadius(5)
              }
            }

            DashedRule({ color: LPColor.lcdDash })
          }
          .width('100%')

          Stack() {
            PetStage({
              petName: this.store.petName,
              dayCount: this.store.dayCount,
              state: this.store.state,
              hatched: this.store.hatched,
              bursting: this.store.lastDeltaToken > 0,
              feedToken: this.store.feedToken,
              lastWorkoutEndedAt: this.store.lastWorkoutEndedAt ?? 0,
              onHatch: () => {
                this.store.markHatched();
              }
            })
            EnergyParticleField({ token: this.store.feedToken })
          }
          .width('100%')
          .height(208)

          if (this.store.demoMode) {
            Button('⇄ 换一换')
              .height(32)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(LPColor.paperCard)
              .fontColor(LPColor.ink)
              .border({ width: 1, color: LPColor.ink })
              .borderRadius(16)
              .shadow({ radius: 3, color: '#33000000', offsetY: 2 })
              .opacity(this.store.hatched ? 1 : 0.3)
              .enabled(this.store.hatched)
              .onClick(() => {
                if (this.store.hatched) {
                  this.cycleDemoState();
                }
              })
          }

          StatTriad({
            stats: this.store.stats,
            onDecrement: (kind: StatKind) => this.store.debugDecrement(kind)
          })

          StepsSection({ store: this.store })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 34 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(LPColor.paper)

      if (this.showResetConfirm) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => this.showResetConfirm = false)

        Column({ space: 14 }) {
          Text('重置后会回到首启流程')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
          Text('当前所有 stats、卡片和孵化记录都会清掉。')
            .fontSize(13)
            .fontColor(LPColor.muted)
            .textAlign(TextAlign.Center)
          Row({ space: 10 }) {
            Button('取消')
              .height(38)
              .layoutWeight(1)
              .fontSize(14)
              .backgroundColor(LPColor.paper)
              .fontColor(LPColor.ink)
              .border({ width: 1, color: LPColor.ink })
              .onClick(() => this.showResetConfirm = false)
            Button('重新开始')
              .height(38)
              .layoutWeight(1)
              .fontSize(14)
              .backgroundColor(LPColor.coral)
              .fontColor(Color.White)
              .onClick(() => this.performReset())
          }
          .width('100%')
        }
        .width('86%')
        .padding(18)
        .backgroundColor(LPColor.paperCard)
        .borderRadius(12)
        .border({ width: 2, color: LPColor.ink })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}
