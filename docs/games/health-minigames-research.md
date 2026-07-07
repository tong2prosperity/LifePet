# Pibo 健康小游戏调研（Features/Games 落地指南）

> 立项日期 2026-07-05。面向 `Pibo/Features/Games` 游戏列表的选型与落地。
> 已有第一款：**地图涂鸦 / walk doodle**（运动能量，GPS 圈地）。本文回答「下一批做什么、怎么做、文案能怎么说」。
>
> **筛选标准（四条硬门槛）**：① 对体能 / 智力 / 记忆力有轻微提升；② 对健康有益；③ 短时（1–5 分钟）内可获得反馈；④ 能打发时间。
>
> 研究方法：一轮 deep-research 多代理对抗验证（认知训练角度，25 条断言 3 票制核验）+ 两轮补充调研（呼吸/正念、姿态识别 exergame）。**证据分级贯穿全文：【硬证据】= 同行评审 RCT / 元分析 / 官方文档；【产品观察】= 商业产品与工程实践。**

---

## 0. 一页结论（TL;DR）

| 品类 | 健康证据强度 | 即时反馈 | 工程量 | Pibo 契合度 | 结论 |
|---|---|---|---|---|---|
| **微运动 exercise snack**（步频/深蹲计数） | 🟢 强（VILPA 队列 + 代谢 RCT） | 强 | 低（CoreMotion） | 高（直接回流运动能量） | **首推，继 walk doodle 之后最稳** |
| **呼吸 / 正念**（跟随节拍养花） | 🟢 强（5 分钟 RCT + 慢呼吸元分析） | 强 | 低（开环节拍器） | 高（接 HRV 压力叙事 + glitch 恢复） | **强推，与手表 CRC 呼吸器呼应** |
| **认知训练**（记忆矩阵 / 双 n-back） | 🟡 有限（只有「近迁移」成立） | 强 | 中 | 中 | **可做，但文案有法律红线** |
| **摄像头体感 exergame**（前摄接花瓣） | 🟢 强（同 VILPA） | 强 | 高（Vision + 架机） | 中（仪式感强、准入成本高） | **进阶款，非首发** |

**三条贯穿全文的红线 / 铁律：**

1. **认知游戏文案铁律**：科学只支持「练这个技能本身会进步」（近迁移），**不支持**「提升智力 / 记忆力 / 注意力 / 延缓认知衰退」（远迁移，效应量为零）。后者正是 2016 年 FTC 罚 Lumosity 200 万美元的原因——**Pibo 绝不能碰**。
2. **呼吸铁律**：默认 **~6 次/分、呼气长于吸气**（吸 4s / 呼 6s）；宣传锚定「即时放松」而非「治疗焦虑」。
3. **微运动铁律**：VILPA 是**观察性关联**，文案说「每天几分钟剧烈活动与更低疾病风险相关」，**不能**说「玩这个游戏能防癌」。

---

## 1. 认知训练类（Lumosity / Peak / 双 n-back）

### 1.1 科学证据：近迁移成立，远迁移为零

这是本次调研**证据最硬、也最反直觉**的结论，经 25 条断言 3 票对抗验证，全部一致通过：

- **【硬证据】远迁移 =「提升流体智力 / 日常认知 / 记忆力」在方法学上不成立。** 控制安慰剂与发表偏倚后，效应量与真实方差**归零**，横跨工作记忆训练、电子游戏、音乐、象棋、exergame 所有程序类型和所有人群。
  - Simons et al. 2016, *Psychological Science in the Public Interest*（130+ 研究共识综述）：https://journals.sagepub.com/doi/abs/10.1177/1529100616661983
  - Melby-Lervåg/Redick/Hulme 2016 元分析（87 篇 / 145 组对照，含 n-back 与 Cogmed）：对真实认知不泛化，非言语 g=0.05（不显著）、言语 g=0.05（不显著）：https://pmc.ncbi.nlm.nih.gov/articles/PMC4968033/
  - Sala et al. 2019 二阶元分析（最大模型 k=233）：「控制安慰剂和发表偏倚后总效应量与真实方差等于零」：https://online.ucpress.edu/collabra/article/5/1/18/113004/Near-and-Far-Transfer-in-Cognitive-Training-A

- **【硬证据】近迁移**（在与被训练任务相似的记忆任务上进步）**确实成立**：言语工作记忆 g=0.31、视空间工作记忆 g=0.28（对治疗性对照 p<.01），效应量受人群调节；连领域最著名的怀疑派也承认「近迁移的存在似乎无可置疑」。
  - Li et al. 2021 *Scientific Reports*（148 名 18–26 岁健康成人，30 分钟/天 × 20 天）：双 n-back 提升工作记忆，且比记忆宫殿法有更广的向未训练任务的迁移：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7862396/
  - **重要限定**：近迁移只在**结构化、多次、难度自适应**训练下成立。玩一局不产生可测提升——Pibo 若要主张「练这个技能有进步」，游戏必须是**可重复 + 难度自适应**的。

### 1.2 文案红线（FTC v. Lumosity，2016）⚠️

**【硬证据】** FTC 以 200 万美元和解认定 Lumosity 虚假广告（另有 5000 万判决暂缓），明令禁止三类宣称。这为 Pibo 认知小游戏划出**不可逾越的文案红线**：

1. ❌ 提升日常 / 学校 / 工作 / 运动表现
2. ❌ 延缓年龄相关认知衰退、预防轻度认知障碍 / 痴呆 / 阿尔茨海默症
3. ❌ 缓解中风 / 脑外伤 / PTSD / ADHD / 化疗副作用等疾病相关认知损伤
4. ❌ 谎称科学研究已证明上述益处

来源：https://www.ftc.gov/news-events/news/press-releases/2016/01/lumosity-pay-2-million-settle-ftc-deceptive-advertising-charges-its-brain-training-program

> ✅ **Pibo 能说的**：「练这个记忆挑战本身，你会越来越准」+「打发时间」+「陪 Pibo 玩」。
> ❌ **Pibo 不能说的**：「变聪明」「提升记忆力 / 智力 / 专注力」「防痴呆」。
> 与产品目标第 ① 条（「对智力/记忆力轻微提升」）存在张力——**产品叙事需据此收窄到「被训练技能本身」**。

### 1.3 可复用的玩法机制（均可纯 SpriteKit/SwiftUI 落地）

**【产品观察】** Lumosity 官网按 记忆/速度/注意/灵活/问题解决/词汇/数学 七类组织，每款对应一个命名能力，都是 1–5 分钟 2D 短会话：https://www.lumosity.com/en/cognitive-games/

| 机制 | 玩法 | 训练能力 | 落地 |
|---|---|---|---|
| **记忆矩阵** Memory Matrix | 网格闪现图案 → 回忆并点亮瓷砖位置 | 空间记忆 | 最易实现，纯 SpriteKit 网格 |
| **双 n-back** | 同步呈现「听觉字母流 + 视觉方块位置流」，当前刺激与 n 步前匹配时响应 | 工作记忆 | ~20 trial/block 正好 1–5 分钟 |
| **Speed Match** | 当前符号与上一个是否相同，快速判断 | 处理速度 | 极简 |
| **Train of Thought** | 引导越来越多的列车按颜色进站 | 分配注意力 | 中等 |
| **Pet Detective / 路径规划** | 规划最短取送路径 | 问题解决 | 中等 |

**【硬证据 · 工程可行性】** 双 n-back 核心机制无专利 / 付费墙——游戏机制不受版权保护，可自由重实现。开源实现 Brain Workshop（GPL）可作参考，**但 GPL 只授权其源码，不得拷贝进 Pibo 专有工程**，机制自己重写即可：https://brainworkshop.sourceforge.net/

> ⚠️ **被对抗验证驳回、不要据此立论的说法**（0-3 未通过）：
> - 一条 2025 元分析声称「脑训练游戏确能改善认知/处理速度/工作记忆」——被驳回；
> - 「Brain Age 与普通 Tetris 对认知同样有效」——被驳回；
> - Brain Workshop 官网转述的「Jaeggi 2008 双 n-back 提升流体智力」——被驳回（已被二阶元分析归因于被动对照与偏倚）。

---

## 2. 呼吸 / 正念类（与手表 CRC 呼吸器呼应）

> Pibo 已在手表端有 CRC 呼吸训练器（`Pibo Watch App/Features/CRCBreathing/`）。手机端呼吸小游戏可与之形成叙事闭环，并复用 HRV 压力监测。

### 2.1 健康证据（硬证据充足）

- **【硬证据 · RCT n=111】每天 5 分钟就有可测效果，且「呼气长于吸气」是关键机制。** Balban et al. 2023, *Cell Reports Medicine*（Stanford）：三种每天 5 分钟、持续 1 个月的控制呼吸法在情绪改善、能量/平静提升上均显著优于正念观呼吸；**强调延长呼气的 cyclic sighing（循环叹息）效果最佳**。
  - 论文：https://www.cell.com/cell-reports-medecine/fulltext/S2666-3791(22)00474-8
  - Stanford 解读：https://med.stanford.edu/news/insights/2023/02/cyclic-sighing-can-help-breathe-away-anxiety.html

- **【硬证据 · 元分析】慢呼吸即时降心率/血压/升 HRV：**
  - 2017 元分析：慢呼吸降心率 −1.72 bpm、收缩压 −6.36 mmHg、舒张压 −6.39 mmHg：https://pubmed.ncbi.nlm.nih.gov/28502461/
  - 2023 元分析（31 项研究，n=1133）：慢呼吸后 SDNN（HRV）中高度提升（SMD=0.77）：https://link.springer.com/article/10.1007/s12671-023-02294-2 —— **直接支撑「呼吸 → HRV」，是 Pibo 压力监测的姊妹机制**。

- **【硬证据 · RCT】~6 次/分（0.1 Hz 共振频率）是最优速率：** 6 次/分产生最强 HRV 提升；箱式呼吸在 5–6 次/分区间内也有效但略弱：https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0336615 ；共振呼吸 RCT：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8924557/

- **边界（诚实标注）**：5 分钟单次 → 急性降唤醒可靠；慢性抗压韧性需 4–8 周每日练习。呼吸领域缺大样本 RCT，宣传要保守（说「即时放松」不说「治疗焦虑」）。

### 2.2 产品玩法拆解（产品观察）

**跨全部产品的共同交互原语**：一个随呼吸周期**胀缩/起落的视觉引导物** + 实时反馈。差异只在引导物是「圆」还是「角色/世界」，以及有无真实呼吸检测。

- **Apple Watch 呼吸**：圆形图案吸气放大/呼气缩小 + 手腕触觉双通道；1–5 分钟可调，4–10 次/分可选。**视觉圆 + 触觉是最低成本的无外设引导。** https://support.apple.com/guide/watch/start-a-reflect-or-breathe-session-apd371dfe3d7/watchos
- **Breathwrk**：一个 pacing ball 起搏球 expand/contract，用户只跟球、不数数。https://www.breathwrk.com/
- **Calm / Headspace**：都**不把呼吸做成独立游戏**，而是氛围化引导嵌入冥想——**Pibo 的差异化机会 = 把呼吸游戏化 + 角色化**。
- **DEEP（VR，Pibo 最该抄的一档）**：**呼吸是唯一操控**——真实呼吸映射到水下 avatar 的上浮/下沉，在珊瑚礁间漂浮。https://safeinourworld.org/news/how-vr-breathing-game-deep-helps-with-sleep-anxiety-and-long-covid-by-joe-donnelly/ ——**「呼吸 → 角色动作」的直接映射比「跟着圆呼吸」更有游戏性**，正是拓麻歌子叙事想要的。

### 2.3 手机端无外设呼吸检测（硬证据，按精度/契合度排序）

| 通道 | 精度 | 姿势 | 结论 |
|---|---|---|---|
| **加速度计（手机贴胸口）** | 最高，Bland-Altman ±1.4 bpm，事件检测灵敏度 ~95% | 屏幕朝外贴胸、静坐 30s | **首选**——「把 Pibo 抱在胸口」是天然游戏动作。https://pmc.ncbi.nlm.nih.gov/articles/PMC9052820/ |
| **麦克风（呼气声）** | ~1 bpm 内约 87–90% | 对着手机长呼气 | 次选——呼气声比吸气响，正好强化「呼气更长」。对噪声/风敏感。https://www.sciencedirect.com/science/article/abs/pii/S1746809422007728 |
| **前摄 Vision（胸廓/头动光流）** | 可行，工程量最大 | 上半身入画、光照稳定 | 进阶/可选。https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6631485/ |

> **关键工程判断**：Apple / Breathwrk / Calm 主流 app **根本不检测，只做开环节拍引导**。**Pibo 的 MVP 完全可以先不检测**，用纯视觉节拍器 + 触觉，把检测留作后续「验证你真的在呼吸」的增强层。

### 2.4 给 Pibo 的呼吸游戏机制建议

- **机制 A「陪 Pibo 呼吸 · 花开花合」（MVP，开环，最低成本）**：头顶花随节拍吸 4s 绽放 / 呼 6s 收拢，Pibo 身体同步起伏。`SKAction.scale` 即可，无需检测。每完成一周期掉一片花瓣进花田（复用「能量收集」视觉），5 分钟 ≈ 30 周期 = 30 片。一局 = RCT 的「每天 5 分钟」剂量，算作**呼吸能量**喂头顶花。
- **机制 B「Pibo 漂浮 · 潜水上浮」（DEEP 式，可加检测）**：吸气 Pibo 上浮、呼气下沉，穿过光环。无检测版=光环时机即正确节拍；有检测版=加速度计抱胸 / 麦克风叹气驱动真·生物反馈。连续命中攒 combo，画面越来越亮。
- **机制 C「对 Pibo 叹一口气 · 呼气吹开迷雾」（麦克风，强化呼气更长）**：屏幕蒙雾（= Pibo 的 glitch/坏心情），长呼气吹散、Pibo 露笑；雾的透明度实时跟呼气声能量。**天然接 Pibo 的 glitch/发疯态恢复机制**（完成一个健康任务恢复）。证据锚 cyclic sighing。

**共通守则**：默认吸 4s / 呼 6s（≈6 次/分），可选 box 4-4-4-4；只加不减、正向反馈（攒花瓣/combo），对齐「不卖惨、傲娇」tone；MVP 先做开环机制 A，检测留后续。

---

## 3. 微运动 / exergame 类（步数驱动 + 姿态识别）

### 3.1 健康证据：这是继 walk doodle 之后证据最硬的品类

- **【硬证据 · 系统综述】Exercise snacks = 1–5 分钟碎片化运动**（如 3×20 秒爬楼、每 30 分钟 3 分钟活动 break），**精准匹配 Pibo 的即时反馈窗口**，持续改善餐后血糖、胰岛素、甘油三酯；分散式短时活动降餐后血糖甚至**优于连续 30 分钟**。2025 *Healthcare* 综述：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12732512/
- **【硬证据 · 队列】VILPA（融入日常的短促剧烈活动）：** Stamatakis et al. 2022 *Nature Medicine*（UK Biobank ~2.5 万不锻炼人群）——**每天仅 3–4 分钟即与全因/心血管/癌症死亡率大幅下降相关**，剂量-反应近线性：https://www.nature.com/articles/s41591-022-02100-x ；2023 *JAMA Oncology*：每天 3.4–3.6 分钟 VILPA 与总癌症发病降低 17–18% 相关：https://pmc.ncbi.nlm.nih.gov/articles/PMC10375384/
- **【硬证据】爬楼 snack**：每天 3×20 秒爬楼冲刺，6 周提升久坐成年人心肺适能：https://cdnsciencepub.com/doi/10.1139/apnm-2018-0675
- **表述边界**：VILPA 是**观察性关联非因果**，且验证的是「日常剧烈片段」不是游戏本身。文案说「每天几分钟剧烈活动与更低疾病风险相关」，**不说「玩这个游戏能防癌」**。另注：本轮一条「exercise snack 依从性 ≥80%」的断言未通过对抗验证（1-2）——**微运动有益是硬证据，但「用户会长期坚持玩」尚无强支撑**，需靠养成情感钩子 + gamification 补。

### 3.2 iOS 动作检测技术与先例（工程落地）

| 技术 | 关键点 | 适用性 |
|---|---|---|
| **Vision 2D `VNDetectHumanBodyPoseRequest`** | iOS 14+，19 个关节 2D 归一化坐标 + confidence；iPhone 12+ 单帧 ~8–15ms 可实时 | **离手玩**，需架机 + 退后 2–3m 全身入画。https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest |
| **Vision 3D `VNDetectHumanBodyPose3DRequest`** | iOS 17+，17 关节米制，不要求 LiDAR，单人 | 需深度判定（深蹲深度）时用，比 2D 重 |
| **ARKit body tracking** | 后置摄像头骨骼追踪 | ❌ 后摄=玩家看不到屏幕，不适合单人自玩 |
| **CoreMotion `CMMotionManager`** | 加速度/陀螺/attitude 最高 100Hz（WWDC23 批量传感器 200/800Hz）；`CMPedometer` 给步频/爬楼 | **零架机零场地，手持/贴身即玩**；能可靠计次/计节奏，但判不了姿态质量（可作弊）。https://developer.apple.com/videos/play/wwdc2023/10179/ |

**先例产品（产品观察）：**
- **Active Arcade (Nex)**：前摄全身追踪，手机靠椅子/墙即玩，15 合 1，播放超 1 亿次。**但公司已转向电视端 Nex Playground——信号：手机小屏 + 远距离站位体验天花板低。** https://apps.apple.com/us/app/active-arcade/id1553158383
- **Plaicise**：同类前摄 AR fitness，用户差评集中在**跳跃漏判、前摄启动失败**——摄像头方案的可靠性风险实证。https://get.plaicise.com/
- **【硬证据】Kaia Health Motion Coach**：JMIR 前瞻队列证明**普通手机单目摄像头做动作质量评估非劣于物理治疗师**（一致性 0.828 vs 治疗师互评 0.833）：https://pmc.ncbi.nlm.nih.gov/articles/PMC8317029/
- **7 Minute Workout（HICT，Klika & Jordan 2013）**：定时器 + 示范视频 + 打卡，**没有任何检测**——这一代产品的空白正是「app 不知道你有没有做」，**传感器验证 + 即时反馈是 Pibo 的差异点**。https://journals.lww.com/acsm-healthfitness/Fulltext/2013/05000/HIGH_INTENSITY_CIRCUIT_TRAINING_USING_BODY_WEIGHT_.5.aspx

> **主线判断**：对 Pibo「1–5 分钟顺手一局」的定位，**CoreMotion 是低风险主线**（零门槛、随时玩、只计次），**Vision 摄像头玩法是仪式感更强的进阶款**（体验上限高但有架机 + 光线准入成本）。

### 3.3 给 Pibo 的微运动游戏机制建议（按实现风险从低到高）

- **机制 A「摇花铃」— 手持深蹲/起立计数（CoreMotion，主推）**：双手把手机捧胸前当「花铃」，跟 Pibo 节拍深蹲；每次下-上行程铃响 + 花瓣迸发 + haptic，连击让头顶花越晃越亮。一局 60–90s，目标 15–25 次。技术：`CMMotionManager` deviceMotion ~50Hz，userAcceleration 垂直分量 + attitude pitch 双阈值状态机，0.8s 最小周期防抖。零架机、失败模式温和；可作弊但用「Pibo 只看花铃响不响」的傲娇文案消解、不做防作弊。
- **机制 B「原地踏步点灯」— 步频节奏（CMPedometer）**：手机拿手里/揣兜，原地踏步 2–3 分钟给萤火虫充电；步频达目标区间（~120 步/分，冲刺段 ~150）灯亮，掉出变暗。结束按点亮时长占比给 好/中/坏。**结束的步数被现有 HealthKit 观察管线自然收进当日数据——成果直接回流主循环**；与 walk doodle 形成「出门画画/在家踏步」互补。实现量最小。
- **机制 C「镜前接花瓣」— 前摄全身体感（Vision 2D，进阶款）**：手机靠墙立、人退后全身入画，Pibo 撒花瓣，玩家伸手/侧移/下蹲让**手腕关节点**碰目标；90s 一局，接住数=运动能量。**入口做架机引导页**（剪影对位 + 全身入画检测通过才开始，规避 Plaicise 式差评）。技术：`AVCaptureSession` 前摄 → Vision 每帧取 wrist/elbow/ankle → 坐标映射进现有 `SKScene` 碰撞。准入成本最高，作为列表第 2–3 款而非首发。

**共同反馈设计**：每 rep 一次 haptic + 音效（Kaia/Active Arcade 都强调逐动作即时反馈）；局末 10 秒内给「能量已收集」pop 接回现有 `EnergySproutFlow`；用 streak 而非排行榜（exercise-snack 文献指出依从性靠 gamification）。

---

## 4. 落地优先级建议（给 Features/Games 列表排期）

按「证据硬度 × 即时反馈 × 工程量 × Pibo 契合度」综合：

1. **P0 · 呼吸「花开花合」（机制 A，开环）** — 证据硬、工程最小、接 HRV/glitch 叙事、复用现有 SpriteKit 动画。**性价比最高的下一款。**
2. **P0 · 微运动「原地踏步点灯」或「摇花铃」（CoreMotion）** — 证据硬、成果回流运动能量、与 walk doodle 互补。二选一先做。
3. **P1 · 认知「记忆矩阵」** — 最易实现的认知游戏；**上线前先过一遍文案红线**（只说「练这个会更准」）。
4. **P1 · 呼吸「吹散迷雾」（麦克风）** — 作为 glitch 态恢复的解药之一，叙事钩子强。
5. **P2 · 双 n-back** — 认知硬核向，受众窄；难度自适应才能主张近迁移。
6. **P2 · 摄像头体感「镜前接花瓣」（Vision）** — 仪式感最强但准入成本高，做完架机引导页再上。

**每款游戏的通用要求**：可重复 + 难度自适应（认知类的近迁移前提）、局末接回现有能量收集 pop、正向反馈 streak、成果尽量回流 HealthKit/能量主循环。

---

## 5. 遗留问题（openQuestions）

- 拓麻歌子式养成的情感钩子能否弥补脑训练/微运动本身枯燥、坚持率低的短板？现有证据未覆盖游戏化/情感绑定对训练依从性的影响。
- 除代谢终点外，1–5 分钟微运动对「打发时间/情绪/即时精力」这类主观即时反馈是否有证据？本轮证据集中在餐后血糖等生理指标。
- 呼吸慢性效果（4–8 周）如何在养成节奏里体现，而非只做单次急性放松？

---

## 附录 · 核心来源清单

**认知训练（硬证据）**
- Simons 2016 PSPI 共识综述：https://journals.sagepub.com/doi/abs/10.1177/1529100616661983
- Melby-Lervåg 2016 元分析：https://pmc.ncbi.nlm.nih.gov/articles/PMC4968033/
- Sala 2019 二阶元分析：https://online.ucpress.edu/collabra/article/5/1/18/113004/Near-and-Far-Transfer-in-Cognitive-Training-A
- Li 2021 双 n-back RCT：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7862396/
- FTC v. Lumosity（文案红线）：https://www.ftc.gov/news-events/news/press-releases/2016/01/lumosity-pay-2-million-settle-ftc-deceptive-advertising-charges-its-brain-training-program
- Lumosity 玩法目录：https://www.lumosity.com/en/cognitive-games/
- Brain Workshop（GPL，仅机制参考）：https://brainworkshop.sourceforge.net/

**呼吸 / 正念（硬证据）**
- Balban 2023 五分钟呼吸 RCT（Cell Reports Medicine）：https://www.cell.com/cell-reports-medecine/fulltext/S2666-3791(22)00474-8
- 慢呼吸元分析（HR/BP）：https://pubmed.ncbi.nlm.nih.gov/28502461/
- 慢呼吸元分析（HRV/情绪）：https://link.springer.com/article/10.1007/s12671-023-02294-2
- Box vs 6/min RCT（PLOS One）：https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0336615
- 共振呼吸 RCT：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8924557/
- 麦克风呼吸检测：https://www.sciencedirect.com/science/article/abs/pii/S1746809422007728
- 加速度计胸廓呼吸：https://pmc.ncbi.nlm.nih.gov/articles/PMC9052820/
- 前摄/RGB 呼吸检测：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6631485/

**微运动 / exergame（硬证据 + 工程）**
- Exercise snacks 系统综述：https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12732512/
- VILPA 2022 Nature Medicine：https://www.nature.com/articles/s41591-022-02100-x
- VILPA 2023 JAMA Oncology：https://pmc.ncbi.nlm.nih.gov/articles/PMC10375384/
- 爬楼 snack（APNM 2019）：https://cdnsciencepub.com/doi/10.1139/apnm-2018-0675
- HICT 7分钟锻炼源论文：https://journals.lww.com/acsm-healthfitness/Fulltext/2013/05000/HIGH_INTENSITY_CIRCUIT_TRAINING_USING_BODY_WEIGHT_.5.aspx
- Kaia 单目 CV 动作评估（JMIR）：https://pmc.ncbi.nlm.nih.gov/articles/PMC8317029/
- Vision 2D 姿态：https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
- Vision 3D 姿态：https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest
- CoreMotion / WWDC23：https://developer.apple.com/videos/play/wwdc2023/10179/
- Active Arcade（先例）：https://apps.apple.com/us/app/active-arcade/id1553158383

**产品观察**
- Apple Watch 呼吸：https://support.apple.com/guide/watch/start-a-reflect-or-breathe-session-apd371dfe3d7/watchos
- Breathwrk：https://www.breathwrk.com/
- DEEP VR 呼吸游戏：https://safeinourworld.org/news/how-vr-breathing-game-deep-helps-with-sleep-anxiety-and-long-covid-by-joe-donnelly/
