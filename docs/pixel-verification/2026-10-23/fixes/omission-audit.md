# 像素迁移遗漏复核（2026-10-23）

用户要求在运动旧弹窗修复之后继续检查类似遗漏。本轮按批准决定、正式 Core 0.34.4、
Harmony-first 记录与实际调用入口核对，修正下列仍能影响当前功能的旧接线。
本轮没有新增 Core 阈值、服务端合同、付费能力或健康记录写入。

## 发现与修复

| 范围 | 遗漏与现在的行为 | 主要实现 |
| --- | --- | --- |
| 运动回应 | 去掉旧五分钟入队限制，改用已发布 Core 同日／观测开始合同；引导前、跨日、未来记录不回应。恢复也检查观测边界；批量旧事件不能覆盖更新的待回应事件。显式 DEBUG 模拟仍可演练，不写 HealthKit。 | `PiboCoreWorkoutAdapter`、`PetStateStore`、`PiboApp` |
| HRV 提醒 | 从旧分级升级策略改为决定 055 的 Core 变化提醒：每天偏低一次、当天恢复一次、偏高不推；新安装默认关闭，原开关和有效发送检查点保留。逐条测量通知只在 DEBUG 开发入口，正式设置不展示。回到 App 重读系统提醒状态，静默授权不冒充横幅可用。 | `StressChangeAlertStore`、`StressNotifier`、`SettingsView` |
| bo 系统通知（双端） | 第一枚与前台成熟仅在森林反馈；后续后台成熟只使用已有权限，不申请权限；成熟周期去重，收取／回前台会撤掉通知并使等待中的发布失效。iOS 同时移除历史 first-ripe 路径。 | 双端 `BoMaturityNotifier`、iOS `WorkoutCompletionNotifier`、Harmony `Index`／`BoLedgerStore` |
| 首日授权提示 | 主动双击 Pibo 且确实缺健康授权时，首日可先播放对应台词，再显示一次授权说明；每日限制、前后台及其他弹层检查仍有效。其他数据缺失提示保留首日保护。 | `HealthRecoveryPromptStore`、`HomeStageInteractions` |
| 陪伴天数 | 内容预算与解锁层级统一读取身份相识日，避免与时间线使用不同起点。 | `HomeCompanionController` |
| 成熟 bo 引导 | HUD 金色成熟标记、清楚的 bo 余额、成熟时“▲ 上拉收取”；拉动、对白、角色隐藏时提示让位。装饰页解释余额来源；引导不再把基础睡眠回顾描述为吊床解锁能力。 | `GrowthHud`、`PixelStageView`、`GrowthSheets`、`DailyOnboardingView` |
| 桌面组件 | 缺失指标只在显示时回退为 0，并显示等待同步；不写成健康事实。真实零值保留，过日清掉旧日读数，角色元数据更新不覆盖最后健康更新时间。 | `PiboWidgetSnapshot`、`PetStateWidgetBridge`、`PiboWidgets` |
| 已退役入口 | 关闭遗留临时合作引导 DEBUG 旁路；不再通过旧参数打开。 | `PiboReleaseScope` |
| 旧 UI 残留 | 授权说明、历史页关闭／分享／今天按钮、空身体指标和卡片外框改为现有像素组件；正文继续保证可读性。44 点分享／关闭按钮重新预留间距并对齐。 | `HealthDataStatusSheet`、`HistoryScreen`、`PiboHistoryView`、`HistoryCard`／`HistoryVitalsCard` |

## 复核后未发现新增问题的范围

- 睡眠回顾及提醒读取基础能力，不受吊床购买／放置门控；已有自动化覆盖。
- 当前发布入口没有恢复 Studio、Gym、旧二楼、小游戏、会员购买或 Shadow 入口。
- 食物相机仍依赖服务端 `is_food` 成功确认；失败不新增合成健康记录或奖励。
- 角色显示、拍一拍、组件和手表身份恢复的既有用例通过；本轮未改像素金值。
- 不把历史文档的“iOS 待补齐”文字直接当成运行缺陷，检查实际调用与决定是否已经覆盖。

## 验证

- iOS 全量 swift-testing：**485 项，93 个 suite 全部通过**，iPhone 17／iOS 26.5 Simulator。
  日志 `/tmp/pibo-omission-complete-tests.log`。
- 新回归覆盖运动同日／观测边界、首日授权一次、通知偏好迁移／每日策略／无权限／异步取消、
  成熟提示对拉动／对白／角色隐藏让位、组件真实零值与健康时间保存。
- 全量测试后只调整历史页两处按钮间距；最终 Debug 与 Release 模拟器构建通过。
  日志 `/tmp/pibo-omission-layout-build.log`、`/tmp/pibo-omission-layout-release.log`。
- Harmony：生产平台通知测试通过，`node tools/run_all_checks.mjs` **123 条检查全部通过**；
  default 产品 Debug HAP（手机／手表）构建通过。
  日志 `/tmp/harmony-omission-checks.log`、`/tmp/harmony-omission-build.log`。
- Harmony 本轮限定文件本地提交：`3c93c9c`（`fix: suppress duplicate bo maturity reminders`），未推送。
  交接记录：`HarmonyPibo/docs/harmony-first/2026-10-23-bo成熟提醒遗漏复核.md`。
- `git diff --check` 双端通过；没有纳入两端工作区既有无关修改。

## 页面证据与验收边界

已查看最终模拟器截图：[历史页](omission-audit/history.png)、[授权说明](omission-audit/health.png)、
[装饰页](omission-audit/decor.png)、[设置页](omission-audit/settings.png)。
截图通过 DEBUG 直达入口打开真实页面，不申请健康权限或构造健康样本。
成熟手势提示由实际 renderer 回归测试验证，未把临时成熟值写入真实账本。

本轮没有完成双端真机的后台通知中心验收、iOS 桌面系统刷新、真实成熟收取或真机音频／触觉测试。
编译仍有仓库既有并发隔离等告警；构建成功不等于这些告警已清零。
音频冷启动和运动弹窗的前轮证据分别见 [音频](audio-cold-start.md) 与 [运动回应](workout-forest-response.md)。
