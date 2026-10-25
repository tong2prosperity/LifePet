# iOS 深入复核（2026-10-23）

用户本轮要求只排查 iOS。检查和修改均限制在 Pibo iOS 工程；没有读取、修改或构建 HarmonyPibo，
没有调整 Core 版本、业务阈值、服务端或健康权限。
本轮接续 [恢复场景复核](lifecycle-audit.md)，重点检查实际 SwiftUI 视图时钟和异步任务边界。

## 已复现并修复

| 问题 | 修复 | 主要代码 |
| --- | --- | --- |
| 开启减弱动态后，视图不再投递任何渲染时钟，剧情回调无法执行 | 保留功能时钟，继续通过已有 reduceMotion 画法冻结装饰动画，并清理粒子、停止摇动采样。剧情步骤与互动仍可完成。 | `PixelStageView.swift` |
| 取消识别后快速重试，旧任务 defer 会清空新任务引用；旧缩略图写入返回后仍可能触发成功 UI | 为每次拍摄／选图分配独立身份，只有当前任务可以收尾或更新相机。识别、图片读取和缩略图保存后的 UI 回调逐一核对身份；取消和离开页面使旧身份失效。 | 新 `CameraCaptureTaskController.swift`、`PiboCameraView.swift` |
| 后端识别返回时任务已经取消，仍启动 Vision 与 JPEG 编码 | 在识别前后和持久化之前检查取消；取消路径不生成照片、投影或迟到错误提示。已经成功提交的真实记录不会被事后删除。 | `HomePhotoSaveCoordinator.swift` |
| 日常控制器没有随首页离开／后台停止，仍可能更新最后见面时间；重启问候会丢弃正在进行的剧情完成回调 | 首页和前后台生命周期明确启停日常、成长时钟。未激活时不启动，不重复写停止时间；恢复时保留正在进行的剧情和探索步骤。延迟问候也检查前台与遮挡。 | `HomeDayController.swift`、`HomeView.swift` |
| 账号失效后相机及排队的重拍请求仍然存在 | 关闭相机和餐食选择，清除排队重拍、登录恢复意图及待展示投影；本地设置和健康详情保持可用。 | `HomePresentationState.swift` |
| 运动／步数与 HRV 提醒跨越系统异步等待时，用户关闭开关或回到前台，旧请求仍可能送达 | 增加发送代次检查，等待授权、进入发送队列和系统 add 返回后均复核。失效请求撤回，只有成功发布才记录已发送。前台 delegate 再抑制运动／bo／睡眠重复横幅，以及用户已经关闭的 HRV 提醒。 | `WorkoutCompletionNotifier.swift`、`StressNotifier.swift`、`StressNotificationScheduling.swift`、`AppNotificationRouter.swift` |

通知替身接口只封装系统投递，不复制 Core 的资格、静默时段或每日限制。
已有偏好键、运动去重键、健康数据、成长账本和历史记录格式不变。

## 回归证据

- 新的真实 SwiftUI 窗口测试先在修复前失败：`PixelReducedMotionLifecycleTests` 的剧情完成回调为 0。
  日志 `/tmp/pibo-ios-deep-reduce-before.log`。
  修复后同一视图测试通过；这不是绕过视图直接调用 renderer 的测试。
- 第一批针对性测试 **17 项／6 套件通过**，日志 `/tmp/pibo-ios-deep-targeted.log`。
- 最终 iPhone 17／iOS 26.5 Simulator：**504 项 swift-testing、99 套件全量通过**；XCTest 也通过。
  日志 `/tmp/pibo-ios-deep-final-tests.log`。
- 最后补齐显式模块导入与拍摄期间相册按钮禁用后，相机／减弱动态／账号清理的针对性检查 **22 项／4 套件通过**。
  日志 `/tmp/pibo-ios-deep-final-camera-check.log`。
- iOS Debug 测试构建和 Release 模拟器构建成功，包含工程内嵌 Watch／Widget 目标。
  Release 最终增量核对日志 `/tmp/pibo-ios-deep-final-release.log`。
- 新增／扩展用例覆盖：减弱动态下真实视图时钟、识别取消后重试与迟到收尾、识别后的取消、
  剧情中断恢复、未激活时不改最后见面时间、账号失效清理、发送中关闭开关／回前台、成功发送去重、
  HRV 发送失败不消费当天提醒，以及前台横幅的最后一道检查。
- `git diff --check` 通过。未提交其他已有工作区修改，也未向远端推送。

## 验证边界

相机任务与通知测试使用可控替身，不请求系统权限、不调用真实识别服务、不创建用户健康记录。
减弱动态测试在实际 UIHostingController／UIWindow 中运行，验证传入减弱动态表现时功能时钟继续工作；
没有操作目标设备上的系统辅助功能设置。

本轮没有真机验证摄像头、相册云端下载、系统通知中心、音频、触觉、耗电或内存峰值。
这些不能以模拟器和替身通过替代。编译仍有仓库既有并发隔离／SDK 告警，未宣称清零。
