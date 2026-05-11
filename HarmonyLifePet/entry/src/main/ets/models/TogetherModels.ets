import { PetSpriteName } from './PetSpriteModels';

export enum MessageSender {
  Me = 'me',
  Them = 'them'
}

export interface FriendHealth {
  steps: string;
  stepsShort: string;
  sleep: string;
  sleepShort: string;
  hr: string;
  cal: string;
  rest: string;
}

export interface TogetherMessage {
  id: string;
  who: MessageSender;
  text: string;
  time: string;
}

export interface Friend {
  id: string;
  displayName: string;
  petName: string;
  sprite: PetSpriteName;
  relation: string;
  daysTogether: number;
  myStatus: string;
  otherStatus: string;
  myHealth: FriendHealth;
  otherHealth: FriendHealth;
  messages: TogetherMessage[];
}

export interface PlazaMember {
  id: string;
  name: string;
  sprite: PetSpriteName;
  isMe: boolean;
}

export interface PlazaSnapshot {
  goalTitle: string;
  goalCurrent: number;
  goalTotal: number;
  onlineCount: number;
  myContribSteps: string;
  myRank: string;
  exerciseCount: string;
  members: PlazaMember[];
}

export function goalPercent(snapshot: PlazaSnapshot): number {
  if (snapshot.goalTotal <= 0) {
    return 0;
  }
  return Math.min(1, snapshot.goalCurrent / snapshot.goalTotal);
}

export const demoFriends: Friend[] = [
  {
    id: 'nova',
    displayName: '鱼',
    petName: 'NOVA',
    sprite: PetSpriteName.Blob,
    relation: '异地恋',
    daysTogether: 245,
    myStatus: '运动中',
    otherStatus: '刚睡下',
    myHealth: { steps: '8,432', stepsShort: '8.4k步', sleep: '6h 18m', sleepShort: '6h18眠', hr: '72', cal: '425', rest: '1h 30m' },
    otherHealth: { steps: '3,240', stepsShort: '3.2k步', sleep: '7h 42m', sleepShort: '7h42眠', hr: '68', cal: '312', rest: '2h 18m' },
    messages: [
      { id: 'nova-1', who: MessageSender.Them, text: '早安~ 今天慢跑加油 🏃', time: '昨日 22:10' },
      { id: 'nova-2', who: MessageSender.Me, text: '收到！晚上想你', time: '昨日 22:14' },
      { id: 'nova-3', who: MessageSender.Them, text: '我刚到家，洗漱睡了', time: '昨日 22:30' },
      { id: 'nova-4', who: MessageSender.Me, text: '今天跑了 5km 啦~', time: '今早 08:20' },
      { id: 'nova-5', who: MessageSender.Them, text: '太棒了 ✨', time: '5 分钟前' }
    ]
  },
  {
    id: 'mom',
    displayName: '妈妈',
    petName: 'BUTTON',
    sprite: PetSpriteName.Noct,
    relation: '家人',
    daysTogether: 89,
    myStatus: '在跑步',
    otherStatus: '在散步',
    myHealth: { steps: '8,432', stepsShort: '8.4k步', sleep: '6h 18m', sleepShort: '6h18眠', hr: '72', cal: '425', rest: '1h 30m' },
    otherHealth: { steps: '5,120', stepsShort: '5.1k步', sleep: '8h 02m', sleepShort: '8h02眠', hr: '64', cal: '210', rest: '3h 12m' },
    messages: [
      { id: 'mom-1', who: MessageSender.Them, text: '早起去公园走走啦', time: '07:00' },
      { id: 'mom-2', who: MessageSender.Them, text: '记得吃早饭 🥣', time: '07:32' },
      { id: 'mom-3', who: MessageSender.Me, text: '吃过啦！中午回家吃饭吗', time: '08:15' },
      { id: 'mom-4', who: MessageSender.Them, text: '中午不用啦，你忙', time: '09:14' }
    ]
  },
  {
    id: 'aj',
    displayName: '阿杰',
    petName: 'ZIP',
    sprite: PetSpriteName.Hush,
    relation: '挚友',
    daysTogether: 34,
    myStatus: '在跑步',
    otherStatus: '健身房',
    myHealth: { steps: '8,432', stepsShort: '8.4k步', sleep: '6h 18m', sleepShort: '6h18眠', hr: '72', cal: '425', rest: '1h 30m' },
    otherHealth: { steps: '12,420', stepsShort: '12k步', sleep: '6h 30m', sleepShort: '6h30眠', hr: '58', cal: '720', rest: '45m' },
    messages: [
      { id: 'aj-1', who: MessageSender.Me, text: '今晚一起练腿？', time: '昨日 18:00' },
      { id: 'aj-2', who: MessageSender.Them, text: '来！20 点见 💪', time: '昨日 18:05' },
      { id: 'aj-3', who: MessageSender.Them, text: '完成！明天继续', time: '昨日 23:00' }
    ]
  }
];

export const plazaSnapshot: PlazaSnapshot = {
  goalTitle: '全社区累计步行 1,000,000 步',
  goalCurrent: 624318,
  goalTotal: 1000000,
  onlineCount: 248,
  myContribSteps: '3,240',
  myRank: '#84',
  exerciseCount: '1,024',
  members: [
    { id: 'p1', name: '姈姈', sprite: PetSpriteName.Noct, isMe: false },
    { id: 'p2', name: '阿杰', sprite: PetSpriteName.Hush, isMe: false },
    { id: 'p3', name: '小丽', sprite: PetSpriteName.Blob, isMe: false },
    { id: 'p4', name: '老王', sprite: PetSpriteName.Bean, isMe: false },
    { id: 'p5', name: '泡泡', sprite: PetSpriteName.Blob, isMe: false },
    { id: 'p6', name: 'KAI', sprite: PetSpriteName.Hush, isMe: false },
    { id: 'p7', name: '兔妹', sprite: PetSpriteName.Noct, isMe: false },
    { id: 'p8', name: '阿仔', sprite: PetSpriteName.Blob, isMe: false },
    { id: 'p9', name: '小满', sprite: PetSpriteName.Bean, isMe: false },
    { id: 'p10', name: '橘子', sprite: PetSpriteName.Blob, isMe: false },
    { id: 'p11', name: '小七', sprite: PetSpriteName.Noct, isMe: false },
    { id: 'p12', name: '欢欢', sprite: PetSpriteName.Hush, isMe: false }
  ]
};
