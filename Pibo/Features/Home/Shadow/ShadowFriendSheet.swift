import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The complete one-friend Shadow Pibo flow. It mirrors the Harmony contract:
/// a connection is mutual, health numbers never leave the device, and the
/// latest valid semantic snapshot remains useful while either side is offline.
struct ShadowFriendSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(ShadowService.self) private var service
    @Environment(ShadowFriendStore.self) private var friendStore
    @Environment(ShadowSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let ownerName: String
    var manifestMode = false

    @State private var page: Page = .automatic
    @State private var shortCode = ""
    @State private var feedback = ""
    @State private var showsLogin = false
    @State private var disconnectAction: DisconnectAction?

    private enum Page { case automatic, invite, code, manage, blocks }
    private enum DisconnectAction { case disconnect, block }
    private enum Mode {
        case loggedOut, empty, invite, code, pending, incoming, waiting
        case manifest, status, manage, blocks, ended
    }

    private var view: ShadowStateDTO? { service.view }
    private var friendName: String {
        service.incoming?.inviterDisplayName ?? view?.friend?.displayName ?? "好友"
    }

    private var mode: Mode {
        guard auth.phase == .loggedIn else { return .loggedOut }
        switch page {
        case .invite: return .invite
        case .code: return .code
        case .manage: return .manage
        case .blocks: return .blocks
        case .automatic: break
        }
        if service.incoming != nil { return .incoming }
        if view?.endedEvent != nil || view?.state == .ended { return .ended }
        if view?.state == .inviteOutgoing { return .pending }
        if view?.state == .activeWaitingSnapshot { return .waiting }
        if let view, view.state.isActive {
            if manifestMode, friendStore.needsManifestTeaching(view) { return .manifest }
            return .status
        }
        return .empty
    }

    private var eyebrow: String {
        switch mode {
        case .incoming: "来自\(friendName)的邀请"
        case .pending: "邀请已发出"
        case .waiting: "已和\(friendName)连接"
        case .manifest: "首次显示"
        case .status: "\(friendName)的 Pibo · \(ShadowFriendPresentationValues.relativeUpdate(view?.friend?.snapshot))"
        case .manage: "好友 · \(friendName)"
        case .invite: "只能连接 1 位好友"
        case .blocks: "好友隐私设置"
        case .ended: "好友连接"
        default: "好友 Pibo"
        }
    }

    private var title: String {
        switch mode {
        case .loggedOut: "登录后连接好友"
        case .invite: "邀请好友连接 Pibo"
        case .code: "输入好友邀请短码"
        case .pending: "等待好友接受邀请"
        case .incoming: "接受\(friendName)的好友邀请？"
        case .waiting: "还没有收到\(friendName)的状态"
        case .manifest: "这是\(friendName)的 Pibo"
        case .status: "\(friendName)的 Pibo"
        case .manage: "管理与\(friendName)的连接"
        case .blocks: "已屏蔽的用户"
        case .ended: "好友连接已经结束"
        case .empty: "连接 1 位好友"
        }
    }

    private var detents: Set<PresentationDetent> {
        switch mode {
        case .manage, .invite, .incoming, .blocks: [.fraction(0.72), .large]
        case .code, .pending: [.fraction(0.62), .large]
        case .manifest, .status: [.fraction(0.48), .large]
        default: [.fraction(0.54), .large]
        }
    }

    var body: some View {
        VStack(spacing: LP.Spacing.m) {
            PiboMossSheetHandle()
            header
            ScrollView {
                VStack(spacing: LP.Spacing.m) {
                    content
                    if service.isBusy { ProgressView().tint(PiboMoss.Color.foundationTeal) }
                    if !feedback.isEmpty {
                        feedbackText(feedback, color: PiboMoss.Color.foundationTeal)
                    } else if let error = service.lastError {
                        feedbackText(error.displayMessage, color: SwiftUI.Color(hex: 0x8F3D36))
                    }
                }
                .padding(.bottom, LP.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.top, LP.Spacing.s)
        .piboMossSheet(detents: detents)
        .task(id: service.incomingCredential) {
            guard auth.phase == .loggedIn,
                  !service.incomingCredential.isEmpty,
                  service.incoming == nil else { return }
            _ = await service.previewInvitation()
        }
        .onDisappear {
            if manifestMode, let view, friendStore.needsManifestTeaching(view) {
                friendStore.markManifestTeachingShown(view)
            }
        }
        .sheet(isPresented: $showsLogin) { BackendLoginView() }
        .onChange(of: auth.phase) { _, phase in
            guard phase == .loggedIn else { return }
            showsLogin = false
            Task {
                await sync.syncNow(forceSnapshot: true)
                if !service.incomingCredential.isEmpty { _ = await service.previewInvitation() }
            }
        }
        .confirmationDialog(
            disconnectAction == .block
                ? "解除连接并屏蔽\(friendName)？"
                : "解除与\(friendName)的连接？",
            isPresented: Binding(
                get: { disconnectAction != nil },
                set: { if !$0 { disconnectAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(disconnectAction == .block ? "解除连接并屏蔽" : "解除好友连接", role: .destructive) {
                let block = disconnectAction == .block
                disconnectAction = nil
                Task { if await service.disconnect(block: block) { dismiss() } }
            }
            Button("保留连接", role: .cancel) { disconnectAction = nil }
        } message: {
            Text(disconnectAction == .block
                ? "解除后，你们都不能再看到对方的 Pibo 状态。屏蔽后，\(friendName)也不能再次邀请你。"
                : "解除后，你和\(friendName)都不能再看到对方的 Pibo 状态。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .lpText(LP.Typography.c1Medium)
                    .tracking(1.1)
                    .foregroundStyle(PiboMoss.Color.foundationTeal)
                Text(title)
                    .lpText(LP.Typography.h3)
                    .foregroundStyle(PiboMoss.Color.forestInk)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭好友面板")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .loggedOut: loggedOutContent
        case .empty: emptyContent
        case .invite: inviteContent
        case .code: codeContent
        case .pending:
            if let invitation = view?.outgoingInvitation { pendingContent(invitation) }
            else { emptyContent }
        case .incoming: incomingContent
        case .waiting: waitingContent
        case .manifest: manifestContent
        case .status:
            if let snapshot = view?.friend?.snapshot { statusContent(snapshot) }
            else { waitingContent }
        case .manage:
            if let view { manageContent(view) } else { emptyContent }
        case .blocks: blocksContent
        case .ended:
            if let view { endedContent(view) } else { emptyContent }
        }
    }

    private var loggedOutContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("好友连接会跟随你的 Pibo 账号，并在设备之间保持一致。")
            PiboMossPrimaryButton(title: "登录 Pibo") { showsLogin = true }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("连接后，你和好友都能在自己的首页看到对方 Pibo 的最新状态。")
            infoRow(icon: "person.2", text: "只能连接 1 位好友 · 双方接受后生效")
            PiboMossPrimaryButton(title: "邀请好友") { page = .invite }
            PiboMossSecondaryButton(title: "输入邀请短码") { page = .code }
            if (view?.blockedCount ?? 0) > 0 {
                textButton("管理已屏蔽用户") {
                    page = .blocks
                    Task { await service.refreshBlocks() }
                }
            }
            privacyNote("好友只能看到 Pibo 状态，看不到步数、睡眠时长或其他健康数据。")
        }
    }

    private var inviteContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("好友接受后，你们都能看到对方 Pibo 的最新状态。任何一方都可以暂停分享或解除连接。")
            optionRow(icon: "link", title: "生成邀请链接", detail: "生成后可分享消息或二维码") {
                feedback = ""
                Task {
                    if await service.createInvitation(displayName: ShadowSnapshotValues.displayName(ownerName)) == nil {
                        feedback = service.lastError?.displayMessage ?? "邀请暂时无法生成"
                    } else {
                        page = .automatic
                    }
                }
            }
            privacyNote("一次只能发送 1 个邀请。邀请会在 72 小时后失效。")
        }
    }

    private var codeContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("让好友把邀请页面里的 10 位短码发给你。输入短码后，你仍需要明确接受邀请。")
            TextField("输入 10 位邀请短码", text: $shortCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .tracking(2)
                .padding(.horizontal, LP.Spacing.m)
                .frame(height: 52)
                .background(PiboMoss.Color.raisedNeutral, in: RoundedRectangle(cornerRadius: PiboMoss.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                        .strokeBorder(PiboMoss.Color.hairline, lineWidth: 1)
                }
                .onChange(of: shortCode) { _, value in shortCode = normalizedCode(value) }
            PiboMossPrimaryButton(
                title: "查看邀请",
                disabledReason: "请输入完整短码",
                isEnabled: shortCode.count == 10 && !service.isBusy
            ) {
                feedback = ""
                Task {
                    if await service.previewInvitation(shortCode) == nil {
                        feedback = service.lastError?.displayMessage ?? "这个邀请无法使用"
                    } else {
                        page = .automatic
                    }
                }
            }
        }
    }

    private func pendingContent(_ invitation: ShadowInvitationDTO) -> some View {
        VStack(spacing: LP.Spacing.m) {
            HStack(spacing: LP.Spacing.m) {
                ShadowQRCode(value: invitation.inviteUrl)
                    .frame(width: 108, height: 108)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18).strokeBorder(PiboMoss.Color.hairline.opacity(0.7))
                    }
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text("PIBO · \(invitation.shortCode)")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    Text("\(ShadowFriendPresentationValues.inviteExpiry(invitation.expiresAt))\n好友接受前不会分享状态")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ShareLink(item: invitationShareText(invitation)) {
                mossPrimaryLabel("发送邀请")
            }
            Button {
                UIPasteboard.general.string = invitation.shortCode
                feedback = "邀请短码已复制。"
            } label: {
                mossSecondaryLabel("复制邀请短码")
            }
            .buttonStyle(.plain)
            textButton("取消邀请", color: SwiftUI.Color(hex: 0x8F3D36)) {
                Task { _ = await service.cancelInvitation(id: invitation.id) }
            }
        }
    }

    private var incomingContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("接受后，你和\(friendName)都能在首页看到对方 Pibo 的最新状态。")
            infoRow(icon: "eye", text: "在线时很快更新；离线时显示上次状态")
            privacyNote("不会分享步数、睡眠时长或其他健康数据。你可以随时暂停分享。")
            if service.incoming?.canAccept == false {
                feedbackText(incomingUnavailableReason, color: SwiftUI.Color(hex: 0x8F3D36))
                PiboMossPrimaryButton(title: "知道了") { dismiss() }
            } else {
                PiboMossPrimaryButton(title: "接受并连接", isEnabled: !service.isBusy) {
                    Task {
                        if await service.acceptInvitation(
                            displayName: ShadowSnapshotValues.displayName(ownerName)
                        ) != nil {
                            await sync.syncNow(forceSnapshot: true)
                        }
                    }
                }
                PiboMossSecondaryButton(title: "拒绝邀请", isEnabled: !service.isBusy) {
                    Task { if await service.rejectIncoming(block: false) { dismiss() } }
                }
                textButton("拒绝并屏蔽", color: SwiftUI.Color(hex: 0x8F3D36)) {
                    Task { if await service.rejectIncoming(block: true) { dismiss() } }
                }
            }
        }
    }

    private var waitingContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("连接已完成。收到\(friendName)下次更新的状态后，对方的 Pibo 会显示在你的首页。")
            infoRow(icon: "hourglass", text: "目前还没有收到\(friendName)的状态")
            privacyNote("系统只接收\(friendName)接受连接后的状态，不读取之前的健康数据。")
        }
    }

    private var manifestContent: some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("以后，\(friendName)的 Pibo 会显示在首页。点击它可以查看最近分享的状态。")
            privacyNote("这段说明只出现 1 次。以后状态更新时不会自动打开面板。")
            PiboMossPrimaryButton(title: "返回首页") { dismiss() }
        }
    }

    private func statusContent(_ snapshot: ShadowSnapshotDTO) -> some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("当前状态：\(ShadowFriendPresentationValues.stateSentence(snapshot.publicStateId))")
            infoRow(
                icon: "clock",
                text: "\(ShadowFriendPresentationValues.relativeUpdate(snapshot)) · 不包含健康数据"
            )
            if view?.friend?.sharingPaused == true {
                privacyNote("\(friendName)已暂停状态分享。这里显示的是暂停前最后一次状态。")
            }
            PiboMossPrimaryButton(title: "给\(friendName)送一束光", isEnabled: !service.isBusy) {
                Task {
                    feedback = await service.sendLight() == nil
                        ? "暂时没有送出。"
                        : "已给\(friendName)送出一束光。"
                }
            }
            textButton("管理好友连接") { page = .manage }
        }
    }

    private func manageContent(_ value: ShadowStateDTO) -> some View {
        VStack(spacing: LP.Spacing.m) {
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: "camera.macro")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PiboMoss.Color.foundationTeal)
                    .frame(width: 48, height: 48)
                    .background(SwiftUI.Color(hex: 0xE5E5F5).opacity(0.72), in: Circle())
                    .overlay { Circle().strokeBorder(PiboMoss.Color.foundationTeal.opacity(0.55), lineWidth: 2) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(friendName).lpText(LP.Typography.b3Medium).foregroundStyle(PiboMoss.Color.forestInk)
                    Text("\(ShadowFriendPresentationValues.connectedDate(value.connectedAt))\n状态\(ShadowFriendPresentationValues.relativeUpdate(value.friend?.snapshot))")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            manageToggle(
                icon: "square.and.arrow.up",
                title: "把我的 Pibo 状态发给\(friendName)",
                detail: "关闭后，\(friendName)只能看到你关闭前的状态",
                isOn: !value.mySharingPaused
            ) { enabled in Task { _ = await service.setSharingPaused(!enabled) } }
            manageToggle(
                icon: "eye",
                title: "在首页显示\(friendName)的 Pibo",
                detail: "关闭后只隐藏显示，不解除好友连接",
                isOn: !friendStore.hideOnHome
            ) { enabled in friendStore.setHideOnHome(!enabled) }
            privacyNote("关闭分享后，你仍能查看\(friendName)最近一次更新的 Pibo 状态。")
            textButton("解除好友连接", color: SwiftUI.Color(hex: 0x8F3D36)) {
                disconnectAction = .disconnect
            }
            Divider().overlay(SwiftUI.Color(hex: 0x9F4B43).opacity(0.15))
            textButton("解除连接并屏蔽\(friendName)", color: SwiftUI.Color(hex: 0x8F3D36)) {
                disconnectAction = .block
            }
        }
    }

    private var blocksContent: some View {
        VStack(spacing: 0) {
            if service.blocks.blocks.isEmpty {
                bodyText("没有已屏蔽的用户。")
            } else {
                ForEach(service.blocks.blocks) { block in
                    HStack {
                        Text(block.displayName)
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(PiboMoss.Color.forestInk)
                        Spacer()
                        Button("解除屏蔽") { Task { _ = await service.unblock(id: block.id) } }
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(PiboMoss.Color.foundationTeal)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    Divider().overlay(PiboMoss.Color.hairline.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endedContent(_ value: ShadowStateDTO) -> some View {
        VStack(spacing: LP.Spacing.m) {
            bodyText("这段好友连接已经结束。你们都不能再看到对方的 Pibo 状态。")
            PiboMossPrimaryButton(title: "知道了") {
                if let id = value.endedEvent?.id { Task { await service.acknowledgeEnded(id: id) } }
                dismiss()
            }
        }
    }

    private func bodyText(_ value: String) -> some View {
        Text(value)
            .lpText(LP.Typography.b3Regular)
            .foregroundStyle(PiboMoss.Color.forestInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PiboMoss.Color.foundationTeal)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.34), in: Circle())
            Text(text)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
    }

    private func privacyNote(_ value: String) -> some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PiboMoss.Color.foundationTeal)
            Text(value)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(PiboMoss.Color.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: icon).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).lpText(LP.Typography.b3Medium)
                    Text(detail).lpText(LP.Typography.c1Regular).foregroundStyle(PiboMoss.Color.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(PiboMoss.Color.tertiaryInk)
            }
            .foregroundStyle(PiboMoss.Color.forestInk)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(PiboMoss.Color.hairline.opacity(0.7)) }
    }

    private func manageToggle(
        icon: String,
        title: String,
        detail: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(PiboMoss.Color.foundationTeal)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lpText(LP.Typography.b3Medium).foregroundStyle(PiboMoss.Color.forestInk)
                Text(detail).lpText(LP.Typography.c1Regular).foregroundStyle(PiboMoss.Color.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .tint(PiboMoss.Color.foundationTeal)
        }
        .frame(minHeight: 68)
        .overlay(alignment: .bottom) { Divider().overlay(PiboMoss.Color.hairline.opacity(0.7)) }
    }

    private func textButton(_ title: String, color: SwiftUI.Color = PiboMoss.Color.foundationTeal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func feedbackText(_ value: String, color: SwiftUI.Color) -> some View {
        Text(value)
            .lpText(LP.Typography.c1Regular)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func mossPrimaryLabel(_ title: String) -> some View {
        Text(title)
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: PiboMoss.Control.buttonHeight)
            .background(PiboMoss.Color.foundationTeal, in: RoundedRectangle(cornerRadius: PiboMoss.Radius.control))
    }

    private func mossSecondaryLabel(_ title: String) -> some View {
        Text(title)
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(PiboMoss.Color.forestInk)
            .frame(maxWidth: .infinity, minHeight: PiboMoss.Control.buttonHeight)
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                    .strokeBorder(PiboMoss.Color.hairline.opacity(0.7))
            }
    }

    private func normalizedCode(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
    }

    private var incomingUnavailableReason: String {
        switch service.incoming?.reason {
        case "relationship_exists": "你已经连接了 1 位好友。请先解除现有连接，再接受新的邀请。"
        case "own_invitation": "这是你自己发出的邀请，不能由你接受。"
        default: "这个邀请已经失效或无法使用。"
        }
    }

    private func invitationShareText(_ invitation: ShadowInvitationDTO) -> String {
        "我邀请你和我连接 Pibo。接受后，我们都能看到对方 Pibo 的最新状态。\n\(invitation.inviteUrl)\n邀请短码：\(invitation.shortCode)"
    }
}

private struct ShadowQRCode: View {
    let value: String

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(8)
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(PiboMoss.Color.forestInk)
        }
    }

    private var image: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}
