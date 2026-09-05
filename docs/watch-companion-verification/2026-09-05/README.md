# Pibo Apple Watch 实施验收 · 2026-09-05

本轮按用户要求移除呼吸训练，把手表收敛为同一只 Pibo 的腕上陪伴。本轮未发布商店版本。

## 已交付

- 删除 CRC 入口、时长选择、训练与报告、传感器采集、训练/正念写入以及后台训练配置；保留既有健康历史。
- 身体双击执行 iPhone/Core 选好的短动作和触觉。单击不触发，不推进文案、健康主状态或 bo。减少动态效果时只保留静态回应与触觉。
- 头顶 bo 与说明使用真实账本的连续进度、阶段和成熟数量；详情显示已获得的共同能力。活动数字移入详情，手表健康读取由用户主动触发。
- 身份、成长和关系与当天活动事实分开缓存；跨日只清除今日活动展示。暂时 dataUnknown 保留同一只 Pibo 最近可信表现及其原时间，新宠物不继承旧状态。
- Shadow 暂停或离线保留最后有效映照，不暗示在线；隐藏、退出账号、解除关系和切换账号仍能撤下相应投影。自有健康、成长和能力不会进入好友公开载荷。
- 接收快照先校验、合并再持久化，拒绝乱序和无效数据；WCSession 激活后补发/请求，回前台先处理跨日再发布。

## 构建与测试

| 验证 | 结果 |
| --- | --- |
| Pibo iOS Simulator Debug 构建 | 通过，包含 watch 和 widget 依赖 |
| Pibo 全量测试，iPhone 17 / iOS 26.5 | 444 项通过，含参数化共 446 次运行，0 失败、0 跳过 |
| watchOS Simulator Debug / Release | 通过 |
| watchOS 真机架构 Release，关闭代码签名 | 通过；不等同于真机运行验收 |
| Debug / Release 最终 Info.plist | 仅保留活动读取说明；无健康写入说明、运动传感器说明、workout-processing 或 UIBackgroundModes |
| `git diff --check` | 通过 |

新增缓存回归覆盖跨日重载、未知状态与原时间保留、新宠物隔离、暂停保留、坏/旧好友 revision、隐藏/解除、账号/关系切换、乱序/未来时间/非有限进度、站立分钟精度和好友载荷隔离。全量运行时还补齐了既有 `HomeIdleSpeechContextResolverTests` 对已发布 energetic 动画的期望，业务映射保持不变。

Core 继续固定在已发布的 `0.18.1`，没有加入手表本地健康阈值或更改 SDK。

本次执行命令（本地构建均加 `-disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO`）：

```sh
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project Pibo.xcodeproj -scheme Pibo -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild -project Pibo.xcodeproj -scheme 'Pibo Watch App' -configuration Debug -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project Pibo.xcodeproj -scheme 'Pibo Watch App' -configuration Release -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project Pibo.xcodeproj -scheme 'Pibo Watch App' -configuration Release -destination 'generic/platform=watchOS' build
```

## 实际界面走查

除 Release 首次连接外，下列有数据页面使用显式 `-PiboWatchPreview` 内存预览。预览不会写入 HealthKit、账本、持久缓存或后端；Release 不包含此入口。它们证明布局和交互，不代表已完成真实手机/手表同步。

| 场景 | 观察与证据 |
| --- | --- |
| 46mm 首页，fresh | Pibo、双击提示、状态时间完整可见。[截图](01-home-46mm.png) |
| 真实成长/能力的显示布局，fresh | 0.64 预览进度与成长说明；详情显示吊床能力。[成长](02-growth-46mm.png)、[同步](03-sync-details-46mm.png)、[能力](04-capabilities-46mm.png) |
| 跨日，cached | 显示两天前的时间，保持 Pibo 与成长。[截图](05-cached-home-46mm.png) |
| 暂停好友，cached | 保留小岚最后映照，并写明暂停与更新时间。[截图](06-paused-shadow-46mm.png) |
| 跨日活动，cached | 过期活动数字撤下，显示尚未同步，不显示零分或健康惩罚。[截图](07-expired-daily-activity-46mm.png) |
| 40mm 无健康数据，unknown | 中性 Pibo、没有假 bo，状态与双击提示在首屏可见。[截图](08-unknown-home-40mm.png) |
| 40mm 身体单击/双击，unknown | 单击没有回应环；双击立即回应，再次双击可再次触发。[回应帧](09-double-tap-response-40mm.png)、[原始录屏](09-double-tap-40mm.mp4) |
| 40mm 成熟 bo，ripe | 显示成熟叶形与 1 枚 bo，下一步提示在手机森林投入共同物件。[首页](10-ripe-home-40mm.png)、[说明](11-ripe-growth-40mm.png) |
| 40mm Release 首次连接，无启动参数 | 直接进入中性陪伴页面，没有自动健康授权弹窗；引导在 iPhone 打开 Pibo。[首页](12-release-first-connection-40mm.png)、[说明](13-release-first-growth-40mm.png) |

截图为重新构建安装后的原始 Simulator 窗口截图；录屏为对应 40mm 模拟器原始视频。

## 验证边界

未宣称通过真实双设备同步、实际触觉、系统息屏/耗电、VoiceOver/系统减少动态效果或健康权限拒绝的真机验收。首版短动作使用已有矢量形象和原生变换，专用动作素材仍需独立设计。未新增好友送光、complication、腕上物件消费或呼吸替代模式。

已有 Swift 6 隔离警告和 AppIntents 元数据提示仍按原工程情况保留。本轮没有改动原先未跟踪的 `docs/backend-membership-contract.md`。
