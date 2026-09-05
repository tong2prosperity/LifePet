import Foundation
import Testing
@testable import Pibo

struct MembershipContractTests {
    @Test func appleVerificationAlwaysCarriesExplicitProvider() throws {
        let data = try JSONCoding.encoder.encode(
            MembershipVerifyRequest(signedTransaction: "signed-jws")
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["provider"] as? String == "apple_iap")
        #expect(object["signed_transaction"] as? String == "signed-jws")
    }

    @Test func appAccountTokenResponseUsesTheServerContract() throws {
        let data = Data(#"{"app_account_token":"4f9daec9-a4ee-41e4-bb42-ffecf8b03f03","server_time":"2026-09-03T01:00:00Z"}"#.utf8)
        let response = try JSONCoding.decoder.decode(MembershipAppAccountTokenResponse.self, from: data)
        #expect(UUID(uuidString: response.appAccountToken) != nil)
    }

    @Test func debugHealthFixturesAreOptInOnly() {
        #if DEBUG
        #expect(!PiboApp.shouldSeedDebugHistory(arguments: []))
        #expect(!PiboApp.shouldSeedDebugHistory(arguments: ["-SomeOtherFlag"]))
        #expect(PiboApp.shouldSeedDebugHistory(arguments: ["-PiboHistoryDemoContent"]))
        #endif
    }
}
