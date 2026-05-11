import { CatalogPet } from '../models/CatalogModels';
import { PetSpriteName } from '../models/PetSpriteModels';
import { LPColor } from '../theme/LPTheme';

const CHART_WIDTH = 340;
const CHART_HEIGHT = 140;
const PAD_LEFT = 22;
const PAD_RIGHT = 18;
const PAD_TOP = 15;
const PAD_BOTTOM = 28;

const DEFAULT_CHART_PET: CatalogPet = {
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
export struct CatalogTrajectoryLegend {
  build() {
    Row({ space: 10 }) {
      LegendChip({ color: LPColor.coral, label: '心情', thick: true })
      LegendChip({ color: LPColor.muted, label: '精力', thick: false })
      LegendChip({ color: LPColor.ink, label: '体力', thick: false })
    }
  }
}

@Component
struct LegendChip {
  @Prop color: string = LPColor.ink;
  @Prop label: string = '';
  @Prop thick: boolean = false;

  build() {
    Row({ space: 4 }) {
      Column()
        .width(10)
        .height(this.thick ? 3 : 2)
        .backgroundColor(this.color)
      Text(this.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
  }
}

@Component
export struct CatalogTrajectoryChart {
  @Prop pet: CatalogPet = DEFAULT_CHART_PET;

  private valuesCount(): number {
    return Math.max(this.pet.series.vitality.length, this.pet.series.energy.length, this.pet.series.mood.length, 1);
  }

  private vy(value: number): number {
    const v = Math.max(0, Math.min(100, value));
    const top = PAD_TOP;
    const bottom = CHART_HEIGHT - PAD_BOTTOM;
    return top + (1 - v / 100) * (bottom - top);
  }

  private dx(day: number): number {
    const n = Math.max(this.pet.totalDays, this.valuesCount(), 1);
    const left = PAD_LEFT;
    const right = CHART_WIDTH - PAD_RIGHT;
    if (n <= 1) {
      return (left + right) / 2;
    }
    return left + (day - 1) * (right - left) / (n - 1);
  }

  private safeValue(values: number[], index: number): number {
    if (index < 0 || index >= values.length) {
      return 0;
    }
    return Math.max(0, Math.min(100, values[index]));
  }

  private axisDays(): number[] {
    const n = Math.max(this.pet.totalDays, 1);
    if (n <= 3) {
      return [1, n];
    }
    if (n <= 7) {
      return [1, Math.ceil(n / 2), n];
    }
    if (n <= 14) {
      return [1, 5, 10, n];
    }
    return [1, 5, 10, 15, n];
  }

  private uniqueAxisDays(): number[] {
    const out: number[] = [];
    this.axisDays().forEach((day: number) => {
      if (day <= this.pet.totalDays && !out.includes(day)) {
        out.push(day);
      }
    });
    return out;
  }

  private endDay(): number {
    return this.pet.isAlive ? Math.max(1, this.pet.days) : Math.max(1, this.pet.totalDays);
  }

  private endMood(): number {
    return this.safeValue(this.pet.series.mood, this.endDay() - 1);
  }

  build() {
    Stack() {
      ChartGrid()
      AxisLabels({ days: this.uniqueAxisDays() })
      LineSeries({ values: this.pet.series.energy, totalDays: this.pet.totalDays, color: LPColor.muted, width: 1.2 })
      LineSeries({ values: this.pet.series.vitality, totalDays: this.pet.totalDays, color: LPColor.ink, width: 1.2 })
      LineSeries({ values: this.pet.series.mood, totalDays: this.pet.totalDays, color: LPColor.coral, width: 1.8 })
      LastDots({
        day: this.endDay(),
        totalDays: this.pet.totalDays,
        vitality: this.safeValue(this.pet.series.vitality, this.endDay() - 1),
        energy: this.safeValue(this.pet.series.energy, this.endDay() - 1),
        mood: this.endMood()
      })
      if (this.pet.isAlive) {
        Column()
          .width(7)
          .height(7)
          .border({ width: 1, color: LPColor.coral })
          .borderRadius(4)
          .position({ x: this.dx(this.endDay()) - 3.5, y: this.vy(this.endMood()) - 3.5 })
        Text('· 今天 ·')
          .fontSize(7)
          .fontFamily('monospace')
          .fontColor(LPColor.coral)
          .position({ x: Math.max(PAD_LEFT, this.dx(this.endDay()) - 52), y: 2 })
      } else {
        VerticalDashedLine({ x: this.dx(this.endDay()) })
        Text('✦ 升天')
          .fontSize(7)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
          .position({ x: Math.max(PAD_LEFT, this.dx(this.endDay()) - 48), y: 2 })
      }
    }
    .width(CHART_WIDTH)
    .height(CHART_HEIGHT)
    .constraintSize({ maxWidth: '100%' })
  }
}

@Component
struct VerticalDashedLine {
  @Prop x: number = PAD_LEFT;

  private dashIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < 24; i++) {
      out.push(i);
    }
    return out;
  }

  build() {
    Column({ space: 2 }) {
      ForEach(this.dashIndexes(), (index: number) => {
        Column()
          .width(1)
          .height(2)
          .backgroundColor(LPColor.muted)
      }, (index: number) => `v-dash-${index}`)
    }
    .width(1)
    .height(CHART_HEIGHT - PAD_TOP - PAD_BOTTOM)
    .position({ x: this.x, y: PAD_TOP })
  }
}

@Component
struct ChartGrid {
  build() {
    Stack() {
      GridLine({ value: 100, dashed: true, color: LPColor.lcdDash })
      GridLine({ value: 50, dashed: true, color: LPColor.lcdDash })
      GridLine({ value: 0, dashed: false, color: '#BBAE99' })
      GridLine({ value: 85, dashed: true, color: '#D14B3D55' })
      GridLine({ value: 30, dashed: true, color: '#D14B3D55' })
    }
    .width(CHART_WIDTH)
    .height(CHART_HEIGHT)
  }
}

@Component
struct GridLine {
  @Prop value: number = 0;
  @Prop color: string = LPColor.lcdDash;
  @Prop dashed: boolean = false;

  private y(): number {
    const top = PAD_TOP;
    const bottom = CHART_HEIGHT - PAD_BOTTOM;
    return top + (1 - this.value / 100) * (bottom - top);
  }

  build() {
    Row({ space: this.dashed ? 3 : 0 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (index: number) => {
        Column()
          .height(1)
          .layoutWeight(1)
          .backgroundColor(this.color)
      }, (index: number) => index.toString())
    }
    .width(CHART_WIDTH - PAD_LEFT - PAD_RIGHT)
    .height(1)
    .position({ x: PAD_LEFT, y: this.y() })
  }
}

@Component
struct AxisLabels {
  @Prop days: number[] = [];

  private dx(day: number): number {
    const n = Math.max(this.days[this.days.length - 1] ?? 1, 1);
    const left = PAD_LEFT;
    const right = CHART_WIDTH - PAD_RIGHT;
    if (n <= 1) {
      return (left + right) / 2;
    }
    return left + (day - 1) * (right - left) / (n - 1);
  }

  build() {
    Stack() {
      ForEach([100, 50, 0], (value: number) => {
        Text(value.toString())
          .fontSize(7)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
          .position({ x: 6, y: PAD_TOP + (1 - value / 100) * (CHART_HEIGHT - PAD_BOTTOM - PAD_TOP) - 4 })
      }, (value: number) => `y-${value}`)
      ForEach(this.days, (day: number) => {
        Text(`D${day}`)
          .fontSize(7)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
          .position({ x: this.dx(day) - 8, y: CHART_HEIGHT - PAD_BOTTOM + 7 })
      }, (day: number) => `d-${day}`)
    }
    .width(CHART_WIDTH)
    .height(CHART_HEIGHT)
  }
}

@Component
struct LineSeries {
  @Prop values: number[] = [];
  @Prop totalDays: number = 1;
  @Prop color: string = LPColor.ink;
  @Prop width: number = 1.2;

  private dx(day: number): number {
    const n = Math.max(this.totalDays, 1);
    const left = PAD_LEFT;
    const right = CHART_WIDTH - PAD_RIGHT;
    if (n <= 1) {
      return (left + right) / 2;
    }
    return left + (day - 1) * (right - left) / (n - 1);
  }

  private vy(value: number): number {
    const v = Math.max(0, Math.min(100, value));
    const top = PAD_TOP;
    const bottom = CHART_HEIGHT - PAD_BOTTOM;
    return top + (1 - v / 100) * (bottom - top);
  }

  private segmentIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < Math.max(0, this.values.length - 1); i++) {
      out.push(i);
    }
    return out;
  }

  build() {
    Stack() {
      ForEach(this.segmentIndexes(), (index: number) => {
        Line()
          .startPoint([this.dx(index + 1), this.vy(this.values[index])])
          .endPoint([this.dx(index + 2), this.vy(this.values[index + 1])])
          .stroke(this.color)
          .strokeWidth(this.width)
      }, (index: number) => `seg-${index}`)
    }
    .width(CHART_WIDTH)
    .height(CHART_HEIGHT)
  }
}

@Component
struct LastDots {
  @Prop day: number = 1;
  @Prop totalDays: number = 1;
  @Prop vitality: number = 0;
  @Prop energy: number = 0;
  @Prop mood: number = 0;

  private dx(day: number): number {
    const n = Math.max(this.totalDays, 1);
    const left = PAD_LEFT;
    const right = CHART_WIDTH - PAD_RIGHT;
    if (n <= 1) {
      return (left + right) / 2;
    }
    return left + (day - 1) * (right - left) / (n - 1);
  }

  private vy(value: number): number {
    const v = Math.max(0, Math.min(100, value));
    return PAD_TOP + (1 - v / 100) * (CHART_HEIGHT - PAD_BOTTOM - PAD_TOP);
  }

  build() {
    Stack() {
      Dot({ x: this.dx(this.day), y: this.vy(this.energy), color: LPColor.muted, size: 4 })
      Dot({ x: this.dx(this.day), y: this.vy(this.vitality), color: LPColor.ink, size: 4 })
      Dot({ x: this.dx(this.day), y: this.vy(this.mood), color: LPColor.coral, size: 5 })
    }
    .width(CHART_WIDTH)
    .height(CHART_HEIGHT)
  }
}

@Component
struct Dot {
  @Prop x: number = 0;
  @Prop y: number = 0;
  @Prop color: string = LPColor.ink;
  @Prop size: number = 4;

  build() {
    Column()
      .width(this.size)
      .height(this.size)
      .backgroundColor(this.color)
      .borderRadius(this.size / 2)
      .position({ x: this.x - this.size / 2, y: this.y - this.size / 2 })
  }
}
