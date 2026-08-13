import Foundation
import XCTest
@testable import Pibo

final class PiboThemeSelectionPersistenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PiboThemeSelectionPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testMissingSelectionRestoresDefaultWithoutPersistingIt() {
        let restored = PiboThemeSelectionPersistence.restore(from: defaults)

        XCTAssertEqual(restored, PiboThemeCatalog.defaultTheme.id)
        XCTAssertNil(defaults.object(
            forKey: PiboPersistenceKeys.Defaults.selectedThemeID
        ))
    }

    func testRegisteredSelectionRoundTrips() {
        let themeID = PiboThemeCatalog.defaultTheme.id

        PiboThemeSelectionPersistence.save(themeID, to: defaults)

        XCTAssertEqual(
            defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID),
            themeID
        )
        XCTAssertEqual(
            PiboThemeSelectionPersistence.restore(from: defaults),
            themeID
        )
    }

    func testUnknownSelectionFallsBackAndRemovesStalePersistence() {
        defaults.set(
            "retired-theme",
            forKey: PiboPersistenceKeys.Defaults.selectedThemeID
        )

        let restored = PiboThemeSelectionPersistence.restore(from: defaults)

        XCTAssertEqual(restored, PiboThemeCatalog.defaultTheme.id)
        XCTAssertNil(defaults.object(
            forKey: PiboPersistenceKeys.Defaults.selectedThemeID
        ))
    }

    func testSavingUnknownSelectionDoesNotOverwriteRegisteredSelection() {
        let themeID = PiboThemeCatalog.defaultTheme.id
        PiboThemeSelectionPersistence.save(themeID, to: defaults)

        PiboThemeSelectionPersistence.save("unknown-theme", to: defaults)

        XCTAssertEqual(
            defaults.string(forKey: PiboPersistenceKeys.Defaults.selectedThemeID),
            themeID
        )
    }

    func testResetRemovesPersistedSelection() {
        PiboThemeSelectionPersistence.save(
            PiboThemeCatalog.defaultTheme.id,
            to: defaults
        )

        PiboThemeSelectionPersistence.reset(in: defaults)

        XCTAssertNil(defaults.object(
            forKey: PiboPersistenceKeys.Defaults.selectedThemeID
        ))
    }
}
