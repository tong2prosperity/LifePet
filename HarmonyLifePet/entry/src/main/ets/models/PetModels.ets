export enum PetState {
  Sick = 'SICK',
  Sleeping = 'SLEEPING',
  Tired = 'TIRED',
  Normal = 'NORMAL',
  Excited = 'EXCITED',
  Blissful = 'BLISSFUL'
}

export function showsSparkles(state: PetState): boolean {
  return state === PetState.Excited || state === PetState.Blissful;
}

export enum StatKind {
  Vitality = 'vitality',
  Energy = 'energy',
  Mood = 'mood'
}

export function statLabel(kind: StatKind): string {
  switch (kind) {
    case StatKind.Vitality:
      return '体力';
    case StatKind.Energy:
      return '精力';
    case StatKind.Mood:
      return '心情';
    default:
      return '';
  }
}

export function statEmoji(kind: StatKind): string {
  switch (kind) {
    case StatKind.Vitality:
      return '💪';
    case StatKind.Energy:
      return '⚡';
    case StatKind.Mood:
      return '❤️';
    default:
      return '';
  }
}

export function statSourceCopy(kind: StatKind): string {
  switch (kind) {
    case StatKind.Vitality:
      return '步数 · 运动分钟 · 活动卡路里';
    case StatKind.Energy:
      return '总睡眠 · 深睡 · REM';
    case StatKind.Mood:
      return 'HRV · 心率稳定度';
    default:
      return '';
  }
}

export function statSupplementCopy(kind: StatKind): string {
  switch (kind) {
    case StatKind.Vitality:
      return '走 1000 步 +4 / 运动 10 分钟 +10';
    case StatKind.Energy:
      return '每睡 1 小时 +6 / 深睡多 30 分钟 +15';
    case StatKind.Mood:
      return '冥想 5 分钟 +15 / 深呼吸 1 次 +3';
    default:
      return '';
  }
}

export interface Stat {
  kind: StatKind;
  value: number;
}

export enum StepStatus {
  Done = 'done',
  Suggest = 'suggest'
}

export enum StepKind {
  Run = 'run',
  Sleep = 'sleep',
  Breath = 'breath',
  Meditate = 'meditate',
  Walk = 'walk'
}

export function stepKindQuitLabel(kind: StepKind): string {
  switch (kind) {
    case StepKind.Run:
      return '跑步';
    case StepKind.Sleep:
      return '睡眠';
    case StepKind.Breath:
      return '深呼吸';
    case StepKind.Meditate:
      return '冥想';
    case StepKind.Walk:
      return '走路';
    default:
      return '';
  }
}

export interface StepItem {
  id: string;
  status: StepStatus;
  kind: StepKind;
  actionLabel: string;
  titleValue: string;
  affects: StatKind;
  gain: number;
  time: string;
  fromAutoSensor: boolean;
}

export interface PendingWorkout {
  id: string;
  kind: WorkoutKind;
  label: string;
  durationMin: number;
  kcal?: number;
  endedAt: number;
  gainVitality: number;
}

export enum WorkoutKind {
  Run = 'run',
  Walk = 'walk',
  Cycle = 'cycle',
  Hiit = 'hiit',
  Yoga = 'yoga',
  Other = 'other'
}

export interface RawMetrics {
  steps: number;
  exerciseMinutes: number;
  activeEnergy: number;
  standMinutes: number;
  heartRate: number;
  hrv: number;
  hrvBaseline?: number;
  restingHR: number;
  sleepTotal: number;
  sleepDeep: number;
  sleepREM: number;
  sleepStart?: number;
  mindfulMinutes: number;
}

export const emptyRawMetrics: RawMetrics = {
  steps: 0,
  exerciseMinutes: 0,
  activeEnergy: 0,
  standMinutes: 0,
  heartRate: 0,
  hrv: 0,
  restingHR: 0,
  sleepTotal: 0,
  sleepDeep: 0,
  sleepREM: 0,
  mindfulMinutes: 0
};
