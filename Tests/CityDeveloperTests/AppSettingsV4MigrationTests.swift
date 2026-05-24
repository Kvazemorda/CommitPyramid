import XCTest
@testable import CommitPyramid

final class AppSettingsV4MigrationTests: XCTestCase {

    // Тесты используют UserDefaults.standard (как продакшн AppSettings).
    // setUp сохраняет текущее значение settings-ключа, tearDown восстанавливает.
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

    func test_DefaultTemplateFamilyIsAuto() {
        // Пусто в UserDefaults → AppSettings.load() даёт defaults
        let settings = AppSettings.load()
        XCTAssertEqual(settings.templateFamily, "auto")
        XCTAssertEqual(settings.previewTemplateSilhouette, false)
    }

    func test_V3ToV4MigrationPreservesOtherSettings() throws {
        // Засеиваем UserDefaults в формате v3 (без templateFamily)
        let v3JSON: [String: Any] = [
            "version": 3,
            "tasksJsonlPath": "file:///tmp/tasks.jsonl",
            "dataDirectory": "file:///tmp/data",
            "hotkeyKeyCode": 5,
            "hotkeyModifiers": 0,
            "catchUpIntervalMinutes": 10,
            "commitWeightMultiplier": 0.5,
            "taskWeightMultiplier": 2.0
        ]
        let v3Data = try JSONSerialization.data(withJSONObject: v3JSON)
        UserDefaults.standard.set(v3Data, forKey: settingsKey)

        let settings = AppSettings.load()
        XCTAssertEqual(settings.commitWeightMultiplier, 0.5,
                       "v3 commitWeightMultiplier должен сохраниться")
        XCTAssertEqual(settings.taskWeightMultiplier, 2.0,
                       "v3 taskWeightMultiplier должен сохраниться")
        XCTAssertEqual(settings.catchUpIntervalMinutes, 10)
        XCTAssertEqual(settings.templateFamily, "auto",
                       "v3 не знал про templateFamily → дефолт auto")
        XCTAssertEqual(settings.previewTemplateSilhouette, false)
    }

    func test_TemplateFamilyPersistenceRoundtrip() {
        let s1 = AppSettings.load()
        s1.templateFamily = "egyptian"
        s1.previewTemplateSilhouette = true
        s1.save()

        let s2 = AppSettings.load()
        XCTAssertEqual(s2.templateFamily, "egyptian")
        XCTAssertEqual(s2.previewTemplateSilhouette, true)
    }
}
