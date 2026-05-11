# Health Service Kit Access Notes

## 中文结论

不需要先拿到 Health Service Kit 审批才能开发 LifePet。

“服务申请权限审批”指开发者侧的数据访问准入，不是用户手机上点同意的
系统弹窗。也就是说，需要先在 AppGallery Connect / 华为开发者平台为
这个应用申请开通 Health Service Kit，并说明为什么要读步数、运动记录、
心率、HRV、睡眠等具体数据。审批通过后，应用才有资格在运行时向用户请求
这些已获批的数据范围。

可以先完成：

- 鸿蒙 UI
- 宠物状态机
- Demo / Mock 健康数据
- 本地存储
- 图鉴、上香、一起页
- `HealthDataProvider` 抽象

必须等审批后才能完成：

- 读取真实华为健康数据
- 真机上的 Health Service Kit 授权弹窗
- 上架前的真实健康数据链路验证

## 官方依据（2026-05-11 核查）

- 华为开发者联盟的 Health Service Kit / 运动健康服务产品页明确列出
  `HarmonyOS` 为支持平台，并说明应用和服务开发者需要在取得用户授权的
  前提下，读取华为和生态伙伴开放的运动健康数据或写入数据到运动健康服务。
  参考：
  <https://developer.huawei.com/consumer/cn/hms/huaweihealth/>
- AppGallery Connect 的 HarmonyOS 准备流程要求先在 AGC 创建应用，创建时
  平台选择 HarmonyOS，并让 DevEco 工程的应用名称、包名与 AGC 中创建的
  应用保持一致。参考：
  <https://developer.huawei.com/consumer/en/codelab/AGCPreparation-HarmonyOS/>
- 华为运动健康服务 Codelab 的接入准备写明：需要注册开发者帐号，在开发者
  管理台创建应用、配置应用信息并申请 Health Kit 服务；申请 Health Kit
  时需要勾选产品必须申请的数据授权并提交数据权限申请，申请结果通过邮件
  反馈。参考：
  <https://developer.huawei.com/consumer/cn/codelab/HUAWEIHiHealthCore/index.html>
- 另一个健康场景 Codelab 把 AGC 申请步骤拆成：选择 `Health Kit`、点击
  `申请Health kit服务`、选择需要获取的数据后提交、确认应用已开启。它还
  说明只有获得用户授权后应用才能访问数据。参考：
  <https://developer.huawei.com/consumer/cn/codelab/MyHealth>
- HarmonyOS NEXT 官方推荐并长期演进 Stage 模型，使用 `UIAbility` /
  `WindowStage` 等组件承载应用入口与窗口；当前 `HarmonyLifePet` 按这个
  模型组织。参考：
  <https://developer.huawei.com/consumer/cn/arkui/arkui-stage/>

## 2026-05-11 二次复核

- 官方 Health Service Kit 产品页当前仍列出 `HarmonyOS` 为支持平台，并把
  “应用和服务”接入方式描述为：在取得用户授权前提下读取或写入运动健康
  数据。它没有在公开页面给出可直接替换 `HuaweiHealthDataService` 的
  HarmonyOS 6 ArkTS 读取样例。参考：
  <https://developer.huawei.com/consumer/cn/hms/huaweihealth/>
- 当前可检索到的官方 Codelab 仍主要是 HMS / HiHealth Core 的 Android
  Java/Kotlin 示例，流程包含登录、申请 scope、请求用户授权、注册实时
  步数监听等。它们可作为权限和数据模型参考，但不能直接复制到
  HarmonyOS Stage 模型 ArkTS 工程。参考：
  <https://developer.huawei.com/consumer/cn/codelab/HUAWEIHiHealthCore/index.html>
  和
  <https://developer.huawei.com/consumer/cn/codelab/MyHealth>

因此当前代码保持 `HuaweiHealthDataService` 为隔离的真实服务适配层：
Mock/UI/业务逻辑可以继续完成；等 AGC 服务、Client ID、签名和数据权限
审批明确后，再按届时 SDK 文档实现真实授权和读取。

这里有两个不同的授权层：

1. 开发者平台服务审批：在 AppGallery Connect / 华为开发者平台为这个应用
   开通 Health Service Kit，并申请具体健康数据范围。
2. 用户运行时授权：应用启动后，用户同意把这些健康数据授权给 LifePet。

没有第 1 步，代码可以继续写，但真实健康数据读不到。完成第 1 步后，
仍然需要第 2 步，否则用户拒绝授权时也读不到数据。

Health Service Kit has two separate gates:

1. Platform/service access for the app in Huawei developer tooling.
   - Create or select the app in AppGallery Connect.
   - Apply for Health Kit / Health Service Kit.
   - Select the required data categories, such as steps, workouts, heart rate,
     HRV, active energy, sleep, and mindful minutes.
   - Configure the app identity and Client ID / signing information required by
     the service.
2. Runtime user authorization.
   - Ask the signed-in user to authorize the specific health data scopes.
   - Handle denied, unavailable, and revoked states in app UI.

Development does not need to block on approval. The app can implement UI,
business rules, persistence, demo mode, and the `HealthDataProvider` contract
first. Real user health reads should stay behind `HuaweiHealthDataService` and
replace `MockHealthDataService` only after service access and data scopes are
approved.

For LifePet, the minimum useful data scopes are:

- steps / daily activity
- exercise minutes
- workout records
- active energy
- stand minutes
- heart rate
- HRV
- resting heart rate
- sleep
- meditation or mindfulness duration, if available

Keep the permission request aligned with product copy: every requested scope
must map to a visible user benefit in vitality, energy, mood, sleep cards,
workout feeding, or memorial history.

## LifePet 申请时不要请求全部权限

华为 Codelab 为演示方便会请求全部 scope。LifePet 上架版本不应照搬这种
做法，而应只申请 `requiredHealthScopes` 中能解释清楚用户价值的数据：

- 步数、站立、活动能量：体力、今日活动完成度
- 运动分钟、运动记录：运动投喂、今日建议、卡片记录
- 心率、静息心率、HRV：心情和压力状态
- 睡眠总量、深睡、REM、开始时间：精力和睡眠卡片
- 冥想 / 正念时长：心情建议

申请材料里需要把每个 scope 对应到这些用户可见功能；否则即使代码完成，
也可能在服务或数据权限审批阶段被要求补充说明。
