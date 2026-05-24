import XCTest
@testable import CommitPyramid

final class CityEngineTemplateAssignmentTests: XCTestCase {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ce-tmpl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(at dir: URL, templateFamily: String = "egyptian") -> CityEngine {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)
        engine.templateFamily = templateFamily
        return engine
    }

    func testNewProjectGetsTemplateAssigned() {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        engine.ingestTaskCompletion(
            project: "proj-A", title: "first task",
            taskId: nil, source: nil, ts: Date()
        )
        let project = engine.state.projects["proj-A"]
        XCTAssertNotNil(project)
        XCTAssertNotNil(project?.templateName)
        XCTAssertEqual(project?.templateFamily, "egyptian")
    }

    func testTemplateAssignmentIsDeterministic() {
        let dir1 = makeTempDir(); let dir2 = makeTempDir()
        let e1 = makeEngine(at: dir1)
        let e2 = makeEngine(at: dir2)
        e1.ingestTaskCompletion(project: "proj-X", title: "t",
            taskId: nil, source: nil, ts: Date())
        e2.ingestTaskCompletion(project: "proj-X", title: "t",
            taskId: nil, source: nil, ts: Date())
        let n1 = e1.state.projects["proj-X"]?.templateName
        let n2 = e2.state.projects["proj-X"]?.templateName
        XCTAssertNotNil(n1)
        XCTAssertEqual(n1, n2)
    }

    func testFirstUnitIsRoadInTemplate() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        engine.ingestTaskCompletion(project: "proj-R", title: "first",
            taskId: nil, source: nil, ts: Date())
        let project = try XCTUnwrap(engine.state.projects["proj-R"])
        let firstUnitId = try XCTUnwrap(project.unitIds.first)
        let unit = try XCTUnwrap(engine.state.units[firstUnitId.uuidString])
        XCTAssertEqual(unit.kind, .road)
        let templateName = try XCTUnwrap(project.templateName)
        let template = try XCTUnwrap(DistrictTemplateCatalog.byName(templateName))
        let roadSlots = template.slots.filter { $0.role == .road }
        let absoluteRoadSlots: Set<GridPoint> = Set(roadSlots.map {
            GridPoint(x: project.districtOrigin.x + $0.x,
                      y: project.districtOrigin.y + $0.y)
        })
        XCTAssertTrue(absoluteRoadSlots.contains(unit.position),
            "Expected \(unit.position) to be in road slots \(absoluteRoadSlots)")
    }

    func testTemplateAssignmentReplayable() throws {
        // First engine writes events, then second engine on same dir replays them.
        // CityEngine.init() calls replayFromLog() automatically (see CityEngineTests).
        let dir = makeTempDir()
        let e1 = makeEngine(at: dir)
        e1.ingestTaskCompletion(project: "proj-Replay", title: "t",
            taskId: nil, source: nil, ts: Date())
        let nameFirst = try XCTUnwrap(e1.state.projects["proj-Replay"]?.templateName)

        // Second engine on same dir — init replays events.jsonl automatically.
        // templateFamily must match so that Picker resolves the same family.
        let e2 = makeEngine(at: dir)
        let nameSecond = try XCTUnwrap(e2.state.projects["proj-Replay"]?.templateName)
        XCTAssertEqual(nameFirst, nameSecond)
    }
}
