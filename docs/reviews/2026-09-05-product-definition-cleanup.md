# Pibo 定义简化与旧文档删除清单（已执行）

日期：2026-09-05。状态：用户已批准 A＋B，现已执行文档清理。代码与资产保持不变。

## 已确认的新方向

> Pibo 是一款以真实健康数据喂养的电子宠物 App。用户的睡眠与活动影响它的状态和成长；它与用户共同生活，逐渐形成习惯、记忆和关系，并用可理解的表情、行动与简短表达关心用户。

产品体验优先于世界观解释。异世界身份提供性格和惊喜，不能否定养宠；健康映射要直观，不必逐项机械同步。成长既包括能力变化，也包括关系变化。表达可以明显、鲜活、有趣，不用低幅动作证明自尊。

“健康数据是喂食”是产品表达，不意味着新增饥饿条、照片发放 bo、改变 Core 阈值、把缺失数据判为不健康，或重新开放死亡/权限惩罚。新的具体数值、健康影响程度、盈利价格与付费范围仍需单独确定；保留当前有效商业边界。

## A. 已整份删除：18 份

下表逐一列出删除对象；不是目录递归删除。删除前先迁移仍有效的独有内容，并改完所有保留文件的引用。

| ID | 文件 | 删除理由 | 保留内容的去向 |
|---|---|---|---|
| A01 | `docs/narrative-rebuild/decisions/001-Pibo角色关系模型.md` | 整篇以“绝对不是被照顾者、不承担喂养、数据不能成为饲料”为基础，与本次确认直接冲突。 | 新的一页产品定义；其中不以死亡、权限和负罪感逼迫用户的边界迁入现行边界。 |
| A02 | `docs/narrative-rebuild/decisions/027-低健康积累对Pibo的影响.md` | 文件自己已声明旧正文不再完整生效，却仍保留绝对“不虚弱、不受苦”的长篇规则。 | 把开头的现行未决边界、数据缺失不等于低健康、不可自行增加惩罚规则并入产品定义；不把删除理解为批准伤害机制。 |
| A03 | `docs/narrative-rebuild/drafts/Pibo基础逻辑宪章-v0.1.md` | 未拍板草稿；关系基础排除养宠。 | 新产品定义与精简后的决定 002。 |
| A04 | `docs/narrative-rebuild/drafts/Pibo基础逻辑宪章-v0.2.md` | 旧宪章的第二份重复草稿，仍排除被照顾者。 | 新产品定义与精简后的决定 002。 |
| A05 | `docs/narrative-rebuild/drafts/Pibo故事基础圣经-v0.1.md` | 三套未批准竞争世界观，含把养宠视为风险的旧前提。 | 已批准的世界设定继续保留在 003–011；本轮不删除世界观本身。 |
| A06 | `docs/narrative-rebuild/drafts/Pibo故事基础圣经-v0.2.md` | 旧决定合并副本，重复非宠物定义、拔取入库和旧阶段约束。 | 保留独立世界设定与最新版故事大纲；提取独有且仍有效的内容后删除。 |
| A07 | `docs/narrative-rebuild/03-基础逻辑批次问卷.md` | 以“绝不是被照顾者”为已拍板前提的旧问题集。 | 本次明确方向已经回答关系问题。 |
| A08 | `docs/narrative-rebuild/06-Pibo人物基础批次提案.md` | 已结束的三选一人物提案；重复“不喜欢被当宠物、非宠物主体性”。 | 精简后的决定 005。 |
| A09 | `docs/narrative-rebuild/07-相遇与连接规则批次提案.md` | 混合竞争模型、撤回的归航芽解释和旧拔取/库存模型。 | 决定 006 保留故事窗口设定；现行 bo 合同归 031/046。 |
| A10 | `docs/narrative-rebuild/08-一年主线骨架批次提案.md` | 旧提案要求首阶段让用户理解“Pibo 不是宠物”。 | 保留已批准故事材料，退出产品定义入口。 |
| A11 | `docs/narrative-rebuild/13-二十一个主线事件-v0.1.md` | 已被 v0.2、v0.3 修订的最早大纲。 | 保留 16-二十一个主线事件-v0.3.md 作为故事材料。 |
| A12 | `docs/narrative-rebuild/15-二十一个主线事件-v0.2.md` | 已有 v0.3，不再并列维护三份主线大纲。 | 保留 v0.3，清除其中被后续规则推翻的产品断言。 |
| A13 | `docs/narrative-rebuild/20-Onboarding叙事流程-v0.1.md` | 旧骨架包含非宠物目标，已有逐屏稿、最终文案和跨平台规格。 | 先把仍有效的流程要求合入 23，最终文案 22 保留。 |
| A14 | `docs/narrative-rebuild/21-Onboarding逐屏方案-v0.2.md` | 工作台词明确由 22 替代；与 23 的流程重复。 | 独有画面/资产要求先合入 23；保留 22 的文案。 |
| A15 | `docs/narrative-rebuild/collaboration/README.md` | 声称只读此页即可了解当前方向，却定义“不是需要照顾的电子宠物”。 | 新的一页产品定义、docs/README 和精简后的 HANDOFF 取代此重复简报。 |
| A16 | `docs/narrative-rebuild/process/2026-07-23-共同经历模型.md` | 候选模型明确规定健康数据不决定 Pibo 健康、不能成为饲料。 | 养成与关系成长的新定义；不把该模型继续保留为另一套产品原则。 |
| A17 | `docs/narrative-rebuild/process/2026-07-23-共同经历概念纠偏.md` | 依赖已否定的共同经历模型，规定没有一方负责饲养；讨论尚未拍板。 | 保留“不假装知道未采集的生活事实”的要求到现行定义，删除旧推导。 |
| A18 | `product-web-prototype/pibo-home-features-spec.md` | 魔丸人格、拔毛、数据二楼、旧拍击次数和旧台词池；已被当前森林/六状态/双击/直接投入替代。 | 当前产品定义、05 工程状态和现行功能决定；HTML 原型文件不在删除范围。 |

## B. 保留文件，删除过时段落并简化

这些不是整份删除。清理范围限于表中内容；不全面重写工程合同或覆盖现有未提交修改。

| ID | 文件 | 定位 | 拟删改内容 |
|---|---|---|---|
| B01 | [README.md](/Users/trevorlink/Project/hackathon/Pibo/README.md) | 开头定义、核心玩法、状态表、主页交互、寿命、文案语气、旧路线图与工程结构 | 删除吸能量、养不好发疯/生病/离去、魔丸→傲娇、拔毛、数据二楼、iOS-only 与 Watch 全废弃等旧叙述；保留并校正构建入口。 |
| B02 | [CLAUDE.md](/Users/trevorlink/Project/hackathon/Pibo/CLAUDE.md) | Project Goal、角色定义与叙事指导、过期主页/门控/工程快照 | 删除“不是宠物或被照顾者”和旧阶段限制；改为引用统一产品定义及 AGENTS。保留 HealthKit ambiguous asleep 映射、睡眠投递、Core 发布与并发等独有工程约束。 |
| B03 | [AGENTS.md](/Users/trevorlink/Project/hackathon/Pibo/AGENTS.md) | Product & Architecture Notes 中角色、叙事真源与未决物件描述 | 用新定义替换绕行式身份限定；删除空 docs/narrative 真源引用；将已由 046 解决的风铃价值/后续成本未决描述同步为当前规则。其余工程约束保留。 |
| B04 | [docs/README.md](/Users/trevorlink/Project/hackathon/Pibo/docs/README.md) | 开头、叙事入口、games 与健康数据目录描述 | 移除旧 prototype 作为主页机制入口、三维能量及“游戏场”当前页面暗示；建立产品定义/工程状态/故事素材三条入口。 |
| B05 | [docs/narrative-rebuild/README.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/README.md) | 当前阶段、重复索引、与现有叙事文档关系、推进顺序 | 删除“独立重构线尚未迁移”“docs/narrative 仍是真源”和必须先完成哲学/故事推演的入口顺序；删除本清单文件链接。 |
| B06 | [docs/narrative-rebuild/decisions/README.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/README.md) | 001/027/032/034 等摘要与分组 | 移除被删除决定；将故事与小说决定从当前产品规则列表中分开；当前关系只指向新定义。 |
| B07 | [docs/narrative-rebuild/HANDOFF.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/HANDOFF.md) | 当前入口及全部历史检查点 | 缩短为当前入口、确实未决项和工程状态链接；删除旧日期检查点正文，避免重复保留旧拔取、门控、iOS TODO、受苦和关系纠偏的多套结论。独有仍有效约束先迁入对应规格。 |
| B08 | [docs/narrative-rebuild/decisions/002-Pibo基础逻辑宪章.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/002-Pibo%E5%9F%BA%E7%A1%80%E9%80%BB%E8%BE%91%E5%AE%AA%E7%AB%A0.md) | Pibo 的角色、故事形态、健康能量、伦理约束 | 删除非被照顾者、MVP 以解锁观看为主、健康只推进故事、避免饲养责任等定义；把原理压缩并引用统一产品定义。医学事实、真实数据与权限边界保留。 |
| B09 | [docs/narrative-rebuild/decisions/005-Pibo人物基础.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/005-Pibo%E4%BA%BA%E7%89%A9%E5%9F%BA%E7%A1%80.md) | 恒定性格、表达方式、主体性约束 | 删除“不喜欢被当作宠物”和把宠物化/等待喂养等同于失去主体性的规定；保留认真、好奇、自尊及故事身份；明确表情与肢体可以鲜活外放。 |
| B10 | [docs/narrative-rebuild/decisions/006-App窗口与偶然相遇.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/006-App%E7%AA%97%E5%8F%A3%E4%B8%8E%E5%81%B6%E7%84%B6%E7%9B%B8%E9%81%87.md) | App 与主页世界的定位 | 删除“不是电子宠物房”的排斥表述；窗口模型只解释故事，不限制用户养成与空间表达。 |
| B11 | [docs/narrative-rebuild/decisions/034-Pibo恒定说话风格与中文首发.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/034-Pibo%E6%81%92%E5%AE%9A%E8%AF%B4%E8%AF%9D%E9%A3%8E%E6%A0%BC%E4%B8%8E%E4%B8%AD%E6%96%87%E9%A6%96%E5%8F%91.md) | 决定内容、语气量表、中文规则 5/7、过期平台状态 | 删除情绪外放 2/10、温度 4/10 等过度限幅指标及禁止表达正向喜悦/直接关心的绝对说法；保留简短易懂、具体关心、无医疗结论与中文范围；不要把新定义变成全面重写生产台词的授权。 |
| B12 | [docs/pibo-context-animation-integration.md](/Users/trevorlink/Project/hackathon/Pibo/docs/pibo-context-animation-integration.md) | 文案禁用总表及过期动作/平台状态段 | 删除“夸奖、卖萌、喂养”一概禁用；将旧上下文策略降为历史实现说明或删除已替代正文；保留仍有效的渲染、路径与数据合同。 |
| B13 | [docs/narrative-rebuild/decisions/032-物件硬解锁功能与主页发现.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/032-%E7%89%A9%E4%BB%B6%E7%A1%AC%E8%A7%A3%E9%94%81%E5%8A%9F%E8%83%BD%E4%B8%8E%E4%B8%BB%E9%A1%B5%E5%8F%91%E7%8E%B0.md) | 旧修订链、能力映射、门控和完成反馈 | 删除风铃门控 Walk Doodle、已被 046 替代的物件映射和独立解锁结果页；只保留未被替代的能力原则，引用 043/046。 |
| B14 | [docs/narrative-rebuild/decisions/025-餐食相机与初版功能范围.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/025-%E9%A4%90%E9%A3%9F%E7%9B%B8%E6%9C%BA%E4%B8%8E%E5%88%9D%E7%89%88%E5%8A%9F%E8%83%BD%E8%8C%83%E5%9B%B4.md) | 旧极简 MVP 排除范围 | 移除餐食相机/Walk Doodle 尚未进入当前功能的旧断言；保留餐食命名与识别边界，按 05 对齐。 |
| B15 | [docs/narrative-rebuild/decisions/033-Pibo情境闲聊与拍一拍调度机制.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/033-Pibo%E6%83%85%E5%A2%83%E9%97%B2%E8%81%8A%E4%B8%8E%E6%8B%8D%E4%B8%80%E6%8B%8D%E8%B0%83%E5%BA%A6%E6%9C%BA%E5%88%B6.md) | 旧平台 TODO 与冷却内无反馈条款 | 删除已由 044 替代的整次交互无反馈；保留当前文本调度合同。 |
| B16 | [docs/narrative-rebuild/decisions/046-共同物件渐进解锁、能力与发现反馈.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/046-%E5%85%B1%E5%90%8C%E7%89%A9%E4%BB%B6%E6%B8%90%E8%BF%9B%E8%A7%A3%E9%94%81%E3%80%81%E8%83%BD%E5%8A%9B%E4%B8%8E%E5%8F%91%E7%8E%B0%E5%8F%8D%E9%A6%88.md) | 文件头 iOS 待对齐状态 | 与 05 最新检查点核对后删除过期 TODO；价格、成长链和能力合同不改变。 |
| B17 | [docs/narrative-rebuild/28-Pibo当前实现现状、产品目标与问题审计-v0.1.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/28-Pibo%E5%BD%93%E5%89%8D%E5%AE%9E%E7%8E%B0%E7%8E%B0%E7%8A%B6%E3%80%81%E4%BA%A7%E5%93%81%E7%9B%AE%E6%A0%87%E4%B8%8E%E9%97%AE%E9%A2%98%E5%AE%A1%E8%AE%A1-v0.1.md) | 旧实现全景、目标冲突、待拍板、排查与权威入口 | 删除已解决的镜子还是宠物争论、过期拔取/门控/energetic 回退和工程 TODO；只保留尚未解决的体验问题与验证建议，工程现状统一链接 05。 |
| B18 | [docs/narrative-rebuild/23-Onboarding与事件01-03跨平台MVP规格-v0.1.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/23-Onboarding%E4%B8%8E%E4%BA%8B%E4%BB%B601-03%E8%B7%A8%E5%B9%B3%E5%8F%B0MVP%E8%A7%84%E6%A0%BC-v0.1.md) | 目标定义、旧拔取/账本假设与来源链接 | 替换非养宠目标，合入 20/21 独有有效流程；第一枚真实 bo、恢复、权限、数据幂等与 checkpoint 约束保留。本轮不改 App 流程。 |
| B19 | [docs/narrative-rebuild/16-二十一个主线事件-v0.3.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/16-%E4%BA%8C%E5%8D%81%E4%B8%80%E4%B8%AA%E4%B8%BB%E7%BA%BF%E4%BA%8B%E4%BB%B6-v0.3.md) | 与当前产品冲突的规则断言及否认关心表述 | 保留故事正文；删除“尚不承认关心”的硬性角色要求和旧产品门控/拔取断言，标明故事扩展素材不支配核心养成。 |
| B20 | [docs/narrative-rebuild/decisions/015-二十一个主线事件与动态空间规则.md](/Users/trevorlink/Project/hackathon/Pibo/docs/narrative-rebuild/decisions/015-%E4%BA%8C%E5%8D%81%E4%B8%80%E4%B8%AA%E4%B8%BB%E7%BA%BF%E4%BA%8B%E4%BB%B6%E4%B8%8E%E5%8A%A8%E6%80%81%E7%A9%BA%E9%97%B4%E8%A7%84%E5%88%99.md) | 事件 06 与被新产品决定替代的功能/物件规则 | 与 16 同步删除过时产品断言，保留故事素材，不借清理批准或取消一年返航结局。 |
| B21 | [docs/product-strategy-202608/00-Turnaround-Master-Plan.md](/Users/trevorlink/Project/hackathon/Pibo/docs/product-strategy-202608/00-Turnaround-Master-Plan.md) | 产品定义、旧阶段边界、后续未决 | 引用新统一定义，删除已解决的成本/风铃未决与旧拔取术语；区分 Shadow 已实现与尚有发布门槛。 |
| B22 | [docs/product-strategy-202608/01-Deep-Dive-Bo-and-Identity.md](/Users/trevorlink/Project/hackathon/Pibo/docs/product-strategy-202608/01-Deep-Dive-Bo-and-Identity.md) | 产品身份与物件/Shadow 旧范围 | 删除成熟 bo 拔取、飞入容器和库存展示章节，引用现行 03 直接投入方案；与新定义及 043/046 对齐，移除旧成本与未实现好友的断言。 |
| B23 | [docs/product-strategy-202608/02-Contextual-Actions-Design.md](/Users/trevorlink/Project/hackathon/Pibo/docs/product-strategy-202608/02-Contextual-Actions-Design.md) | 动作表现边界与旧平台状态 | 允许直观、有趣、可读的表情/肢体；保留互动不伪造健康恢复、睡眠保护及六状态合同。保留已有未提交动画更新。 |
| B24 | [docs/product-strategy-202608/04-Day-1-Journey-and-Item-Inspection.md](/Users/trevorlink/Project/hackathon/Pibo/docs/product-strategy-202608/04-Day-1-Journey-and-Item-Inspection.md) | 旧拔取/物件成本/门控描述 | 以真实事件和当前直接投入替换过期流程，不改成固定日期成熟承诺。 |
| B25 | [docs/product-strategy-202608/05-P0-Implementation-Status.md](/Users/trevorlink/Project/hackathon/Pibo/docs/product-strategy-202608/05-P0-Implementation-Status.md) | 相机章节 2 与后续 is_food 合同矛盾、末尾 iOS 046 待对齐、旧版本混杂 | 合并为当前事实；删除先投影后确认食物的旧流程和已关闭 TODO；保留发布前真机验收门槛及已有未提交内容。 |
| B26 | [product-web-prototype/README.md](/Users/trevorlink/Project/hackathon/Pibo/product-web-prototype/README.md) | LifePet 命名与原型用途 | 仅保留“历史 HTML 原型，不是当前规则”的简短说明；不删除 HTML。 |
| B27 | [数值系统-开发方案.md](/Users/trevorlink/Project/hackathon/Pibo/%E6%95%B0%E5%80%BC%E7%B3%BB%E7%BB%9F-%E5%BC%80%E5%8F%91%E6%96%B9%E6%A1%88.md) | 文档状态及过期中心化计算/拔取/价目开发指令 | 不整篇删除账本设计；删除作为当前开发方案的指令性入口，仍有效账本约束归 Core/当前接口文档。 |
| B28 | [bo-经济后端架构设计.md](/Users/trevorlink/Project/hackathon/Pibo/bo-%E7%BB%8F%E6%B5%8E%E5%90%8E%E7%AB%AF%E6%9E%B6%E6%9E%84%E8%AE%BE%E8%AE%A1.md) | 决策摘要与贯穿原则 | 删除必须登录、服务端权威计算 bo、服务端驱动动画、固定服务端日界等过时当前指令；保留有价值的幂等与后端结构说明，引用 031/Core。 |

## C. 保留，不随本批删除

- 故乡、取火者、失忆、引路者等世界观（决定 003–011 中除明确列为局部修订者外），最新主线 v0.3、事件深化、Onboarding 最终文案 22、小说正文及小说决定 035–042。它们移出产品必读入口，但本次方向确认没有取消这些创作资产或批准改写返航终局。
- 决定 028 的现行付费分账/基本社交/购买资产保护；031 的真实数据、Core 单一规则源与幂等；043–046 的好友隐私、双击反馈、准备度、物件能力合同。局部过期状态按 B 表处理。
- 所有 Swift / ArkTS / Rust、测试、媒体、JSONL 生产台词、原型 HTML、数值表、代码迁移记录以及本轮动画预览。
- research/、methods/、其余 process/ 是创作素材或论证记录，不因日期旧一律删除；从当前产品规则入口移开。以后若要做纯历史资料瘦身，另列精确清单。
- legacy_docs/ 下发现 27 个忽略追踪的文档/脚本/截图，其中包括旧软件手册和世界观 DOCX/PDF/Pages。本轮未逐份审阅，不纳入删除，也不假设可由 Git 恢复。docs/narrative/ 当前为空目录；删除错误的真源引用即可。

## D. 新的最小文档结构

1. 新增 docs/PRODUCT.md：一页产品定义、健康→状态/成长→互动→关系循环、角色表达原则与当前边界。这是产品/设计/动画的唯一总入口。
2. docs/product-strategy-202608/05-P0-Implementation-Status.md：仅描述当前工程现状、未完成项和验证边界。
3. decisions/：保留详细功能合同；区分产品规则与故事/小说素材，清掉已被替代的旧正文。
4. README / AGENTS / CLAUDE / docs/README / HANDOFF 只作必要摘要和指路，避免重新复制五套角色定义。

## E. 执行与验收范围

- 用户已批准执行 A 和 B；新增统一产品定义，完成精确删除与引用修复。
- 清理前复核工作树与清单哈希；若目标有新修改，先合并核对，不能用旧快照覆盖。
- A 中仍有效的反强迫、未知数据、权限与恢复要求必须先保留到新定义或有效规格；删除旧文件不是批准相反规则。
- 更新保留 Markdown 对 A 的直接链接、URL 编码链接和路径引用；需要历史缘由时只留简短替代说明，不复制被淘汰全文。
- 原型 README 保留历史用途，不让旧 HTML 内容进入当前规则。
- 验收：目标文件数量准确；保留入口无互相冲突的角色定义；相机成功、双击、Core、当前成本与免费能力合同一致；无新断链；现有未提交内容保留。不修改运行时，无需重跑 App 全套测试。

## 审查边界

主审范围是此 iOS 仓库的当前入口、叙事决策、产品策略和相关旧规格。另对 HarmonyPibo、pibo-core、pibo_design、pibo-media 的根入口做了关键词抽查，未发现同样明确的“不是宠物”定义；这不等于完成兄弟仓库全文审计，也不授权删除它们的文件。

## 执行补充

2026-09-05：18 份文档已删除，28 份指定文档已修订，并修复保留文档对删除对象的引用。关于 iOS 046，工作树已有回声代码，但不足以证明全部表现验收；因此保留逐项核验门槛，未机械删除真实 TODO。审查表记录原提案，当前规则只见 PRODUCT。

## 最终验证

- 删除集合与批准 A 表完全相同：18 份。
- B 表 28 份均已修订；另有 2 份保留文档仅修复指向已删除资料的链接。
- 相对清理前没有新增 Markdown 文件断链；`git diff --check` 通过。
- 所有快照中的非文档文件保持哈希不变，既有动画文档增量保留；CLAUDE 的关键 ambiguous asleep 映射说明逐字保留。
- 未运行 App 构建或测试，本轮只改变文档。
