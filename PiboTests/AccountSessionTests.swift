import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct AccountSessionTests {
    @Test func rootGateOrdersOnboardingLoginHome() {
        #expect(RootGate.resolve(shouldPresentFirstRun: true, isAuthenticated: false) == .onboarding)
        #expect(RootGate.resolve(shouldPresentFirstRun: true, isAuthenticated: true) == .onboarding)
        #expect(RootGate.resolve(shouldPresentFirstRun: false, isAuthenticated: false) == .login)
        #expect(RootGate.resolve(shouldPresentFirstRun: false, isAuthenticated: true) == .home)
        #expect(RootGate.resolve(shouldPresentFirstRun: true, isAuthenticated: false, bypassesGates: true) == .home)
    }

    @Test func masksMainlandNumbersOnly() {
        #expect(AuthService.maskAccountPhone("+8615912345256") == "159****5256")
        #expect(AuthService.maskAccountPhone("15912345256") == "159****5256")
        #expect(AuthService.maskAccountPhone("8615912345256") == "159****5256")
        #expect(AuthService.maskAccountPhone("+44 20 7946 0958 12") == "")
        #expect(AuthService.maskAccountPhone("12345") == "")
    }

    @Test func loginPhoneNormalizationAndBackendFormat() {
        #expect(LoginFlowView.normalizedPhone("159 1234 5256") == "15912345256")
        #expect(LoginFlowView.normalizedPhone("+86 159-1234-5256") == "15912345256")
        #expect(LoginFlowView.normalizedPhone("1591234525699") == "15912345256")
        #expect(LoginFlowView.backendPhone("15912345256") == "+8615912345256")
    }

    @Test func tokenStoreKeepsOnlyMaskedPhoneAndClearsItWithTheSession() {
        let tokens = TokenStore(service: "PiboTests.auth.\(UUID().uuidString)")
        defer { tokens.clear() }

        tokens.save(access: "a", refresh: "r", userId: "u1", maskedPhone: "159****5256")
        #expect(tokens.isLoggedIn)
        #expect(tokens.maskedPhone == "159****5256")

        // Refresh rotation rewrites the pair without touching the masked phone.
        tokens.save(access: "a2", refresh: "r2")
        #expect(tokens.maskedPhone == "159****5256")

        tokens.clear()
        #expect(!tokens.isLoggedIn)
        #expect(tokens.maskedPhone == nil)
        #expect(tokens.userId == nil)
    }

    @Test func preUpgradeSessionHasNoMaskedPhone() {
        let tokens = TokenStore(service: "PiboTests.auth.\(UUID().uuidString)")
        defer { tokens.clear() }
        tokens.save(access: "a", refresh: "r", userId: "u1")
        let auth = AuthService(tokens: tokens)
        #expect(auth.phase == .loggedIn)
        #expect(auth.accountPhone == nil)
    }

    @Test func restoredSessionExposesMaskedPhone() {
        let tokens = TokenStore(service: "PiboTests.auth.\(UUID().uuidString)")
        defer { tokens.clear() }
        tokens.save(access: "a", refresh: "r", userId: "u1", maskedPhone: "138****2530")
        #expect(AuthService(tokens: tokens).accountPhone == "138****2530")
    }

    @Test func settingsHealthEntryFollowsRealConnectionWhenStoryPaused() {
        func shows(_ state: HealthDataService.AuthState) -> Bool {
            SettingsHealthEntryPolicy.showsConnectRow(
                temporaryCooperationEnabled: false,
                storyAccepted: false,
                hasObservedHealthSource: false,
                healthAuthState: state
            )
        }
        #expect(shows(.unknown))
        #expect(shows(.denied))
        #expect(!shows(.granted))
        #expect(!shows(.requesting))
        #expect(!shows(.unavailable))

        // Story mode keeps its original observed-source rule.
        #expect(SettingsHealthEntryPolicy.showsConnectRow(
            temporaryCooperationEnabled: true,
            storyAccepted: true,
            hasObservedHealthSource: false,
            healthAuthState: .granted
        ))
        #expect(!SettingsHealthEntryPolicy.showsConnectRow(
            temporaryCooperationEnabled: true,
            storyAccepted: false,
            hasObservedHealthSource: false,
            healthAuthState: .unknown
        ))
    }

    @Test func legalDocumentsMatchSharedContract() {
        #expect(LegalDocuments.updatedAt == "2026-09-15")
        #expect(LegalDocuments.document(id: "privacy") == LegalDocuments.privacyPolicy)
        #expect(LegalDocuments.document(id: "terms") == LegalDocuments.userAgreement)
        #expect(LegalDocuments.document(id: "other") == nil)
        #expect(LegalDocuments.privacyPolicy.title == "隐私协议")
        #expect(LegalDocuments.userAgreement.title == "用户协议")
        #expect(LegalDocuments.privacyPolicy.sections.map(\.heading) == [
            "适用范围", "我们收集的信息", "我们如何使用信息", "第三方服务", "权限说明",
            "存储与保留期限", "删除与注销", "未成年人", "协议更新与联系我们",
        ])
        #expect(LegalDocuments.userAgreement.sections.map(\.heading) == [
            "服务说明", "账号", "使用规范", "知识产权", "服务变更与终止", "免责与责任限制", "协议更新",
        ])
        let allText = (LegalDocuments.privacyPolicy.sections + LegalDocuments.userAgreement.sections)
            .flatMap(\.paragraphs).joined()
        #expect(!allText.contains("HarmonyOS"))
        #expect(!allText.contains("华为"))
    }
}
