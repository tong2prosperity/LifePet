import SwiftUI

/// Phone + SMS login, shown on demand (2026-09-28): the meal camera asks for
/// it with its reason, and Settings 「手机号 · 未登录」 opens it. Nothing blocks
/// Home any more, so the page is always presented and always closable. The
/// code page can go back to the phone page. 隐私政策 / 用户协议 open the in-app
/// legal reader.
struct LoginFlowView: View {
    var purpose: LoginPurpose = .account
    let onComplete: () -> Void
    /// Leaves without logging in. A camera request is dropped with it.
    var onClose: (() -> Void)? = nil

    @Environment(AuthService.self) private var auth
    @State private var phone = ""
    @State private var showingVerification = false
    @State private var legalDocument: LegalDocument?

    var body: some View {
        LoginPhoneView(
            phone: $phone,
            purpose: purpose,
            onCodeSent: { showingVerification = true },
            onOpenLegal: { legalDocument = $0 },
            onClose: onClose
        )
        .navigationDestination(isPresented: $showingVerification) {
            LoginVerificationView(phone: phone, onComplete: onComplete)
        }
        .onChange(of: showingVerification) { _, showing in
            if !showing { auth.resetToPhoneEntry() }
        }
        .fullScreenCover(item: $legalDocument) { document in
            LegalDocumentView(document: document, onClose: { legalDocument = nil })
        }
    }

    /// The backend expects E.164 with the mainland prefix.
    static func backendPhone(_ digits: String) -> String {
        "+86" + digits
    }

    /// Digits only, dropping a pasted 86 country code, capped at 11.
    static func normalizedPhone(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        if digits.count > 11, digits.hasPrefix("86") { digits.removeFirst(2) }
        return String(digits.prefix(11))
    }
}

private struct LoginPhoneView: View {
    static let consentReminder = "请先阅读并勾选同意隐私政策和用户协议"

    @Binding var phone: String
    let purpose: LoginPurpose
    let onCodeSent: () -> Void
    let onOpenLegal: (LegalDocument) -> Void
    let onClose: (() -> Void)?

    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Consent is the user's own act: never pre-ticked.
    @State private var acceptedTerms = false
    @State private var sending = false
    @State private var feedback = ""
    @State private var consentNudgeOffset: CGFloat = 0

    private var isPhoneValid: Bool {
        phone.count == 11
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: LP.Spacing.l) {
                        Spacer()
                            .frame(height: max(96, proxy.size.height * 0.18))
                        titleBlock
                        phoneField

                        // Enabled by a full number alone: an unticked consent
                        // answers the tap with a visible reason instead of a
                        // silently grey button.
                        Button(action: sendCode) {
                            LoginPrimaryButtonLabel(title: "验证并登录")
                        }
                        .buttonStyle(LoginPrimaryButtonStyle(enabled: isPhoneValid))
                        .disabled(!isPhoneValid || sending)
                        .accessibilityHint("发送验证码并进入验证码输入页面")

                        if sending {
                            ProgressView()
                                .tint(LP.Colorful.teal600)
                                .frame(maxWidth: .infinity)
                        } else if !feedback.isEmpty {
                            Text(feedback)
                                .lpText(LP.Typography.b4Regular)
                                .foregroundStyle(LP.Fill.foundationError)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)

                termsRow
            }
            .padding(.horizontal, LP.Spacing.xxl5)
            .padding(.bottom, LP.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LP.Fill.bgSurface.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LP.Content.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, LP.Spacing.s)
                    .accessibilityLabel("关闭登录")
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: phone) { _, value in
            let digits = LoginFlowView.normalizedPhone(value)
            if digits != value { phone = digits }
            feedback = ""
        }
    }

    private func sendCode() {
        guard isPhoneValid, !sending else { return }
        guard acceptedTerms else {
            nudgeConsent()
            return
        }
        sending = true
        feedback = ""
        Task {
            let sent = await auth.startLogin(phone: LoginFlowView.backendPhone(phone))
            sending = false
            if sent {
                onCodeSent()
            } else {
                feedback = auth.lastError?.displayMessage ?? "验证码暂时无法发送，请稍后重试"
            }
        }
    }

    /// Red reason, four short shakes of the consent row and a light tap.
    /// Reduce Motion keeps the reason and the haptic, not the shake.
    private func nudgeConsent() {
        feedback = Self.consentReminder
        LPHaptics.decline()
        guard !reduceMotion else { return }
        consentNudgeOffset = 0
        withAnimation(.easeOut(duration: 0.07).repeatCount(4, autoreverses: true)) {
            consentNudgeOffset = 6
        }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            consentNudgeOffset = 0
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(purpose.title)
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .accessibilityAddTraits(.isHeader)

            Text(purpose.subtitle)
                .lpText(LP.Typography.body)
                .foregroundStyle(LP.Content.quarternary)
                .fixedSize(horizontal: false, vertical: true)
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
        HStack(alignment: .center, spacing: 0) {
            Button {
                acceptedTerms.toggle()
                if acceptedTerms, feedback == Self.consentReminder { feedback = "" }
            } label: {
                ZStack {
                    Circle()
                        .stroke(LP.Content.secondary, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if acceptedTerms {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x522A39))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("同意隐私政策和用户协议")
            .accessibilityValue(acceptedTerms ? "已勾选" : "未勾选")

            // Link-styled runs: tapping 隐私政策 / 用户协议 opens the reader.
            Text(legalAttributedText)
                .font(.system(size: 12))
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    if let document = LegalDocuments.document(id: url.host() ?? "") {
                        onOpenLegal(document)
                    }
                    return .handled
                })
        }
        .offset(x: consentNudgeOffset)
    }

    private var legalAttributedText: AttributedString {
        var text = AttributedString("登录即代表你同意我们的 ")
        var privacy = AttributedString("隐私政策")
        privacy.link = URL(string: "pibo-legal://\(LegalDocuments.privacyPolicy.id)")
        privacy.inlinePresentationIntent = .stronglyEmphasized
        privacy.underlineStyle = .single
        privacy.foregroundColor = LP.Content.primary
        var terms = AttributedString("用户协议")
        terms.link = URL(string: "pibo-legal://\(LegalDocuments.userAgreement.id)")
        terms.inlinePresentationIntent = .stronglyEmphasized
        terms.underlineStyle = .single
        terms.foregroundColor = LP.Content.primary
        text += privacy
        text += AttributedString(" 和 ")
        text += terms
        return text
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

    @Environment(AuthService.self) private var auth
    @State private var code = ""
    @State private var validationState: ValidationState = .editing
    @State private var feedback = ""
    @State private var countdown = 59
    @State private var resendGeneration = 0
    @State private var busy = false
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(spacing: LP.Spacing.xxl) {
            Text("请输入验证码")
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Image("login_otp_pibo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 99)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Text("验证码已发送至")
                Text(formattedPhone)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17))
            .foregroundStyle(LP.Content.primary)

            verificationInput

            Button(action: resend) {
                Text(countdown > 0 ? "重新发送 \(countdown)s" : "重新发送")
                    .font(.system(size: 17))
                    .underline()
                    .foregroundStyle(LP.Content.primary.opacity(countdown > 0 ? 0.44 : 0.72))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(countdown > 0 || busy)
            .accessibilityLabel(countdown > 0 ? "重新发送，\(countdown) 秒后可用" : "重新发送验证码")
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
            guard code.count == 6, validationState != .success else { return }
            await verify(code)
        }
    }

    private func verify(_ digits: String) async {
        guard !busy else { return }
        busy = true
        feedback = ""
        let loggedIn = await auth.completeLogin(
            phone: LoginFlowView.backendPhone(phone),
            code: digits
        )
        busy = false
        guard loggedIn else {
            validationState = .error
            feedback = auth.lastError?.displayMessage ?? "无效验证码，请重试"
            LPHaptics.decline()
            return
        }
        // `RootView` switches to Home on the phase change itself.
        validationState = .success
        LPHaptics.success()
        onComplete()
    }

    private func resend() {
        guard countdown == 0, !busy else { return }
        busy = true
        feedback = ""
        Task {
            let sent = await auth.startLogin(phone: LoginFlowView.backendPhone(phone))
            busy = false
            guard sent else {
                validationState = .error
                feedback = auth.lastError?.displayMessage ?? "验证码暂时无法发送，请稍后重试"
                return
            }
            countdown = 59
            resendGeneration += 1
            code = ""
            validationState = .editing
            isCodeFocused = true
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
                .frame(minHeight: 24)
        }
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(6))
            if digits != value { code = digits }
            if validationState == .error { validationState = .editing }
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
            if busy {
                ProgressView().tint(LP.Colorful.teal600)
            } else {
                Color.clear
            }
        case .success:
            Label("验证码已验证", systemImage: "checkmark")
                .foregroundStyle(LP.Fill.foundationSuccess)
                .font(.system(size: 15))
        case .error:
            Label(feedback.isEmpty ? "无效验证码，请重试" : feedback,
                  systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(LP.Fill.foundationError)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
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
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(enabled ? LP.Colorful.teal600 : LP.Content.quarternary, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

#Preview("Phone") {
    NavigationStack {
        LoginFlowView(onComplete: {})
    }
    .environment(AuthService())
    .preferredColorScheme(.light)
}
