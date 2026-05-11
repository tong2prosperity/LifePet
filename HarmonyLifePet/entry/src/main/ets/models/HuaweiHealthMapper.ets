import { HealthEvent, HealthEventType, numericEvent } from './HealthModels';
import { WorkoutKind } from './PetModels';

export const HuaweiSleepStage = {
  Awake: 'awake',
  InBed: 'inBed',
  Asleep: 'asleep',
  AsleepCore: 'asleepCore',
  AsleepDeep: 'asleepDeep',
  AsleepRem: 'asleepRem',
  AsleepUnspecified: 'asleepUnspecified'
};

export interface HuaweiDailyHealthSnapshot {
  steps?: number;
  exerciseMinutes?: number;
  activeEnergyKcal?: number;
  standMinutes?: number;
  heartRateBpm?: number;
  hrvMs?: number;
  restingHeartRateBpm?: number;
  mindfulMinutes?: number;
}

export interface HuaweiSleepSample {
  stage: string;
  start: number;
  end: number;
}

export interface HuaweiWorkoutSample {
  id?: string;
  activity: string;
  duration: number;
  kcal?: number;
  end: number;
}

export function mapDailySnapshot(snapshot: HuaweiDailyHealthSnapshot): HealthEvent[] {
  const events: HealthEvent[] = [];
  pushNumber(events, HealthEventType.Steps, snapshot.steps);
  pushNumber(events, HealthEventType.ExerciseMinutes, snapshot.exerciseMinutes);
  pushNumber(events, HealthEventType.ActiveEnergy, snapshot.activeEnergyKcal);
  pushNumber(events, HealthEventType.StandMinutes, snapshot.standMinutes);
  pushNumber(events, HealthEventType.HeartRate, snapshot.heartRateBpm);
  pushNumber(events, HealthEventType.Hrv, snapshot.hrvMs);
  pushNumber(events, HealthEventType.RestingHR, snapshot.restingHeartRateBpm);
  pushNumber(events, HealthEventType.MindfulMinutes, snapshot.mindfulMinutes);
  return events;
}

export function mapSleepSamples(samples: HuaweiSleepSample[]): HealthEvent {
  const sorted = samples
    .filter((sample) => sample.end > sample.start)
    .sort((left, right) => left.start - right.start);
  const hasStages = sorted.some((sample) => isStageSleep(sample.stage));
  const sessions = [];
  const sessionGap = 4 * 3600 * 1000;

  sorted.forEach((sample) => {
    const counts = isStageSleep(sample.stage) ||
      (sample.stage === HuaweiSleepStage.Asleep && !hasStages);
    if (!counts) {
      return;
    }
    const duration = sample.end - sample.start;
    const deep = sample.stage === HuaweiSleepStage.AsleepDeep ? duration : 0;
    const rem = sample.stage === HuaweiSleepStage.AsleepRem ? duration : 0;
    const last = sessions.length > 0 ? sessions[sessions.length - 1] : undefined;
    if (last && sample.start - last.end < sessionGap) {
      last.end = Math.max(last.end, sample.end);
      last.total += duration;
      last.deep += deep;
      last.rem += rem;
    } else {
      sessions.push({
        start: sample.start,
        end: sample.end,
        total: duration,
        deep,
        rem
      });
    }
  });

  const latest = sessions.reduce((candidate, session) => {
    if (!candidate || session.end > candidate.end) {
      return session;
    }
    return candidate;
  }, undefined);

  return {
    type: HealthEventType.Sleep,
    total: latest?.total ?? 0,
    deep: latest?.deep ?? 0,
    rem: latest?.rem ?? 0,
    start: latest?.start
  };
}

export function bucketHuaweiWorkoutActivity(activity: string): WorkoutKind {
  const key = activity.toLowerCase().replace(/[\s_-]/g, '');
  switch (key) {
    case 'running':
    case 'run':
      return WorkoutKind.Run;
    case 'walking':
    case 'walk':
    case 'hiking':
      return WorkoutKind.Walk;
    case 'cycling':
    case 'cycle':
    case 'handcycling':
      return WorkoutKind.Cycle;
    case 'highintensityintervaltraining':
    case 'hiit':
    case 'functionalstrengthtraining':
    case 'traditionalstrengthtraining':
    case 'strengthtraining':
    case 'crosstraining':
      return WorkoutKind.Hiit;
    case 'yoga':
    case 'pilates':
    case 'flexibility':
    case 'mindandbody':
    case 'barre':
      return WorkoutKind.Yoga;
    default:
      return WorkoutKind.Other;
  }
}

export function mapWorkoutSamples(
  samples: HuaweiWorkoutSample[],
  emittedIds: string[] = []
): HealthEvent[] {
  const seen = new Set<string>(emittedIds);
  const events: HealthEvent[] = [];
  samples
    .filter((sample) => sample.duration > 0 && sample.end > 0)
    .sort((left, right) => left.end - right.end)
    .forEach((sample) => {
      const id = sample.id ?? `${sample.activity}-${sample.end}-${sample.duration}`;
      if (seen.has(id)) {
        return;
      }
      seen.add(id);
      emittedIds.push(id);
      events.push({
        type: HealthEventType.WorkoutFinished,
        kind: bucketHuaweiWorkoutActivity(sample.activity),
        duration: sample.duration,
        kcal: sample.kcal,
        end: sample.end
      });
    });
  return events;
}

function pushNumber(events: HealthEvent[], type: HealthEventType, value: number | undefined): void {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
    events.push(numericEvent(type, value));
  }
}

function isStageSleep(stage: string): boolean {
  return stage === HuaweiSleepStage.AsleepCore ||
    stage === HuaweiSleepStage.AsleepDeep ||
    stage === HuaweiSleepStage.AsleepRem ||
    stage === HuaweiSleepStage.AsleepUnspecified;
}
