import SwiftUI
import StoreKit

/// Pibo 会员 purchase page (behind the settings「Pibo 会员」row): current
/// status, the monthly / yearly auto-renewable plans, and 恢复购买. Purchases
/// run through `MembershipService` (StoreKit 2 + pibo-server registration).
struct MembershipSheet: View {
    @Environment(MembershipService.self) private var membership
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var showLogin = false
    @State private var pendingProductID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                header
                statusCard
                plansSection
                footer
            }
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showLogin) {
            BackendLoginView()
        }
        .onChange(of: auth.phase) { _, phase in
            guard phase == .loggedIn,
                  let id = pendingProductID,
                  let product = membership.products.first(where: { $0.id == id }) else { return }
            pendingProductID = nil
            showLogin = false
            Task { await membership.purchase(product) }
        }
        .task {
            if membership.products.isEmpty { await membership.loadProducts() }
            await membership.refreshServerStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text("Pibo 会员"))
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
            // Pibo 的傲娇口吻 — 会员是「约定」的延长线，不是买服务。
            Text(AppLocalization.text("...约定...再续一段...啵。"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .padding(.top, LP.Spacing.s)
    }

    // MARK: 当前状态

    private var statusCard: some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: membership.isMember ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(membership.isMember ? LP.Fill.foundationAccent : LP.Content.quarternary)
            VStack(alignment: .leading, spacing: 2) {
                Text(membership.isMember
                     ? AppLocalization.text(membership.entitlement?.plan == "monthly" ? "月度会员 · 已开通" : "年度会员 · 已开通")
                     : AppLocalization.text("尚未开通"))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                if let expires = membership.entitlement?.expiresAt {
                    Text(AppLocalization.text("有效期至 ") + expires.formatted(date: .abbreviated, time: .omitted))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                if let accountStatusText {
                    Text(accountStatusText)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }

    private var accountStatusText: String? {
        guard auth.phase == .loggedIn,
              let status = membership.serverStatus,
              let provider = status.provider else { return nil }
        let store = switch provider {
        case "apple_iap": "Apple App Store"
        case "huawei_iap": "华为应用内支付"
        default: provider
        }
        return "账号记录 · \(store) · \(status.isActive ? "有效" : "已结束")"
    }

    // MARK: 方案

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("选择方案"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            if membership.products.isEmpty {
                HStack {
                    if membership.isLoadingProducts {
                        ProgressView()
                        Text(AppLocalization.text("正在加载商店..."))
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    } else {
                        Text(membership.lastError ?? AppLocalization.text("商店暂时不可用"))
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                }
                .padding(LP.Spacing.m)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(membership.products.enumerated()), id: \.element.id) { index, product in
                        planRow(product)
                        if index < membership.products.count - 1 {
                            Divider().overlay(LP.Separator.primary)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgContainer)
                )
            }

            if let error = membership.lastError, !membership.products.isEmpty {
                Text(error)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Fill.foundationError)
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let owned = membership.entitlement?.productID == product.id
        let purchasing = membership.purchasingProductID == product.id
        return HStack(spacing: LP.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(product.displayPrice + periodSuffix(product))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: 0)
            if owned {
                Text(AppLocalization.text("当前方案"))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Fill.foundationAccent)
            } else {
                Button {
                    LPHaptics.tap()
                    if auth.phase == .loggedIn {
                        Task { await membership.purchase(product) }
                    } else {
                        pendingProductID = product.id
                        showLogin = true
                    }
                } label: {
                    Group {
                        if purchasing {
                            ProgressView()
                        } else {
                            Text(AppLocalization.text(
                                auth.phase == .loggedIn ? "订阅" : "登录后订阅"
                            ))
                                .lpText(LP.Typography.b3Medium)
                        }
                    }
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LP.Fill.foundationAccent))
                }
                .buttonStyle(.plain)
                .disabled(membership.purchasingProductID != nil)
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
    }

    private func periodSuffix(_ product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .month: return AppLocalization.text(" / 月")
        case .year: return AppLocalization.text(" / 年")
        default: return ""
        }
    }

    // MARK: 恢复购买 + 说明

    private var footer: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Button {
                Task { await membership.restore() }
            } label: {
                Text(AppLocalization.text("恢复购买"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Fill.foundationAccent)
            }
            .buttonStyle(.plain)

            Text(AppLocalization.text("订阅自动续期，可随时在 App Store 的订阅设置中取消。"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.quarternary)
        }
    }
}

#Preview {
    MembershipSheet()
        .environment(MembershipService())
        .environment(AuthService())
        .environment(EconomyService())
}
