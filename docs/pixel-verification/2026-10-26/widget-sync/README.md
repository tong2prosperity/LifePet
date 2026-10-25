# iOS Widget 数据同步排查 · 2026-10-26

范围仅 iOS 的 App → App Group → WidgetKit。没有修改 HarmonyPibo，也没有更改 Core 领域规则或依赖 pin。

## 已修复

| 问题 | 修复后的行为 |
| --- | --- |
| HealthKit 后台观察回调只更新 App 实时值，组件数字依赖前台历史查询 | 在健康查询成功返回后，通过 App 持有的同步接收器合并并保存组件快照，再完成观察回调；不依赖 SwiftUI `onChange` 是否在后台执行 |
| 没有查到记录与真实 0 混同 | 缺失显示 `--`；真实测得的 0 显示 `0`；错误保留最后有效事实，成功的空查询更新为未知 |
| 后返回的历史查询、无关历史行编辑可能盖掉较新的实时数据 | SwiftData 和组件载荷分别保存三项指标的采集时间，逐项拒绝过期更新；没有历史行时保留已有实时快照；旧行的通用编辑时间只用于首次接入 |
| 午夜后 5 分钟才清昨日活动 | 时间线预先包含当地次日 00:00 的清理项，不依赖系统是否准时重新调用 provider；使用 Calendar 日历加日，覆盖夏令时 |
| 改时区后新一天的边界可能比旧边界更早，正常回调被误认为过期 | 实时查询必须对应当前时区今天的准确起点；换日界线后清空旧窗口事实，接受新窗口并拒绝旧时区延迟回调 |
| 外观发布受好友账号恢复守卫影响 | 在好友恢复守卫之前发布本机组件的完整健康／身份／像素快照，不要求已配对手表 |
| 同名新宠物可能继承旧宠物投影 | 快照绑定宠物 UUID；身份改变清除上一身份的健康和外观载荷；同身份元数据更新保留真实健康时间 |
| 少一个活动目标时，其他已知目标的进度也缺失 | 每项事实／目标独立投影，继续调用 Core 的进度转换；未知事实不生成假 0 进度 |
| App Group 不可用时静默写进 App 私有 defaults，损坏读取还会删共享键 | 只使用有容器授权的 App Group；保存失败返回并记录日志；扩展读取损坏载荷只回退，不删除共享数据 |
| 仅查询秒数改变也请求重新加载 | 精确采集时间仍保存；载荷内容及“更新 HH:mm”分钟均未变化时跳过额外 reload |
| 锁屏圆形组件没有消费成长／配饰载荷，桌面森林漏接变形 | 各尺寸通过同一外观投影读取成长、叶子、配饰、成熟度、变形与卡住状态；新增实际栅格差异回归 |

保留 widget kind、App Group ID、快照键和可选字段向后兼容。没有为组件新增健康读取权限，也没有用轮询强迫系统刷新。

## 验证

- 定向回归第一轮：39 项／3 套通过。
- 完整回归第一轮：528 项／103 套通过；之后补齐锁屏外观数据接线并重新验证。
- 锁屏外观接线后完整回归：529 项／103 套全部通过；随后补充时区切换回归并重新验证。
- 最终完整回归：**530 项／103 套全部通过**；本轮新增 16 项同步、时区与实际像素输出回归。
- 最终 Release 构建：**BUILD SUCCEEDED**（包含 iOS App 与 Widget 扩展）。保留已有的其他模块并发隔离警告；本次涉及的 Widget／健康接线文件无新增编译警告。
- 测试包含独立 UserDefaults 往返／损坏读取、内存 SwiftData 乱序合并、跨日旧回调、未知与 0、身份切换、时区切换、独立目标、夏令时午夜、reload 去重以及真实像素输出差异。
- App 与扩展 entitlements 均使用 `group.com.piboworld.app.iPibo`；App 有 HealthKit background-delivery entitlement，扩展无需自行查询 HealthKit。

测试命令：

```sh
xcodebuild test -project Pibo.xcodeproj -scheme Pibo \
  -destination 'platform=iOS Simulator,id=1A6A5ABC-10E7-4269-BC40-6392A449DF58' \
  -derivedDataPath /tmp/pibo-pixel-parity-build -parallel-testing-enabled NO
xcodebuild build -project Pibo.xcodeproj -scheme Pibo -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pibo-pixel-release-build
```

日志：`/tmp/pibo-widget-sync-full-final.log`、`/tmp/pibo-widget-sync-release-final.log`。

## 系统刷新边界与发布状态

这次验证覆盖接线、存储、合并和时间线逻辑。模拟器不能证明真实设备在锁屏／后台唤醒时的 HealthKit 数据交付和 WidgetKit 实际刷新时延；这些仍需真机验收。`reloadTimelines` 是更新请求，实际显示由系统调度与预算决定，不能承诺即时刷新。参见 [Apple WidgetKit 更新说明](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/) 和 [HealthKit 观察查询说明](https://developer.apple.com/documentation/healthkit/executing-observer-queries)。

先前归档的 1.5 (6) 生成于本次修复之前，不含这些代码；上传仍受 Xcode 的 App Store Connect 账号认证阻塞。本次没有上传旧归档。恢复发布时需要先生成含本次修复的新归档。
