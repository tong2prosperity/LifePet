import { LPColor } from '../theme/LPTheme';

interface ParticleDot {
  x: number;
  y: number;
  size: number;
  color: string;
  opacity: number;
}

@Component
export struct EnergyParticleField {
  @Prop @Watch('onTokenChanged') token: number = 0;
  @Prop targetXPercent: number = 50;
  @Prop targetY: number = 92;
  @Prop startY: number = 176;
  @State visible: boolean = false;
  @State elapsed: number = 0;
  private lastToken: number = 0;
  private timerId: number = -1;
  private particleCount: number = 16;
  private particleDuration: number = 0.9;
  private particleStagger: number = 0.038;

  aboutToAppear(): void {
    this.onTokenChanged();
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private active(): boolean {
    return this.visible;
  }

  private onTokenChanged(): void {
    if (this.token <= 0 || this.token === this.lastToken) {
      return;
    }
    this.lastToken = this.token;
    this.visible = true;
    this.elapsed = 0;
    this.clearTimer();
    animateTo({ duration: 1508, curve: Curve.Linear }, () => {
      this.elapsed = this.particleDuration + this.particleStagger * (this.particleCount - 1);
    });
    this.timerId = setTimeout(() => {
      this.visible = false;
      this.elapsed = 0;
      this.timerId = -1;
    }, 1600);
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private dots(): ParticleDot[] {
    const out: ParticleDot[] = [];
    for (let index = 0; index < this.particleCount; index++) {
      const local = this.elapsed - index * this.particleStagger;
      if (local < 0 || local > this.particleDuration) {
        continue;
      }
      const t = local / this.particleDuration;
      const eased = t * t;
      const jitterX = Math.sin(index * 2.17) * 22;
      const jitterY = Math.cos(index * 1.41) * 8;
      const startX = 50 + jitterX / 3.6;
      const startY = this.startY + jitterY;
      const lift = -28 * 4 * t * (1 - t);
      const x = startX + (this.targetXPercent - startX) * eased;
      const y = startY + (this.targetY - startY) * eased + lift;
      const size = 8 * (1 - 0.7 * eased);
      out.push({
        x,
        y,
        size,
        color: this.energyColor(index),
        opacity: t < 0.8 ? 1 : Math.max(0, 1 - (t - 0.8) / 0.2)
      });
    }
    return out;
  }

  private energyColor(index: number): string {
    switch (index % 3) {
      case 0:
        return '#3EB24E';
      case 1:
        return LPColor.coral;
      default:
        return '#4A90D9';
    }
  }

  build() {
    Stack() {
      if (this.active()) {
        ForEach(this.dots(), (dot: ParticleDot, index: number) => {
          Column()
            .width(dot.size)
            .height(dot.size)
            .backgroundColor(dot.color)
            .borderRadius(dot.size / 2)
            .opacity(dot.opacity)
            .position({ x: `${dot.x}%`, y: dot.y })
        }, (dot: ParticleDot, index: number) => `${this.token}-${index}`)
      }
    }
    .width('100%')
    .height(208)
  }
}
