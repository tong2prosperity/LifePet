import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'LifePet', 'EntryAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'LifePet', `Failed to load content: ${err.code} ${err.message}`);
        return;
      }
      hilog.info(DOMAIN, 'LifePet', 'Index loaded');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'LifePet', 'EntryAbility onDestroy');
  }
}
