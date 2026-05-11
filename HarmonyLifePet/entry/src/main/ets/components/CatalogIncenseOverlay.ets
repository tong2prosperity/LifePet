import { CatalogPet } from '../models/CatalogModels';
import { PetSpriteName } from '../models/PetSpriteModels';
import { MemorialAudioPlayer, memorialAudioForPet } from '../services/MemorialAudioPlayer';
import { LPColor } from '../theme/LPTheme';
import { common } from '@kit.AbilityKit';

interface MemorialBar {
  height: number;
  color: string;
  opacity: number;
}

interface SmokeParticle {
  x: number;
  y: number;
  radius: number;
  opacity: number;
}

const DEFAULT_INCENSE_PET: CatalogPet = {
  id: 'empty',
  name: 'BEAN',
  sprite: PetSpriteName.Bean,
  isAlive: false,
  dates: '今日',
  days: 1,
  totalDays: 1,
  stats: { vitality: 0, energy: 0, mood: 0 },
  series: { vitality: [0], energy: [0], mood: [0] },
  moments: [],
  bio: '',
  memorialTitle: '《纪念曲》',
  memorialDuration: '0:15',
  isRare: false
};

@Component
export struct CatalogIncenseOverlay {
  @Prop pet: CatalogPet = DEFAULT_INCENSE_PET;
  @State elapsed: number = 0;
  private timerId: number = -1;
  private memorialAudio: MemorialAudioPlayer = new MemorialAudioPlayer();
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.elapsed = 0;
    this.clearTimer();
    this.timerId = setInterval(() => {
      this.elapsed = Math.min(15, this.elapsed + 1);
      if (this.elapsed >= 15) {
        this.clearTimer();
      }
    }, 1000);
    const context = getContext(this) as common.UIAbilityContext;
    void this.memorialAudio.play(context, memorialAudioForPet(this.pet));
  }

  aboutToDisappear(): void {
    this.clearTimer();
    void this.memorialAudio.stop();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private close(): void {
    this.clearTimer();
    void this.memorialAudio.stop();
    this.onClose();
  }

  private progress(): number {
    return this.elapsed / 15;
  }

  private elapsedLabel(): string {
    if (this.elapsed >= 15) {
      return '✦ 完成';
    }
    return `0:${this.elapsed.toString().padStart(2, '0')}`;
  }

  build() {
    Column() {
      Blank()

      Text('— 上 香 —')
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor('#6A5030')
        .letterSpacing(4)
        .margin({ bottom: 6 })
      Text(`为 ${this.pet.name}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E0C070')
        .letterSpacing(2)
        .margin({ bottom: 20 })

      IncenseSprite()
        .width(60)
        .height(165)
        .margin({ bottom: 20 })

      Column({ space: 8 }) {
        Text(this.pet.memorialTitle ?? '《纪念曲》')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#9A7840')

        MemorialWaveform({ pet: this.pet, progress: this.progress(), muted: true })

        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width('100%')
            .height(2)
            .backgroundColor('#6A50304D')
            .borderRadius(1)
          Column()
            .width(`${Math.floor(this.progress() * 100)}%`)
            .height(2)
            .backgroundColor('#C8903C')
            .borderRadius(1)
        }
        .width('100%')
        .height(2)

        Row() {
          Text(this.elapsedLabel())
          Blank()
          Text('0:15')
        }
        .width('100%')
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor('#6A5030')
        .letterSpacing(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 22 })

      Button('收香')
        .height(38)
        .padding({ left: 32, right: 32 })
        .backgroundColor(Color.Transparent)
        .fontColor('#9A7840')
        .fontSize(16)
        .letterSpacing(3)
        .border({ width: 1.5, color: '#9A784080' })
        .borderRadius(8)
        .onClick(() => this.close())

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0A0602F5')
  }
}

@Component
export struct MemorialWaveform {
  @Prop pet: CatalogPet = DEFAULT_INCENSE_PET;
  @Prop progress: number = 0.18;
  @Prop muted: boolean = false;

  private barCount(): number {
    return Math.min(this.pet.series.vitality.length, this.pet.series.energy.length, this.pet.series.mood.length);
  }

  private waveformHeight(): number {
    return this.muted ? 26 : 40;
  }

  private bars(): MemorialBar[] {
    const out: MemorialBar[] = [];
    const count = this.barCount();
    const maxHeight = this.waveformHeight() - 6;
    for (let index = 0; index < count; index++) {
      const vitality = this.pet.series.vitality[index];
      const energy = this.pet.series.energy[index];
      const mood = this.pet.series.mood[index];
      const avg = (vitality + energy + mood) / 3;
      const played = (index / Math.max(1, count)) < this.progress;
      out.push({
        height: Math.max(3, avg / 100 * maxHeight),
        color: this.barColor(vitality, energy, mood, played),
        opacity: this.muted ? 0.72 : 0.9
      });
    }
    return out;
  }

  private barColor(vitality: number, energy: number, mood: number, played: boolean): string {
    if (this.muted) {
      return played ? '#C8903C' : '#C8A860';
    }
    if (mood >= vitality && mood >= energy) {
      return played ? LPColor.coral : '#E67A6955';
    }
    if (energy >= vitality) {
      return played ? LPColor.muted : '#6E665A55';
    }
    return played ? LPColor.ink : '#1E1A1755';
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.muted ? '#6A503080' : '#6E665A80')
        .position({ x: 0, y: this.waveformHeight() - 1 })
      Row({ space: 1.5 }) {
        ForEach(this.bars(), (bar: MemorialBar, index: number) => {
          Column()
            .layoutWeight(1)
            .height(bar.height)
            .backgroundColor(bar.color)
            .opacity(bar.opacity)
        }, (bar: MemorialBar, index: number) => index.toString())
      }
      .width('100%')
      .height(this.waveformHeight())
      .alignItems(VerticalAlign.Bottom)
      Column()
        .width(1)
        .height(this.waveformHeight())
        .backgroundColor(LPColor.coral)
        .position({ x: `${Math.floor(Math.max(0, Math.min(1, this.progress)) * 100)}%`, y: 0 })
    }
    .width('100%')
    .height(this.waveformHeight())
  }
}

@Component
struct IncenseSprite {
  @State pulse: boolean = false;
  @State smokeTime: number = 0;
  private pulseTimerId: number = -1;
  private smokeTimerId: number = -1;

  aboutToAppear(): void {
    this.clearTimers();
    this.pulseTimerId = setInterval(() => {
      animateTo({ duration: 800, curve: Curve.EaseInOut }, () => {
        this.pulse = !this.pulse;
      });
    }, 800);
    this.smokeTimerId = setInterval(() => {
      this.smokeTime = (this.smokeTime + 0.1) % 3;
    }, 100);
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.pulseTimerId >= 0) {
      clearInterval(this.pulseTimerId);
      this.pulseTimerId = -1;
    }
    if (this.smokeTimerId >= 0) {
      clearInterval(this.smokeTimerId);
      this.smokeTimerId = -1;
    }
  }

  private smokeParticles(): SmokeParticle[] {
    const particles: [number, number, number, number, number][] = [
      [30, 18, 2.5, 0.7, 0.0],
      [27, 16, 3.5, 0.5, 0.9],
      [33, 20, 2.0, 0.6, 1.8],
      [29, 14, 3.0, 0.4, 2.5]
    ];
    const out: SmokeParticle[] = [];
    for (const particle of particles) {
      const phase = ((this.smokeTime - particle[4]) % 3 + 3) % 3 / 3;
      const radius = particle[2];
      out.push({
        x: particle[0] + this.smokeDrift(phase) - radius,
        y: particle[1] - 65 * phase - radius,
        radius,
        opacity: particle[3] * this.smokeEnvelope(phase)
      });
    }
    return out;
  }

  private smokeDrift(t: number): number {
    if (t < 0.3) {
      return 4 * (t / 0.3);
    }
    if (t < 0.65) {
      return 4 - 7 * ((t - 0.3) / 0.35);
    }
    return -3 + 4 * ((t - 0.65) / 0.35);
  }

  private smokeEnvelope(t: number): number {
    if (t < 0.3) {
      return this.lerp(0.8, 0.5, t / 0.3);
    }
    if (t < 0.65) {
      return this.lerp(0.5, 0.2, (t - 0.3) / 0.35);
    }
    return this.lerp(0.2, 0, (t - 0.65) / 0.35);
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  build() {
    Stack() {
      ForEach(this.smokeParticles(), (particle: SmokeParticle, index: number) => {
        Column()
          .width(particle.radius * 2)
          .height(particle.radius * 2)
          .borderRadius(particle.radius)
          .backgroundColor('#C8AF82')
          .opacity(particle.opacity)
          .position({ x: particle.x, y: particle.y })
      }, (particle: SmokeParticle, index: number) => index.toString())
      PixelRect({ x: 29, y: 34, w: 2, h: 12, color: '#B8B090' })
      PixelRect({ x: 29, y: 46, w: 2, h: 60, color: '#8B6840' })
      PixelRect({ x: 17, y: 106, w: 26, h: 2, color: '#7A6040' })
      PixelRect({ x: 18, y: 108, w: 24, h: 2, color: '#8B7050' })
      PixelRect({ x: 20, y: 110, w: 20, h: 12, color: '#6B5030' })
      PixelRect({ x: 17, y: 122, w: 26, h: 3, color: '#4A3020' })
      PixelRect({ x: 20, y: 125, w: 5, h: 4, color: '#3A2010' })
      PixelRect({ x: 35, y: 125, w: 5, h: 4, color: '#3A2010' })
      PixelRect({ x: 21, y: 114, w: 18, h: 1, color: '#9A8060B3' })
      PixelRect({ x: 21, y: 118, w: 18, h: 1, color: '#9A8060B3' })
      PixelRect({ x: 27, y: 108, w: 6, h: 4, color: '#C8B88899' })
      Column()
        .width(4)
        .height(5)
        .backgroundColor('#C83828')
        .position({ x: 28, y: 26 })
        .opacity(this.pulse ? 0.3 : 1)
      Column()
        .width(2)
        .height(4)
        .backgroundColor('#FF8028')
        .position({ x: 29, y: 23 })
        .opacity(this.pulse ? 1 : 0.3)
    }
    .width(60)
    .height(165)
  }
}

@Component
struct PixelRect {
  @Prop x: number = 0;
  @Prop y: number = 0;
  @Prop w: number = 1;
  @Prop h: number = 1;
  @Prop color: string = LPColor.ink;

  build() {
    Column()
      .width(this.w)
      .height(this.h)
      .backgroundColor(this.color)
      .position({ x: this.x, y: this.y })
  }
}
