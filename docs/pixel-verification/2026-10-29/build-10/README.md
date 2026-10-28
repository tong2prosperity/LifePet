# Pibo 1.5 (10) 发布记录 · 2026-10-29

- 代码已提交并推送至 `origin/main`：`27130da6bbf2c9f83d24a6b8defeb4de7d27b9fb`（`fix: ship companion feedback fixes in build 10`）。
- iOS App、Watch App、Widget 的 Debug／Release 构建号统一由 9 提升至 **10**；版本号保持 **1.5**。
- 内容包含本轮体验修复与复审、实际随包的健康记录／Widget 更新，精确固定已发布 Core `0.35.0`。
- 完整测试 686 项通过、0 失败；最后定向回归 16 项通过、0 失败。

归档：`/Users/trevorlink/Library/Developer/Xcode/Archives/2026-10-29/Pibo 1.5 (10).xcarchive`。

验证均通过：

1. Release `xcodebuild archive`。
2. `Tools/verify_release_metadata.py`：三端均为 1.5 (10)，`ITSAppUsesNonExemptEncryption` 为 Boolean false。
3. `Tools/verify_archive_symbols.py`：三个二进制与 dSYM UUID 一致，Core 静态链接且包含 Rust 调试信息，无空 framework 壳。
4. `codesign --verify --deep --strict`。

上传：命令行导出因 Xcode 的团队账号认证返回 `Failed to Use Accounts`，随后改用 Xcode Organizer 的 App Store Connect 分发路径完成签名与上传。Organizer 明确显示 **Pibo 1.5 (10) uploaded**、Build Number 10；[App Store Connect](https://appstoreconnect.apple.com/teams/4ef64852-7895-4181-bc61-f363635052a7/apps/6796563663/testflight/ios) 已出现 **Version 1.5, Build (10)**，核对时状态为 **Processing**。

未添加 TestFlight 测试组、通知测试者或提交 App Store 审核；Apple 后续处理状态以线上为准。

日志：`/tmp/pibo-release-10-archive.log`、`/tmp/pibo-release-10-upload.log`（CLI 失败原因）；结构化回执见 [build-manifest.json](build-manifest.json)。
