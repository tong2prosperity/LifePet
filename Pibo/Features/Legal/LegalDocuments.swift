import Foundation

/// 隐私协议与用户协议的应用内正文 —— 登录页与设置页「关于」区的唯一来源。
///
/// 与 HarmonyOS `models/LegalDocuments.ets` 同源（同一份中文正文、同一生效日期）。
/// 只有平台名词按 iOS 的真实数据流替换：HarmonyOS 设备 → iPhone、华为运动健康服务 →
/// Apple 健康（HealthKit）、和风天气与 0.1° 降精度 → Apple 天气（WeatherKit）与公里级粗略
/// 位置；iOS 触觉反馈不需要系统权限，因此「振动」一条不列入权限说明。修改数据流时同步改这里。
struct LegalSection: Hashable, Sendable {
    let heading: String
    let paragraphs: [String]
}

struct LegalDocument: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let updatedAt: String
    let sections: [LegalSection]
}

enum LegalDocuments {
    static let updatedAt = "2026-09-15"

    static func document(id: String) -> LegalDocument? {
        switch id {
        case privacyPolicy.id: privacyPolicy
        case userAgreement.id: userAgreement
        default: nil
        }
    }

    static let privacyPolicy = LegalDocument(
        id: "privacy",
        title: "隐私协议",
        updatedAt: updatedAt,
        sections: [
            LegalSection(heading: "适用范围", paragraphs: [
                "本协议说明 Pibo（以下简称「本应用」）在 iPhone 上如何收集、使用、存储和删除你的信息。使用本应用即表示你已阅读并同意本协议。",
                "本应用面向个人用户，用于把真实生活数据转化为一只陪伴型小生命的状态。本应用不提供医疗诊断，也不构成健康建议。",
            ]),
            LegalSection(heading: "我们收集的信息", paragraphs: [
                "账号信息：登录需要你的手机号。我们通过短信验证码确认手机号归属，并在服务端保存该手机号与一个不透明的账号标识，用于识别你的账号。",
                "健康数据：在你明确授权后，本应用通过 Apple 健康（HealthKit）读取步数、活动能量、运动记录、睡眠、心率、心率变异性、静息心率与血氧等数据。这些数据只在本设备上处理并生成 Pibo 的状态、成长与历史记录，不会上传到我们的服务器。",
                "餐食照片：使用餐食相机时，原始照片只保存在本应用的本地目录。为了识别食物与营养，本应用会把一份经过尺寸约束的分析副本上传到我们的对象存储并交给识别服务处理；分析副本最多保留 30 天后自动删除。",
                "位置信息：为了展示当地天气，本应用会在你授权后获取公里级的粗略位置，并通过 Apple 天气（WeatherKit）请求天气。我们不保存你的坐标。",
                "设备信息：为保证功能正常，本应用会在本地记录通知、声音、触觉等设置，以及必要的运行日志。运行日志不包含你的昵称、照片、验证码或健康数值。",
            ]),
            LegalSection(heading: "我们如何使用信息", paragraphs: [
                "用于完成登录、恢复会话和保护账号安全。",
                "用于在设备上计算 Pibo 的六种状态、bo 的生长与收取、拍一拍反馈以及足迹与睡眠详情。",
                "用于识别餐食并生成营养估算与 Pibo 的观察文案。",
                "用于展示当地天气对森林场景的影响。",
                "我们不会出售你的个人信息，也不会把健康数据用于广告或画像。",
            ]),
            LegalSection(heading: "第三方服务", paragraphs: [
                "短信验证码由阿里云短信服务发送，仅传递你的手机号与验证码模板。",
                "餐食分析副本存储于腾讯云对象存储，并由我们配置的大模型识别服务处理食物与营养信息。",
                "天气数据来自 Apple 天气（WeatherKit），我们只向其提供粗略位置。",
                "Apple 健康由 Apple 提供，健康数据的读取遵循其授权与权限规则。",
            ]),
            LegalSection(heading: "权限说明", paragraphs: [
                "相机：用于拍摄餐食照片。",
                "位置：用于获取粗略位置以展示当地天气。",
                "通知：用于发送运动完成、睡眠总结与压力提醒。",
                "健康数据授权：用于读取运动、睡眠与心率等记录。以上权限均可在系统设置中随时关闭，关闭后对应功能不可用，但不影响其他功能。",
            ]),
            LegalSection(heading: "存储与保留期限", paragraphs: [
                "健康记录、bo 账本、餐食历史与设置保存在本设备的应用沙箱中，卸载应用即删除。",
                "服务端只保留账号信息、登录会话与餐食识别所需的临时分析副本；分析副本 30 天后自动删除。",
            ]),
            LegalSection(heading: "删除与注销", paragraphs: [
                "你可以在「设置 → 账号 → 注销账号」中注销账号。注销会立即撤销你的登录凭证、删除服务端与该账号关联的全部数据，并在本设备上清除本应用的所有本地数据，随后应用会重新进入首次使用流程。",
                "注销不可撤销。若你只是想暂时停用，可以选择退出登录，本地记录会保留。",
            ]),
            LegalSection(heading: "未成年人", paragraphs: [
                "本应用不面向 14 周岁以下的未成年人。如果我们发现在未获得监护人同意的情况下收集了未成年人信息，将尽快删除。",
            ]),
            LegalSection(heading: "协议更新与联系我们", paragraphs: [
                "本协议可能随功能变化而更新，更新后会在本页显示新的生效日期；重大变更会在应用内提示。",
                "如对本协议或你的信息有任何疑问，可通过应用市场页面提供的开发者联系方式与我们联系。",
            ]),
        ]
    )

    static let userAgreement = LegalDocument(
        id: "terms",
        title: "用户协议",
        updatedAt: updatedAt,
        sections: [
            LegalSection(heading: "服务说明", paragraphs: [
                "Pibo 是一款把真实生活数据转化为陪伴型小生命的应用。你在设备上的活动、睡眠与餐食会影响 Pibo 的状态与成长。",
                "本应用提供的状态、观察文案与营养估算仅供陪伴与参考，不是医疗诊断、治疗建议或饮食计划。如有健康问题，请咨询专业人士。",
            ]),
            LegalSection(heading: "账号", paragraphs: [
                "你需要使用本人手机号完成短信验证码登录。首次验证通过的手机号会自动注册账号。",
                "请妥善保管你的手机与验证码。通过你的账号进行的操作视为你本人的行为。",
                "你可以随时退出登录或注销账号。注销会删除与该账号关联的服务端数据与本设备上的本地数据，且不可恢复。",
            ]),
            LegalSection(heading: "使用规范", paragraphs: [
                "请勿利用本应用从事违反法律法规或侵犯他人权益的行为。",
                "请勿通过非正常手段干扰服务运行、伪造健康数据或攻击我们的服务端。",
                "餐食照片仅用于识别你自己的餐食，请勿上传含有他人隐私或违法内容的图片。",
            ]),
            LegalSection(heading: "知识产权", paragraphs: [
                "Pibo 的形象、动画、文案、音频与界面设计由我们或相应权利人享有权利。未经许可，请勿复制、传播或用于商业用途。",
                "你拍摄的餐食照片仍归你所有；你授权我们为完成识别在必要范围内处理其分析副本。",
            ]),
            LegalSection(heading: "服务变更与终止", paragraphs: [
                "我们可能根据产品规划调整、暂停或终止部分功能，并尽量提前在应用内说明。",
                "如你违反本协议，我们可以限制或终止向你提供服务。",
            ]),
            LegalSection(heading: "免责与责任限制", paragraphs: [
                "健康数据的完整性依赖你的设备、穿戴设备与 Apple 健康；数据缺失或延迟时，Pibo 会如实显示不可用，而不会伪造数据。",
                "在法律允许的范围内，我们不对因使用或无法使用本应用造成的间接损失承担责任。",
            ]),
            LegalSection(heading: "协议更新", paragraphs: [
                "本协议可能随功能变化而更新，更新后会在本页显示新的生效日期。继续使用本应用即表示你接受更新后的协议。",
            ]),
        ]
    )
}
