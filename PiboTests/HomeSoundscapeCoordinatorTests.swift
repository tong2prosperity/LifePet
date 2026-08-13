import Foundation
import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeSoundscapeCoordinatorTests {
    @Test func startPreservesConfigurationOrderAndEnvironmentValues() {
        let fixture = Fixture()
        let environment = PiboStageEnvironment(
            localHour: 12,
            weather: .clear
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let petID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        HomeSoundscapeCoordinator.start(
            enabled: false,
            presentation: .active,
            environment: environment,
            date: date,
            petID: petID,
            soundscape: fixture
        )

        #expect(fixture.events == ["enabled:false", "presentation:active", "refresh", "apply"])
        #expect(fixture.appliedEnvironment == environment)
        #expect(fixture.appliedDate == date)
        #expect(fixture.appliedPetID == petID)
    }

    @Test func updateOnlyAppliesTheSuppliedEnvironmentValues() {
        let fixture = Fixture()
        let environment = PiboStageEnvironment(
            localHour: 23,
            weather: .rain
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let petID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        HomeSoundscapeCoordinator.update(
            environment: environment,
            date: date,
            petID: petID,
            soundscape: fixture
        )

        #expect(fixture.events == ["apply"])
        #expect(fixture.appliedEnvironment == environment)
        #expect(fixture.appliedDate == date)
        #expect(fixture.appliedPetID == petID)
    }

    @Test func stopSuspendsBeforeStoppingPlayback() {
        let fixture = Fixture()

        HomeSoundscapeCoordinator.stop(soundscape: fixture)

        #expect(fixture.events == ["presentation:suspended", "stop"])
    }
}

@MainActor
private final class Fixture: HomeSoundscapeControlling {
    private(set) var events: [String] = []
    private(set) var appliedEnvironment: PiboStageEnvironment?
    private(set) var appliedDate: Date?
    private(set) var appliedPetID: UUID?

    func setEnabled(_ enabled: Bool) {
        events.append("enabled:\(enabled)")
    }

    func setPresentation(_ presentation: SoundscapePresentation) {
        events.append("presentation:\(presentation)")
    }

    func refreshExternalAudioSuppression() {
        events.append("refresh")
    }

    func apply(environment: PiboStageEnvironment, date: Date, petID: UUID) {
        events.append("apply")
        appliedEnvironment = environment
        appliedDate = date
        appliedPetID = petID
    }

    func stop() {
        events.append("stop")
    }
}
