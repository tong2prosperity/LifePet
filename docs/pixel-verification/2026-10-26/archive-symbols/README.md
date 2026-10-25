# PiboCoreFFI 上传符号告警修复 · 2026-10-26

> 后续更新：最新推荐归档为 **1.5 (9)**，同样通过本文符号检查，并已补上加密声明。见 [加密声明记录](../export-compliance/README.md)。下文 1.5 (8) 是本轮符号修复的验证产物，未包含后续加密声明。

## 原因与影响

用户上传的 1.5 (7) 显示 `Upload completed with warnings`。归档内 `PiboCoreFFI.framework` 的 UUID 确为 `E562FFE0-44DA-3ECE-B2EB-49B51793C7B7`，与截图一致；它约 50KB，没有导出符号，主 App 的动态依赖也不包含它。

发布的 Core 原始二进制实际上是静态 archive。`builtin-copy -remove-static-executable` 处理 framework-type XCFramework 时，把静态代码留在主 App 中，同时生成并嵌入了空 dylib framework。上传校验把这个空壳当作需要独立 dSYM 的运行镜像，因而告警。项目 Release 原本已经是 `dwarf-with-dsym`，不是 App 漏开了这个选项。

这条警告本身不表示 App 上传失败。旧包的静态代码正常运行；原 Rust release archive 还设置了 strip，缺少完整 Rust 调试信息，因此旧包不能事后凭重建获得匹配的 Rust 源码级符号。

Apple 说明：[静态 framework 的链接与嵌入](https://developer.apple.com/documentation/xcode/creating-a-static-framework)、[构建调试信息及 UUID 对应关系](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)。

## 修复

- Core 正式发布并推送 `0.34.6`（`1884fa7`），iOS exact pin 与 `Package.resolved` 已接入正式标签；Harmony 子模块同步正式版本。
- XCFramework 改为显式 `.a` library slices + C headers，保持原 `PiboCoreFFI` 模块与 Swift API，避免 Xcode 再嵌入无用 framework 壳。
- C 头文件及 module map 位于 `Headers/PiboCoreFFI/`。同时消费 PiboChessNative 时，两者不会争写 Xcode 的 `include/module.modulemap`。
- 仅 Apple builder 覆盖 release 的 debug/strip 选项，保留真实 Rust DWARF；Core 调试信息进入主 App 的 dSYM。没有创建假 dSYM，也没有关闭符号上传。
- Rust 领域规则、C ABI 和其他平台 release profile 不变。没有修改 SwiftPM 缓存中的包或让 App 指向本地 SDK。
- iOS 主 App、Watch 与 Widget 构建号统一为 **1.5 (8)**，新归档包含此前 Widget 同步修复。
- 新增 `Tools/verify_archive_symbols.py`：检查归档内没有 Core framework 壳、App 没有该动态依赖、每个 App／扩展／framework 的 UUID 匹配 dSYM，并验证主 App dSYM 内真实的 `pibo_growth_level` Rust 调试条目。旧归档会明确失败。

## 验证

- Core：`cargo fmt --check`、285 项 Rust 测试、无默认特性的 release 构建、Apple artifact verifier、清理缓存后的 91 项 Swift FFI 测试均通过。
- 额外 iOS 兼容构建：Core 与正式 PiboChessSDK `0.1.1` 同时参与的独立消费包构建通过，验证静态库头文件输出不冲突。
- Harmony：125 项本地检查与 Debug HAP 构建全部通过。
- iOS：530 项／103 套测试全部通过；1.5 (8) **ARCHIVE SUCCEEDED**；App／Watch／Widget 三个 dSYM UUID 全部匹配，主 App dSYM 内存在真实 Rust `pibo_growth_level` 调试条目；`codesign --verify --deep --strict` 通过。
- App Store Connect：已按此前上传授权尝试提交 1.5 (8)，但命令行导出立即失败：`Failed to Use Accounts`，要求团队 `XD36G5SYYU` 的 App Store Connect 访问权限。**没有上传成功**。可以在 Xcode Organizer 选择新的 1.5 (8) 归档手动 Distribute；不能继续使用旧的 1.5 (7) 归档验证此修复。

验证命令：

```sh
python3 Tools/verify_archive_symbols.py \
  '/Users/trevorlink/Library/Developer/Xcode/Archives/2026-10-26/Pibo 1.5 (8).xcarchive'
```

归档路径：`/Users/trevorlink/Library/Developer/Xcode/Archives/2026-10-26/Pibo 1.5 (8).xcarchive`。
日志：`/tmp/pibo-core-symbols-*.log`、`/tmp/pibo-symbol-fix-archive.log`、`/tmp/pibo-symbol-fix-app-tests.log`、`/tmp/pibo-symbol-fix-harmony-*.log`。

旧的 1.5 (7) 归档不会随源代码更新自动改变；修复只对重新归档的构建生效。

符号审计日志：`/tmp/pibo-symbol-fix-archive-audit.log`。上传尝试：`/tmp/pibo-symbol-fix-upload/upload.log`；没有关闭 `uploadSymbols`，也没有改写已上传的旧包。
