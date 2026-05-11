import { HealthEvent, HealthEventType, numericEvent } from '../models/HealthModels';
import {
  HuaweiDailyHealthSnapshot,
  HuaweiSleepSample,
  HuaweiWorkoutSample,
  mapDailySnapshot,
  mapSleepSamples,
  mapWorkoutSamples
} from '../models/HuaweiHealthMapper';
import { WorkoutKind } from '../models/PetModels';

export interface HealthScopeDescriptor {
  id: string;
  label: string;
  purpose: string;
}

export const requiredHealthScopes: HealthScopeDescriptor[] = [
  { id: 'steps', label: '步数 / 日常活动', purpose: '计算体力和每日进度' },
  { id: 'exerciseMinutes', label: '运动分钟', purpose: '补充体力评分和今日运动进度' },
  { id: 'workout', label: '运动记录', purpose: '触发运动投喂和今日卡片' },
  { id: 'activeEnergy', label: '活动能量', purpose: '补充体力评分' },
  { id: 'standMinutes', label: '站立分钟', purpose: '补充今日活动完成度' },
  { id: 'heartRate', label: '心率', purpose: '辅助心情和状态判断' },
  { id: 'hrv', label: 'HRV', purpose: '计算心情波动' },
  { id: 'restingHR', label: '静息心率', purpose: '辅助心情基线和压力判断' },
  { id: 'sleep', label: '睡眠 / 深睡 / REM', purpose: '计算精力和睡眠卡片' },
  { id: 'mindful', label: '冥想 / 正念时长', purpose: '改善心情建议' }
];

export enum HealthAuthState {
  Unknown = 'unknown',
  Requesting = 'requesting',
  Granted = 'granted',
  Denied = 'denied',
  Unavailable = 'unavailable',
  PlatformApprovalRequired = 'platformApprovalRequired'
}

export interface HealthDataProvider {
  authState: HealthAuthState;
  requestAuthorization(): Promise<HealthAuthState>;
  reconcile(): Promise<HealthEvent[]>;
}

export class MockHealthDataService implements HealthDataProvider {
  authState: HealthAuthState = HealthAuthState.Unknown;

  async requestAuthorization(): Promise<HealthAuthState> {
    this.authState = HealthAuthState.Granted;
    return this.authState;
  }

  async reconcile(): Promise<HealthEvent[]> {
    const now = Date.now();
    const sleepStart = now - 9.5 * 3600000;
    return [
      numericEvent(HealthEventType.Steps, 8420),
      numericEvent(HealthEventType.ExerciseMinutes, 28),
      numericEvent(HealthEventType.ActiveEnergy, 318),
      numericEvent(HealthEventType.StandMinutes, 84),
      numericEvent(HealthEventType.HeartRate, 74),
      numericEvent(HealthEventType.Hrv, 52),
      numericEvent(HealthEventType.RestingHR, 61),
      {
        type: HealthEventType.Sleep,
        total: 6.2 * 3600,
        deep: 1.1 * 3600,
        rem: 1.3 * 3600,
        start: sleepStart
      },
      numericEvent(HealthEventType.MindfulMinutes, 0),
      {
        type: HealthEventType.WorkoutFinished,
        kind: WorkoutKind.Run,
        duration: 28 * 60,
        kcal: 218,
        end: now - 2 * 60 * 1000
      }
    ];
  }
}

/// Real Health Service Kit adapter placeholder.
///
/// Huawei Health Service Kit requires developer-console service approval plus
/// runtime user authorization. Keep this class separate so UI/business work
/// can continue with MockHealthDataService while the approval process runs.
export class HuaweiHealthDataService implements HealthDataProvider {
  authState: HealthAuthState = HealthAuthState.PlatformApprovalRequired;
  readonly scopes: HealthScopeDescriptor[] = requiredHealthScopes;
  private emittedWorkoutIds: string[] = [];

  async requestAuthorization(): Promise<HealthAuthState> {
    this.authState = HealthAuthState.PlatformApprovalRequired;
    return this.authState;
  }

  async reconcile(): Promise<HealthEvent[]> {
    return [];
  }

  protected mapApprovedSamples(
    daily: HuaweiDailyHealthSnapshot,
    sleep: HuaweiSleepSample[],
    workouts: HuaweiWorkoutSample[]
  ): HealthEvent[] {
    return [
      ...mapDailySnapshot(daily),
      mapSleepSamples(sleep),
      ...mapWorkoutSamples(workouts, this.emittedWorkoutIds)
    ];
  }
}
