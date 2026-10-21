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

- `pibo-core 0.34.3`：C ABI 早已有 `day`／`explore`／`season`／`echo`／`emote`／`shape`，
  但 Swift 包没有包装，iOS 读不到。新增 `Sources/PiboCore/PiboDay.swift`（纯类型映射，
  规则仍全在 Rust），并补上 `pibo_decor_scene`（0.34.2）与 QWeather 条件／风廓线。
  0.34.3 补上 `boat`／`kite`／`telescope` 三个装饰 id —— 此前 `PiboCoreDecorID` 只到
  `tent`，`catalog` 会把小溪与山坡的三件悄悄丢掉，装饰页因此永远只有「空地」。
- iOS 依赖从 `0.24.0` 提到 `0.34.3`，`Package.resolved` 同步；旧调用点全部照常编译。

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
| `.../Day/PixelDayDirector.swift` | `pixel/day/PixelDayDirector.ets` | 节拍机：走路／做事／等待／下台／瞬移／回调，漫游点、过溪石、躲藏、伪装、变形阶段与剧本表演 |
| `.../Day/HomeDayController.swift` | `services/day/HomeDayController.ets` | 把 Core 的 `day_choose`／`explore_trip`／`echo_choose` 变成舞台计划，问候、邀请、换场、出门、离家日记 |
| `.../Day/HomeSeasonController.swift` | `services/day/HomeSeasonController.ets` | 两季各七拍的分镜、季节之间的来信、报告与旧笔记、木板与过溪 |

### 存储与协调（规则全部读 Core）

| Swift 位置 | 对应 ArkTS | 内容 |
| --- | --- | --- |
| `Pibo/Services/Growth/*` | `services/growth/*` | `GrowthStore`、`WishStore`、`DecorStore`、`GrowthCoordinator`、`GrowthCopyCatalog`、`GrowthPresentation` |
| `Pibo/Services/Growth/PolaroidStore.swift` | `services/growth/PolaroidStore.ets` | 每晚一张森林拍立得：整数倍放大到相纸、存 PNG、留 60 张，键 `pibo_growth_polaroid/shots.v1` |
| `Pibo/Features/Home/Growth/HomeGrowthController.swift` | `services/growth/HomeGrowthController.ets` | 成长反馈队列：离开摘要、升级、多一颗心、心愿盖章、装饰、流星、纪念日、早晨睡眠、摇一摇、拍立得；每次只演一件，等弹层与气泡让位 |
| `Pibo/Services/Day/PiboDayStore.swift` | `services/day/PiboDayStore.ets` | 场景、出行、收藏、离家日记、展示位，键 `pibo_day/state.v1` |
| `Pibo/Services/Day/PiboSeasonStore.swift` | `services/day/PiboSeasonStore.ets` | 两季节拍进度、来信、报告、木板与笔记页，键 `pibo_season/state.v1` |
| `Pibo/Services/Day/PiboDayPresentation.swift` | `services/day/PiboDayPresentation.ets` | 收藏／目的地／场景／回声的本地化名字 |
| `Pibo/Services/Day/MealStickerPixels.swift` | `services/day/MealStickerPixels.ets` | 把餐食照片解成 24×24 索引贴纸 |
| `Pibo/Features/Home/Pixel/HomePixelStageLook.swift` | `components/home/HomeForestScene.ets` | 把 Home 的全部状态读成 `PixelStageRenderer.Look`；舞台本身不认识 store |

### 像素 UI 外壳（进行中）

| Swift 位置 | 对应 ArkTS | 内容 |
| --- | --- | --- |
| `.../Pixel/UI/PixelUI.swift` | `pixel/ui/PixelUI.ets` | 纸色／墨色／叶色等语义色、32 个图标 stamp、面板、文字、按钮、分段条、心、标题、开关 |
| `.../Pixel/UI/GrowthHud.swift` | `pixel/ui/GrowthHud.ets` | 等级章、金色经验条、熟悉度心、读数徽章行、`bo` 与心愿小条 |
| `.../Pixel/UI/GrowthSheets.swift` | `pixel/ui/GrowthSheets.ets` | 成长页（英雄图、能量来源、下一级解锁）、今日小心愿、森林装饰（按场景分组、先扣后得）、升级卡与底部弹层宿主 |
| `.../Pixel/UI/PixelFont.swift` | `pixel/ui/PixelFont.ets` | Fusion Pixel 12px 简体子集（OFL-1.1），12px 整数倍取字号 |
| `.../Pixel/UI/DaySheets.swift` | `pixel/ui/DaySheets.ets` | 森林地图（三张场景缩略图、等级门槛、一起去）与收藏架（24 格剪影、摆出来／收回来、散步日记） |
| `.../Pixel/UI/StorySheets.swift` | `pixel/ui/StorySheets.ets` | 第一季的纸：报告、来信、旧笔记（横线纸、划掉的错页、落款） |
| `.../Pixel/PixelStageHits.swift` | `pixel/PixelStage.ets`（`updateHitRegions`） | 舞台的全部可点框：地点、装饰、收藏篮、摆出来的收藏、野餐垫与贴纸、诱饵、两季的物件、Pibo 与叶子 |
| `.../Pixel/UI/ReadoutReport.swift` | `pixel/ui/ReadoutReport.ets` + `components/home/HomeStatusObserver.ets` | 读数徽章的报告：结论与分数、睡眠／负荷、七日方块、主要依据的便签、撕边纸条（按格打印出来） |
| `.../Wellness/WellnessReadout.swift` | `models/WellnessReadout.ets` | 今日一句话结论、不可用标题／细节、分段与原因文案、更新时间 |

字体：鸿蒙用 `font.registerFont({ familyName: 'PiboPixel' })` 起别名；Core Text 没有别名，
iOS 直接向文件里的族名 `Fusion Pixel 12px Prop zh-Hans` 取字，`PixelFont.family` 一处说明。
`PixelFont.register()` 在 `PiboApp.init()` 里调用一次，首帧不会闪回系统字体。

### 接线

- 五个 store（成长／心愿／装饰／日程／季节）在 `PiboApp` 里创建并注入环境，
  `GrowthCoordinator` 跟着账本重算一起刷新。
- 首页可用 `-PiboPixelHome` 切到像素舞台（`PiboReleaseScope.pixelHome`）。它自带 Pibo 的
  一天，并且已经把真实的健康、账本、成长线索、装饰、季节进度接进来。
- 像素模式下 `GrowthHud` 占左上角（12／10），顶栏的旧 `bo` 浮标同时收起，与鸿蒙
  `HomePage.GrowthChrome` 的位置和遮挡规则一致（全屏页或成长弹层打开时整块隐藏）。
- HUD 的四个入口都通了：成长／心愿／装饰打开像素弹层（`PixelSheetHost`），读数打开
  现有的状态观测仪。调试用 `-PiboPixelSheet=growth|wishes|decor` 直接开某一页。
- 舞台上的路牌与篮子已经接好：`HomeDayController.onPlaceTapped` 收到 `trailSign`／`basket`
  就调 `HomeDayOverlays.showDayMap/showShelf`，打开森林地图与收藏架（`-PiboPixelSheet=map|shelf`
  可直接看）。地图的「一起去」走 `travelTo`：Pibo 从边缘走出去，场景在幕后换掉。
  收藏架的「日记写在足迹里 ›」先落到足迹页最新一天（iOS 的 `HistoryFocus` 还没有日期焦点）。
- 第一季的纸（报告／来信／旧笔记）由 `StoryPaperHost` 显示，弹层与成长页同一套纸框；
  `-PiboSeasonMoment=season:notebook|season:report|season:open-letter` 在舞台就绪两秒后
  打开对应的一页（正常路径是点舞台上的旧舱与信箱）。
- 读数徽章的报告（决定 062）在像素模式下替代旧的状态观测卡片：HUD 的读数行对所有人打开
  （`readoutOpen`，不经过观测仪物件），纸条从徽章下方按格打印出来，`-PiboObserver=1` 可直接看。
  非像素模式仍是原来的 `statusObserverPanel`。
- 舞台会接住手势了（`PixelStageHits.swift`）：点哪里由同一帧的布局算出框，最上面那个赢。
  Pibo 身上双击是拍一拍（先让导演播，再交给 Home 的拍一拍对话与成长反馈），单击是瞥一眼
  （收起当前那句）；叶子上拉是收取 bo；路牌开地图、篮子开收藏架、食物贴纸开这一餐；
  装饰里属于「一天里的地点」的走 `onPlaceTapped`，吊床／观测仪／草丛各走各的。
  调试用 `-PiboStageTap=actor|leaf|sign|basket|star`，三秒后点一次对应框的中心
  （模拟器没法合成触摸，这里要验的是框本身）。
- 成长反馈由 `HomeGrowthController` 每 800 ms 取一件来演；升级卡与拍立得卡在首页最上层。
  `-PiboGrowthMoment=growth:level`（或 `growth:away`／`growth:heart`／`growth:polaroid` 等）
  在舞台就绪两秒后播放一次。
- 气泡新增一行 `fact`（小一号的灰字），成长时刻把「步数 +42」「第 7 天」放这里。
- 吊床在 iOS 没有单独的「放置／收起」状态：解锁即入林，装饰页只如实显示已放置。
- 离家日记的文案还没移植，离开摘要先走通用那句（`awayDiary` 传 nil）。
- 舞台在尺寸稳定后会重新上报布局；首次 `onAppear` 时视图还没铺满，只报一次会让导演
  按旧舞台量出来的点走路。

调色板表、字形表、坐标与绘制顺序与鸿蒙逐字节一致；两个移植子任务各自用 Node 跑原 ArkTS
并逐帧比对（角色 714 帧、场景 799 行哈希），差异为 0。

### 验证入口

```bash
# 模拟器上单独打开像素舞台（不挂载 Home，避免位置说明等弹层盖住画面）
SIMCTL_CHILD_PIBO_PIXEL_STAGE=1 xcrun simctl launch booted com.piboworld.app.iPibo
```

`-PiboOpenPixelStage` 同样可用；`-PiboPixelHour=19` 固定时段，`-PiboSeasonBeat=N` 当场播放
第 N 拍，`-PiboForestHour=10` 固定首页森林的光。

## 待移植（按依赖顺序）

### 1. 像素 UI 外壳（剩余）

- 已完成：`PixelUI`、`GrowthHud`、`GrowthSheets`（含升级卡与拍立得卡）、`PixelFont`、
  `WellnessReadout`、`PolaroidStore`、`HomeGrowthController`、`DaySheets`、`StorySheets`、
  `ReadoutReport`（含 `HomeStatusObserver` 的纸条外壳）。
- 待移植：`RecordWindows`（309）、`FootprintsDiary`（196）、
  `PixelMonthCalendar`（167）、`PixelViewfinder`（144）、`PixelOnboardingArt`（98）、
  `PodPanelArt`（47）、`PixelPortrait`（42）。
- 成长页的拍立得一段还没接上（`PolaroidStore` 已有 `latest`，等足迹页一起做）。

### 2. 舞台交互

- 已完成：命中框与点击分发（地点／装饰／篮子／收藏／贴纸／诱饵／Pibo／叶子／流星）、
  双击拍一拍、单击瞥一眼、叶子上拉的拖动。
- 待移植：摇一摇（`onShake`）、收取 bo 的完整回路（`onCollectBo` + 提示气泡）、
  叶子未熟时的提示与音效、`audio/PixelStageSounds`（徽章读数的 bip-bip 等）。
- 相机页、读数报告、足迹日记、餐食详情的像素外壳（数据视图沿用现有图表）。

### 3. 页面接线与旧表现退役

- `HomePage`／`Index` 的图层顺序（HUD 在 chrome 之后、成长弹层在反馈之后）。
- 旧 SpriteKit 舞台与旧 UI 在像素版通过验收后整批退役（决定 069）。

### 4. 测试与验收

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
| 2026-10-21 | 日导演与 `renderFrame` 合成；成长／心愿／装饰／日程／季节存储与两个协调器；季节分镜；Core 0.34.2；首页像素舞台接线 |
| 2026-10-21 | 像素 UI 起步：`PixelUI`、`GrowthHud`、像素字体注册、`WellnessReadout`；HUD 挂到首页左上角，旧 `bo` 浮标在像素模式收起 |
| 2026-10-21 | 成长／心愿／装饰弹层与升级卡；Core 0.34.3 补三个装饰 id；HUD 四个入口接通 |
| 2026-10-21 | 成长反馈队列与每晚拍立得；升级卡、拍立得卡在首页播放；气泡补 `fact` 行 |
