# 像素迁移恢复场景复核（2026-10-23）

接续 [第一轮遗漏复核](omission-audit.md)。本轮针对实际前后台、页面遮挡、延迟回调和指标缺失检查，
沿用已发布 Core 0.34.4，没有添加健康阈值、奖励规则、服务器合同或权限。

## 已修复

| 问题 | 修复后的行为 | 平台／位置 |
| --- | --- | --- |
| 长期回调捕获冷启动时的未激活状态 | 日常、剧情和成长控制器改为在调用时读取实时应用状态；不再因最初 scenePhase 未激活而永久不执行。此项在普通单元测试通过后，由模拟器实际页面复核发现。 | iOS `HomeView.startPixelDay` |
| 原生全屏页返回后成长队列停住 | Home 再出现时重新启动队列，已有像素场景不需要重新绑定；不再仅在第一次绑定场景时启动。 | iOS `HomeView` |
| 升级揭晓在延迟期间被其他页面抢占而丢失 | 队列保留升级事件，先等待原表演延迟，再等待前台、空闲界面和 Pibo 可见；揭晓卡真正显示后才消费持久化事件，等待期间重建控制器或重启仍能继续。 | 双端 `HomeGrowthController` |
| 拍立得异步完成时跳过展示 | 冲印成功的照片仍保存；若此时后台或其他页面打开，保留待展示状态，返回森林后再展示。进程终止后已存照片仍可从小架子查看。 | Harmony `HomeGrowthController`；iOS 当前同步保存没有该异步等待 |
| 有任意健康数据就把缺失运动当作零 | 按步数／运动各自采集记录向 Core 传入值；缺失仍为空，实际测得 0 保留，旧记录正值兼容。iOS 日导演的步数可用性也改为读步数自身记录。 | iOS `GrowthActivityFacts`／`PiboApp`／`HomeView`，Harmony `GrowthCoordinator` |
| 通知跳转和睡眠卡抢占未关闭页面 | 检查前台、原生弹层关闭过程及像素小窗、读数报告、成长卡、运动回应、餐食表演、收取等遮挡；等待期间不消费请求，恢复前台或遮挡结束时重试。 | iOS `HomePresentationPolicy`／`HomeStateObservationModifier`；Harmony 已有前台 watch 与统一 overlays 检查 |
| 组件健康更新抹掉角色和陪伴状态 | 更新健康事实时保留像素外观、陪伴状态及其有效期；不把旧日健康读数一并保留下来。 | iOS `PetStateWidgetBridge` |

## 自动化与构建

- iPhone 17／iOS 26.5 Simulator：全量 **492 项 swift-testing、94 套件通过**；XCTest 也通过。
  最终日志 `/tmp/pibo-continuation-runtime-tests.log`。
- 新增 `HomeGrowthLifecycleTests` 执行真实队列启动／停止、等待与恢复，检查延迟事件持久化，
  并通过正式 Core 验证缺失运动仍是 unknown；通知协调器、前台恢复顺序和组件元数据用例扩展。
- iOS Debug、Release 模拟器构建成功（含内嵌 Watch、Widget）。
  日志 `/tmp/pibo-continuation-runtime-build.log`、`/tmp/pibo-continuation-runtime-release.log`。
- Harmony：`tools/test_growth_lifecycle.mjs` 执行生产控制器，覆盖遮挡／后台／停止／重建、
  异步冲印以及缺失和真实零；全量 **124 条检查通过**，default 产品 Debug HAP 构建成功。
  日志 `/tmp/harmony-continuation-final-checks.log`、`/tmp/harmony-continuation-final-build.log`。
- Harmony 本地提交 `b7e1f52`（`fix: retain growth feedback across interruptions`），未推送。
  交接记录 `docs/harmony-first/2026-10-23-成长反馈恢复与缺失指标复核.md`。
- 双端差异检查通过；没有提交工作区其他已有修改。

## 模拟器证据

- [冷启动后正常显示升级揭晓](lifecycle-audit/level.png)：显式 DEBUG 成长预览，不发放成长奖励。
- [同一个预览等待装饰页让位](lifecycle-audit/level-covered.png)：延迟结束后仍只显示装饰页，无叠加揭晓卡。

截图来自最终运行时修复后的实际 App，已逐张查看。遮挡结束后恢复、进程重建后的队列恢复由自动化验证。
本轮没有将预览等级、模拟运动、权限或健康样本写入真实成长账本。

双端目标设备的多任务、进程终止与后台恢复仍待真机验收；本轮没有做真机音频、触觉或通知中心验收。
构建仍有仓库既有并发隔离／SDK 告警，未宣称告警清零。
