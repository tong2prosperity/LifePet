# Pibo

一款以真实健康数据喂养的电子宠物 App：有成长、有陪伴、有关系，并用自己的方式关心用户。

产品、角色和动画的统一定义见 [docs/PRODUCT.md](docs/PRODUCT.md)。当前交付与发布前验证见[工程状态](docs/product-strategy-202608/05-P0-Implementation-Status.md)。

## 当前产品

固定竖屏 SpriteKit 森林承载 Pibo、健康驱动的 `bo` 生长和共同物件；SwiftUI 承载操作与展示。身体双击产生回应；成熟 `bo` 从物件 Half Sheet 确认直接投入。历史独立全屏打开。餐食相机、散步涂鸦与 Shadow 基础好友关系不受物件门控；具体上线门槛见工程状态。

## 工程

- `Pibo/`：iOS App，读取设备上的 HealthKit。
- `Pibo Watch App/Features/CRCBreathing/`：独立 CRC 呼吸训练。
- `PiboWidgets/`：Widget 与 Live Activity。
- `Shared/DesignSystem/`：LP 设计系统；`Shared/Logging/LPLog.swift`：统一日志。
- `Pibo/Services/Core/`：共享 Rust `pibo-core` 的薄适配层，规则不在平台重复实现。
- HarmonyOS、后端与生产媒体在独立仓库；App 构建使用已选定并同步进本仓库的资源。

完整目录、并发、依赖与发布规则见 [AGENTS.md](AGENTS.md)。HealthKit 睡眠映射等专项约束见 [CLAUDE.md](CLAUDE.md)。Xcode 使用文件系统同步分组，新增源文件通常不需修改项目文件。

## 构建与测试

通过 Xcode 选择 `Pibo` scheme。依赖使用 Xcode SwiftPM，Core 必须固定到已发布的精确版本。

```bash
xcodebuild -project Pibo.xcodeproj -scheme Pibo -configuration Debug build
xcodebuild test -project Pibo.xcodeproj -scheme Pibo -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild -project Pibo.xcodeproj -list
```

真实设备健康数据、相机分割、后台识别和好友同步仍需对应验收，不能用模拟器结果代替。
