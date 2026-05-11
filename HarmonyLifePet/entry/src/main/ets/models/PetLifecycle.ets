import { startOfDayMs } from '../utils/DateUtils';

export interface DecayCatchup {
  ticks: number;
  vitalityDecay: number;
  energyDecay: number;
  moodDecay: number;
  nextLastDecayAt: number;
}

export function shouldResetForNewDay(lastSeenDate: number, nowMs: number = -1): boolean {
  const effectiveNow = nowMs >= 0 ? nowMs : Date.now();
  return startOfDayMs(effectiveNow) > startOfDayMs(lastSeenDate);
}

export function computeDecayCatchup(lastDecayAt: number, nowMs: number = -1): DecayCatchup {
  const effectiveNow = nowMs >= 0 ? nowMs : Date.now();
  const interval = 4 * 3600000;
  const elapsed = effectiveNow - lastDecayAt;
  if (elapsed < interval) {
    return {
      ticks: 0,
      vitalityDecay: 0,
      energyDecay: 0,
      moodDecay: 0,
      nextLastDecayAt: lastDecayAt
    };
  }

  const ticks = Math.floor(elapsed / interval);
  let energyTicks = 0;
  for (let idx = 1; idx <= ticks; idx++) {
    const tickTime = new Date(lastDecayAt + idx * interval);
    if (tickTime.getHours() >= 7) {
      energyTicks += 1;
    }
  }

  return {
    ticks,
    vitalityDecay: ticks * 5,
    energyDecay: energyTicks * 5,
    moodDecay: ticks * 5,
    nextLastDecayAt: lastDecayAt + ticks * interval
  };
}
