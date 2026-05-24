import XCTest
@testable import CommitPyramid

final class ProjectStateTemplateFieldsTests: XCTestCase {

    func test_DefaultsForNewProject() {
        let project = ProjectState(
            id: "p1", name: "p1",
            createdAt: Date(), lastActivityAt: Date(),
            taskCount: 0, stage: 0, decayLevel: 0, lastDecayLogged: 0,
            districtOrigin: GridPoint(x: 0, y: 0), unitIds: []
        )
        XCTAssertNil(project.templateName)
        XCTAssertNil(project.templateFamily)
        XCTAssertEqual(project.eraLevel, 0)
    }

    func test_CodableRoundtripWithNewFields() throws {
        let original = ProjectState(
            id: "p1", name: "Project One",
            createdAt: Date(timeIntervalSince1970: 1000),
            lastActivityAt: Date(timeIntervalSince1970: 2000),
            taskCount: 5, stage: 2, decayLevel: 0, lastDecayLogged: 0,
            districtOrigin: GridPoint(x: 10, y: 20),
            unitIds: [UUID()],
            templateName: "stage1-deir-el-medina",
            templateFamily: "egyptian",
            eraLevel: 1
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectState.self, from: encoded)

        XCTAssertEqual(decoded.templateName, "stage1-deir-el-medina")
        XCTAssertEqual(decoded.templateFamily, "egyptian")
        XCTAssertEqual(decoded.eraLevel, 1)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.unitIds, original.unitIds)
    }

    func test_CodableBackwardsCompatLegacyJSON() throws {
        // Legacy JSON (формат до TASK-048a — без templateName/templateFamily/eraLevel)
        let legacyJSON = """
        {
          "id": "legacy-project",
          "name": "Legacy Project",
          "createdAt": 0,
          "lastActivityAt": 100,
          "taskCount": 3,
          "stage": 1,
          "decayLevel": 0,
          "lastDecayLogged": 0,
          "districtOrigin": { "x": 5, "y": 5 },
          "unitIds": []
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectState.self, from: data)

        XCTAssertEqual(decoded.id, "legacy-project")
        XCTAssertEqual(decoded.taskCount, 3)
        XCTAssertNil(decoded.templateName, "Legacy snapshot должен дать templateName = nil")
        XCTAssertNil(decoded.templateFamily, "Legacy snapshot должен дать templateFamily = nil")
        XCTAssertEqual(decoded.eraLevel, 0, "Legacy snapshot должен дать eraLevel = 0")
    }
}
