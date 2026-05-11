import { LPColor } from '../theme/LPTheme';

@Component
export struct DashedRule {
  @Prop color: string = LPColor.lcdDash;
  @Prop segments: number = 32;

  private items(): number[] {
    const out: number[] = [];
    for (let index = 0; index < this.segments; index++) {
      out.push(index);
    }
    return out;
  }

  build() {
    Row({ space: 3 }) {
      ForEach(this.items(), (item: number) => {
        Column()
          .layoutWeight(1)
          .height(1)
          .backgroundColor(this.color)
      }, (item: number) => item.toString())
    }
    .width('100%')
    .height(1)
  }
}
