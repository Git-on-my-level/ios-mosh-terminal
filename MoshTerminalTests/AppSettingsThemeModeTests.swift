import XCTest
@testable import MoshTerminal

final class AppSettingsThemeModeTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsThemeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultThemeModeIsDark() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.themeMode, .dark)
    }
}

