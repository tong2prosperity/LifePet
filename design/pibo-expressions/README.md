# Pibo 表情系统 · Expression System (矢量 / SVG)

基于 Figma 形象 [`node 3904:1804`](https://www.figma.com/design/wQtaSAaU2InhraMiu4Mi6r/Pibo?node-id=3904-1804) 的
**纯矢量（SVG）参数化脸部系统**。

> **忠于原始 UI**：body 轮廓、渐变阴影、描边小脚、头顶海藻芽、以及默认脸（眼/眉/海豹鼻/脸颊弧）
> 全部来自 Figma 导出的**真实矢量**（见 `src/body.svg` `src/sprout.svg`，已剥离画布 chrome），
> **不做手工近似**。表情系统只替换会随情绪变化的脸部部件，并严格沿用原始的锚点、尺寸与配色。

## 脸部解剖（source of truth）

| 部件 | 描述 | 颜色（Figma 变量） |
|---|---|---|
| **眉毛 brows** | 小圆点 / 怒 V / 八字，情绪第一读点 | `#c2ccd3`（怒时 `#7c8b95`） |
| **眼睛 eyes** | 稍大的圆点，可睁/闭/眯/眩晕… | `#454f58` (grey 750) |
| **海豹鼻 muzzle** | 两个交叠的浅灰圆＝鼻子+上唇，**常驻** | `#cdd7dd` (grey 350) |
| **脸颊弧 cheeks** | 两条浅灰小勾（胡须/腮线），可换腮红 | `#d7e0e5` (grey 300) |
| **嘴 mouth** | **仅在需要时才画**，由情绪决定 | `#454f58` |
| 身体 body | 白色 mochi 蛋形 + 两只小脚 | `#fbfcfc` (grey 25) |
| 芽 sprout | 头顶青绿三叶芽 | `#20937a` (teal 600) |
| 附加 extras | Zzz / 汗滴 / 怒气💢 / 泪 / 爱心 / 星光 / glitch | — |

## 文件

```
pibo-face.js               参数化脸部引擎（纯函数, ESM, 浏览器+node 通用）
                           内嵌原始 body/sprout/muzzle/cheeks 真实矢量 path
faces.js                   16 个情绪配置表 → 映射项目状态
build.mjs                  node build.mjs → 生成 svg/*.svg + 合成大图
index.html                 交互 gallery（预设 + 实时合成器 + 下载）
svg/pibo-NN-*.svg          16 张独立情绪矢量图
pibo-expression-sheet.svg  一张总览大图（4 列）
src/body.svg src/sprout.svg  Figma 原始导出（provenance, 含 chrome）
```

## 用法

```bash
# 生成/重建所有静态 SVG
node build.mjs

# 浏览 + 自定义合成（任意静态服务器）
python3 -m http.server -d . 8000   # → http://localhost:8000
```

代码里直接用引擎：

```js
import { buildSVG } from './pibo-face.js';
const svg = buildSVG({
  brows:'angry', eyes:'x', muzzle:true, cheeks:'none',
  mouth:'cat', extras:['anger'], bg:'#f2d3cf'
});
```

## 部件取值

- **brows**: `flat` `raised` `angry` `sad` `none`
- **eyes**: `dot` `wide` `sparkle` `happy(^_^)` `sleep(‿‿)` `half(半睁)` `squeeze(>_<)` `x` `spiral(眩晕)` `heart`
- **muzzle**: `true` / `false`
- **cheeks**: `default` `blush` `none`
- **mouth**: `none` `smile` `frown` `wavy` `open` `o` `cat(ω)`
- **extras**: `zzz` `anger` `sweat` `tear` `hearts` `sparkle` `glitch`

## 映射到项目状态（CLAUDE.md）

6-态活动机 `PiboActivityState` + 拍一拍 `PiboSpeechLine.mood`：

| 情绪 | 项目状态 |
|---|---|
| 发呆 Idle | `IDLE` 发呆（默认） |
| 活跃 Active | `ACTIVE` 步数≥10k / 运动中 |
| 烦躁 Irritated | `IRRITATED` 久坐 / 睡不足 |
| 深眠 Sleeping | `SLEEPING` 22:00–06:00 / 拔毛后 |
| 初醒 Waking | `WAKING` 06:00–10:00 首开 |
| 被打扰 Disturbed | 🅿️ 10min 内≥3 次拍 |
| 正常·说话 Content | pat mood 正常（白圆框） |
| 生气·扭头 Angry | pat mood 生气（黑框+扭头） |
| 呓语 Murmur | pat mood 呓语（深眠/自语） |
| 大笑 / 惊讶 / 难过 / 害羞 / 喜欢 | 能量收集 / 拍照误读 / decline arc / 亲密度 |
| 生病 Sick / 发疯 Glitch | 生病态 / 发疯态 glitch 故障艺术 |

## 接入 iOS 的两条路

1. **静态资源**：`svg/*.svg` → `rsvg-convert -f pdf` 转矢量 PDF imageset（同 `theme-asset-pipeline`
   里 walk_* 的做法），放进 `Assets.xcassets`，按 `activityState` 选图。
2. **SpriteKit 程序化**：`pibo-face.js` 的部件参数模型（brows/eyes/mouth/…）可直接移植成
   `PiboStageScene` 里的程序化脸部图层，实现表情间的补间动画（眨眼/嘴动），无需 16 张位图。
