# 森林首页水面与实时倒影方案

> 2026-07-12 基线。适用于 iOS 首页的 SpriteKit 森林场景。Figma 源文件为 [Pibo `3817:2130`](https://www.figma.com/design/wQtaSAaU2InhraMiu4Mi6r/Pibo?node-id=3817-2130&m=dev)，场景画布为 `3817:2132`，河流组为 `3908:133`，干净的 S 形水面为 `3900:227`。

## 最终结论

水面必须由三个互相独立的层组成：

1. 干净水面底图：只提供 S 形水域、基础颜色和静态线条。
2. 实时倒影层：从树木、前景叶片和 Pibo 的当前 SpriteKit 节点生成透视倒影。
3. 水面高光层：在倒影上方生成随时间移动的流光。

旧的 `forest_river@3x.png` 是扁平化合成图。它既包含水面和倒影，也包含清晰的深色叶片、枝干等前景内容，不能再作为水面底图、遮罩或水花采样源。文件即使保留在资源目录，也不得重新接入运行时渲染。

## 素材职责

| 素材 / 节点 | 当前职责 | 约束 |
| --- | --- | --- |
| `forest_water_static@3x.png` | 水面底图、倒影裁剪遮罩、流光纹理、水花落点 alpha 采样 | 水面系统唯一允许直接使用的河流位图 |
| `forest_river@3x.png` | 旧素材，仅供问题追溯 | 禁止参与运行时绘制或采样 |
| `forest_bg_tree` / `forest_secondary_tree` | 远景树木及其倒影源 | 倒影只采样水面接触点以上的部分 |
| `forest_main_leaf_*` / `forest_front_leaf_*` | 可摆动的前景叶片及其实时倒影源 | 前景实体仍正常遮挡水面；不要误认为实体叶片是烘焙残留 |
| Pibo body / head | Pibo 实体及其实时倒影源 | 倒影随动作、成长形态和显隐状态更新 |

`ForestSceneManifest.river.image`、水面底层纹理、遮罩纹理、高光纹理和 `forestWaterSamples` 必须全部指向 `forest_water_static`。这样可以从代码层面阻止旧合成图重新泄漏到水面。

## SpriteKit 合成顺序

同一条河流使用相同的设计 frame：`x = -34`、`y = 487`、`width = 448.2329`、`height = 382.7229`。

| z 顺序 | 内容 | 实现 |
| --- | --- | --- |
| `3.0` | 干净水面底层 | `forest_water_static` + `ForestWaterBase.fsh` |
| `3.2` | 实时倒影 | `SKCropNode`，mask 为 `forest_water_static` |
| `3.6` | 流动高光 | `forest_water_static` + `ForestStream.fsh`，`screen` 混合 |
| `11...39` | 岸边、石头和前景叶片实体 | 按场景原有 z 顺序自然遮挡水面与倒影 |

倒影和高光都受同一个 S 形 alpha 遮罩约束，任何像素都不应越出水域。

## 实时倒影原理

### 1. 反射源

`ForestThemeRenderer` 在主题安装、场景重建或尺寸变化后，为以下节点创建 `ForestReflectionProxy`：

- 远景树：`forest_bg_tree`、`forest_secondary_tree`；
- 主景和前景叶片：`forest_main_leaf_1/2`、`forest_front_leaf_1/2`；
- Pibo body 和 head。

代理直接引用源节点纹理，因此叶片摆动、Pibo 动作、贴图切换、透明度和显隐状态都会同步到倒影。

### 2. 水面接触点

所有接触点都使用 Figma 的 393×852 顶左坐标系，再由 `ForestLayoutMapper` 转为 SpriteKit 坐标。当前叶片接触点为：

| 源节点 | 接触 y | 基础透明度 |
| --- | ---: | ---: |
| `forest_main_leaf_1` | 730 | 0.26 |
| `forest_main_leaf_2` | 730 | 0.26 |
| `forest_front_leaf_1` | 825 | 0.22 |
| `forest_front_leaf_2` | 820 | 0.22 |

接触点 x 使用素材 frame 的中点。只截取接触点以上的纹理区域，避免把水面以下或屏幕外的透明区域送入网格。

### 3. 透视投影

倒影不是屏幕空间的简单 `yScale = -1`。每个代理使用 `4 × 6` 的 `SKWarpGeometryGrid`，将源纹理顶点从接触点向水面投影：

- `verticalCompression = 0.52`：纵向压缩，模拟俯视水面的透视；
- `tipWidthScale = 0.72`：远端宽度收窄；
- `outwardDrift = 0.08`：根据接触点相对画面中心的位置产生轻微横向漂移；
- `rippleStrength = 1`：叠加宽波和细波的水平位移。

水面越靠近观察者，波纹横向位移越明显。低电量模式保留宽波、去掉细波，并把位移振幅降到约 52%。

### 4. 倒影着色

`ForestReflection.fsh` 负责：

- 将源颜色向深青绿色水色混合 56%；
- 从接触点向倒影末端逐渐降低透明度；
- 输出正确的预乘 alpha，避免白边、矩形色块和透明区域发亮；
- 乘以当前连续光照模型中的 `water.reflectionStrength`。

水面高光位于倒影之上，因此强高光可以自然遮住部分倒影，符合真实水面的视觉关系。

### 5. 交互叶片的运动方向

可交互叶片必须把“静态透视”和“实时形变”分开计算：

1. 首帧记录每个网格顶点的静止设计坐标，并用它计算接触点、纵向压缩、末端收窄和水波扰动，保证 Figma 透视不随拖拽漂移。
2. 每帧计算当前顶点相对静止顶点的位移，把该位移以相同视觉方向叠加到静态倒影。纵向位移乘 `verticalCompression`，横向位移乘该顶点的透视宽度系数。

因此，叶片向屏幕下方移动 `Δy > 0` 时，倒影也向下移动 `Δy × verticalCompression`。不能在交互期间把当前顶点重新代入固定接触点镜像公式；该公式会让源点下移时反射深度变小，表现为倒影错误地向上移动。

当前只有四个可交互叶片代理使用 `followSourceDeformation`。远景树木和 Pibo 仍使用固定接触点的 `mirrored` 投影，避免改变非交互对象的自然反射行为。

## 水流实现

### 底图折射

`ForestWaterBase.fsh` 保持原始 alpha 轮廓不动，只偏移纹理内部的颜色采样：

```text
横向宽波：0.0100 × rippleStrength
横向细波：0.0034 × rippleStrength
纵向扰动：0.0035 × rippleStrength
```

宽波、细波和纵向波使用不同空间频率与时间速度，避免整张水面像一张平移的贴纸。低电量模式关闭细波和纵向波。

### 表面流光

`ForestStream.fsh` 生成两种移动高光：

- 较宽、较慢的 band，强度系数 0.12；
- 较窄、较快的 sparkle，强度系数 0.20。

高光使用 `screen` 混合，只在静态水面 alpha 内输出。水面整体颜色、暗度与高光强度继续由当前连续时间光照模型控制。

## 性能约束

- 不创建第二套水面渲染器；Water Lab 通过 `PiboStageScene` 转发调参到生产 `ForestThemeRenderer`。
- 水面底图和高光各为一个 sprite；倒影使用少量 `4 × 6` 网格代理。
- 每帧只更新两个水面 shader 的时间 uniform 和倒影网格顶点，不生成新位图。
- 纹理、shader 和倒影代理在场景重建时创建，不在逐帧热路径中分配。
- 低电量模式关闭高频细波和 sparkle，并降低倒影扰动。

## 禁止回归项

- 不得把 `forest_river` 重新设为 `ForestSceneManifest.river.image`。
- 不得把 `forest_river` 用作水面底图、倒影 mask、流光纹理或随机水花采样源。
- 不得用完整场景截图或扁平化 Figma group 代替干净水面素材。
- 不得把倒影直接烘焙回 `forest_water_static`。
- 不得用简单上下翻转替代三维水面接触点与透视压缩。
- 看到水面上的深色叶片时，应先区分：它是 z 较高的真实前景叶片、实时倒影，还是底图残留。

如果未来设计需要更强的手工倒影，只能新增“reflection-only”透明 matte；该 matte 不能包含水面底色、岸边实体或前景叶片原图。

## 验收方法与当前基线

### 资产与代码检查

1. 全仓搜索 `forest_river`，生产渲染与采样代码中不应存在引用。
2. 检查 `ForestSceneManifest.river.image` 和 `forestWaterSamples` 均为 `forest_water_static`。
3. `git diff --check` 必须通过。

曾用于定位问题的设计坐标 `(228, 703)`：

- 干净水面像素为 `#3FCAC5`；
- 旧 `forest_river` 像素为 `#03230F`；
- 对应位置的前景叶片纹理为透明。

因此该深色像素可明确归因于旧水面素材，而不是实时前景层。修复后的实际首页在 `(228, 703)`、`(247, 703)` 和 `(228, 720)` 均恢复为经过当前环境光处理的水面色；真实前景叶片覆盖的位置仍按正常 z 顺序保留。

### 模拟器验收

2026-07-12，iPhone 17 Pro / iOS 26.5 Simulator：

- Pibo Debug 构建成功；运行日志无 SpriteKit、Shader、Metal、warp、fault 或 assertion 错误。
- 固定画面倒影关闭/开启：11,684 个像素的最大通道差大于 8，证明清理底图后实时倒影仍在工作。
- 水流相隔一秒：水域平均最大通道差为 2.95%；14.5% 的水域像素变化超过 2%，11.4% 超过 5%。
- 首页红框对应位置复核：原烘焙深色叶形已消失，水面保持 S 形轮廓和动态流光。
- 叶片向下拖拽回归测试通过：旧固定镜像结果会向上，`followSourceDeformation` 结果按 `Δy × 0.52` 向下；测试位于 `StageArchitectureTests.testInteractiveLeafReflectionFollowsDownwardDeformation`。

Water Lab 的确定性截图参数：

```text
-PiboWaterLab
-PiboWaterLabCapture
-PiboWaterReflectionIntensity=0|1
```

`-PiboWaterLabCapture` 会暂停动画并折叠面板，适合生成倒影开/关的像素级对照。水流验证应移除该参数，折叠面板后截取相隔一秒的两帧。

## 代码入口

- `Pibo/Features/Home/Stage/PiboStageScene.swift`：主题无关的场景生命周期、输入路由与 Water Lab 调参入口。
- `Pibo/Features/Home/Stage/Forest/ForestThemeRenderer.swift`：森林分层、水面、倒影源、接触点与运行时更新。
- `Pibo/Features/Home/Stage/PiboWeatherEffectController.swift`：跨主题共用的雨幕、落点与水花池。
- `Pibo/Features/Home/Stage/Forest/ForestSceneManifest.swift`：水域 frame、唯一水面素材和场景层级。
- `Pibo/Features/Home/Stage/Forest/ForestReflectionProjection.swift`：透视投影与网格更新。
- `Pibo/Features/Home/Stage/Forest/ForestWaterBase.fsh`：底图折射与流动。
- `Pibo/Features/Home/Stage/Forest/ForestReflection.fsh`：倒影水色、衰减与预乘 alpha。
- `Pibo/Features/Home/Stage/Forest/ForestStream.fsh`：水面移动高光。
- `Pibo/Features/WaterLab/WaterLabView.swift`：生产水面调试与截图验证入口。
