# Pibo 文档库（docs/）

面向工程与设计的技术文档目录。产品/世界观类文档仍在 `legacy_docs/` 与 `product-web-prototype/`，本目录专门收纳「实现层」参考资料。

## 目录

### health-data/ — 健康与运动数据
- [Apple Watch × HealthKit 数据目录](health-data/apple-watch-healthkit-data-catalog.md)
  Apple Watch 能采集、并能被 iOS 端通过 HealthKit 读到的全部运动/健康数据清单。按「戴表必有 / 习惯触发 / 型号依赖 / 需主动测量」分级，含类型系统说明、采样特性、授权与后台读取要点，以及到 Pibo 三维能量（活力 / 静息 / 心绪）的映射建议。

> 范围约定：本目录的健康数据文档**只统计「Apple Watch 采集 → 写入 HealthKit → iOS 可读」这条链路**，不含 iPhone 自身传感器、第三方手环/秤/血压计写入 HealthKit 的数据。
