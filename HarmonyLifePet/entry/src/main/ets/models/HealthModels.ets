import { WorkoutKind } from './PetModels';

export enum HealthEventType {
  Steps = 'steps',
  ExerciseMinutes = 'exerciseMinutes',
  ActiveEnergy = 'activeEnergy',
  StandMinutes = 'standMinutes',
  HeartRate = 'heartRate',
  Hrv = 'hrv',
  RestingHR = 'restingHR',
  Sleep = 'sleep',
  MindfulMinutes = 'mindfulMinutes',
  WorkoutFinished = 'workoutFinished'
}

export interface HealthEvent {
  type: HealthEventType;
  value?: number;
  total?: number;
  deep?: number;
  rem?: number;
  start?: number;
  kind?: WorkoutKind;
  duration?: number;
  kcal?: number;
  end?: number;
}

export function numericEvent(type: HealthEventType, value: number): HealthEvent {
  return { type, value };
}
