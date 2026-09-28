/// Why the login page is showing. Login is on demand (2026-09-28, mirrors
/// HarmonyOS `LoginPurpose`): the meal camera is the only MVP feature that
/// needs an account, so the page says so instead of blocking Home.
enum LoginPurpose: Equatable {
    /// Settings 「手机号 · 未登录」.
    case account
    /// The meal camera asked first; a successful login resumes the camera.
    case mealCamera

    var title: String {
        switch self {
        case .account: "登录 Pibo 账号"
        case .mealCamera: "拍餐食前，先登录一下"
        }
    }

    var subtitle: String {
        switch self {
        case .account: "目前账号只用于餐食识别。未注册的手机号验证通过后将自动注册。"
        case .mealCamera: "识别盘子里的食物需要连上 Pibo 的服务。未注册的手机号验证通过后将自动注册。"
        }
    }
}
