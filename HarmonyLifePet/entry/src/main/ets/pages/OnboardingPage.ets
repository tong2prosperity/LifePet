import { PetStateStore } from '../stores/PetStateStore';
import { LPColor } from '../theme/LPTheme';
import { HealthAuthState } from '../services/HealthDataService';

interface OnboardingBenefit {
  emoji: string;
  title: string;
  subtitle: string;
}

const onboardingBenefits: OnboardingBenefit[] = [
  { emoji: '💪', title: '步数 / 运动 / 卡路里', subtitle: '→ 体力' },
  { emoji: '⚡', title: '睡眠 · 深睡 · REM', subtitle: '→ 精力' },
  { emoji: '❤️', title: 'HRV / 心率 / 冥想', subtitle: '→ 心情' },
  { emoji: '🏃', title: '已完成的运动', subtitle: '→ 自动打勾今日卡片' }
];

enum OnboardingActionVariant {
  Primary = 'primary',
  Secondary = 'secondary',
  Ghost = 'ghost'
}

@Component
export struct OnboardingPage {
  @ObjectLink store: PetStateStore;
  @Prop authState: HealthAuthState = HealthAuthState.Unknown;
  onConnect: () => void = () => {};
  onDemo: () => void = () => {};
  onLater: () => void = () => {};

  build() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 10 }) {
          Text('LIFEPET')
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(LPColor.coral)
            .letterSpacing(2)
          Text('先把你身体里的小生物\n接进来。')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
          Text('你不是喂宠物，你的身体就是宠物的食物。')
            .fontSize(15)
            .fontStyle(FontStyle.Italic)
            .fontColor(LPColor.muted)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          Text('LifePet 会读取（不写入）')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(LPColor.muted)
          ForEach(onboardingBenefits, (benefit: OnboardingBenefit) => {
            OnboardingRow({ emoji: benefit.emoji, title: benefit.title, subtitle: benefit.subtitle })
          }, (benefit: OnboardingBenefit) => benefit.title)
        }
        .width('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 8 })
        .backgroundColor(LPColor.paperCard)
        .border({ width: 1.5, color: LPColor.ink })
        .borderRadius(10)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })

        if (this.authState === HealthAuthState.Unavailable) {
          Column({ space: 12 }) {
            Text('当前设备不支持 Health Service Kit · 仅 Demo 模式可用')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
              .textAlign(TextAlign.Center)
            OnboardingActionButton({
              label: '用 Demo 数据继续',
              variant: OnboardingActionVariant.Primary,
              onTap: () => this.onDemo()
            })
          }
          .width('100%')
        } else if (this.authState === HealthAuthState.Requesting) {
          Row({ space: 12 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(LPColor.coral)
            Text('等你授权…')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Column({ space: 12 }) {
            OnboardingActionButton({
              label: '连接 Health Service Kit',
              variant: OnboardingActionVariant.Primary,
              onTap: () => this.onConnect()
            })
            OnboardingActionButton({
              label: '用 Demo 数据继续',
              variant: OnboardingActionVariant.Secondary,
              onTap: () => this.onDemo()
            })
            OnboardingActionButton({
              label: '以后再说',
              variant: OnboardingActionVariant.Ghost,
              onTap: () => this.onLater()
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}

@Component
struct OnboardingActionButton {
  @Prop label: string = '';
  @Prop variant: OnboardingActionVariant = OnboardingActionVariant.Secondary;
  onTap: () => void = () => {};

  private isPrimary(): boolean {
    return this.variant === OnboardingActionVariant.Primary;
  }

  private isGhost(): boolean {
    return this.variant === OnboardingActionVariant.Ghost;
  }

  build() {
    Button(this.label)
      .width('100%')
      .height(44)
      .fontSize(11)
      .fontFamily('monospace')
      .fontWeight(FontWeight.Bold)
      .letterSpacing(2.2)
      .backgroundColor(this.isPrimary() ? LPColor.ink : (this.isGhost() ? Color.Transparent : LPColor.paperCard))
      .fontColor(this.isPrimary() ? LPColor.paper : LPColor.ink)
      .border({
        width: 1.5,
        color: LPColor.ink,
        style: this.isGhost() ? BorderStyle.Dashed : BorderStyle.Solid
      })
      .borderRadius(2)
      .onClick(() => this.onTap())
  }
}

@Component
struct OnboardingRow {
  @Prop emoji: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Row({ space: 12 }) {
      Text(this.emoji)
        .fontSize(18)
        .fontColor(LPColor.coral)
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.ink)
        Text(this.subtitle)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }
}
