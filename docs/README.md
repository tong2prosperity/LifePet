# Pibo 文档库（docs/）

面向工程与设计的技术文档目录。首页交互/机制文档在 `product-web-prototype/`；**叙事/世界观的当前真源在本目录 `narrative/`**（取代 `legacy_docs/` 与 0603 文档里的旧世界观框架）。

## 目录

### narrative/ — 叙事 / 世界观（当前真源）
- [Pibo 叙事圣经 · 失忆 × 约定 × 碎片叙事](narrative/pibo-narrative-bible.md)
  Pibo 是谁、故事怎么讲、语气怎么拿。三根支柱（性格恒定 / 失忆装置 / 魂系碎片），
  「AI 科幻外壳 → 无年代『失去身体』神话」的取舍，花的隐喻，表达系统，记忆恢复度进度轴，
  衰退叙事，与代码的迁移接口。**取代**旧的「异世界种花小精灵 + 魔丸→傲娇→伙伴三阶段」框架。
- [Pibo 故事线 · 约定条文 + 碎片池 + 显影规则](narrative/pibo-storyline-fragments.md)
  可直接落地的作者素材：约定全 12 条（含第七条终显情感锚）、揭示层 L0–L5、四类碎片文案池、
  载体→机制映射、记忆恢复度模型、衰退行为、续写风格指南。

### health-data/ — 健康与运动数据
- [Apple Watch × HealthKit 数据目录](health-data/apple-watch-healthkit-data-catalog.md)
  Apple Watch 能采集、并能被 iOS 端通过 HealthKit 读到的全部运动/健康数据清单。按「戴表必有 / 习惯触发 / 型号依赖 / 需主动测量」分级，含类型系统说明、采样特性、授权与后台读取要点，以及到 Pibo 三维能量（活力 / 静息 / 心绪）的映射建议。

> 范围约定：本目录的健康数据文档**只统计「Apple Watch 采集 → 写入 HealthKit → iOS 可读」这条链路**，不含 iPhone 自身传感器、第三方手环/秤/血压计写入 HealthKit 的数据。
