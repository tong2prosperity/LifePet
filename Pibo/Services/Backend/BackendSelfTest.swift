#if DEBUG
import Foundation

/// Headless end-to-end check of the client↔server round-trip, used to verify
/// connectivity from the simulator without driving the UI. Enabled by launching
/// the app with the `-PiboBackendSelfTest YES` argument; it logs each step to
/// stdout (capturable via `xcrun simctl launch --console`).
///
/// It exercises the real client path: phone-OTP login (test bypass code 123456)
/// → `EconomySyncCoordinator.syncToday()` (today's seeded health data) → a photo
/// behaviour event. Requires a local pibo-server with `enable_test_bypass:true`.
enum BackendSelfTest {
    static let testPhone = "+8613900000000"
    static let bypassCode = "123456"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PiboBackendSelfTest")
    }

    static func run(auth: AuthService, economy: EconomyService, coordinator: EconomySyncCoordinator) async {
        func line(_ s: String) { print("[selftest] \(s)") }

        line("start base=\(APIConfig.shared.baseURL.absoluteString)")

        guard await auth.startLogin(phone: testPhone) else {
            line("startLogin FAILED: \(auth.lastError?.displayMessage ?? "unknown")")
            return
        }
        line("code sent")

        guard await auth.completeLogin(phone: testPhone, code: bypassCode) else {
            line("completeLogin FAILED: \(auth.lastError?.displayMessage ?? "unknown")")
            return
        }
        line("logged in user=\(auth.userId ?? "?")")

        // Simulators have no real HealthKit data; stamp today's record so the
        // health→sync→mint path is exercised end-to-end.
        if coordinator.todaySamples().isEmpty {
            coordinator.debugStampTodaySteps()
            line("no real health data — stamped today's record (12000 steps)")
        }

        let samples = coordinator.todaySamples()
        line("built \(samples.count) health samples from today's record")

        if let r = await coordinator.syncToday() {
            line("SYNC OK bo_pending=\(r.boPending) bo_balance=\(r.boBalance) energy_pool=\(r.energyPool) minted=\(r.minted.count) state=\(r.piboState) animations=\(r.animations)")
        } else {
            line("SYNC FAILED: \(economy.lastError?.displayMessage ?? "unknown")")
            return
        }

        if let r = await coordinator.recordAction("photo") {
            line("PHOTO ACTION OK bo_pending=\(r.boPending) energy_pool=\(r.energyPool) animations=\(r.animations)")
        }

        line("DONE")
    }
}
#endif
