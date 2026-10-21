# v5.2 原生动画接入验证

2026-09-06，iOS SpriteKit 与 HarmonyOS Canvas。媒体角色资产 0.7.0，Core 0.21.0（`913ecff92bfa10c8e7a87924d7365e84b0fe866e`）。

打开同目录 [index.html](index.html) 查看录屏和截图。设计仓库也保存了相同证据，已有本地服务可打开 <http://127.0.0.1:8793/animation-review-v5/integration-review/>；服务关闭时可直接用浏览器打开 HTML。

## 实际效果

- `ios-settle-rest-review.mp4`：iPhone 17 模拟器原生首页，疲倦 → 4.2 秒安顿 → 持续休息，11 秒静音片段。
- `ios-tired.png`、`ios-resting.png`：iOS 原生首页。休息截图在转场完成约两分钟后取得，用于确认没有回弹至疲倦清醒姿态。
- `harmony-tired.jpeg`、`harmony-resting.jpeg`：Mate 70 Pro 模拟器原生首页。同一套轮廓与动作数据；各模拟器已有健康数据不同，`bo` 填充并非比较对象。
- `ios-food-baseline.png`、`ios-food-left.png`、`ios-food-right.png`：原生 Character Lab 在 1.9 秒固定采样的疲倦／双向观察对照。使用实际 SpriteKit 渲染器；这是纯动作取证，画面不包含真实餐食贴纸或成功记录。

## 接入范围

11 个持续表现、3 个转场、22 个左右食物观察和 1 个既有拍一拍，共 37 段。六个正式健康状态不变；思考、疲倦休息、恢复不足初醒与问候后是表达变体。未解锁吊床在苔藓睡／醒，已解锁继续使用批准的吊床 A/B 睡姿及初醒资源。

两端 Debug「森林细节」面板可选择表现，并用「观察左侧／观察右侧」播放完整原生动作。调试预演不创建餐食、健康事件、奖励或社交消息。正常业务食物仍以服务端确认为食物为前提。

## 已完成验证

- Core：Rust 159 项、Swift wrapper 75 项、no_std 与 Apple XCFramework 构建；先发布 0.20.0 / 0.21.0，再更新两端精确版本。
- 原始动画 17,103 个采样帧与导出轨道比较通过，最大平移误差 0.005 个设计单位。
- iOS：`xcodebuild test -project Pibo.xcodeproj -scheme Pibo -destination 'platform=iOS Simulator,name=iPhone 17'` 全量通过；最后针对动画、会话行为保持和 Shadow 的专项测试通过；最终 Debug build 通过。
- HarmonyOS：`node tools/run_all_checks.mjs` 全部通过；DevEco `assembleHap --mode module -p product=default -p buildMode=debug --no-daemon` 签名包构建通过。
- 两端媒体 `sync-ios --check` / `sync-harmony --check` 与 `verify` 通过。

播放器覆盖循环首尾、食物首尾／取消、持续休息、睡眠闭眼、重复拍一拍、减少动态效果和有限几何坐标。此次模拟器视觉检查不等同于手机真机持续帧率、温升或耗电测试；全新吊床起身与首次试用编舞不在本批稿件中。
