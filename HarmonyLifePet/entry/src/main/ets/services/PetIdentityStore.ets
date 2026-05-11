import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { daysSinceBirth, startOfDayMs } from '../utils/DateUtils';

const STORE_NAME = 'lifepet_identity';

export class PetIdentityStore {
  currentPetId: string = '';
  petName: string = 'BEAN';
  ownerName: string = 'FISH';
  birthDate: number = startOfDayMs();

  constructor() {
    this.currentPetId = this.makePetId();
  }

  get dayCount(): number {
    return daysSinceBirth(this.birthDate);
  }

  async restore(context: common.UIAbilityContext): Promise<void> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    this.currentPetId = String(await pref.get('currentPetId', this.currentPetId));
    this.petName = String(await pref.get('petName', this.petName));
    this.ownerName = String(await pref.get('ownerName', this.ownerName));
    const restoredBirthDate = Number(await pref.get('birthDate', this.birthDate));
    this.birthDate = Number.isFinite(restoredBirthDate) && restoredBirthDate > 0
      ? startOfDayMs(restoredBirthDate)
      : startOfDayMs();
  }

  async persist(context: common.UIAbilityContext): Promise<void> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    await pref.put('currentPetId', this.currentPetId);
    await pref.put('petName', this.petName);
    await pref.put('ownerName', this.ownerName);
    await pref.put('birthDate', this.birthDate);
    await pref.flush();
  }

  resetToFreshPet(): void {
    this.currentPetId = this.makePetId();
    this.petName = 'BEAN';
    this.ownerName = 'FISH';
    this.birthDate = startOfDayMs();
  }

  seedDemoBirth(): void {
    this.birthDate = startOfDayMs() - 6 * 86400000;
  }

  private makePetId(): string {
    const bytes: number[] = [];
    for (let index = 0; index < 16; index++) {
      bytes.push(Math.floor(Math.random() * 256));
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = bytes.map((value: number) => value.toString(16).padStart(2, '0'));
    return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10, 16).join('')}`;
  }
}
