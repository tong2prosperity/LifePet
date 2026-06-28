import SwiftUI

/// Phone-OTP login + a small connectivity panel. Not wired into the main flow
/// (the demo must run without a server); present it where login is needed, or
/// from a debug entry, to exercise the auth + economy round-trip against a
/// running pibo-server.
struct BackendLoginView: View {
    @Environment(AuthService.self) private var auth
    @Environment(EconomyService.self) private var economy
    @Environment(\.dismiss) private var dismiss

    @State private var phone = "+8613800000000"
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                switch auth.phase {
                case .loggedOut:
                    phoneSection
                case let .codeSent(phone):
                    codeSection(phone: phone)
                case .loggedIn:
                    loggedInSection
                }

                if let err = auth.lastError ?? economy.lastError {
                    Section {
                        Text(err.displayMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Pibo 后台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var phoneSection: some View {
        Section("手机号登录") {
            TextField("手机号 (+86...)", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            Button {
                Task { await auth.startLogin(phone: phone) }
            } label: {
                HStack {
                    Text("获取验证码")
                    if auth.isBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(auth.isBusy || phone.isEmpty)
        }
    }

    private func codeSection(phone: String) -> some View {
        Section("输入验证码") {
            Text("已发送到 \(phone)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("验证码", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button {
                Task { await auth.completeLogin(phone: phone, code: code) }
            } label: {
                HStack {
                    Text("登录")
                    if auth.isBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(auth.isBusy || code.isEmpty)
            Button("改手机号", role: .cancel) { auth.resetToPhoneEntry() }
        }
    }

    private var loggedInSection: some View {
        Group {
            Section("已登录") {
                if let uid = auth.userId {
                    LabeledContent("用户", value: uid)
                }
                Button("退出登录", role: .destructive) {
                    Task { await auth.logout() }
                }
            }

            Section("连通性自测") {
                Button("测试同步（+10000 步）") {
                    Task {
                        let now = Date()
                        let sample = HealthSampleDTO.steps(
                            10000,
                            start: now.addingTimeInterval(-3600),
                            end: now,
                            uuid: UUID().uuidString)
                        await economy.sync(samples: [sample])
                    }
                }
                .disabled(economy.isSyncing)

                Button("刷新状态") {
                    Task { await economy.refreshState() }
                }

                if let s = economy.state {
                    LabeledContent("头顶 bo", value: "\(s.boPending)")
                    LabeledContent("Pibo 状态", value: s.piboState)
                }
                if let sync = economy.lastSync, !sync.animations.isEmpty {
                    LabeledContent("待演动画", value: sync.animations.joined(separator: ", "))
                }
            }
        }
    }
}
