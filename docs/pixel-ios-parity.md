# iOS 像素主线补差（决定 057–069）

> 建立：2026-10-21
> 状态：进行中。渲染基础、角色与场景已移植并可在模拟器出图；日导演、成长／心愿／装饰存储、
> HUD 与弹层、相机／读数／足迹的像素外壳仍待移植。
> 规则源：产品决定见 `docs/narrative-rebuild/decisions/057`–`069`；跨端实施证据见
> HarmonyPibo `docs/harmony-first/2026-10-19-像素化重构.md` 起的像素系列记录。
> 本文只是 iOS 侧的移植进度与顺序，不是新的产品规则源。

## 为什么现在做

决定 057／058／061／065／069 当时写明「iOS 不补齐」。用户于 2026-10-21 改为要求 iOS 跟上
鸿蒙实现进度并完整还原，因此本文件承接该决定，按用户可观察结果补齐，而不是逐行翻译 ArkTS。

## 已完成（2026-10-21）

### Core

- `pibo-core 0.34.1`：C ABI 早已有 `day`／`explore`／`season`／`echo`／`emote`／`shape`，
  但 Swift 包没有包装，iOS 读不到。新增 `Sources/PiboCore/PiboDay.swift`（纯类型映射，
  规则仍全在 Rust），并补上 `pibo_decor_scene` 与 QWeather 条件／风廓线。
- iOS 依赖从 `0.24.0` 提到 `0.34.1`，`Package.resolved` 同步；旧调用点全部照常编译。

### 渲染与画面

| Swift 位置 | 对应 ArkTS | 内容 |
| --- | --- | --- |
| `Pibo/Features/Home/Pixel/Render/PixelPalette.swift` | `pixel/render/PixelPalette.ets` | 78 个 ink、四种 mood 的调色板表、循环色环（水／火／星）与字形表 |
| `.../Render/PixelFrame.swift` | `pixel/render/PixelFrame.ets` | 索引画布、Bayer 抖动、字形 stamp、RGBA 输出、循环色区域 |
| `.../Render/PixelArt.swift` | `pixel/render/PixelArt.ets` | 贴纸描边、接地影子、噪声、植被 |
| `.../Render/PixelMemo.swift` | `pixel/render/PixelMemo.ets` | 纯绘制调用缓存 |
| `.../Render/PixelCanvas.swift` | `pixel/ui/PixelCanvas.ets` | CGImage 输出与整数倍最近邻放大 |
| `.../Character/*` | `pixel/character/*` | Pibo 身体／叶子／表情／动作／一天姿态／变形形态 |
| `.../Scene/*` | `pixel/scene/*`、`pixel/effects/*`、`pixel/day/PixelShape.ets` | 森林静态与生命层、地点、装饰、季节、第二季、氛围、收藏、野餐垫、光源、特效 |
| `.../PixelStageView.swift` | `pixel/PixelStage.ets` 的 `renderFrame` | 按批准的绘制顺序合成一帧：静态森林 → 生命层 → 地点 → 季节 → 装饰后层 → Pibo → 前层 → 灯光 |

调色板表、字形表、坐标与绘制顺序与鸿蒙逐字节一致；两个移植子任务各自用 Node 跑原 ArkTS
并逐帧比对（角色 714 帧、场景 799 行哈希），差异为 0。

### 验证入口

```bash
# 模拟器上单独打开像素舞台（不挂载 Home，避免位置说明等弹层盖住画面）
SIMCTL_CHILD_PIBO_PIXEL_STAGE=1 xcrun simctl launch booted com.piboworld.app.iPibo
```

`-PiboOpenPixelStage` 同样可用；`-PiboPixelHour=19` 可固定时段截图。

## 待移植（按依赖顺序）

### 1. 日导演与舞台行为

- `pixel/day/PixelDayDirector.ets`（1075）：按 Core `day_choose`／`day_invite`／`day_greet`／
  `explore_trip`／`echo_choose`／`shape_plan` 驱动走路、活动、躲藏、变形、出门。
- `pixel/PixelStage.ets` 其余部分：命中区域、双击拍一拍、叶子上拉收取、场景换场横向卷轴、
  摇一摇、舞台时刻队列、`PixelStageEffects`、`audio/PixelStageSounds`。

### 2. 存储与协调（规则全部读 Core）

- `services/growth/GrowthStore`（288）、`WishStore`、`DecorStore`（123）、`GrowthCoordinator`（234）、
  `GrowthCopyCatalog`（123）、`GrowthPresentation`。
- `services/day/PiboDayStore`（307）、`PiboSeasonStore`（326）、`HomeDayController`（1054）、
  `HomeSeasonController`（939）。
- 持久化语义必须一致：健康经验由账本推导、只持久化互动经验与每日计数、装饰先扣 `bo` 再记账。

### 3. 像素 UI 外壳

- `pixel/ui/PixelUI`（267）、`GrowthHud`（150）、`GrowthSheets`（508）、`DaySheets`（291）、
  `RecordWindows`（309）、`ReadoutReport`（370）、`FootprintsDiary`（196）、
  `PixelMonthCalendar`（167）、`PixelViewfinder`（144）、`PixelOnboardingArt`（98）、
  `StorySheets`（88）、`PodPanelArt`（47）、`PixelPortrait`（42）。
- 像素字体：鸿蒙用 Fusion Pixel 12px 简体子集（OFL-1.1，约 1 MB）。iOS 需同样引入并只在
  气泡、HUD、标题使用；正文与健康图表保持系统字体。
- 文案：`rawfile/pibo-growth.zh-Hans.jsonl`（185 条，13 个时刻 × 三档语气）与拍一拍
  `minTone` 过滤。

### 4. 页面接线与旧表现退役

- `HomePage`／`Index` 的图层顺序（HUD 在 chrome 之后、成长弹层在反馈之后）。
- 相机页、读数报告、足迹日记、餐食详情的像素外壳（数据视图沿用现有图表）。
- 旧 SpriteKit 舞台与旧 UI 在像素版通过验收后整批退役（决定 069）。

### 5. 测试与验收

- 渲染金值：把鸿蒙 `tools/fixtures/pixel-visual-baseline.json` 的帧在 iOS 侧复现，
  加一条 XCTest 逐像素比对。
- 玩法：成长基线／上限／跨日、心愿判定、装饰先扣后得、出门与收藏、季节节拍、变形阶段。
- 真机：拍一拍手感、叶子上拉、摇一摇灵敏度、耗电与帧率。

## 本机环境注意

这台机器的命令行沙箱会拦住 Xcode 的嵌套沙箱，`xcodebuild` 默认会以
`sandbox-exec: sandbox_apply: Operation not permitted` 失败。两处一次性设置后可正常构建与测试：

```bash
defaults write com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox -bool YES
xcodebuild ... OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
```

第二条只用于命令行验证，不要写进工程设置。模拟器上若残留系统定位授权弹窗，
`xcrun simctl shutdown` 后重新 `boot` 可清掉。

## 修订

| 日期 | 变化 |
| --- | --- |
| 2026-10-21 | 建立；Core 0.34.1、渲染基础、角色、场景、舞台预览完成并在模拟器出图 |
