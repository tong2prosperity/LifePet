import {
  emptyRawMetrics,
  PendingWorkout,
  PetState,
  RawMetrics,
  Stat,
  StatKind,
  StepItem,
  StepKind,
  StepStatus,
  stepKindQuitLabel,
  WorkoutKind
} from '../models/PetModels';
import {
  computeEnergy as deriveEnergy,
  computeMood as deriveMood,
  computeVitality as deriveVitality,
  derivePetState as deriveStateFromStats,
  deriveStats
} from '../models/PetDerivation';
import { computeDecayCatchup, shouldResetForNewDay } from '../models/PetLifecycle';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HealthEvent, HealthEventType } from '../models/HealthModels';
import { DailySnapshotStore } from '../services/DailySnapshotStore';
import { PetIdentityStore } from '../services/PetIdentityStore';
import { greeting, dateLabel, makeId, relativeTimeLabel, startOfDayMs } from '../utils/DateUtils';

const APP_STATE_STORE = 'lifepet_app_state';

@Observed
export class PetStateStore {
  identity: PetIdentityStore = new PetIdentityStore();
  snapshots: DailySnapshotStore = new DailySnapshotStore();

  stats: Stat[] = PetStateStore.demoStats();
  state: PetState = PetState.Excited;
  steps: StepItem[] = [];
  demoMode: boolean = false;
  healthConnected: boolean = false;
  toast: string = '';
  pendingWorkout?: PendingWorkout;
  feedToken: number = 0;
  lastDeltaToken: number = 0;
  lastWorkoutEndedAt?: number;
  onboardingDone: boolean = false;
  hatched: boolean = false;

  private raw: RawMetrics = { ...emptyRawMetrics };
  private hasIngestedAny: boolean = false;
  private quitCounts: Map<StepKind, number> = new Map<StepKind, number>();
  private lastInteractionAt: Map<StepKind, number> = new Map<StepKind, number>();
  private decayPending: Map<StatKind, number> = new Map<StatKind, number>();
  private lastSeenDate: number = startOfDayMs();
  private lastDecayAt: number = Date.now();
  private context?: common.UIAbilityContext;
  private restored: boolean = false;
  private toastToken: number = 0;
  private burstTimerId: number = -1;

  get ownerName(): string {
    return this.identity.ownerName;
  }

  get petName(): string {
    return this.identity.petName;
  }

  get dayCount(): number {
    return this.identity.dayCount;
  }

  get greetingText(): string {
    return greeting();
  }

  get dateText(): string {
    return dateLabel();
  }

  async bootstrap(context: common.UIAbilityContext): Promise<void> {
    if (this.restored) {
      return;
    }
    this.context = context;
    await this.identity.restore(context);
    await this.snapshots.restore(context);
    const pref = await preferences.getPreferences(context, APP_STATE_STORE);
    this.onboardingDone = Boolean(await pref.get('onboardingDone', this.onboardingDone));
    this.hatched = Boolean(await pref.get('hatched', this.hatched));
    this.demoMode = Boolean(await pref.get('demoMode', this.demoMode));
    this.healthConnected = Boolean(await pref.get('healthConnected', this.healthConnected));
    this.lastSeenDate = Number(await pref.get('lastSeenDate', this.lastSeenDate));
    this.lastDecayAt = Number(await pref.get('lastDecayAt', this.lastDecayAt));
    const pendingRaw = String(await pref.get('pendingWorkout', ''));
    let shouldClearPendingWorkout = false;
    if (pendingRaw.length > 0) {
      try {
        const restoredPending = JSON.parse(pendingRaw) as PendingWorkout;
        const now = Date.now();
        const age = now - restoredPending.endedAt;
        const sameDay = startOfDayMs(restoredPending.endedAt) === startOfDayMs(now);
        if (age <= 60 * 60 * 1000 && sameDay) {
          this.pendingWorkout = restoredPending;
        } else {
          this.pendingWorkout = undefined;
          shouldClearPendingWorkout = true;
        }
      } catch (e) {
        this.pendingWorkout = undefined;
        shouldClearPendingWorkout = true;
      }
    }
    if (shouldClearPendingWorkout) {
      await pref.put('pendingWorkout', '');
      await pref.flush();
    }
    if (this.demoMode) {
      this.identity.seedDemoBirth();
      this.stats = PetStateStore.demoStats();
      this.steps = PetStateStore.demoSteps();
      this.state = PetState.Excited;
    } else {
      this.refreshBaseline();
    }
    this.restored = true;
    this.checkDayRollover();
    this.applyDecayCatchup();
  }

  async persist(): Promise<void> {
    if (!this.context) {
      return;
    }
    await this.identity.persist(this.context);
    const pref = await preferences.getPreferences(this.context, APP_STATE_STORE);
    await pref.put('onboardingDone', this.onboardingDone);
    await pref.put('hatched', this.hatched);
    await pref.put('demoMode', this.demoMode);
    await pref.put('healthConnected', this.healthConnected);
    await pref.put('lastSeenDate', this.lastSeenDate);
    await pref.put('lastDecayAt', this.lastDecayAt);
    await pref.put('pendingWorkout', this.pendingWorkout ? JSON.stringify(this.pendingWorkout) : '');
    await pref.flush();
  }

  markHatched(): void {
    this.hatched = true;
    this.persistSoon();
  }

  continueWithDemo(): void {
    this.demoMode = true;
    this.healthConnected = false;
    this.onboardingDone = true;
    this.identity.seedDemoBirth();
    this.stats = PetStateStore.demoStats();
    this.steps = PetStateStore.demoSteps();
    this.state = PetState.Excited;
    this.persistSoon();
  }

  continueLater(): void {
    this.onboardingDone = true;
    this.demoMode = false;
    this.healthConnected = false;
    this.stats = PetStateStore.demoStats();
    this.steps = [];
    this.persistSoon();
  }

  notify(message: string): void {
    this.showToast(message);
  }

  reset(): void {
    this.recordSnapshot();
    this.raw = { ...emptyRawMetrics };
    this.hasIngestedAny = false;
    this.quitCounts.clear();
    this.lastInteractionAt.clear();
    this.decayPending.clear();
    this.stats = PetStateStore.demoStats();
    this.state = PetState.Excited;
    this.steps = [];
    this.demoMode = false;
    this.healthConnected = false;
    this.toast = '';
    this.pendingWorkout = undefined;
    this.feedToken = 0;
    this.clearBurstTimer();
    this.lastDeltaToken = 0;
    this.lastWorkoutEndedAt = undefined;
    this.onboardingDone = false;
    this.hatched = false;
    this.identity.resetToFreshPet();
    this.lastSeenDate = startOfDayMs();
    this.lastDecayAt = Date.now();
    this.refreshBaseline();
    this.persistSoon();
  }

  checkDayRollover(): void {
    const today = startOfDayMs();
    if (!shouldResetForNewDay(this.lastSeenDate, today)) {
      return;
    }
    if (this.demoMode) {
      this.identity.seedDemoBirth();
      this.lastSeenDate = today;
      this.persistSoon();
      return;
    }
    this.recordSnapshot(this.lastSeenDate);
    this.raw = { ...emptyRawMetrics };
    this.hasIngestedAny = false;
    this.steps = [];
    this.quitCounts.clear();
    this.lastInteractionAt.clear();
    this.decayPending.clear();
    this.pendingWorkout = undefined;
    this.lastWorkoutEndedAt = undefined;
    this.toast = '';
    this.clearBurstTimer();
    this.lastDeltaToken = 0;
    this.lastSeenDate = today;
    this.lastDecayAt = Date.now();
    this.refreshBaseline();
    this.persistSoon();
  }

  applyDecayCatchup(): void {
    if (this.demoMode) {
      return;
    }
    const catchup = computeDecayCatchup(this.lastDecayAt);
    if (catchup.ticks === 0) {
      return;
    }
    this.addDecay(StatKind.Vitality, catchup.vitalityDecay);
    this.addDecay(StatKind.Mood, catchup.moodDecay);
    this.addDecay(StatKind.Energy, catchup.energyDecay);
    this.lastDecayAt = catchup.nextLastDecayAt;
    this.persistSoon();
    if (this.hasIngestedAny) {
      this.recompute();
    }
  }

  ingest(event: HealthEvent): void {
    if (this.demoMode) {
      return;
    }
    switch (event.type) {
      case HealthEventType.Steps:
        this.raw.steps = event.value ?? 0;
        break;
      case HealthEventType.ExerciseMinutes:
        this.raw.exerciseMinutes = event.value ?? 0;
        break;
      case HealthEventType.ActiveEnergy:
        this.raw.activeEnergy = event.value ?? 0;
        break;
      case HealthEventType.StandMinutes:
        this.raw.standMinutes = event.value ?? 0;
        break;
      case HealthEventType.HeartRate:
        this.raw.heartRate = event.value ?? 0;
        break;
      case HealthEventType.Hrv:
        this.raw.hrv = event.value ?? 0;
        break;
      case HealthEventType.RestingHR:
        this.raw.restingHR = event.value ?? 0;
        break;
      case HealthEventType.Sleep:
        this.raw.sleepTotal = event.total ?? 0;
        this.raw.sleepDeep = event.deep ?? 0;
        this.raw.sleepREM = event.rem ?? 0;
        this.raw.sleepStart = event.start;
        break;
      case HealthEventType.MindfulMinutes:
        this.raw.mindfulMinutes = event.value ?? 0;
        break;
      case HealthEventType.WorkoutFinished:
        this.handleNewWorkout(event.kind ?? WorkoutKind.Other, event.duration ?? 0, event.end ?? Date.now(), event.kcal);
        return;
      default:
        break;
    }
    this.hasIngestedAny = true;
    this.recompute();
    if (event.type === HealthEventType.Sleep) {
      this.upsertSleepCard();
    }
  }

  markDone(id: string): void {
    const index = this.steps.findIndex((item: StepItem) => item.id === id);
    if (index < 0 || this.steps[index].status !== StepStatus.Suggest) {
      return;
    }
    const item = this.steps[index];
    this.steps[index] = { ...item, status: StepStatus.Done, time: '刚刚' };
    this.applyGain(item.affects, item.gain);
    this.showToast(`完成！+${item.gain} 已到账`);
    this.lastInteractionAt.set(item.kind, Date.now());
    this.regenerateSuggestions();
    this.persistSoon();
  }

  quit(id: string): void {
    const index = this.steps.findIndex((item: StepItem) => item.id === id);
    if (index < 0 || this.steps[index].status !== StepStatus.Suggest) {
      return;
    }
    const kind = this.steps[index].kind;
    this.steps.splice(index, 1);
    const count = (this.quitCounts.get(kind) ?? 0) + 1;
    this.quitCounts.set(kind, count);
    this.lastInteractionAt.set(kind, Date.now());
    const label = stepKindQuitLabel(kind);
    this.showToast(count >= 3 ? `📍 ${label} 已被 quit ${count} 次，偏好已更新` : `已跳过 · 下次少推${label}`);
    this.regenerateSuggestions();
    this.persistSoon();
  }

  consumePendingWorkout(): void {
    if (!this.pendingWorkout) {
      return;
    }
    const pw = this.pendingWorkout;
    this.pendingWorkout = undefined;
    this.insertDoneCard(pw, '刚刚');
    this.applyGain(StatKind.Vitality, pw.gainVitality);
    this.showToast(`${this.petName} 吃饱了！+${pw.gainVitality} 体力`);
    this.feedToken = Date.now();
    this.persistSoon();
  }

  dismissPendingWorkout(): void {
    if (!this.pendingWorkout) {
      return;
    }
    const pw = this.pendingWorkout;
    this.pendingWorkout = undefined;
    this.insertDoneCard(pw, '刚刚');
    this.applyGain(StatKind.Vitality, pw.gainVitality);
    this.persistSoon();
  }

  debugDecrement(kind: StatKind): void {
    this.applyGain(kind, -5);
    if (!this.demoMode) {
      this.addDecay(kind, 5);
    }
    this.persistSoon();
  }

  private recompute(): void {
    if (!this.hasIngestedAny) {
      return;
    }
    const oldVitality = this.statValue(StatKind.Vitality);
    const oldEnergy = this.statValue(StatKind.Energy);
    const oldMood = this.statValue(StatKind.Mood);
    this.stats = deriveStats(this.raw, {
      vitality: this.decayPending.get(StatKind.Vitality) ?? 0,
      energy: this.decayPending.get(StatKind.Energy) ?? 0,
      mood: this.decayPending.get(StatKind.Mood) ?? 0
    });
    const vitality = this.statValue(StatKind.Vitality);
    const energy = this.statValue(StatKind.Energy);
    const mood = this.statValue(StatKind.Mood);
    if (oldVitality !== vitality || oldEnergy !== energy || oldMood !== mood) {
      this.triggerBurst();
    }
    this.state = this.derivePetState(vitality, energy, mood);
    this.regenerateSuggestions();
    this.recordSnapshot();
  }

  private computeVitality(): number {
    return deriveVitality(this.raw);
  }

  private computeEnergy(): number {
    return deriveEnergy(this.raw);
  }

  private computeMood(): number {
    return deriveMood(this.raw);
  }

  private derivePetState(vitality: number, energy: number, mood: number): PetState {
    return deriveStateFromStats(vitality, energy, mood);
  }

  private handleNewWorkout(kind: WorkoutKind, duration: number, end: number, kcal?: number): void {
    const durMin = Math.max(1, Math.floor(duration / 60));
    const gain = Math.min(60, durMin);
    const label = this.workoutLabel(kind);
    this.lastWorkoutEndedAt = this.lastWorkoutEndedAt ? Math.max(this.lastWorkoutEndedAt, end) : end;
    this.steps = this.steps.filter((item: StepItem) => !(item.status === StepStatus.Suggest && this.stepKindForWorkout(kind) === item.kind));
    const fresh = Date.now() - end < 5 * 60000;
    if (fresh) {
      if (this.pendingWorkout) {
        this.dismissPendingWorkout();
      }
      this.pendingWorkout = {
        id: makeId('pending'),
        kind,
        label,
        durationMin: durMin,
        kcal,
        endedAt: end,
        gainVitality: gain
      };
      this.persistSoon();
      return;
    }
    this.insertDoneCard({
      id: makeId('workout'),
      kind,
      label,
      durationMin: durMin,
      kcal,
      endedAt: end,
      gainVitality: gain
    }, relativeTimeLabel(end));
  }

  private insertDoneCard(pw: PendingWorkout, time: string): void {
    const item: StepItem = {
      id: makeId('step'),
      status: StepStatus.Done,
      kind: this.stepKindForWorkout(pw.kind) ?? StepKind.Run,
      actionLabel: pw.label,
      titleValue: `${pw.durationMin} 分钟`,
      affects: StatKind.Vitality,
      gain: pw.gainVitality,
      time,
      fromAutoSensor: true
    };
    this.steps = [item, ...this.steps];
  }

  private upsertSleepCard(): void {
    if (this.raw.sleepTotal < 30 * 60) {
      this.steps = this.steps.filter((item: StepItem) => !(item.kind === StepKind.Sleep && item.fromAutoSensor));
      return;
    }
    const title = this.sleepDurationLabel(this.raw.sleepTotal);
    const time = this.raw.sleepStart ? relativeTimeLabel(this.raw.sleepStart) : '';
    const gain = this.computeEnergy();
    const found = this.steps.findIndex((item: StepItem) => item.kind === StepKind.Sleep && item.fromAutoSensor);
    const card: StepItem = {
      id: found >= 0 ? this.steps[found].id : makeId('sleep'),
      status: StepStatus.Done,
      kind: StepKind.Sleep,
      actionLabel: '入睡',
      titleValue: title,
      affects: StatKind.Energy,
      gain,
      time,
      fromAutoSensor: true
    };
    if (found >= 0) {
      this.steps[found] = card;
    } else {
      this.steps = [card, ...this.steps];
    }
  }

  private regenerateSuggestions(): void {
    if (this.demoMode || !this.hasIngestedAny) {
      return;
    }
    const maxSuggestions = 2;
    const cooldown = 2 * 3600000;
    const now = Date.now();
    const candidates: StepItem[] = [];
    const waking = new Date().getHours() >= 6 && new Date().getHours() < 22;

    if (this.raw.steps < 8000 && this.statValue(StatKind.Vitality) < 85 && waking && this.isAllowed(StepKind.Walk, now, cooldown)) {
      const needed = Math.max(500, Math.min(2000, 8000 - this.raw.steps));
      const deficit = Math.ceil(needed / 500) * 500;
      candidates.push(this.suggest(StepKind.Walk, '再走', `${deficit} 步`, StatKind.Vitality, Math.max(2, Math.floor(deficit / 1000) * 4)));
    }
    if (this.raw.exerciseMinutes < 20 && this.statValue(StatKind.Vitality) < 75 && waking && this.isAllowed(StepKind.Run, now, cooldown)) {
      candidates.push(this.suggest(StepKind.Run, '去跑', '20 分钟', StatKind.Vitality, 20));
    }
    if (this.raw.mindfulMinutes < 5 && this.statValue(StatKind.Mood) < 85 && this.isAllowed(StepKind.Meditate, now, cooldown)) {
      candidates.push(this.suggest(StepKind.Meditate, '冥想', '5 分钟', StatKind.Mood, 15));
    }
    if (this.statValue(StatKind.Mood) < 65 && this.isAllowed(StepKind.Breath, now, cooldown)) {
      candidates.push(this.suggest(StepKind.Breath, '深呼吸', '3 次', StatKind.Mood, 9));
    }

    candidates.sort((a: StepItem, b: StepItem) => this.statValue(a.affects) - this.statValue(b.affects));
    const wanted = candidates.slice(0, maxSuggestions);
    const wantedKinds = wanted.map((item: StepItem) => item.kind);
    this.steps = this.steps.filter((item: StepItem) => item.status === StepStatus.Done || wantedKinds.includes(item.kind));
    wanted.forEach((candidate: StepItem) => {
      if (!this.steps.some((item: StepItem) => item.status === StepStatus.Suggest && item.kind === candidate.kind)) {
        this.steps.push(candidate);
      }
    });
  }

  private suggest(kind: StepKind, actionLabel: string, titleValue: string, affects: StatKind, gain: number): StepItem {
    return {
      id: makeId('suggest'),
      status: StepStatus.Suggest,
      kind,
      actionLabel,
      titleValue,
      affects,
      gain,
      time: '',
      fromAutoSensor: false
    };
  }

  private isAllowed(kind: StepKind, now: number, cooldown: number): boolean {
    if ((this.quitCounts.get(kind) ?? 0) >= 3) {
      return false;
    }
    const last = this.lastInteractionAt.get(kind);
    return last === undefined || now - last >= cooldown;
  }

  private applyGain(kind: StatKind, gain: number): void {
    let changed = false;
    const updated = this.stats.map((item: Stat) => {
      if (item.kind !== kind) {
        return item;
      }
      const next = this.clamp(item.value + gain);
      if (next !== item.value) {
        changed = true;
      }
      return { kind: item.kind, value: next };
    });
    if (!changed) {
      return;
    }
    this.stats = updated;
    this.state = this.derivePetState(
      this.statValueFrom(updated, StatKind.Vitality),
      this.statValueFrom(updated, StatKind.Energy),
      this.statValueFrom(updated, StatKind.Mood)
    );
    this.triggerBurst();
    this.recordSnapshot();
  }

  private refreshBaseline(): void {
    if (this.demoMode) {
      return;
    }
    const today = startOfDayMs();
    const entries = this.snapshots.recent(this.identity.currentPetId, 8);
    const priorHRVs = entries
      .filter((item) => startOfDayMs(item.date) < today && item.hrv > 0)
      .map((item) => item.hrv);
    const baseline = priorHRVs.length >= 3
      ? priorHRVs.reduce((sum: number, value: number) => sum + value, 0) / priorHRVs.length
      : undefined;
    this.raw.hrvBaseline = baseline;
    if (this.hasIngestedAny) {
      this.recompute();
    }
  }

  private recordSnapshot(date: number = startOfDayMs()): void {
    if (!this.context || this.demoMode || !this.hasIngestedAny) {
      return;
    }
    this.snapshots.write(this.context, {
      petId: this.identity.currentPetId,
      date: startOfDayMs(date),
      vitality: this.statValue(StatKind.Vitality),
      energy: this.statValue(StatKind.Energy),
      mood: this.statValue(StatKind.Mood),
      stateTag: this.state,
      steps: this.raw.steps,
      exerciseMinutes: this.raw.exerciseMinutes,
      activeEnergy: this.raw.activeEnergy,
      standMinutes: this.raw.standMinutes,
      hrv: this.raw.hrv,
      restingHR: this.raw.restingHR,
      sleepTotal: this.raw.sleepTotal,
      sleepDeep: this.raw.sleepDeep,
      sleepREM: this.raw.sleepREM,
      mindfulMinutes: this.raw.mindfulMinutes,
      completedStepKinds: this.steps
        .filter((item: StepItem) => item.status === StepStatus.Done)
        .map((item: StepItem) => item.kind as string),
      updatedAt: Date.now()
    });
  }

  private addDecay(kind: StatKind, amount: number): void {
    this.decayPending.set(kind, (this.decayPending.get(kind) ?? 0) + amount);
  }

  private statValue(kind: StatKind): number {
    return this.statValueFrom(this.stats, kind);
  }

  private statValueFrom(stats: Stat[], kind: StatKind): number {
    const found = stats.find((item: Stat) => item.kind === kind);
    return found ? found.value : 50;
  }

  private clamp(value: number): number {
    return Math.min(100, Math.max(0, value));
  }

  private stepKindForWorkout(kind: WorkoutKind): StepKind | undefined {
    if (kind === WorkoutKind.Run) {
      return StepKind.Run;
    }
    if (kind === WorkoutKind.Walk) {
      return StepKind.Walk;
    }
    return undefined;
  }

  private workoutLabel(kind: WorkoutKind): string {
    switch (kind) {
      case WorkoutKind.Run:
        return '跑步';
      case WorkoutKind.Walk:
        return '走路';
      case WorkoutKind.Cycle:
        return '骑行';
      case WorkoutKind.Hiit:
        return '高强度训练';
      case WorkoutKind.Yoga:
        return '瑜伽';
      default:
        return '运动';
    }
  }

  private sleepDurationLabel(seconds: number): string {
    const totalMin = Math.floor(seconds / 60);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    if (h === 0) {
      return `${m} 分`;
    }
    if (m === 0) {
      return `${h} 小时`;
    }
    return `${h} 小时 ${m} 分`;
  }

  private showToast(message: string): void {
    this.toast = message;
    const token = Date.now();
    this.toastToken = token;
    setTimeout(() => {
      if (this.toastToken === token) {
        this.toast = '';
      }
    }, 2000);
  }

  private triggerBurst(): void {
    const token = Date.now();
    this.lastDeltaToken = token;
    this.clearBurstTimer();
    this.burstTimerId = setTimeout(() => {
      if (this.lastDeltaToken === token) {
        this.lastDeltaToken = 0;
      }
      this.burstTimerId = -1;
    }, 1600);
  }

  private clearBurstTimer(): void {
    if (this.burstTimerId >= 0) {
      clearTimeout(this.burstTimerId);
      this.burstTimerId = -1;
    }
  }

  private persistSoon(): void {
    void this.persist();
  }

  private static demoStats(): Stat[] {
    return [
      { kind: StatKind.Vitality, value: 88 },
      { kind: StatKind.Energy, value: 74 },
      { kind: StatKind.Mood, value: 82 }
    ];
  }

  private static demoSteps(): StepItem[] {
    return [
      { id: 'demo_run', status: StepStatus.Done, kind: StepKind.Run, actionLabel: '跑步', titleValue: '28 分钟', affects: StatKind.Vitality, gain: 32, time: '07:30', fromAutoSensor: true },
      { id: 'demo_sleep', status: StepStatus.Done, kind: StepKind.Sleep, actionLabel: '入睡', titleValue: '6 小时 12 分', affects: StatKind.Energy, gain: 24, time: '昨 23:30', fromAutoSensor: true },
      { id: 'demo_breath', status: StepStatus.Done, kind: StepKind.Breath, actionLabel: '深呼吸', titleValue: '3 次', affects: StatKind.Mood, gain: 9, time: '15:30', fromAutoSensor: false },
      { id: 'demo_walk', status: StepStatus.Suggest, kind: StepKind.Walk, actionLabel: '再走', titleValue: '1500 步', affects: StatKind.Vitality, gain: 6, time: '', fromAutoSensor: false },
      { id: 'demo_meditate', status: StepStatus.Suggest, kind: StepKind.Meditate, actionLabel: '冥想', titleValue: '5 分钟', affects: StatKind.Mood, gain: 15, time: '', fromAutoSensor: false }
    ];
  }
}
