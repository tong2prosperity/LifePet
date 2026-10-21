# iOS 会员账号绑定与后端合同

> 最近核对：2026-09-03  
> 客户端：StoreKit 2  
> provider：`apple_iap`

## 新购与恢复

- 新购前必须登录 Pibo 账号。客户端调用 `POST /api/v1/membership/app-account-token`，把返回的稳定 UUID 作为 StoreKit 2 的 `appAccountToken`；取不到或无法解析 token 时不拉起支付。
- `POST /api/v1/membership/verify` 始终显式发送 `provider = apple_iap` 和 StoreKit 2 的签名交易 JWS。服务端保留缺省 Apple provider 只用于旧客户端兼容，新客户端不依赖该缺省值。
- 经 StoreKit 本机验证的交易先更新本机 entitlement，再 best-effort 登记服务端，最后 `finish()`。服务端暂时不可达不能撤销用户已付款的本机权益；后续 entitlement 刷新会再次登记。
- 恢复购买使用 `AppStore.sync()` 和 `Transaction.currentEntitlements`，即使用户尚未登录 Pibo 账号也允许恢复本机权益；只有服务端登记需要登录。
- `GET /api/v1/membership/status` 仅展示账号侧记录，并按 `provider` 区分 Apple App Store 与华为应用内支付。它不能覆盖或伪造本机 StoreKit entitlement。

## 隐私与账号删除

- 客户端日志和分析事件不记录 JWS、`appAccountToken`、账号 token 或交易正文。
- 服务端账号导出入口为 `GET /api/v1/account/export`；会员模块的导出包含账号所属订阅和绑定记录。
- 账号删除由服务端统一隐私事务调用 membership Subject，清理订阅、Apple `appAccountToken`、华为 binding token 和 provider event 去重记录。
- 删除账号不会伪造 App Store 退款或取消系统订阅；用户仍应在 App Store 管理订阅。重新登录后的账号归属必须重新通过服务端 token 与 StoreKit 交易校验。

## 发布前验收

- App Store Sandbox：月／年新购、取消、Ask to Buy、进程退出后恢复、续期、退款／撤销。
- 账号边界：同一 StoreKit 交易跨 Pibo 账号登记必须被服务端拒绝；退出登录后不得显示上一账号的服务端会员状态。
- 故障边界：离线或 `/verify` 失败时保留本机权益；未验证交易不得授予权益。
- 隐私：执行账号导出和删除，确认会员记录进入导出且删除后相关表无残留。
