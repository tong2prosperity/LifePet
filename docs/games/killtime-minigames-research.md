# Pibo 纯娱乐 kill-time 小游戏调研（游戏场选型）

> 立项日期 2026-07-05。面向 `Pibo/Features/Games`「游戏场」的**纯娱乐向**选型。
> **本文刻意抛开健康/医学正当性**——只问「好不好玩、能不能掏出手机刷一把打发时间、贴不贴 Pibo 的皮」。健康正当性向的选型见姊妹文档 [health-minigames-research.md](health-minigames-research.md)。
>
> 已有第一款：**地图涂鸦 / walk doodle**（运动能量，出门圈地）。本文回答「游戏场里再塞几款纯 kill-time 的小游戏，做哪些、怎么套皮、怎么接养成主循环」。
>
> 研究方法：两路并行网络调研——① 头部虚拟宠物/养成 app 的内嵌小游戏拆解；② 超休闲/放置/一分钟游戏机制 × SpriteKit 可行性。**分级贯穿全文：【事实】= 有来源支撑的产品机制/官方文档；【推断】= 为 Pibo 场景做的设计迁移判断。**
>
> ⚠️ **与世界观的张力**：CLAUDE.md 写「every game is 健康相关，the worldview demands it」。本文是用户明确要求「不考虑医学、纯 kill time」下的探路——落地时要么给纯娱乐游戏套一层轻能量叙事（见 §4 挂钩建议），要么作为「游戏场」里的休闲支线，由产品决策。

---

## 0. 一页结论（TL;DR）

**最值得做的两款（SpriteKit 甜点区 + 最贴 Pibo 花世界观）：**

| 推荐 | 机制原型 | 套皮 | 一局 | 实现 | 为什么 |
|---|---|---|---|---|---|
| 🥇 **合成花朵** | Suika / 合成大西瓜（物理掉落合成） | 落花种，同种合并升级：种子→嫩芽→花苞→…→大花 | 2–5 min | 低-中（1–2 天，SKPhysics 原生） | 上瘾最强 + 直接接「花的品种」既定设定 |
| 🥈 **叠花盆** | Stack（Ketchapp 堆叠） | 移动花盆/礼物盒叠成花塔，叠歪切掉，Pibo 傲娇吐槽 | 1–3 min | 低（最快出成品） | 最省工时，魔丸态演出天然 |

**最轻性格演出（几乎零成本，最能演傲娇）：**
- 🎭 **猜拳** — 一局 3 秒，纯即时反馈，Pibo 输了扭头、赢了得意。桌宠掌机标配。

**通用铁律（跨全部宠物 app 验证）：**
1. **一局玩法尽量喂多条线**——Pou 的「一局 = 金币 + 心情 + 体重」是最紧挂钩样板。Pibo 一局应同时给「货币/能量 + 花状态变化 + 掉落碎片/装扮」。
2. **短局可刷 > 长任务**——单局 ≤90 秒 + 3 星难度档 + 高分刷新，把留存做成「反复刷」而非「一次通关」。
3. **收集与拍照本身即内容**——Neko Atsume / Adventure Kingdom 证明「图鉴 + 拍照挑战」比「获得物」更耐刷；Pibo 的花品种图鉴 + 露珠相机拍照生涯是现成落点。

---

## 1. 超休闲机制 × SpriteKit 可行性

【事实】SpriteKit 物理引擎基于 Box2D，给任意节点加 `SKPhysicsBody` 即接入物理，`SKPhysicsContactDelegate.didBegin(_:)` 处理碰撞；GitHub 有开源 [Stacker（SpriteKit 堆叠）](https://github.com/maartene/Stacker) 可参考。来源：[SKPhysicsBody 文档](https://developer.apple.com/documentation/spritekit/skphysicsbody)、[SpriteKit 碰撞教程](https://code.tutsplus.com/tutorials/spritekit-from-scratch-physics-and-collisions--cms-26413)。

| 机制 | 代表作 | 核心循环【事实】 | 上瘾点 | 实现难度 | 一局 | SpriteKit 契合 |
|---|---|---|---|---|---|---|
| **物理掉落合成** | Suika / 合成大西瓜 | 顶部落物，两同物接触→合成大一级 | 不可预测物理→每局不同 + 连锁爆 | 中 | 2–5 min | **高（SKPhysics 甜点）** |
| **堆叠** | Stack | 移动块点屏对齐叠高，偏移切掉，越叠越窄加速 | 渐进压力 + 完美连击 | 低 | 1–3 min | **高** |
| **单键 / 计时点击** | Flappy Bird, Stack, Aa | 单点触发一个动作/精确时刻停下 | 反射本能 + 即时重开 | 低 | 30s–3 min | **高** |
| **颜色配对** | Color Switch, Aa | 识别并匹配颜色/形状 | 冥想式专注 | 低 | 1–2 min | 高 |
| **放置点击** | Cookie Clicker | 点→赚币→买自动化→指数增长 | 每点即时奖励 + 离线也涨 | 低-中 | 碎片/无限 | 中（数值+UI为主） |
| **升降穿缝** | Helix Jump | 转平台让落球穿缺口 | 未知障碍期待 | 中 | 1–3 min | 中（原版3D，2D会丢灵魂） |
| **无限跑酷** | endless runner | 持续触屏躲障 | 操控亲密感 | 中 | 1–3 min | 中（无限地形量大） |

**【推断】按几天窗口分层：**
- **强推（1–2 天可出）**：物理掉落合成（SKPhysics 天生适配，物理的「不可预测」免费）、堆叠（可不用物理，纯位置对齐+切割，开源可抄）、单键/计时（一个移动节点 + 一次点击判定，最省）。
- **较契合（2–3 天）**：单键物理（Flappy 类 `applyImpulse` + 障碍生成）、颜色精度旋转。
- **坑多别短期做**：Helix Jump（3D 深度错觉 2D 化丢灵魂）、流体引导解谜（SKPhysics 上流体很吃力）、endless runner（无限地形 + <16ms 平滑触控，几天做不精）、纯 idle（机制简单但上瘾靠长期数值调参，hackathon 里调不好会空洞）。

**爆款「一局接一局」心理【事实】**：即时反馈 + 秒重开无加载摩擦；易学难精；难度随进度上升；每几秒一个奖励（数字上升/解锁/新视觉）触发多巴胺循环。来源：[GDevelop casual loops](https://gdevelop.io/blog/casual-game-loops)、[ejaw 10 大机制](https://ejaw.net/top-10-hyper-casual-mechanics/)、[Suika 上瘾分析](https://blockblastpuzzle.online/en/games/suika_game)。

---

## 2. 头部宠物/养成 app 内嵌了什么小游戏

> 看别人怎么把小游戏塞进养宠主循环。**核心洞察：小游戏几乎都是「金币主水龙头」，金币回流到装扮/收集/解锁。**

| 产品 | 内嵌小游戏【事实】 | 与主循环挂钩 | 来源 |
|---|---|---|---|
| **My Tamagotchi Forever** | ~7 款：Match-3、Band Practice（节奏点击）、Fruit Slice（划切）、Hide & Seek（AR 找茬）、Hoops（投篮）、Bouncy Balls（打砖块） | 产 Gotchi Points → 买游乐设施/装饰/升级 | [gamezebo](https://www.gamezebo.com/walkthroughs/my-tamagotchi-forever-mini-game-guide/) · [fandom](https://tamagotchi.fandom.com/wiki/My_Tamagotchi_Forever) |
| **Tamagotchi Paradise** | 6 款各 3 档难度 3 星：喂奶瓶（喂食反应）、送维生素（跳平台）、驾云收币躲鸟（单键收集躲避） | 产币但**刻意不加 happiness**（赚币与养宠解耦，避免小游戏变苦役） | [tamavault](https://tamavault.com/paradise/mini-games/) |
| **Pou** | 30+ 款（足球/开车/Sudoku/match-3…），Game Room 里玩 | **一局喂 3 条线：金币（买装扮）+ fun 条（心情）+ 体重（玩游戏消脂）**——最紧挂钩样板 | [poupedia](https://poupedia.com/Minigames) |
| **Neko Atsume** | **无传统小游戏**，纯放置 idle | 放食物玩具→关 app→回来看猫来过→留鱼（货币）→买摆设。**零惩罚零内疚**；Catbook 图鉴 + 拍照即内容 | [设计拆解](https://alexiamandeville.medium.com/game-design-breakdown-the-simplicity-of-neko-atsume-a8616a937a47) · [wiki](https://en.wikipedia.org/wiki/Neko_Atsume) |
| **Widgetable** | 小游戏成分弱 | 养宠 + widget 常驻 + **每 24h 宠物"串门"到伴侣手机**（社交裂变） | [App Store](https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226) |
| **Finch** | 「小游戏」=自我照护活动（呼吸/测验/白噪音/拉伸/日记） | 活动→彩虹石→装扮鸟屋 + 派鸟探险 | [fandom](https://finch.fandom.com/wiki/Activities) |
| **Tamagotchi Adventure Kingdom**（Apple Arcade） | 开放世界任务 + 内嵌 PAC-MAN + Tama-Camera **90 个拍照挑战** | 任务奖励→造物/装扮/近 300 角色收集；**拍照挑战本身是长任务链** | [fandom](https://tamagotchi.fandom.com/wiki/Tamagotchi_Adventure_Kingdom) |
| **Happy Pet Story** | 钓鱼、**猜拳**、气球爆破、**音乐节奏点击** | 配合任务（如"多钓鱼"） | [review](https://sevpoots.wordpress.com/2015/03/02/ios-happy-pet-story-1-02-review-tips-and-tricks-fun-facts/) |
| **微信/抖音养成小程序** | 救助宠物、**合成类**（同级宠物拖合成升级）、离线挂机产币 | HOOKED 模型：触发→行动→多变酬赏→沉没成本；抖音标准**单局 ≤3 min + 即点即玩 + 社交裂变** | [woshipm](https://www.woshipm.com/operate/1676653.html) · [抖音小游戏文档](https://developer.open-douyin.com/docs/resource/zh-CN/mini-game/guide/minigame/introduction) |

**短会话 vs 长线【事实】**：属「一局 1–3 min 立即反馈可反复刷」的——节奏点击、划切、单键收集躲避、喂食反应、投篮、猜拳（3 秒/局），配 3 星 + 难度档做成刷分。**不属此类**（长线）——Neko Atsume 放置、Widgetable/Finch 打卡、Adventure Kingdom 任务链、微信合成挂机。

---

## 3. 与宠物 IP 结合最好的机制（含 Pibo 套皮）

> 每类 =【事实：来源产品】+【推断：Pibo（傲娇小生物 + 头顶花）套皮】。按套皮自然度 + Pibo 花世界观契合度排序。

1. **合成花朵（Suika 换皮）★首选** — 落花种/花苞，同种合并升级到 Pibo 头顶的大花。**直接呼应「认知/记录能量解锁花品种」既定设定**，物理滚动免费，一局 2–5 min。是「合成大西瓜换成合成花朵」的最优解，与 CLAUDE.md 的花品种体系天然接口。
2. **叠花盆 / 给 Pibo 叠积木（Stack 换皮）** — 移动花盆叠成花塔，偏移切掉；魔丸态傲娇反应（叠歪了「...歪了啵...」）。实现最省，1–2 天。
3. **喂食接物（Feed/Catch）** — 接落下的能量/露珠喂头顶花，接得好→绽放动画、接漏→花蔫。傲娇口「哼，勉强够吃」。事实：Paradise 喂奶瓶、Pou 喂食影响体重。
4. **猜拳（3 秒/局）★最轻性格演出** — 纯运气 + 表情演出，无限连刷，**最能演傲娇**（输了扭头嘴硬）。事实：Happy Pet Story + 几乎所有掌机 9 模式之一。极低成本高演出。
5. **节奏点击（Rhythm Tap）** — 跟着 Pibo 哼的**乱码音节**点节拍（呼应「乱码语言」设定），Combo 越高花越亮。事实：Band Practice 点音符收金币。
6. **浇水计时（Timing 换皮）** — 露珠落下，点屏在花上方精确接住浇灌，连成功→花开。契合「露珠相机」意象。
7. **捉迷藏（Hide & Seek）** — Pibo 躲进场景限时点找，找到掉一片**记忆碎片**（接 Pibo 碎片叙事）。事实：My Tamagotchi Forever AR 找茬。
8. **宠物跑酷（Runner）** — Pibo 拖着头顶花往前跑一键跳，越跑花越大/掉瓣。契合「游戏场」跑道意象，但与养花叙事关联偏弱。
9. **放置产币（微信系）** — 离开时花/能量缓慢累积，回来有惊喜。**需警惕与 Pibo「零惩罚、不卖惨」调性冲突——学 Neko Atsume 的零内疚版本**。

**装扮/收集是留存地基（非玩法而是承接层）**【事实】：Pou/Finch/Adventure Kingdom/Neko Atsume 的货币最终都流向装扮/收集；上瘾点是**收集完成度 + 稀有度**，照片/图鉴是比「获得物」更多的可收集内容。【推断】Pibo 小游戏产出的货币应回流到**头顶花的品种/装扮 + 拍照图鉴**（Pibo 已有露珠相机 + 品种/SSR 稀有度占位，正好接住）。

---

## 4. 落地建议

**做哪几款（按性价比）：**
1. **P0 · 合成花朵（Suika）** — 上瘾最强、最贴花世界观、SKPhysics 甜点。作为 walk doodle 之后的第二款主打（运动能量之外的「花品种能量」，机制互补）。
2. **P0 · 叠花盆（Stack）** — 最快出成品，与合成花朵**共用 SKPhysics + 掉落输入代码**，可一起做。
3. **P1 · 猜拳** — 几乎零成本，把「陪它打发时间」的最轻交互 + 傲娇演出补上。
4. **P1 · 节奏点击（乱码音节）** — 呼应乱码语言设定，Combo 花越亮。
5. **P2 · 放置/收集底座** — 图鉴 + 拍照挑战做长期留存锚，但数值/调性风险，留后。

**每款游戏的通用要求（三条铁律落地）：**
- 单局 ≤90 秒可掏出即玩，配 **3 星 + 难度档**做成反复刷分（别做一次性通关）。
- **一局喂多条线**：结束同时给「货币/能量 + 头顶花状态变化 + 掉落碎片/装扮」，局末接回现有 `EnergySproutFlow` 的「能量已收集」pop。
- 货币回流到**花品种图鉴 + 露珠相机拍照生涯**（现成的收集/稀有度承接层）。
- 保持「零惩罚、不卖惨、傲娇」tone——放置/挂机类要学 Neko Atsume 的零内疚，不做「不玩就掉分」的惩罚设计。

**与世界观的取舍（留给产品决策）**：纯 kill-time 游戏若要进「游戏场」，两条路——① 套一层轻能量叙事（合成花朵=花品种能量、接露珠=浇灌头顶花），让它名义上仍「养花」；② 明确作为休闲支线，接受它不承担健康正当性。合成花朵/叠花盆走 ① 最顺，猜拳/跑酷更像 ②。

---

## 附录 · 核心来源清单

**超休闲机制 × SpriteKit**
- ejaw 10 大超休闲机制：https://ejaw.net/top-10-hyper-casual-mechanics/
- GDevelop casual game loops：https://gdevelop.io/blog/casual-game-loops
- Suika Game（Wikipedia）：https://en.wikipedia.org/wiki/Suika_Game
- Suika 上瘾分析：https://blockblastpuzzle.online/en/games/suika_game
- Stack（Ketchapp）：https://games.lol/stack/
- Helix Jump：https://www.crazygames.com/game/helix-jump
- SKPhysicsBody 文档：https://developer.apple.com/documentation/spritekit/skphysicsbody
- SpriteKit 碰撞教程：https://code.tutsplus.com/tutorials/spritekit-from-scratch-physics-and-collisions--cms-26413
- 开源 Stacker（SpriteKit）：https://github.com/maartene/Stacker

**宠物/养成 app 内嵌小游戏**
- My Tamagotchi Forever 小游戏指南：https://www.gamezebo.com/walkthroughs/my-tamagotchi-forever-mini-game-guide/
- Tamagotchi Paradise 小游戏：https://tamavault.com/paradise/mini-games/
- Tamagotchi Adventure Kingdom：https://tamagotchi.fandom.com/wiki/Tamagotchi_Adventure_Kingdom
- Pou 小游戏：https://poupedia.com/Minigames
- Neko Atsume 设计拆解：https://alexiamandeville.medium.com/game-design-breakdown-the-simplicity-of-neko-atsume-a8616a937a47
- Widgetable：https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226
- Finch 活动：https://finch.fandom.com/wiki/Activities
- Happy Pet Story：https://sevpoots.wordpress.com/2015/03/02/ios-happy-pet-story-1-02-review-tips-and-tricks-fun-facts/
- 微信养成运营拆解：https://www.woshipm.com/operate/1676653.html
- 抖音小游戏开发文档：https://developer.open-douyin.com/docs/resource/zh-CN/mini-game/guide/minigame/introduction
