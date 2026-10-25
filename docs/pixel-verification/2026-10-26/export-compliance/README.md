# App Store Connect 加密声明 · 2026-10-26

## 原因与当前问卷

用户截图是加密出口合规问卷；选中的第一项表示 App 实现了专有／非标准加密算法，会触发文档提交要求。它不是 App 运行错误，也不是前一轮 dSYM 上传告警。

核对当前 iOS 实现与固定依赖后，应选择第四项 **None of the algorithms mentioned above**，按页面继续并保存：

- `APIClient` 与 DataSneaker `EventPipeline` 使用 Apple `URLSession` 进行 HTTPS；
- `TokenStore` 使用系统 Security／Keychain `SecItem*` 保存凭据；
- Core `0.34.6` 的 Rust 依赖只有数学库 libm，拥有领域规则，不是加密实现；
- PiboChessSDK `0.1.1` 的 Swift／C++ 棋盘引擎及 DataSneaker `0.1.0` 没有发现额外加密库或独立加密算法实现；
- 未发现应用自行实现 AES／RSA 等加密，或引入 OpenSSL／BoringSSL／CryptoSwift／libsodium 等实现。

“自研 App／专有 SDK”不等于“专有加密算法”。这里的判断依据是实际加密实现。

## 防止重复填写

已上传的 1.5 (7) 与此前生成的 1.5 (8) 都没有 `ITSAppUsesNonExemptEncryption`。Apple 会因此逐构建询问，即使当前只使用系统提供的加密能力。

在 App、Watch、Widget 的 Debug／Release 共六项构建配置中，补充：

```text
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
```

Xcode 会将其合并为成品 Info.plist 中的 Boolean `false`。这表示当前 App 没有使用需要额外文档的非豁免加密，并不表示 HTTPS 没有加密。没有添加或伪造 `ITSEncryptionExportComplianceCode`。

Apple 依据：[ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)、[系统 HTTPS 与加密声明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。声明按当前代码和依赖核对；未来接入新的自研／第三方加密实现时需要重新评估。

## 验证与新归档

- 新归档：**1.5 (9)**，包含 Core `0.34.6` 的符号打包修复与此前 Widget 同步修复；
- `xcodebuild archive`：**ARCHIVE SUCCEEDED**；
- 新工具 `Tools/verify_release_metadata.py` 在真实归档里检查各 App／扩展的声明类型与值、版本及构建号一致性；旧 1.5 (8) 明确失败，新 1.5 (9) 通过；
- App、Watch、Widget 成品中均为 Boolean `false`，没有误写成字符串 `"NO"`；
- 原 `Tools/verify_archive_symbols.py` 继续通过：没有 Core 空 framework，三个可执行文件 UUID 分别匹配 dSYM，App dSYM 包含真实 Rust 调试信息；
- `codesign --verify --deep --strict` 通过；
- 本轮仅修改发布元数据，没有变更运行逻辑，因此没有重复运行已在 Core `0.34.6` 下通过的 530 项 App 测试。

发布前可运行：

```sh
python3 Tools/verify_release_metadata.py '/path/to/Pibo.xcarchive'
python3 Tools/verify_archive_symbols.py '/path/to/Pibo.xcarchive'
```

归档：`/Users/trevorlink/Library/Developer/Xcode/Archives/2026-10-26/Pibo 1.5 (9).xcarchive`。
日志：`/tmp/pibo-export-compliance-archive.log`、`/tmp/pibo-export-compliance-metadata.log`、`/tmp/pibo-export-compliance-symbols.log`。

## 已上传构建与后续提交

当前网页中的旧构建需要手动按实际情况选择第四项保存；修改本地工程不会改写已上传的旧二进制。

后续使用新的 1.5 (9) 归档。新包携带声明，按 Apple 的此项元数据规则可避免重复问卷。本轮未尝试上传 1.5 (9)：上一轮命令行仍被团队 App Store Connect 账号认证阻塞，不能将本地归档验证等同于线上合规状态已更新。
