import { CatalogPage } from './CatalogPage';
import { HomePage } from './HomePage';
import { OnboardingPage } from './OnboardingPage';
import { TogetherPage } from './TogetherPage';
import { WorkoutSheet } from '../components/WorkoutSheet';
import { HealthAuthState, HealthDataProvider } from '../services/HealthDataService';
import { createHealthProvider } from '../services/HealthProviderFactory';
import { PetStateStore } from '../stores/PetStateStore';
import { LPColor } from '../theme/LPTheme';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @State store: PetStateStore = new PetStateStore();
  @State currentTab: number = 0;
  @State restored: boolean = false;
  @State healthAuthState: HealthAuthState = HealthAuthState.Unknown;
  private health: HealthDataProvider = createHealthProvider();
  private foregroundTimerId: number = -1;
  private refreshing: boolean = false;

  aboutToAppear(): void {
    this.startForegroundRefreshTimer();
    void this.restoreAndReconcile();
  }

  aboutToDisappear(): void {
    this.clearForegroundRefreshTimer();
  }

  onPageShow(): void {
    void this.foregroundRefresh();
  }

  private startForegroundRefreshTimer(): void {
    if (this.foregroundTimerId >= 0) {
      return;
    }
    this.foregroundTimerId = setInterval(() => {
      void this.foregroundRefresh();
    }, 60000);
  }

  private clearForegroundRefreshTimer(): void {
    if (this.foregroundTimerId >= 0) {
      clearInterval(this.foregroundTimerId);
      this.foregroundTimerId = -1;
    }
  }

  private async restoreAndReconcile(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.store.bootstrap(context);
    this.healthAuthState = this.health.authState;
    if (this.store.onboardingDone && this.store.healthConnected && !this.store.demoMode && this.store.steps.length === 0) {
      const events = await this.health.reconcile();
      events.forEach((event) => this.store.ingest(event));
      await this.store.persist();
    }
    this.restored = true;
  }

  private async foregroundRefresh(): Promise<void> {
    if (this.refreshing || !this.restored || !this.store.onboardingDone) {
      return;
    }
    this.refreshing = true;
    try {
      this.store.checkDayRollover();
      this.store.applyDecayCatchup();
      if (this.store.healthConnected && !this.store.demoMode && this.health.authState === HealthAuthState.Granted) {
        const events = await this.health.reconcile();
        events.forEach((event) => this.store.ingest(event));
        await this.store.persist();
      }
    } finally {
      this.refreshing = false;
    }
  }

  async connectHealth(): Promise<void> {
    this.healthAuthState = HealthAuthState.Requesting;
    const auth = await this.health.requestAuthorization();
    this.healthAuthState = auth;
    if (auth === HealthAuthState.Granted) {
      this.store.onboardingDone = true;
      this.store.demoMode = false;
      this.store.healthConnected = true;
      const events = await this.health.reconcile();
      events.forEach((event) => this.store.ingest(event));
      await this.store.persist();
    } else if (auth === HealthAuthState.PlatformApprovalRequired) {
      this.store.continueLater();
      this.store.notify('Health Service Kit 需要开发者平台审批后才能读取真实数据');
    } else if (auth === HealthAuthState.Denied) {
      this.store.continueLater();
      this.store.notify('用户未授权健康数据，已进入稍后连接模式');
    } else {
      this.store.continueLater();
      this.store.notify('健康数据暂不可用，已进入稍后连接模式');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.restored) {
        Column({ space: 14 }) {
          Text('LIFEPET')
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(LPColor.coral)
            .letterSpacing(2)
          LoadingProgress()
            .width(24)
            .height(24)
            .color(LPColor.coral)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (!this.store.onboardingDone) {
        OnboardingPage({
          store: this.store,
          authState: this.healthAuthState,
          onConnect: () => {
            void this.connectHealth();
          },
          onDemo: () => this.store.continueWithDemo(),
          onLater: () => this.store.continueLater()
        })
      } else {
        Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
          TabContent() {
            HomePage({ store: this.store })
          }
          .tabBar('⌂ 主页')

          TabContent() {
            CatalogPage({ store: this.store })
          }
          .tabBar('▦ 图鉴')

          TabContent() {
            TogetherPage({ store: this.store })
          }
          .tabBar('👥 一起')
        }
        .barBackgroundColor(LPColor.paperCard)
        .selectedIndex(this.currentTab)
        .onChange((index: number) => {
          this.currentTab = index;
        })
      }

      if (this.store.hatched && this.store.pendingWorkout) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#73000000')
          .onClick(() => this.store.dismissPendingWorkout())

        WorkoutSheet({
          workout: this.store.pendingWorkout ?? null,
          petName: this.store.petName,
          onFeed: () => this.store.consumePendingWorkout(),
          onDismiss: () => this.store.dismissPendingWorkout()
        })
      }

      if (this.store.toast.length > 0) {
        Text(this.store.toast)
          .fontSize(14)
          .fontColor(LPColor.paperCard)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(LPColor.ink)
          .border({ width: 1.5, color: LPColor.ink })
          .borderRadius(999)
          .shadow({ radius: 3, color: '#14000000', offsetX: 0, offsetY: 2 })
          .margin({ bottom: 74 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LPColor.paper)
  }
}
