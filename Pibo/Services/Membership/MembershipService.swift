import Foundation
import StoreKit
import os

/// Product ids of the Pibo 会员 auto-renewable subscription group. Must match
/// App Store Connect and the local `PiboStore.storekit` test configuration
/// (Product → Scheme → Run uses it, so purchases work in the simulator with no
/// App Store Connect setup).
enum MembershipProduct {
    static let monthly = "fun.tiebao.co.Pibo.membership.monthly"
    static let yearly = "fun.tiebao.co.Pibo.membership.yearly"
    static let all: Set<String> = [monthly, yearly]
}

/// StoreKit 2 membership client. On-device StoreKit is the entitlement source
/// of truth (works logged-out); every verified transaction's JWS is also pushed
/// to pibo-server (`/api/v1/membership/verify`) when a session exists, so the
/// server keeps its own auditable copy.
@MainActor
@Observable
final class MembershipService {
    /// The locally-held entitlement (from `Transaction.currentEntitlements`).
    struct Entitlement {
        var productID: String
        var expiresAt: Date?

        var plan: String { MembershipProduct.monthly == productID ? "monthly" : "yearly" }
    }

    private(set) var products: [Product] = []
    private(set) var entitlement: Entitlement?
    private(set) var serverStatus: MembershipStatusDTO?
    private(set) var isLoadingProducts = false
    private(set) var purchasingProductID: String?
    private(set) var lastError: String?

    var isMember: Bool { entitlement != nil }

    private let api: APIClient
    private let log = Logger(subsystem: "fun.tiebao.co.Pibo", category: "membership")
    private var updatesTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Call once at launch: starts the lifetime transaction listener (renewals,
    /// Ask-to-Buy approvals, purchases from other devices) and hydrates the
    /// product list + current entitlement.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            // Stable display order: monthly first, then yearly.
            let loaded = try await Product.products(for: MembershipProduct.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            log.error("load products failed: \(String(describing: error))")
            lastError = AppLocalization.text("商店暂时不可用")
        }
    }

    /// Runs a purchase and applies the result. Returns true when the user ends
    /// up entitled (a repurchase of an owned product also lands here via the
    /// updates listener).
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasingProductID = product.id
        lastError = nil
        defer { purchasingProductID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
                Analytics.track(.purchase, screen: "membership",
                                ["product": .string(product.id), "result": isMember ? "success" : "unentitled"])
                return isMember
            case .userCancelled:
                Analytics.track(.purchase, screen: "membership",
                                ["product": .string(product.id), "result": "cancelled"])
                return false
            case .pending:
                lastError = AppLocalization.text("购买等待批准中（家长同意/审核）")
                Analytics.track(.purchase, screen: "membership",
                                ["product": .string(product.id), "result": "pending"])
                return false
            @unknown default:
                return false
            }
        } catch {
            log.error("purchase failed: \(String(describing: error))")
            lastError = AppLocalization.text("购买失败，请重试")
            Analytics.track(.purchase, screen: "membership",
                            ["product": .string(product.id), "result": "failed"])
            return false
        }
    }

    /// 恢复购买 — asks the App Store to sync past transactions, then re-derives
    /// the entitlement.
    func restore() async {
        lastError = nil
        Analytics.track(.purchaseRestore, screen: "membership")
        do {
            try await AppStore.sync()
        } catch {
            log.error("restore failed: \(String(describing: error))")
            lastError = AppLocalization.text("恢复购买失败，请重试")
        }
        await refreshEntitlement()
    }

    /// Re-derives the local entitlement from `currentEntitlements` and pushes
    /// the newest membership JWS to the server (when logged in).
    func refreshEntitlement() async {
        var best: Entitlement?
        var bestJWS: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  MembershipProduct.all.contains(tx.productID),
                  tx.revocationDate == nil else { continue }
            if best == nil || (tx.expirationDate ?? .distantFuture) > (best?.expiresAt ?? .distantPast) {
                best = Entitlement(productID: tx.productID, expiresAt: tx.expirationDate)
                bestJWS = result.jwsRepresentation
            }
        }
        entitlement = best
        if let bestJWS {
            await syncToServer(jws: bestJWS)
        }
    }

    /// Reads the server's view (display-only; local StoreKit wins on-device).
    func refreshServerStatus() async {
        guard await api.isLoggedIn else { return }
        do {
            let status: MembershipStatusDTO = try await api.get("/api/v1/membership/status", authed: true)
            serverStatus = status
        } catch {
            log.debug("server status unavailable: \(String(describing: error))")
        }
    }

    // MARK: - Transaction handling

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let tx) = result else {
            log.error("dropping unverified transaction")
            return
        }
        guard MembershipProduct.all.contains(tx.productID) else {
            await tx.finish()
            return
        }
        if tx.revocationDate == nil, (tx.expirationDate ?? .distantFuture) > .now {
            entitlement = Entitlement(productID: tx.productID, expiresAt: tx.expirationDate)
        } else if entitlement?.productID == tx.productID {
            entitlement = nil
        }
        log.notice("membership tx \(tx.id) product=\(tx.productID, privacy: .public) expires=\(String(describing: tx.expirationDate), privacy: .public)")
        await syncToServer(jws: result.jwsRepresentation)
        await tx.finish()
    }

    /// Best-effort server registration — the local entitlement stands even if
    /// the push fails (offline / logged out); the next refresh retries.
    private func syncToServer(jws: String) async {
        guard await api.isLoggedIn else { return }
        do {
            let status: MembershipStatusDTO = try await api.post(
                "/api/v1/membership/verify",
                body: MembershipVerifyRequest(signedTransaction: jws),
                authed: true)
            serverStatus = status
            log.debug("server verified membership: active=\(status.isActive) plan=\(status.plan ?? "-", privacy: .public)")
        } catch {
            log.error("server verify failed (keeping local entitlement): \(String(describing: error))")
        }
    }
}
