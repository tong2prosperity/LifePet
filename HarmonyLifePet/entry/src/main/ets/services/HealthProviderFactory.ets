import {
  HealthDataProvider,
  HuaweiHealthDataService,
  MockHealthDataService
} from './HealthDataService';

export enum HealthProviderMode {
  Mock = 'mock',
  Huawei = 'huawei'
}

/// Switch this to `HealthProviderMode.Huawei` after AppGallery Connect service
/// access, Client ID, signing, and Health Service Kit scopes are configured.
export const ACTIVE_HEALTH_PROVIDER: HealthProviderMode = HealthProviderMode.Mock;

export function createHealthProvider(): HealthDataProvider {
  switch (ACTIVE_HEALTH_PROVIDER) {
    case HealthProviderMode.Huawei:
      return new HuaweiHealthDataService();
    case HealthProviderMode.Mock:
    default:
      return new MockHealthDataService();
  }
}
