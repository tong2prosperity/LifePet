import SwiftUI

/// Local-only account entry shown before the HealthKit onboarding.
///
/// The production transport will eventually replace the two completion seams
/// below. For now no button calls `AuthService` or touches the network.
struct LoginFlowView: View {
    let onComplete: () -> Void

    var body: some View {
        LoginPhoneView(onAppleContinue: onComplete)
            .navigationDestination(for: LoginRoute.self) { route in
                switch route {
                case .verification(let phone):
                    LoginVerificationView(phone: phone, onComplete: onComplete)
                }
            }
    }
}

private enum LoginRoute: Hashable {
    case verification(phone: String)
}

private struct LoginPhoneView: View {
    let onAppleContinue: () -> Void

    @State private var phone = ""
    @State private var acceptedTerms = true

    private var isPhoneValid: Bool {
        phone.count == 11
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: max(120, proxy.size.height * 0.22))

                VStack(alignment: .leading, spacing: LP.Spacing.l) {
                    titleBlock
                    phoneField

                    NavigationLink(value: LoginRoute.verification(phone: phone)) {
                        LoginPrimaryButtonLabel(title: "验证并登录")
                    }
                    .buttonStyle(LoginPrimaryButtonStyle())
                    .disabled(!isPhoneValid || !acceptedTerms)
                    .accessibilityHint("进入验证码输入页面")

                    Text("or")
                        .lpText(LP.Typography.body)
                        .foregroundStyle(LP.Content.quarternary)
                        .frame(maxWidth: .infinity)

                    Button {
                        guard acceptedTerms else { return }
                        onAppleContinue()
                    } label: {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(LP.Content.primary)
                            .frame(width: 54, height: 54)
                            .overlay {
                                Circle().stroke(LP.Separator.primary, lineWidth: 1)
                            }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!acceptedTerms)
                    .accessibilityLabel("使用 Apple 登录")
                }

                Spacer(minLength: LP.Spacing.xxl)
                termsRow
            }
            .padding(.horizontal, LP.Spacing.xxl5)
            .padding(.bottom, LP.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LP.Fill.bgSurface.ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: phone) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(11))
            if digits != value { phone = digits }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text("欢迎来到 Pibo")
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)

            Text("未注册的手机号验证通过后将自动注册")
                .lpText(LP.Typography.body)
                .foregroundStyle(LP.Content.quarternary)
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text("手机号")
                .lpText(LP.Typography.body)
                .foregroundStyle(LP.Content.quarternary)
                .padding(.leading, LP.Spacing.m)

            HStack(spacing: LP.Spacing.m) {
                Text("+86")
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
                    .padding(.horizontal, 17)
                    .frame(height: 52)
                    .background(fieldBackground)

                TextField("请输入手机号", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .lpText(LP.Typography.body)
                    .foregroundStyle(LP.Content.primary)
                    .padding(.horizontal, 17)
                    .frame(height: 52)
                    .background(fieldBackground)
                    .accessibilityLabel("手机号")
            }
        }
    }

    private var fieldBackground: some View {
        Capsule()
            .fill(LP.Fill.bgContainer)
            .overlay {
                Capsule().stroke(LP.Border.secondary, lineWidth: 1)
            }
    }

    private var termsRow: some View {
        Button {
            acceptedTerms.toggle()
        } label: {
            HStack(alignment: .top, spacing: LP.Spacing.s) {
                ZStack {
                    Circle()
                        .stroke(LP.Content.secondary, lineWidth: 1.5)
                    if acceptedTerms {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x522A39))
                    }
                }
                .frame(width: 20, height: 20)

                (
                    Text("登录即代表你同意我们的 ")
                    + Text("隐私政策").bold().underline()
                    + Text(" 和 ")
                    + Text("用户协议").bold().underline()
                )
                .font(.system(size: 12))
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(acceptedTerms ? "已同意隐私政策和用户协议" : "未同意隐私政策和用户协议")
    }
}

private struct LoginVerificationView: View {
    enum ValidationState: Equatable {
        case editing
        case success
        case error
    }

    let phone: String
    let onComplete: () -> Void

    @State private var code = ""
    @State private var validationState: ValidationState = .editing
    @State private var countdown = 59
    @State private var resendGeneration = 0
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(spacing: LP.Spacing.xxl) {
            Text("请输入验证码")
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity)

            Image("login_otp_pibo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 99)

            VStack(spacing: 0) {
                Text("验证码已发送至")
                Text(formattedPhone)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17))
            .foregroundStyle(LP.Content.primary)

            verificationInput

            Button {
                guard countdown == 0 else { return }
                countdown = 59
                resendGeneration += 1
                code = ""
                validationState = .editing
                isCodeFocused = true
            } label: {
                Text(countdown > 0 ? "重新发送 \(countdown)s" : "重新发送")
                    .font(.system(size: 17))
                    .underline()
                    .foregroundStyle(LP.Content.primary.opacity(countdown > 0 ? 0.44 : 0.72))
            }
            .buttonStyle(.plain)
            .disabled(countdown > 0)
        }
        .padding(.horizontal, LP.Spacing.xxl5)
        .padding(.top, LP.Spacing.xxl3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { isCodeFocused = true }
        .task(id: resendGeneration) {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
        }
        .task(id: code) {
            guard code.count == 6 else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            if code == "000000" {
                validationState = .error
                LPHaptics.decline()
                return
            }

            validationState = .success
            LPHaptics.success()
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }

    private var verificationInput: some View {
        VStack(spacing: LP.Spacing.s) {
            ZStack {
                HStack(spacing: LP.Spacing.s) {
                    ForEach(0..<6, id: \.self) { index in
                        codeBox(at: index)
                    }
                }

                TextField("验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFocused)
                    .opacity(0.01)
                    .accessibilityLabel("六位验证码")
            }
            .contentShape(Rectangle())
            .onTapGesture { isCodeFocused = true }

            statusMessage
                .frame(height: 24)
        }
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(6))
            if digits != value { code = digits }
            if validationState != .editing { validationState = .editing }
        }
    }

    private func codeBox(at index: Int) -> some View {
        let character = index < code.count
            ? String(code[code.index(code.startIndex, offsetBy: index)])
            : ""

        return Text(character)
            .font(.system(size: 21))
            .foregroundStyle(LP.Content.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: 0xE8E1E4, alpha: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .stroke(boxBorderColor(at: index), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch validationState {
        case .editing:
            Color.clear
        case .success:
            Label("验证码已验证", systemImage: "checkmark")
                .foregroundStyle(LP.Fill.foundationSuccess)
                .font(.system(size: 15))
        case .error:
            Label("无效验证码，请重试", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(LP.Fill.foundationError)
                .font(.system(size: 15))
        }
    }

    private func boxBorderColor(at index: Int) -> Color {
        switch validationState {
        case .success:
            return LP.Fill.foundationSuccess
        case .error:
            return LP.Fill.foundationError
        case .editing:
            return index == min(code.count, 5) ? LP.Separator.primary : LP.Separator.secondary
        }
    }

    private var formattedPhone: String {
        guard phone.count == 11 else { return phone }
        let first = phone.prefix(3)
        let middleStart = phone.index(phone.startIndex, offsetBy: 3)
        let middleEnd = phone.index(middleStart, offsetBy: 4)
        let middle = phone[middleStart..<middleEnd]
        let last = phone[middleEnd...]
        return "\(first) \(middle) \(last)"
    }
}

private struct LoginPrimaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(LP.Content.invertPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
    }
}

private struct LoginPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(LP.Colorful.teal600, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

#Preview("Phone") {
    NavigationStack {
        LoginFlowView(onComplete: {})
    }
    .preferredColorScheme(.light)
}

#Preview("Verification") {
    NavigationStack {
        LoginVerificationView(phone: "13832002530", onComplete: {})
    }
    .preferredColorScheme(.light)
}
