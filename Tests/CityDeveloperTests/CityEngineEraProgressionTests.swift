import XCTest
@testable import CommitPyramid

// MARK: - CityEngineEraProgressionTests (TASK-050 F-25)
//
// Integration tests for era progression after stage 5.
//
// StageRules formula (StageRules.swift):
//   byCount: taskCount >= 51 → stage 5
//   byAge:   ageDays >= 366 → stage 5
//   stage = min(byCount, byAge)
//
// Strategy to reach stage 5:
//   - base = now - 400d → ageDays = 400 → byAge = 5
//   - count >= 51 → byCount = 5 → stage = min(5,5) = 5
//
// EraRules:
//   era 1: stage==5, taskCount>=100, ageDays>=30
//   era 2: stage==5, taskCount>=500, ageDays>=180
//   era 3: stage==5, taskCount>=2000, ageDays>=365

final class CityEngineEraProgressionTests: XCTestCase {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ce-era-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(at dir: URL) -> CityEngine {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let e = CityEngine(eventLog: log, snapshotStore: snap)
        e.templateFamily = "egyptian"
        return e
    }

    /// Ingests `count` tasks for a project.
    /// First task uses `baseDate` (sets createdAt).
    /// Remaining tasks use `lateDate` (large ageDays).
    private func ingestN(_ engine: CityEngine, project: String, count: Int,
                         baseDate: Date, lateDate: Date? = nil) {
        let late = lateDate ?? baseDate.addingTimeInterval(86_400 * 400)
        for i in 0..<count {
            let ts = i == 0 ? baseDate : late.addingTimeInterval(TimeInterval(i))
            engine.ingestTaskCompletion(project: project, title: "t\(i)",
                taskId: nil, source: nil, ts: ts)
        }
    }

    // MARK: - Tests

    /// AC1: eraLevel advances on task_completed; era 1 event in log; templateName has "-monumental" suffix.
    func testEraAdvancesOnTaskCompleted() throws {
        DistrictTemplateCatalog.resetCache()
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        // base = 400 days ago → ageDays = 400 > 365 → byAge = 5
        let base = Date().addingTimeInterval(-86_400 * 400)
        let late = Date()

        // Debug: verify catalog has monumental template
        let monumental = DistrictTemplateCatalog.byName("stage5-akhetaten-monumental")
        XCTAssertNotNil(monumental, "CATALOG: stage5-akhetaten-monumental not found!")

        // Ingest 100 tasks: taskCount=100 → byCount=5 → stage=5; ageDays=400 → era=1
        ingestN(engine, project: "era-proj", count: 100, baseDate: base, lateDate: late)

        let project = try XCTUnwrap(engine.state.projects["era-proj"], "Project not created")
        XCTAssertEqual(project.stage, 5, "Expected stage 5 but got \(project.stage) with taskCount=\(project.taskCount) eraLevel=\(project.eraLevel) template=\(project.templateName ?? "nil")")
        XCTAssertEqual(project.eraLevel, 1, "Expected eraLevel 1 after 100 tasks + 400d, got eraLevel=\(project.eraLevel) stage=\(project.stage) template=\(project.templateName ?? "nil")")
        XCTAssertNotNil(project.templateName, "templateName should not be nil")
        XCTAssertTrue(project.templateName?.hasSuffix("-monumental") == true,
            "templateName should have -monumental suffix, got: \(project.templateName ?? "nil")")

        // Check events.jsonl contains at least one eraAdvanced event with title "1".
        let logURL = dir.appendingPathComponent("events.jsonl")
        let logData = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logData.contains("era_advanced"), "events.jsonl should contain era_advanced event")
        XCTAssertTrue(logData.contains("\"1\"") || logData.contains(#""title":"1""#),
            "eraAdvanced event should have title='1'")
    }

    /// AC2: era template migration keeps existing unit positions.
    func testEraTemplateMigrationKeepsUnitPositions() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 400)
        let late = Date()

        // Ingest 51 tasks to reach stage 5 ceremonial (taskCount=51, ageDays=400).
        ingestN(engine, project: "pos-proj", count: 51, baseDate: base, lateDate: late)
        let projectMid = try XCTUnwrap(engine.state.projects["pos-proj"])
        XCTAssertEqual(projectMid.stage, 5)
        XCTAssertEqual(projectMid.eraLevel, 0, "Should be era 0 with only 51 tasks")

        // Snapshot existing unit positions before era-up.
        let unitsBefore = engine.state.units.values
            .filter { $0.projectId == "pos-proj" }
            .map { ($0.id, $0.position) }
        XCTAssertFalse(unitsBefore.isEmpty, "Should have units before era-up")

        // Ingest to reach 100 tasks total (49 more) → era 1.
        ingestN(engine, project: "pos-proj", count: 49, baseDate: base, lateDate: late)

        let projectAfter = try XCTUnwrap(engine.state.projects["pos-proj"])
        XCTAssertEqual(projectAfter.eraLevel, 1, "Expected eraLevel 1 after 100 tasks")
        XCTAssertTrue(projectAfter.templateName?.hasSuffix("-monumental") == true,
            "templateName should be monumental after era-up")

        // All pre-era units retain their positions.
        for (id, oldPos) in unitsBefore {
            let unit = try XCTUnwrap(engine.state.units[id.uuidString],
                "Unit \(id) disappeared after era migration")
            XCTAssertEqual(unit.position, oldPos,
                "Unit \(id) moved from \(oldPos) to \(unit.position) during era migration")
        }
    }

    /// AC3: era state is replayable (second engine reading same events.jsonl yields same result).
    func testEraIsReplayable() throws {
        let dir = makeTempDir()
        let e1 = makeEngine(at: dir)
        // base = 400 days ago (> 365) → byAge = 5
        let base = Date().addingTimeInterval(-86_400 * 400)
        let late = Date()

        // Ingest 100 tasks → era 1 (100 tasks + 400d > threshold for era 1).
        ingestN(e1, project: "replay-proj", count: 100, baseDate: base, lateDate: late)

        let eraLive = e1.state.projects["replay-proj"]?.eraLevel
        let templateLive = e1.state.projects["replay-proj"]?.templateName
        XCTAssertNotNil(eraLive)
        XCTAssertEqual(eraLive, 1, "First engine should reach era 1")
        XCTAssertTrue(templateLive?.hasSuffix("-monumental") == true,
            "First engine templateName should end with -monumental")

        // Second engine on the same directory replays events.jsonl.
        let e2 = makeEngine(at: dir)
        let eraReplay = e2.state.projects["replay-proj"]?.eraLevel
        let templateReplay = e2.state.projects["replay-proj"]?.templateName

        XCTAssertEqual(eraLive, eraReplay,
            "Replayed eraLevel must match live: expected \(eraLive ?? -1), got \(eraReplay ?? -1)")
        XCTAssertEqual(templateLive, templateReplay,
            "Replayed templateName must match live: expected \(templateLive ?? "nil"), got \(templateReplay ?? "nil")")
    }

    /// Edge case: project with 2000+ tasks + 400d age gets era 3 in a single tick.
    func testEraAdvancesThreeLevelsInSingleTick() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 400)
        let late = Date()

        // Ingest 2000 tasks → era 3 (2000 tasks + 400d).
        ingestN(engine, project: "legacy-proj", count: 2000, baseDate: base, lateDate: late)

        let project = try XCTUnwrap(engine.state.projects["legacy-proj"])
        XCTAssertEqual(project.stage, 5)
        XCTAssertEqual(project.eraLevel, 3, "Expected eraLevel 3 after 2000 tasks + 400d")
        XCTAssertTrue(project.templateName?.hasSuffix("-legacy") == true,
            "templateName should have -legacy suffix for era 3, got: \(project.templateName ?? "nil")")
    }
}
