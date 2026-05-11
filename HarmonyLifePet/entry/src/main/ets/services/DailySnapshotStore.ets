import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { startOfDayMs } from '../utils/DateUtils';

const STORE_NAME = 'lifepet_snapshots';

export interface DailySnapshot {
  petId: string;
  date: number;
  vitality: number;
  energy: number;
  mood: number;
  stateTag: string;
  steps: number;
  exerciseMinutes: number;
  activeEnergy: number;
  standMinutes: number;
  hrv: number;
  restingHR: number;
  sleepTotal: number;
  sleepDeep: number;
  sleepREM: number;
  mindfulMinutes: number;
  completedStepKinds: string[];
  updatedAt: number;
}

export class DailySnapshotStore {
  private cache: DailySnapshot[] = [];

  async restore(context: common.UIAbilityContext): Promise<void> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    const raw = String(await pref.get('items', '[]'));
    try {
      this.cache = JSON.parse(raw) as DailySnapshot[];
    } catch (e) {
      this.cache = [];
    }
  }

  async write(context: common.UIAbilityContext, snapshot: DailySnapshot): Promise<void> {
    const day = startOfDayMs(snapshot.date);
    this.cache = this.cache.filter((item: DailySnapshot) => !(item.petId === snapshot.petId && startOfDayMs(item.date) === day));
    this.cache.push({ ...snapshot, date: day, updatedAt: Date.now() });
    const pref = await preferences.getPreferences(context, STORE_NAME);
    await pref.put('items', JSON.stringify(this.cache));
    await pref.flush();
  }

  recent(petId: string, days: number): DailySnapshot[] {
    if (days <= 0) {
      return [];
    }
    const today = startOfDayMs();
    const cutoff = today - (days - 1) * 86400000;
    return this.cache
      .filter((item: DailySnapshot) => item.petId === petId && item.date >= cutoff && item.date <= today)
      .sort((a: DailySnapshot, b: DailySnapshot) => a.date - b.date);
  }

  range(petId: string, from: number, through: number): DailySnapshot[] {
    const start = startOfDayMs(from);
    const end = startOfDayMs(through);
    if (start > end) {
      return [];
    }
    return this.cache
      .filter((item: DailySnapshot) => item.petId === petId && item.date >= start && item.date <= end)
      .sort((a: DailySnapshot, b: DailySnapshot) => a.date - b.date);
  }
}
