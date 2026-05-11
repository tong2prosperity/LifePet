import { PetState, RawMetrics, Stat, StatKind } from './PetModels';

export interface StatDecay {
  vitality: number;
  energy: number;
  mood: number;
}

export function clampScore(value: number): number {
  return Math.min(100, Math.max(0, value));
}

export function computeVitality(raw: RawMetrics): number {
  const base = 20;
  const stepC = raw.steps / 10000 * 40;
  const exC = raw.exerciseMinutes / 30 * 30;
  const kcalC = raw.activeEnergy / 300 * 10;
  return clampScore(Math.floor(base + stepC + exC + kcalC));
}

export function computeSleepScore(raw: RawMetrics): number {
  const totalH = raw.sleepTotal / 3600;
  const deepH = raw.sleepDeep / 3600;
  const remH = raw.sleepREM / 3600;
  const duration = Math.min(1, totalH / 8) * 50;
  const deep = Math.min(1, deepH / 1.5) * 25;
  const rem = Math.min(1, remH / 1.5) * 15;
  const continuity = Math.min(1, totalH / 6) * 10;
  return clampScore(Math.floor(duration + deep + rem + continuity));
}

export function computeEnergy(raw: RawMetrics): number {
  const totalH = raw.sleepTotal / 3600;
  const deepH = raw.sleepDeep / 3600;
  const remH = raw.sleepREM / 3600;
  const base = totalH / 8 * 50 + deepH / 2 * 30 + remH / 1.5 * 20;
  const modifier = (computeSleepScore(raw) - 70) * 0.3;
  return clampScore(Math.floor(base + modifier));
}

export function computeMood(raw: RawMetrics): number {
  if (raw.hrv <= 0) {
    return 50;
  }
  const baseline = raw.hrvBaseline ?? raw.hrv;
  return clampScore(50 + Math.floor((raw.hrv - baseline) * 0.8));
}

export function derivePetState(vitality: number, energy: number, mood: number): PetState {
  if (mood < 30) {
    return PetState.Sick;
  }
  if (energy < 30) {
    return PetState.Sleeping;
  }
  if (vitality < 30) {
    return PetState.Tired;
  }
  if (mood > 85) {
    return PetState.Blissful;
  }
  if (vitality > 85) {
    return PetState.Excited;
  }
  return PetState.Normal;
}

export function deriveStats(raw: RawMetrics, decay: StatDecay): Stat[] {
  const vitality = Math.max(10, computeVitality(raw) - decay.vitality);
  const energy = Math.max(10, computeEnergy(raw) - decay.energy);
  const mood = Math.max(10, computeMood(raw) - decay.mood);
  return [
    { kind: StatKind.Vitality, value: vitality },
    { kind: StatKind.Energy, value: energy },
    { kind: StatKind.Mood, value: mood }
  ];
}
