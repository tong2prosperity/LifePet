# P0 首版改造工程状态

> 更新时间：2026-08-17  
> 用途：把已确认产品方案与当前代码改造状态对齐；后续继续开发先读本文件。  
> 结论：本轮无新增素材的 P0 代码改造已完成；`pibo-core 0.13.3` 已发布，iOS 已接入，HarmonyOS 已同步 submodule 与最小 ABI adapter。专门动作美术、成熟 `bo` 新手势、吊床首次试用动画和物理相机装置仍按确认范围延后。

## 一、已经落地并验证

### 1. 基础餐食相机前置

- iOS 基础相机只受 Release 开关控制，不再要求拥有补梦风铃；
- Walk Doodle 仍保留原有物件门控，本次没有顺带开放；
- 拍摄仍然是用户主动选择，不增加三餐任务或签到；
- 已更新 `HomeFeatureAccessTests`，无共同物件时基础相机仍可用。

### 2. 相机重新接回森林

- 抠图保存后先关闭相机并返回同一个森林，不再自动把用户困在耗时识别 Sheet；
- 食物以短时投影出现在 Pibo 侧前方，Pibo 显示一次“我看看。”；
- 热量识别在后台继续，用户可主动点击“查看估算”；
- 原始照片与展示图同时持久化；抠图失败时直接使用原图，不再丢失记录；
- 识别失败时保留照片，并可用同一张原图重新估算或选择重拍；
- 相机权限拒绝、设备不可用、启动／拍摄失败分别提供设置入口、说明或原地重试；
- 失败不改变 Pibo 主状态、不扣 `bo`、不伪造餐食记录；
- 已通过模拟器视觉走查和 `HomePhotoSaveCoordinatorTests`。

### 3. 第一枚 `bo` 与森林物件闭环

- 首页不再提供共同物件目录、进度窗口或左上角 `+` 入口；
- Core 顺序中的下一个未拥有物件直接以灰态进入森林，一次只显示一个；
- 点击灰态物件打开轻量 Half-sheet；第一项吊床显示当前余额、需要 1 `bo` 和 Pibo 获得的行为；
- 用“唤醒”替换商店式“购买／解锁”表达，但保留准确成本和不足原因；
- 唤醒后同一个森林节点由灰态变为正常状态，下一目标再进入森林；
- 用户仍需主动确认投入，关闭 Half-sheet 不会扣除 `bo`，不自动弹出独立结果页；
- 已通过 `HomePluckCoordinatorTests`、`OrnamentUnlockStoreTests` 和模拟器截图走查。

### 4. 六状态上下文动作与异常闭环

- 首页点击 Pibo 通过 Core 唯一映射执行 `checkConnection / letSleep / morningGreeting / checkIn / play / rest`；
- 只有 `stable / checkIn` 继续进入 Pat V2 的连续拍击逻辑；其余动作去重，健康状态变化会中断动作；
- `dataUnknown` 区分未授权、无可读数据、设备不可用和暂时同步中断，提供授权、设置或重试入口；
- 暂时中断且已有可信记录时保留上次可信状态，并在首页持续显示可点击提示；恢复后自动清除；
- Onboarding 流程未修改。

### 5. 真实 `bo` 连续生长

- 首页头顶生长值改为直接读取 `BoLedgerStore.growthProgress`；
- 四阶段直接读取 Core 的 `dormant / sprouting / forming / ripe`，平台不复制 50% 阈值；
- 现有 vector sprout mesh 已解除固定满尺寸，按持久化的 0...1 进度连续展开；
- 成熟 `bo` 的新拔取动作与手势本轮不改。

### 6. UI 与动效约束

- 使用现有 LP token、SpriteKit 与 SwiftUI motion stack，没有新增素材或第二套视觉系统；
- `.ui-craft/brief.md` 与 `.ui-craft/tokens.md` 记录首版目标用户、现有设计系统和视觉约束；
- 食物投影只做一次短促进入和七秒自动消退；Reduce Motion 下取消缩放弹性；
- SpriteKit 中的 Pibo、灰态目标和已拥有物件均提供 SwiftUI VoiceOver 镜像入口；
- 相机继续是首页右上角悬浮按钮，不制作森林物理装置。

### 7. HarmonyOS 食物相机完整闭环（2026-08-24）

- 拍照先作为草稿提交后台；只有 `is_food == true` 才算拍摄成功并写入正式历史。非食物不投影、
  不说话、不留历史；网络或模型失败保留同一张草稿供原图重试或重拍；
- 后台一次返回食物存在置信度、热量／营养估算和经过约束的 `pibo_observation`；缺失或不安全文案
  统一回退为“我先记下它的样子。”；
- 真食物通过本地分割生成带 7px 白边的透明贴纸，分割不可用时使用带白框原图；贴纸、识别结果和
  原图重试路径在一次历史写入中落盘；
- `observe_food` 先在 `pibo_design/observe-food-lab` 以左右镜像与 Reduce Motion 三种情形验证，
  再按同一 6080ms 时间轴接入 HarmonyOS。六个主状态共用一套 5vp 以内的观察侧移与回正，
  只按吊床构图切换贴纸侧边，不新增状态专用素材；
- 发布版历史页已恢复餐食记录卡，沿用现有 LP 卡片并加入早餐／午餐／晚餐协调色；点击按准确
  `photoId` 打开对应热量与营养详情，不再按餐次误取最新一张；
- `pibo-server c8ced72`、`pibo_design d5856e3`、`HarmonyPibo fffc023 / 9e2b6c5`
  已分别提交；HarmonyOS `entry + wearable` Debug HAP 和全部本地检查通过。当前没有连接中的
  HarmonyOS 设备，原生端真机视觉与真实相机／分割质量仍需发布前验收；
- TODO（iOS）：仅登记同一门控、贴纸投影、观察动作和精确历史详情，不在 HarmonyOS 优先阶段实现。

## 二、共享 Core 发布与双端接入

`/Users/trevorlink/Project/PiboWorld/pibo-core` 已发布 `0.13.3`：

1. 六状态唯一上下文动作：
   - `dataUnknown → checkConnection`
   - `sleeping → letSleep`
   - `waking → morningGreeting`
   - `stable → checkIn`
   - `energetic → play`
   - `tired → rest`
2. 只有 `stable / checkIn` 继续计入原有连续拍击生气逻辑；照料、问候、玩耍和连接检查不被解释成反复戳 Pibo；
3. `bo` 统一生长阶段：
   - `dormant`：无可见进度；
   - `sprouting`：大于 0 且小于 50%；
   - `forming`：达到 50% 但尚未成熟；
   - `ripe`：存在至少一枚真实可拔取 `bo`，优先于下一枚的分数进度。

Rust、C ABI、Swift wrapper、XCFramework 和边界测试已同步；`cargo test` 135 项、Swift Package 66 项全部通过。提交为 `56ca5e80fd519862b2df6241f1b7693374a4f7d0`，Tag `0.13.3` 已 Push。iOS exact pin 已更新到 `0.13.3`；HarmonyOS submodule 与 NAPI／ArkTS 最小 wrapper 已同步。

## 三、明确延后

1. Pibo 的专门动作素材与独立 `energetic`／`dataUnknown` 美术；当前代码使用现有状态资源与轻量程序性反馈；
2. 成熟 `bo` 的新拔取手势、动作和行为；
3. 吊床唤醒后 Pibo 当场跑去检查／首次使用的专门动作；自然睡眠已经按所有权选择吊床；
4. 森林中的物理相机装置；当前继续使用右上角悬浮按钮；
5. 补梦风铃的新价值、Walk Doodle 新位置、后续物件价格重算与 Shadow Pibo。

### 仍需要正式美术

- `energetic` 独立形象与循环动画；
- `dataUnknown` 非受苦、非稳定态的独立表现；
- 六个动作中没有现成资源的问候、玩耍、休息和检查反馈；
- `bo` 发芽／成形的连续可读形象。

正式资源进入 App 前仍需经过 `pibo-media` 审核、稳定 ID、iOS/Harmony 导出和运行时验证。

## 四、本轮验证记录

- `pibo-core`: `cargo fmt --check`、`cargo test`、`cargo build --release --no-default-features`、`./scripts/build-apple.sh`、`swift test` 均通过；
- iOS: Pibo Debug 模拟器完整构建与 `Pibo` 全量测试套件均通过；
- iOS 针对性测试：上下文动作、相机保存、功能门控、首页展示策略、拔取顺序、共同物件库存均通过；
- iPhone 17 模拟器已视觉检查右上角相机、单一灰态吊床目标与检视 Half-sheet；
- HarmonyOS: `tools/test_pibo_core.mjs` 通过，`entry + wearable` Debug HAP 完整构建成功；
- 现存 Xcode 并发隔离警告和 App/Extension build number 警告不是本轮新增，未在本轮扩张修复范围。

## 五、尚未声称完成

- 无新增素材范围内的 iOS P0 代码已完成；专门角色动作／资源动画仍待美术与动作设计；
- HarmonyOS 本轮只同步 Core、NAPI 和 ArkTS adapter，没有实现与 iOS 相同的平台 UI 表现；
- 本轮测试没有替代真实 HealthKit 跨日、相机真机、后台识别和权限拒绝验收；
- Shadow Pibo、Walk Doodle 新位置、补梦风铃新价值和后续物件成本仍按既定顺序留到 P0 之后。
