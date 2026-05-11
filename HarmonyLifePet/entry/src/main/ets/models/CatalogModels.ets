import { PetSpriteName } from './PetSpriteModels';

export enum DeathType {
  Natural = 'natural',
  Chronic = 'chronic',
  Acute = 'acute',
  Starve = 'starve',
  Illness = 'illness'
}

export interface CatalogStats {
  vitality: number;
  energy: number;
  mood: number;
}

export interface CatalogSeries {
  vitality: number[];
  energy: number[];
  mood: number[];
}

export interface CatalogMoment {
  day: number;
  title: string;
  value?: string;
  isDeath: boolean;
}

export interface CatalogPet {
  id: string;
  name: string;
  sprite: PetSpriteName;
  isAlive: boolean;
  deathType?: DeathType;
  dates: string;
  days: number;
  totalDays: number;
  stats: CatalogStats;
  series: CatalogSeries;
  moments: CatalogMoment[];
  bio: string;
  memorialTitle?: string;
  memorialDuration?: string;
  isRare: boolean;
}

export const demoCatalogPets: CatalogPet[] = [
  {
    id: 'bean',
    name: 'BEAN',
    sprite: PetSpriteName.Bean,
    isAlive: true,
    dates: '4/19 → 今日',
    days: 7,
    totalDays: 7,
    stats: { vitality: 88, energy: 74, mood: 82 },
    series: {
      vitality: [45, 58, 70, 75, 82, 85, 88],
      energy: [65, 70, 68, 60, 74, 70, 74],
      mood: [70, 65, 75, 80, 78, 80, 82]
    },
    moments: [
      { day: 1, title: '破壳了，深呼吸 30 秒孵的', isDeath: false },
      { day: 3, title: '首次达到 EXCITED 状态', value: '体力 82', isDeath: false },
      { day: 5, title: '心情达今日峰值', value: 'HRV +28', isDeath: false },
      { day: 7, title: '今天，它还在陪着你', value: '状态良好', isDeath: false }
    ],
    bio: '它是四月中旬来的那只。你刚跑完步的时候它跳得最高，你工作开会的时候它就安静地守着。它还年轻，还在学你的节奏。',
    isRare: false
  },
  {
    id: 'blob',
    name: 'BLOB',
    sprite: PetSpriteName.Blob,
    isAlive: false,
    deathType: DeathType.Natural,
    dates: '3/29 → 4/18',
    days: 21,
    totalDays: 21,
    stats: { vitality: 71, energy: 65, mood: 74 },
    series: {
      vitality: [45, 52, 68, 75, 82, 88, 85, 78, 82, 90, 88, 75, 60, 45, 42, 50, 65, 72, 78, 75, 68],
      energy: [60, 55, 62, 70, 75, 80, 78, 72, 68, 70, 65, 58, 50, 45, 55, 65, 70, 72, 75, 70, 65],
      mood: [55, 62, 70, 75, 80, 85, 88, 82, 78, 82, 85, 75, 65, 40, 42, 58, 72, 80, 85, 82, 75]
    },
    moments: [
      { day: 3, title: '首次 EXCITED', value: '体力 75', isDeath: false },
      { day: 7, title: '三状态全 >80', value: '24h 持续', isDeath: false },
      { day: 10, title: '全生命期最巅峰', value: '综合 95', isDeath: false },
      { day: 14, title: 'SICK 突变', value: '心情 40 ↓', isDeath: false },
      { day: 18, title: '你开始冥想 → 好起来', value: '心情 85', isDeath: false },
      { day: 21, title: '圆满升天', isDeath: true }
    ],
    bio: '你送走了它。它最喜欢你早晨跑步那段——那是它最活跃的节奏。4/11 你压力很大的那天，它生病了；后来好起来，就在你第一次冥想的第二天。它活成了你那段时间的样子。',
    memorialTitle: '《纪念曲 · 圆满》',
    memorialDuration: '0:15',
    isRare: true
  },
  {
    id: 'noct',
    name: 'NOCT',
    sprite: PetSpriteName.Noct,
    isAlive: false,
    deathType: DeathType.Chronic,
    dates: '3/15 → 3/28',
    days: 14,
    totalDays: 14,
    stats: { vitality: 20, energy: 20, mood: 33 },
    series: {
      vitality: [50, 45, 38, 30, 25, 22, 18, 15, 12, 8, 5, 3, 2, 0],
      energy: [40, 35, 30, 28, 25, 22, 20, 18, 15, 12, 10, 8, 5, 3],
      mood: [55, 50, 45, 40, 38, 35, 32, 30, 28, 25, 22, 20, 18, 15]
    },
    moments: [
      { day: 1, title: '破壳', value: '状态 50', isDeath: false },
      { day: 4, title: '警告 · 4 天零运动', value: '体力 30 ↓', isDeath: false },
      { day: 8, title: '体力跌破 15', value: 'TIRED 常态', isDeath: false },
      { day: 11, title: '饱食度 0', value: '持续危险', isDeath: false },
      { day: 14, title: '慢性死 · 10 天零运动', value: '体力 0', isDeath: true }
    ],
    bio: 'NOCT 只活了 14 天。它从没见过早晨的太阳——你总在凌晨才睡，醒来直接坐到电脑前。它等了很久，你始终没动。慢慢地，它懒得再动。被你熬死的第 3 只。',
    memorialTitle: '《纪念曲 · 沉寂》',
    memorialDuration: '0:15',
    isRare: false
  },
  {
    id: 'hush',
    name: 'HUSH',
    sprite: PetSpriteName.Hush,
    isAlive: false,
    deathType: DeathType.Natural,
    dates: '2/15 → 3/7',
    days: 21,
    totalDays: 21,
    stats: { vitality: 61, energy: 79, mood: 71 },
    series: {
      vitality: [60, 62, 58, 60, 65, 62, 60, 58, 62, 65, 60, 62, 65, 60, 58, 62, 65, 62, 60, 58, 62],
      energy: [75, 78, 80, 75, 78, 80, 82, 80, 78, 80, 82, 78, 75, 78, 80, 82, 80, 78, 82, 80, 78],
      mood: [68, 70, 72, 70, 75, 72, 70, 68, 70, 72, 75, 72, 70, 68, 72, 75, 72, 70, 72, 70, 68]
    },
    moments: [
      { day: 1, title: '稳定开端', value: '状态 68', isDeath: false },
      { day: 8, title: '连续 5 天冥想 · 心情峰值', value: '心情 75', isDeath: false },
      { day: 15, title: '最长连续睡眠', value: '8h 12m', isDeath: false },
      { day: 21, title: '从未 SICK · 平静升天', isDeath: true }
    ],
    bio: 'HUSH 是最平静的那只——没有大起大落，也从未病过。它活出了稳定的样子：早睡、冥想、温和地运动。你那段时间正在休长假，它就顺着你的节奏慢慢过完了 21 天。',
    memorialTitle: '《纪念曲 · 静水》',
    memorialDuration: '0:15',
    isRare: false
  }
];
