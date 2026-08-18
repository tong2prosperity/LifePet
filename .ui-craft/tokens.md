# Existing token spine

Pibo 已有 `Shared/DesignSystem/`。首版改造继续以 LP primitive 为基础，并通过 `PiboMoss` 给森林 Half-sheet、相机与餐食结果建立一层稳定的产品语义；它不改写 History 已使用的 LP 主题，也不是第二套基础 token。

## Moss Glass semantic layer

- 代码入口：`Shared/DesignSystem/Pibo/PiboMossGlass.swift`；鸿蒙对应 `entry/src/main/ets/theme/PiboDesignSystem.ets`。
- `canvasMist #EAF1F2`：独立浅色画布；`sheetMoss #E5F0E8`：Half-sheet 叠色；`raisedNeutral #F5F7F4`：局部高可读表面。
- `forestInk #263632` / `secondaryInk #667570` / `hairline #BFD1C9`：文字与边界。
- `foundationTeal #24B596`：唯一交互主强调色；berry / amber / blue 只用于蛋白质、碳水和脂肪的数据标记。
- 标准组件：`PiboMossSheetHandle`、`PiboMossPrimaryButton`、`PiboMossSecondaryButton`、`PiboMossInlineNotice`、`PiboMossSkeletonBar` 与 `.piboMossSheet(...)`。

## Color

- 页面与弹层优先使用 `LP.Fill.*`、`LP.Content.*`、`LP.Border.*`、`LP.Separator.*`。
- 品牌／生长主强调色使用 `LP.Fill.foundationAccent`；Home 既有 teal 控件继续沿用既有 token，不新建第二个同权重强调色。
- 错误只使用 `LP.Fill.foundationError`；Pibo 当前情绪和健康状态不能只靠颜色区分。
- App 保持 light-only，除非未来正式增加暗色 token。

## Typography

- 产品 UI 使用 `LP.Typography.uiH*`、`b*`、`c*`，中文由 PingFang SC 承载。
- Pibo 台词沿用既有 speech bubble 体系，不为上下文动作增加第三套字体。
- `bo` 数量使用 medium UI 字体与等宽数字；按钮和标题使用 sentence case。

## Spacing and shape

- 间距只取 `LP.Spacing.*`；44pt 是最小交互区域。
- 圆角只取 `LP.Radius.*` 或既有组件明确值；不把所有表面做成同一圆角卡片。
- 阴影使用 `LP.Shadow.*` 和现有 `.lpShadow`，不增加泛光作为主要可用性提示。

## Motion

- SwiftUI 与 SpriteKit 延续现有 motion stack，不引入新动画库。
- 高频点击反馈控制在约 100–150ms；面板 200–300ms；首次 `bo`／物件唤醒可以使用现有较长叙事编排。
- 所有新动作必须支持 `accessibilityReduceMotion`，降级后仍直接到达最终状态。
- 动画只表达状态变化、空间关系和确认；不增加无目的漂浮、弹跳或循环闪烁。

## Accessibility

- SpriteKit 交互通过 SwiftUI accessibility representation 提供等价按钮。
- 图标按钮必须有本地化 accessibility label；状态和禁用原因不只靠颜色。
- Toast 不承载持续性或关键错误；`dataUnknown` 提供持久可点击说明。
