import XCTest
@testable import MoshTerminal

final class AppSettingsPredictionPreferenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsPredictionPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultPredictionPreferenceIsAlways() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.predictionDisplayPreference, .always)
    }

#if !DEBUG
    func testStoredAdaptiveClampsToAlwaysInShipping() {
        let defaults = makeDefaults()
        defaults.set(PredictionDisplayPreference.adaptive.rawValue, forKey: "settings.predictionDisplayPreference")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.predictionDisplayPreference, .always)
    }
#endif
}
