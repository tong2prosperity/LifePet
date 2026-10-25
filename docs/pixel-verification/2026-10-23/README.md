# iOS 像素对齐验收 · 2026-10-23

## 工程验证

- Core 精确固定正式标签 `0.34.4`；`Package.resolved` 与鸿蒙版本一致。
- iPhone 17（iOS 26.5 Simulator）全量 swift-testing：461 项、89 个 suite 通过。使用正常模拟器签名；禁签运行无法访问测试 Keychain，不作为通过依据。
- 24 张六状态／四调色板森林角色帧、10 张变形帧由鸿蒙生产 ArkTS 生成 SHA-256，Swift 输出完全一致；基线没有通过改画面或重写期望放行。
- 回归覆盖提问心愿直达／预算／重复回答、连载与记忆条件／熟悉度语气、装饰购买中断恢复／幂等扣款、跨日快照／身份隔离、统计属性过滤与退役事件拦截、遮挡可读性与加速度单位换算。
- iOS Debug + 内嵌 watchOS／WidgetKit 构建通过；iOS Release 模拟器构建通过；独立 watchOS 模拟器构建通过。

## 视觉证据

本目录截图来自模拟器。Watch 的等级／余额／形态来自明确的 `-PiboWatchPreview` 内存样例，不写健康记录、账本、账号或生产同步。iPhone 未授权健康时如实显示空态；调试固定时段只影响森林光线。

- `iphone-home.png`：完整首页像素 HUD 与入口。
- `watch-46mm-ripe.png`：46mm 腕上像素角色与成熟容器入口。
- `watch-40mm-ripe.png`：40mm 小屏首屏，角色与收取入口完整可见。
- [今日心愿](iphone-wishes.png)、[装饰目录](iphone-decor.png)、[读数空态](iphone-readout.png)、
  [足迹空态](iphone-history.png)、[设置](iphone-settings.png)、[相机权限拒绝](iphone-camera-unavailable.png)：
  均来自实际页面。相机截图期间仅调整模拟器 TCC，结束后已恢复为未决定状态。

## 平台差异与未实测

- Apple Watch 小心愿与成长来自手机真实投影；本地 HealthKit 只补只读活动事实。收取需要手机确认同一个容器 token，断连不建立第二套余额，不复制 Core 的健康阈值。
- 手机拍照必须先收到后台 `is_food` 确认才保存成功；模拟器没有物理相机，设备缺失面板可以检查，真实分割与识别服务延迟未由本轮截图覆盖。
- 未声称通过：真机 HealthKit 跨日／权限拒绝、真实配对 WCSession 收取与同步时延、实体触觉、长期电量／热量与实际 FPS、已安装桌面组件的系统刷新时序。
- 当前构建仍有既有 Swift 并发兼容警告与 App／Extension build number 不一致警告；不影响本轮 Debug／Release 构建，发布前需统一版本号。
