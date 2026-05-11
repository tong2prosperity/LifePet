import { DashedRule } from '../components/DashedRule';
import { PixelPetSprite } from '../components/PixelPetSprite';
import {
  Friend,
  FriendHealth,
  MessageSender,
  TogetherMessage,
  demoFriends,
  plazaSnapshot
} from '../models/TogetherModels';
import { PetSpriteName } from '../models/PetSpriteModels';
import { PetStateStore } from '../stores/PetStateStore';
import { ShareActionResult, ShareActionService } from '../services/ShareActionService';
import { LPColor } from '../theme/LPTheme';
import { common } from '@kit.AbilityKit';

const DEFAULT_FRIEND: Friend = demoFriends[0];

@Component
export struct TogetherPage {
  @ObjectLink store: PetStateStore;
  @State section: number = 0;
  @State route: string = 'root';
  @State selectedFriendId: string = '';

  private selectedFriend(): Friend {
    const found = demoFriends.find((friend: Friend) => friend.id === this.selectedFriendId);
    return found ? found : DEFAULT_FRIEND;
  }

  build() {
    if (this.route === 'friend') {
      FriendDetailPane({
        store: this.store,
        friend: this.selectedFriend(),
        onBack: () => {
          this.route = 'root';
        }
      })
    } else if (this.route === 'invite') {
      InvitePane({
        onBack: () => {
          this.route = 'root';
        }
      })
    } else {
      Column() {
        Row() {
          TogetherTabButton({
            label: '朋友',
            active: this.section === 0,
            onTap: () => this.section = 0
          })
          TogetherTabButton({
            label: '广场',
            active: this.section === 1,
            onTap: () => this.section = 1
          })
        }
        .width('100%')

        Column()
          .width('100%')
          .height(1.5)
          .backgroundColor(LPColor.ink)

        if (this.section === 0) {
          FriendsPane({
            onFriend: (id: string) => {
              this.selectedFriendId = id;
              this.route = 'friend';
            },
            onInvite: () => {
              this.route = 'invite';
            }
          })
        } else {
          PlazaPane({ store: this.store })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(LPColor.paper)
    }
  }
}

@Component
struct TogetherTabButton {
  @Prop label: string = '';
  @Prop active: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Blank()
      Text(this.label)
        .fontSize(17)
        .fontWeight(this.active ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.active ? LPColor.ink : LPColor.muted)
      Column()
        .width(30)
        .height(3)
        .backgroundColor(this.active ? LPColor.coral : Color.Transparent)
        .borderRadius(2)
    }
    .layoutWeight(1)
    .height(42)
    .onClick(() => this.onTap())
  }
}

@Component
struct FriendsPane {
  onFriend: (id: string) => void = () => {};
  onInvite: () => void = () => {};

  private pairStarts(): number[] {
    const out: number[] = [];
    for (let i = 0; i < demoFriends.length; i += 2) {
      out.push(i);
    }
    return out;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Row({ space: 0 }) {
            Text('身边的朋友')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.ink)
            Text('.')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.coral)
          }
          Blank()
          AddFriendButton({
            onTap: () => this.onInvite()
          })
        }
        .width('100%')

        ForEach(this.pairStarts(), (start: number) => {
          Row({ space: 10 }) {
            FriendGridCard({
              friend: demoFriends[start],
              onOpen: () => this.onFriend(demoFriends[start].id)
            })
            .layoutWeight(1)
            if (start + 1 < demoFriends.length) {
              FriendGridCard({
                friend: demoFriends[start + 1],
                onOpen: () => this.onFriend(demoFriends[start + 1].id)
              })
              .layoutWeight(1)
            } else {
              Blank()
                .layoutWeight(1)
            }
          }
          .width('100%')
        }, (start: number) => start.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 34 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct FriendGridCard {
  @Prop friend: Friend = DEFAULT_FRIEND;
  onOpen: () => void = () => {};

  private hasNew(): boolean {
    const last = this.friend.messages[this.friend.messages.length - 1];
    return last ? last.who === MessageSender.Them : false;
  }

  build() {
    Stack() {
      Column({ space: 6 }) {
        Column({ space: 4 }) {
          PixelPetSprite({ sprite: this.friend.sprite, size: 52 })
          Text(this.friend.petName)
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(LPColor.lcdInk)
            .letterSpacing(0.5)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(LPColor.lcd)
        .border({ width: 1, color: LPColor.lcdDash, style: BorderStyle.Dashed })
        .borderRadius(8)

        Text(this.friend.displayName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(LPColor.ink)
        Text(`已陪伴 ${this.friend.daysTogether} 天`)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(LPColor.muted)
        Text(this.friend.otherStatus)
          .fontSize(8)
          .fontFamily('monospace')
          .fontColor(LPColor.coral)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('#D14B3D14')
          .borderRadius(8)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 12, bottom: 10 })
      .backgroundColor(LPColor.paperCard)
      .border({ width: 1.5, color: LPColor.ink })
      .borderRadius(12)
      .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })

      if (this.hasNew()) {
        Column()
          .width(8)
          .height(8)
          .backgroundColor(LPColor.coral)
          .border({ width: 2, color: LPColor.paperCard })
          .borderRadius(4)
          .position({ x: '88%', y: 10 })
      }
    }
    .width('100%')
    .onClick(() => this.onOpen())
  }
}

@Component
struct AddFriendButton {
  onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height(32)
        .backgroundColor(LPColor.ink)
        .borderRadius(8)
        .translate({ x: 2, y: 2 })
      Column()
        .width('100%')
        .height(32)
        .backgroundColor(LPColor.ink)
        .borderRadius(8)
      Text('+ 添加')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(LPColor.paperCard)
    }
    .width(64)
    .height(34)
    .margin({ right: 2, bottom: 2 })
    .onClick(() => this.onTap())
  }
}

@Component
struct FriendDetailPane {
  @ObjectLink store: PetStateStore;
  @Prop friend: Friend = DEFAULT_FRIEND;
  @State draft: string = '';
  @State localMessages: TogetherMessage[] = [];
  @State toast: string = '';
  @State pokeNonce: number = 0;
  @State cheerNonce: number = 0;
  onBack: () => void = () => {};
  private toastTimerId: number = -1;
  private messageScroller: Scroller = new Scroller();

  aboutToDisappear(): void {
    this.clearToastTimer();
  }

  private allMessages(): TogetherMessage[] {
    return this.friend.messages.concat(this.localMessages);
  }

  private showToast(text: string): void {
    this.toast = text;
    this.clearToastTimer();
    this.toastTimerId = setTimeout(() => {
      if (this.toast === text) {
        this.toast = '';
      }
      this.toastTimerId = -1;
    }, 1600);
  }

  private clearToastTimer(): void {
    if (this.toastTimerId >= 0) {
      clearTimeout(this.toastTimerId);
      this.toastTimerId = -1;
    }
  }

  private sendText(text: string): void {
    const value = text.trim();
    if (value.length === 0) {
      return;
    }
    this.localMessages = this.localMessages.concat([{
      id: `local-${Date.now()}`,
      who: MessageSender.Me,
      text: value,
      time: '刚刚'
    }]);
    this.draft = '';
    this.scrollMessagesToBottom();
    this.showToast(`已送达 ${this.friend.petName}`);
  }

  private scrollMessagesToBottom(): void {
    setTimeout(() => {
      this.messageScroller.scrollEdge(Edge.Bottom);
    }, 0);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Row({ space: 4 }) {
              Text('‹')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.coral)
              Text('返回')
                .fontSize(16)
                .fontColor(LPColor.ink)
            }
              .height(34)
              .onClick(() => this.onBack())
            Blank()
          }
          .width('100%')

          Row() {
            Column({ space: 2 }) {
              Text(this.friend.daysTogether.toString())
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.ink)
              Text('天 · 一起')
                .fontSize(9)
                .fontFamily('monospace')
                .fontColor(LPColor.muted)
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Text(this.friend.relation)
              .fontSize(10)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.paperCard)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(LPColor.coral)
              .borderRadius(6)
          }
          .width('100%')

          TwinStage({ store: this.store, friend: this.friend, pokeNonce: this.pokeNonce, cheerNonce: this.cheerNonce })

          HealthCompareCard({ friend: this.friend })

          Column({ space: 8 }) {
            Row() {
              Text(`给 ${this.friend.displayName} 留言`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.ink)
              Blank()
              Text(`最近 · ${this.allMessages()[this.allMessages().length - 1].time}`)
                .fontSize(9)
                .fontFamily('monospace')
                .fontColor(LPColor.muted)
            }
            .width('100%')

            Scroll(this.messageScroller) {
              Column({ space: 6 }) {
                ForEach(this.allMessages(), (message: TogetherMessage) => {
                  MessageBubble({ message })
                }, (message: TogetherMessage) => message.id)
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }
            .width('100%')
            .constraintSize({ maxHeight: 154 })
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Off)

            Row({ space: 6 }) {
              TextInput({ placeholder: '说点什么…', text: this.draft })
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .backgroundColor(LPColor.paperCard)
                .border({ width: 1.5, color: LPColor.ink })
                .borderRadius(8)
                .onChange((value: string) => {
                  this.draft = value;
                })
              Button('送出')
                .height(38)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .backgroundColor(LPColor.ink)
                .fontColor(LPColor.paperCard)
                .borderRadius(8)
                .onClick(() => this.sendText(this.draft))
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(LPColor.paperCard)
          .border({ width: 1.5, color: LPColor.ink })
          .borderRadius(10)
          .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })

          Scroll() {
            Row({ space: 6 }) {
              QuickChip({ label: '早安~ 今天慢跑加油', onSend: (text: string) => this.sendText(text) })
              QuickChip({ label: '记得喝水 💧', onSend: (text: string) => this.sendText(text) })
              QuickChip({ label: '想你了', onSend: (text: string) => this.sendText(text) })
              QuickChip({ label: '早点休息', onSend: (text: string) => this.sendText(text) })
            }
            .padding({ left: 2, right: 2 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .height(34)

          Row({ space: 8 }) {
            Button(`戳一下 ${this.friend.petName}`)
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(LPColor.ink)
              .fontColor(LPColor.paperCard)
              .borderRadius(10)
              .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
              .onClick(() => {
                this.pokeNonce += 1;
                this.showToast(`戳了 ${this.friend.petName} 一下 👋`);
              })
            Button('给 TA 加油')
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(LPColor.paperCard)
              .fontColor(LPColor.ink)
              .border({ width: 1.5, color: LPColor.ink })
              .borderRadius(10)
              .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
              .onClick(() => {
                this.cheerNonce += 1;
                this.showToast(`已为 ${this.friend.petName} 加油 ✨`);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12, bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(LPColor.paper)

      if (this.toast.length > 0) {
        ToastBubble({ text: this.toast })
          .margin({ bottom: 24 })
          .onClick(() => this.toast = '')
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct TwinStage {
  @ObjectLink store: PetStateStore;
  @Prop friend: Friend = DEFAULT_FRIEND;
  @Prop pokeNonce: number = 0;
  @Prop cheerNonce: number = 0;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(158)
        .backgroundColor(LPColor.lcd)
        .border({ width: 2, color: LPColor.ink })
        .borderRadius(14)
      Column()
        .width('96%')
        .height(146)
        .border({ width: 1.5, color: LPColor.lcdDash, style: BorderStyle.Dashed })
        .borderRadius(10)

      Row({ space: 6 }) {
        PetColumn({
          petName: this.store.petName,
          sprite: PetSpriteName.Bean,
          status: this.friend.myStatus,
          health: this.friend.myHealth
        })
        LightBand()
          .layoutWeight(1)
        PetColumn({
          petName: this.friend.petName,
          sprite: this.friend.sprite,
          status: this.friend.otherStatus,
          health: this.friend.otherHealth,
          pokeNonce: this.pokeNonce,
          cheerNonce: this.cheerNonce
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    }
    .width('100%')
    .height(158)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
  }
}

@Component
struct PetColumn {
  @Prop petName: string = 'BEAN';
  @Prop sprite: PetSpriteName = PetSpriteName.Bean;
  @Prop status: string = 'NORMAL';
  @Prop health: FriendHealth = DEFAULT_FRIEND.myHealth;
  @Prop @Watch('onPokeNonceChanged') pokeNonce: number = 0;
  @Prop @Watch('onCheerNonceChanged') cheerNonce: number = 0;
  @State shakeX: number = 0;
  @State shakeY: number = 0;
  @State cheerY: number = 8;
  @State cheerOpacity: number = 0;
  @State cheerScale: number = 0.5;
  private shakeTimers: number[] = [];
  private cheerTimers: number[] = [];

  aboutToDisappear(): void {
    this.clearShakeTimers();
    this.clearCheerTimers();
  }

  private onPokeNonceChanged(): void {
    if (this.pokeNonce > 0) {
      this.runPokeShake();
    }
  }

  private onCheerNonceChanged(): void {
    if (this.cheerNonce > 0) {
      this.runCheerFloat();
    }
  }

  private runPokeShake(): void {
    this.clearShakeTimers();
    const frames = [
      { delay: 0, x: -3, y: -12 },
      { delay: 100, x: 3, y: 0 },
      { delay: 200, x: -2, y: -7 },
      { delay: 300, x: 2, y: 0 },
      { delay: 400, x: 0, y: -3 },
      { delay: 450, x: 0, y: 0 }
    ];
    frames.forEach((frame) => {
      const timer = setTimeout(() => {
        animateTo({ duration: frame.delay === 450 ? 50 : 90, curve: Curve.Linear }, () => {
          this.shakeX = frame.x;
          this.shakeY = frame.y;
        });
      }, frame.delay);
      this.shakeTimers.push(timer);
    });
  }

  private runCheerFloat(): void {
    this.clearCheerTimers();
    this.cheerY = 8;
    this.cheerOpacity = 0;
    this.cheerScale = 0.5;
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.cheerY = -30;
      this.cheerOpacity = 1;
      this.cheerScale = 1.1;
    });
    const timer = setTimeout(() => {
      animateTo({ duration: 1000, curve: Curve.EaseInOut }, () => {
        this.cheerY = -72;
        this.cheerOpacity = 0;
        this.cheerScale = 0.7;
      });
    }, 350);
    this.cheerTimers.push(timer);
  }

  private clearShakeTimers(): void {
    this.shakeTimers.forEach((timer) => clearTimeout(timer));
    this.shakeTimers = [];
  }

  private clearCheerTimers(): void {
    this.cheerTimers.forEach((timer) => clearTimeout(timer));
    this.cheerTimers = [];
  }

  build() {
    Column({ space: 4 }) {
      Text(`${this.health.stepsShort} · ${this.health.sleepShort} · ${this.health.hr}♥`)
        .fontSize(8)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor('#FFF4D6EB')
        .border({ width: 1, color: LPColor.lcdInk, style: BorderStyle.Dashed })
        .borderRadius(8)
      Stack() {
        PixelPetSprite({ sprite: this.sprite, size: 62 })
        Text('✨')
          .fontSize(22)
          .opacity(this.cheerOpacity)
          .scale({ x: this.cheerScale, y: this.cheerScale })
          .translate({ y: this.cheerY })
          .position({ x: 56, y: 18 })
      }
      .width(70)
      .height(70)
      .translate({ x: this.shakeX, y: this.shakeY })
      Text(this.petName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(LPColor.ink)
      Text(this.status)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.lcdInk)
    }
    .width(104)
  }
}

@Component
struct LightBand {
  @State phase: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.clearTimer();
    this.timerId = setInterval(() => {
      this.phase = (this.phase + 1 / 78) % 1;
    }, 33);
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private dotIndexes(): number[] {
    return [0, 1, 2, 3];
  }

  private dotPhase(index: number): number {
    return (this.phase + index / 4) % 1;
  }

  private dotX(index: number): string {
    return `${8 + 84 * this.dotPhase(index)}%`;
  }

  private dotY(index: number): number {
    return index === 3 ? 9 : 12;
  }

  private dotSize(index: number): number {
    return index % 2 === 1 ? 4 : 5;
  }

  private dotColor(index: number): string {
    return index % 2 === 1 ? LPColor.coral : '#FFC847';
  }

  private dotOpacity(index: number): number {
    const p = this.dotPhase(index);
    if (p < 0.15) {
      return p / 0.15;
    }
    if (p > 0.85) {
      return (1 - p) / 0.15;
    }
    return 1;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('#D14B3D66')
      ForEach(this.dotIndexes(), (index: number) => {
        Column()
          .width(this.dotSize(index))
          .height(this.dotSize(index))
          .backgroundColor(this.dotColor(index))
          .borderRadius(this.dotSize(index) / 2)
          .opacity(this.dotOpacity(index))
          .position({ x: this.dotX(index), y: this.dotY(index) })
      }, (index: number) => index.toString())
    }
    .width('100%')
    .height(28)
  }
}

@Component
struct HealthCompareCard {
  @Prop friend: Friend = DEFAULT_FRIEND;

  build() {
    Column({ space: 0 }) {
      CompareRow({ label: '今日健康', me: '你', other: this.friend.displayName, header: true })
      CompareRow({ label: '步数', me: this.friend.myHealth.steps, other: this.friend.otherHealth.steps })
      CompareRow({ label: '睡眠', me: this.friend.myHealth.sleep, other: this.friend.otherHealth.sleep })
      CompareRow({ label: '心率', me: this.friend.myHealth.hr, other: this.friend.otherHealth.hr })
      CompareRow({ label: '卡路里', me: this.friend.myHealth.cal, other: this.friend.otherHealth.cal })
      CompareRow({ label: '静息', me: this.friend.myHealth.rest, other: this.friend.otherHealth.rest, last: true })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 4, bottom: 4 })
    .backgroundColor(LPColor.paperCard)
    .border({ width: 1.5, color: LPColor.ink })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct CompareRow {
  @Prop label: string = '';
  @Prop me: string = '';
  @Prop other: string = '';
  @Prop header: boolean = false;
  @Prop last: boolean = false;

  build() {
    Column({ space: 0 }) {
      Row() {
        Text(this.label)
          .fontSize(this.header ? 9 : 13)
          .fontFamily(this.header ? 'monospace' : 'sans-serif')
          .fontColor(this.header ? LPColor.muted : LPColor.muted)
          .layoutWeight(1)
        Text(this.me)
          .fontSize(this.header ? 9 : 12)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(LPColor.coral)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(this.other)
          .fontSize(this.header ? 9 : 12)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(this.header ? LPColor.muted : LPColor.ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 7, bottom: 7 })

      if (!this.last) {
        DashedRule({ color: LPColor.lcdDash })
      }
    }
    .width('100%')
  }
}

@Component
struct MessageBubble {
  @Prop message: TogetherMessage = { id: 'empty', who: MessageSender.Me, text: '', time: '' };

  build() {
    Row() {
      if (this.message.who === MessageSender.Me) {
        Blank().layoutWeight(1)
      }
      Column({ space: 2 }) {
        Text(this.message.text)
          .fontSize(13)
          .fontColor(this.message.who === MessageSender.Me ? LPColor.paperCard : LPColor.ink)
        Text(this.message.time)
          .fontSize(8)
          .fontFamily('monospace')
          .fontColor(this.message.who === MessageSender.Me ? '#FFFEF9AA' : LPColor.muted)
      }
      .alignItems(this.message.who === MessageSender.Me ? HorizontalAlign.End : HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.message.who === MessageSender.Me ? LPColor.coral : LPColor.paperCool)
      .border({ width: 1, color: this.message.who === MessageSender.Me ? LPColor.coral : LPColor.lcdDash })
      .borderRadius(10)
      .constraintSize({ maxWidth: '78%' })
      if (this.message.who === MessageSender.Them) {
        Blank().layoutWeight(1)
      }
    }
    .width('100%')
  }
}

@Component
struct QuickChip {
  @Prop label: string = '';
  onSend: (text: string) => void = () => {};

  build() {
    Button(this.label)
      .height(28)
      .fontSize(12)
      .backgroundColor(LPColor.paperCard)
      .fontColor(LPColor.muted)
      .border({ width: 1, color: LPColor.lcdDash })
      .borderRadius(14)
      .onClick(() => this.onSend(this.label))
  }
}

@Component
struct InvitePane {
  @State selectedRelation: string = '';
  @State toast: string = '';
  private shareActions: ShareActionService = new ShareActionService();
  onBack: () => void = () => {};
  private toastTimerId: number = -1;

  aboutToDisappear(): void {
    this.clearToastTimer();
  }

  private relations(): string[] {
    return ['伴侣', '妈妈', '爸爸', '挚友', '同学', '+ 自定义'];
  }

  private toastWith(text: string): void {
    this.toast = text;
    this.clearToastTimer();
    this.toastTimerId = setTimeout(() => {
      if (this.toast === text) {
        this.toast = '';
      }
      this.toastTimerId = -1;
    }, 1600);
  }

  private async handleAction(action: Promise<ShareActionResult>): Promise<void> {
    const result = await action;
    this.toastWith(result.message);
  }

  private clearToastTimer(): void {
    if (this.toastTimerId >= 0) {
      clearTimeout(this.toastTimerId);
      this.toastTimerId = -1;
    }
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Row({ space: 4 }) {
              Text('‹')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.coral)
              Text('返回')
                .fontSize(16)
                .fontColor(LPColor.ink)
            }
              .height(34)
              .onClick(() => this.onBack())
            Blank()
          }
          .width('100%')

          Column({ space: 14 }) {
            Column({ space: 4 }) {
              Text('邀请 TA 加入')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(LPColor.ink)
              Text('— 创建你们的双人空间 —')
                .fontSize(9)
                .fontFamily('monospace')
                .fontColor(LPColor.muted)
                .letterSpacing(1)
            }

            Text('FISH-7K2')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(LPColor.ink)
              .letterSpacing(4)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 16, bottom: 16 })
              .backgroundColor(LPColor.lcd)
              .border({ width: 2, color: LPColor.ink, style: BorderStyle.Dashed })
              .borderRadius(10)

            Row({ space: 8 }) {
              InviteAction({ label: '复制', primary: false, onTap: () => {
                void this.handleAction(this.shareActions.copyInviteCode('FISH-7K2'));
              } })
              InviteAction({ label: '分享', primary: true, onTap: () => {
                void this.handleAction(this.shareActions.shareInviteCode(this.context(), 'FISH-7K2'));
              } })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 22, bottom: 22 })
          .backgroundColor(LPColor.paperCard)
          .border({ width: 2, color: LPColor.ink })
          .borderRadius(14)
          .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })

          Row({ space: 10 }) {
            Column().layoutWeight(1).height(1).backgroundColor('#6E665A80')
            Text('或')
              .fontSize(9)
              .fontFamily('monospace')
              .fontColor(LPColor.muted)
            Column().layoutWeight(1).height(1).backgroundColor('#6E665A80')
          }
          .width('100%')

          InviteFullAction({
            label: '扫码加入对方',
            onTap: () => this.toastWith('扫码功能即将上线')
          })
          InviteFullAction({
            label: '输入对方邀请码',
            onTap: () => this.toastWith('输入对方邀请码 · 即将上线')
          })

          Column({ space: 8 }) {
            Text('关系昵称')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.ink)
              .width('100%')
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                ForEach(this.relations().slice(0, 3), (relation: string) => {
                  RelationChip({
                    label: relation,
                    active: this.selectedRelation === relation,
                    onPick: (label: string) => {
                      this.selectedRelation = this.selectedRelation === label ? '' : label;
                    }
                  })
                }, (relation: string) => relation)
              }
              .width('100%')
              Row({ space: 6 }) {
                ForEach(this.relations().slice(3), (relation: string) => {
                  RelationChip({
                    label: relation,
                    active: this.selectedRelation === relation,
                    onPick: (label: string) => {
                      this.selectedRelation = this.selectedRelation === label ? '' : label;
                    }
                  })
                }, (relation: string) => relation)
              }
              .width('100%')
            }
            .width('100%')
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12, bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(LPColor.paper)

      if (this.toast.length > 0) {
        ToastBubble({ text: this.toast })
          .margin({ bottom: 24 })
          .onClick(() => this.toast = '')
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct InviteAction {
  @Prop label: string = '';
  @Prop primary: boolean = false;
  onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height(40)
        .backgroundColor(LPColor.ink)
        .borderRadius(8)
        .translate({ x: 2, y: 2 })
      Column()
        .width('100%')
        .height(40)
        .backgroundColor(this.primary ? LPColor.ink : LPColor.paperCard)
        .border({ width: 1, color: LPColor.ink })
        .borderRadius(8)
      Text(this.label)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primary ? LPColor.paperCard : LPColor.ink)
    }
      .layoutWeight(1)
      .height(42)
      .margin({ right: 2, bottom: 2 })
      .onClick(() => this.onTap())
  }
}

@Component
struct InviteFullAction {
  @Prop label: string = '';
  onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height(42)
        .backgroundColor(LPColor.ink)
        .borderRadius(8)
        .translate({ x: 2, y: 2 })
      Column()
        .width('100%')
        .height(42)
        .backgroundColor(LPColor.paperCard)
        .border({ width: 1, color: LPColor.ink })
        .borderRadius(8)
      Text(this.label)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(LPColor.ink)
    }
    .width('100%')
    .height(44)
    .margin({ right: 2, bottom: 2 })
    .onClick(() => this.onTap())
  }
}

@Component
struct RelationChip {
  @Prop label: string = '';
  @Prop active: boolean = false;
  onPick: (label: string) => void = () => {};

  build() {
    Button(this.label)
      .padding({ left: 12, right: 12 })
      .height(32)
      .fontSize(13)
      .backgroundColor(this.active ? LPColor.coral : LPColor.paperCard)
      .fontColor(this.active ? LPColor.paperCard : LPColor.ink)
      .border({ width: 1, color: this.active ? LPColor.coral : LPColor.ink })
      .borderRadius(16)
      .onClick(() => this.onPick(this.label))
  }
}

@Component
struct PlazaPane {
  @ObjectLink store: PetStateStore;
  @State goalCurrent: number = plazaSnapshot.goalCurrent;
  @State onlineCount: number = plazaSnapshot.onlineCount;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.clearTicker();
    this.timerId = setInterval(() => {
      const goalDelta = 20 + Math.floor(Math.random() * 81);
      const onlineDelta = Math.floor(Math.random() * 5) - 2;
      this.goalCurrent = Math.min(plazaSnapshot.goalTotal, this.goalCurrent + goalDelta);
      this.onlineCount = Math.max(180, Math.min(320, this.onlineCount + onlineDelta));
    }, 2400);
  }

  aboutToDisappear(): void {
    this.clearTicker();
  }

  private clearTicker(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private percent(): number {
    if (plazaSnapshot.goalTotal <= 0) {
      return 0;
    }
    return Math.min(1, this.goalCurrent / plazaSnapshot.goalTotal);
  }

  private rowStarts(): number[] {
    return [0, 3, 7, 11];
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text('今日社区 · 大家一起')
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor(LPColor.stickyInk)
            .letterSpacing(1)
          Text(plazaSnapshot.goalTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(LPColor.ink)
          Stack({ alignContent: Alignment.Start }) {
            Column()
              .width('100%')
              .height(8)
              .backgroundColor('#FFFEF999')
              .borderRadius(4)
            Column()
              .width(`${Math.floor(this.percent() * 100)}%`)
              .height(8)
              .backgroundColor(LPColor.coral)
              .borderRadius(4)
          }
          .width('100%')
          .height(8)
          Row() {
            Text(formatInt(this.goalCurrent))
            Blank()
            Text(`${Math.floor(this.percent() * 100)}%`)
          }
          .width('100%')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(LPColor.stickyInk)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(LPColor.sticky)
        .border({ width: 1, color: LPColor.ink })
        .borderRadius(10)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
        .rotate({ angle: -0.3 })

        Row({ space: 8 }) {
          PlazaStat({ label: '在场人数', value: this.onlineCount.toString(), sub: '位宠物主人' })
          PlazaStat({ label: '我的步数贡献', value: plazaSnapshot.myContribSteps, sub: '步', accent: true })
        }
        .width('100%')
        Row({ space: 8 }) {
          PlazaStat({ label: '社区运动次数', value: plazaSnapshot.exerciseCount, sub: '次' })
          PlazaStat({ label: '我的排名', value: plazaSnapshot.myRank, sub: `/ ${this.onlineCount} 人`, accent: true })
        }
        .width('100%')

        Column({ space: 10 }) {
          Row() {
            Text(`● ${this.onlineCount} 人在场`)
              .fontSize(9)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor(LPColor.paperCard)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(LPColor.coral)
              .borderRadius(4)
            Blank()
          }
          .width('100%')

          ForEach(this.rowStarts(), (start: number) => {
            Row({ space: 10 }) {
              if (start === 0) {
                PlazaPetCell({ name: this.store.petName, sprite: PetSpriteName.Bean, isMe: true })
                PlazaPetCell({ name: plazaSnapshot.members[0].name, sprite: plazaSnapshot.members[0].sprite, isMe: false })
                PlazaPetCell({ name: plazaSnapshot.members[1].name, sprite: plazaSnapshot.members[1].sprite, isMe: false })
                PlazaPetCell({ name: plazaSnapshot.members[2].name, sprite: plazaSnapshot.members[2].sprite, isMe: false })
              } else {
                PlazaPetCell({ name: plazaSnapshot.members[start].name, sprite: plazaSnapshot.members[start].sprite, isMe: false })
                if (start + 1 < plazaSnapshot.members.length) {
                  PlazaPetCell({ name: plazaSnapshot.members[start + 1].name, sprite: plazaSnapshot.members[start + 1].sprite, isMe: false })
                } else {
                  Blank().layoutWeight(1)
                }
                if (start + 2 < plazaSnapshot.members.length) {
                  PlazaPetCell({ name: plazaSnapshot.members[start + 2].name, sprite: plazaSnapshot.members[start + 2].sprite, isMe: false })
                } else {
                  Blank().layoutWeight(1)
                }
                if (start + 3 < plazaSnapshot.members.length) {
                  PlazaPetCell({ name: plazaSnapshot.members[start + 3].name, sprite: plazaSnapshot.members[start + 3].sprite, isMe: false })
                } else {
                  Blank().layoutWeight(1)
                }
              }
            }
            .width('100%')
          }, (start: number) => start.toString())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 14 })
        .backgroundColor(LPColor.lcd)
        .border({ width: 2, color: LPColor.ink })
        .borderRadius(14)
        .shadow({ radius: 0, color: LPColor.ink, offsetX: 3, offsetY: 3 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 14, bottom: 34 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct PlazaStat {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop sub: string = '';
  @Prop accent: boolean = false;

  build() {
    Column({ space: 2 }) {
      Text(this.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
      Text(this.value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent ? LPColor.coral : LPColor.ink)
      Text(this.sub)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(LPColor.muted)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(LPColor.paperCard)
    .border({ width: 1, color: LPColor.ink })
    .borderRadius(10)
    .shadow({ radius: 0, color: LPColor.ink, offsetX: 2, offsetY: 2 })
  }
}

@Component
struct PlazaPetCell {
  @Prop name: string = '';
  @Prop sprite: PetSpriteName = PetSpriteName.Bean;
  @Prop isMe: boolean = false;

  build() {
    Column({ space: 3 }) {
      PixelPetSprite({ sprite: this.sprite, size: 40 })
      Text(this.name)
        .fontSize(8)
        .fontWeight(this.isMe ? FontWeight.Bold : FontWeight.Regular)
        .fontFamily('monospace')
        .fontColor(this.isMe ? LPColor.coral : LPColor.lcdInk)
      Text(this.isMe ? 'YOU' : ' ')
        .fontSize(7)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.isMe ? LPColor.coral : LPColor.lcdInk)
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(this.isMe ? '#D14B3D1A' : '#FFFFFF4D')
    .border({ width: this.isMe ? 1 : 0, color: this.isMe ? LPColor.coral : Color.Transparent, style: BorderStyle.Dashed })
    .borderRadius(8)
  }
}

@Component
struct ToastBubble {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(13)
      .fontColor(LPColor.paperCard)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(LPColor.ink)
      .borderRadius(18)
  }
}

function formatInt(value: number): string {
  const s = Math.floor(value).toString();
  const parts: string[] = [];
  for (let i = s.length; i > 0; i -= 3) {
    parts.unshift(s.substring(Math.max(0, i - 3), i));
  }
  return parts.join(',');
}
