import XCTest
@testable import CommitPyramid

final class AppSettingsMapSeedTests: XCTestCase {
    private let settingsKey = "com.commitpyramid.app.settings"
    private var savedData: Data?

    override func setUp() {
        super.setUp()
        savedData = UserDefaults.standard.data(forKey: settingsKey)
        UserDefaults.standard.removeObject(forKey: settingsKey)
    }

    override func tearDown() {
        if let savedData {
            UserDefaults.standard.set(savedData, forKey: settingsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: settingsKey)
        }
        super.tearDown()
    }

    func testDefaultMapSeedIsZero() {
        // No settings in UserDefaults → AppSettings.load() creates defaults
        let s = AppSettings.load()
        XCTAssertEqual(s.mapSeed, 0, "Default mapSeed should be 0")
    }

    func testMapSeedPersistenceRoundtrip() {
        let a = AppSettings.load()
        a.mapSeed = 12345
        a.save()
        let b = AppSettings.load()
        XCTAssertEqual(b.mapSeed, 12345, "mapSeed should persist after save/load")
    }

    func testV4ToV5MigrationDefaultsMapSeedToZero() throws {
        // Simulate v4 JSON without mapSeed field.
        let v4JSON: [String: Any] = [
            "version": 4,
            "tasksJsonlPath": "file:///tmp/tasks.jsonl",
            "dataDirectory": "file:///tmp/data",
            "hotkeyKeyCode": 5,
            "hotkeyModifiers": 0,
            "catchUpIntervalMinutes": 5,
            "commitWeightMultiplier": 0.1,
            "taskWeightMultiplier": 1.0,
            "templateFamily": "auto",
            "previewTemplateSilhouette": false
            // No mapSeed field for v4
        ]
        let v4Data = try JSONSerialization.data(withJSONObject: v4JSON)
        UserDefaults.standard.set(v4Data, forKey: settingsKey)

        let loaded = AppSettings.load()
        XCTAssertEqual(loaded.mapSeed, 0, "v4→v5 migration should default mapSeed to 0")
        XCTAssertEqual(loaded.templateFamily, "auto", "v4→v5 should preserve other fields")
    }
}
