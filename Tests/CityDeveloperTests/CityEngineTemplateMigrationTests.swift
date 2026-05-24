import XCTest
@testable import CommitPyramid

// MARK: - CityEngineTemplateMigrationTests (TASK-049 F-25)
//
// Integration tests for template migration on stage-up.
//
// StageRules formula (StageRules.swift):
//   byCount: 6-12 tasks → stage 2 | 2-5 → stage 1 | 0-1 → stage 0
//   byAge:   46-120 days → stage 3 | 15-45 → stage 2 | 4-14 → stage 1
//   stage = min(byCount, byAge)
//
// Strategy to reach stage 2:
//   - Create project at base = now - 86_400*60 (60 days ago).
//     → project.createdAt = base
//   - Ingest most tasks at ts = now (60 days later).
//     → ageDays = 60 → byAge = 3
//   - count=10 → byCount=2 → stage = min(2, 3) = 2. ✓
//
// ingestN helper: first task at baseDate (sets createdAt), rest at lateDate (now).
// This ensures ageDays is large while giving us the full task count.

final class CityEngineTemplateMigrationTests: XCTestCase {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ce-mig-\(UUID().uuidString)")
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

    /// Закрывает `count` задач для проекта.
    /// Первая задача использует `baseDate` (устанавливает createdAt проекта).
    /// Остальные задачи используют `lateDate` (должен быть ≥46d после baseDate, для byAge≥3).
    /// Это гарантирует: ageDays = lateDate-baseDate ≥ 46 → byAge = 3.
    private func ingestN(_ engine: CityEngine, project: String, count: Int,
                         baseDate: Date, lateDate: Date? = nil) {
        let late = lateDate ?? baseDate.addingTimeInterval(86_400 * 60)
        for i in 0..<count {
            let ts = i == 0 ? baseDate : late.addingTimeInterval(TimeInterval(i))
            engine.ingestTaskCompletion(project: project, title: "t\(i)",
                taskId: nil, source: nil, ts: ts)
        }
    }

    /// Возвращает имя первого шаблона stage 1 из каталога (динамически).
    private func stage1Name() throws -> String {
        let t = try XCTUnwrap(
            DistrictTemplateCatalog.byStage(1, family: "egyptian").first,
            "No stage-1 egyptian template in catalog")
        return t.name
    }

    // MARK: - Tests

    /// AC1: после stage-up до 2 templateName квартала меняется от stage-1.
    /// Использует 10 задач: taskCount=10 → byCount=2, ageDays≈60 → byAge=3 → stage=2.
    /// Legacy-placed units (вне template slots) не блокируют миграцию:
    /// validator проверяет только units на позициях текущего template.
    func testStageUpMigratesTemplate() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 60)
        ingestN(engine, project: "proj-A", count: 10, baseDate: base)
        let project = engine.state.projects["proj-A"]
        XCTAssertNotNil(project)
        XCTAssertGreaterThanOrEqual(project!.stage, 2, "Expected stage progression to 2+")
        let initialName = try stage1Name()
        XCTAssertNotEqual(project!.templateName, initialName,
            "Template should have migrated from \(initialName)")
    }

    /// AC2: позиции существующих юнитов не изменились после миграции template.
    func testMigrationPreservesUnitPositions() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 60)
        let late = Date()
        // Несколько задач до stage 1 (юниты в slot'ах stage1).
        // 3 задачи → taskCount=3 → byCount=1 → stage 1.
        ingestN(engine, project: "proj-B", count: 3, baseDate: base, lateDate: late)
        // Записываем позиции всех существующих юнитов перед stage-up.
        let snapshotBeforeMigration = engine.state.units.values
            .filter { $0.projectId == "proj-B" }
            .map { ($0.id, $0.position) }
        XCTAssertFalse(snapshotBeforeMigration.isEmpty, "Should have units before migration")
        // Ещё задач для достижения stage 2: итого 3+7=10, taskCount=10 → byCount=2.
        ingestN(engine, project: "proj-B", count: 7, baseDate: base, lateDate: late)
        let projectAfter = try XCTUnwrap(engine.state.projects["proj-B"])
        XCTAssertGreaterThanOrEqual(projectAfter.stage, 2)
        // Все existing units на тех же позициях.
        for (id, oldPos) in snapshotBeforeMigration {
            let unit = try XCTUnwrap(engine.state.units[id.uuidString],
                "Unit \(id) disappeared after migration")
            XCTAssertEqual(unit.position, oldPos,
                "Unit \(id) moved from \(oldPos) to \(unit.position)")
        }
    }

    /// AC3: при несовместимом юните в template-слоте (wrong role) миграция skipped.
    /// Сетап: создаём проект, инжектим unit вида .shack (residential) на позицию
    /// road-слота stage1 template → при попытке мигрировать в stage2,
    /// validator видит: position матчит road-slot, но unit.preferredRole=residential ≠ road → fail.
    func testMigrationSkippedWhenIncompatible() throws {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 60)
        let late = Date()
        // Один task → создаётся project + stage1 template + первый road unit.
        engine.ingestTaskCompletion(project: "proj-X", title: "init",
            taskId: nil, source: nil, ts: base)
        guard let project = engine.state.projects["proj-X"] else {
            XCTFail("Project not created"); return
        }
        let stage1Tmpl = try stage1Name()
        XCTAssertEqual(project.templateName, stage1Tmpl)
        // Находим road-слот в stage1 template, который ещё не занят существующими units.
        let stage1Template = try XCTUnwrap(DistrictTemplateCatalog.byName(stage1Tmpl))
        let existingPositions = Set(engine.state.units.values.filter { $0.projectId == "proj-X" }.map { $0.position })
        let freeRoadSlot = try XCTUnwrap(
            stage1Template.slots.first(where: {
                $0.role == .road &&
                !existingPositions.contains(GridPoint(x: project.districtOrigin.x + $0.x,
                                                       y: project.districtOrigin.y + $0.y))
            }),
            "Should have a free road slot in stage1 template")
        // Инжектим shack (residential) на позицию road-слота — role mismatch.
        // При stage2-проверке: validator видит shack.preferredRole=residential ≠ road → fail.
        let absPos = GridPoint(x: project.districtOrigin.x + freeRoadSlot.x,
                               y: project.districtOrigin.y + freeRoadSlot.y)
        let badUnit = UnitState(
            id: UUID(), projectId: "proj-X", kind: .shack,
            position: absPos, tier: 0, decayLevel: 0,
            taskTitle: nil, taskTs: Date(), taskSource: nil
        )
        engine._testInjectUnit(badUnit, into: "proj-X")
        // Ещё задачи до stage 2: taskCount=1, нужно ≥5 задач при ageDays≈60.
        ingestN(engine, project: "proj-X", count: 5, baseDate: base, lateDate: late)
        let projectAfter = try XCTUnwrap(engine.state.projects["proj-X"])
        XCTAssertGreaterThanOrEqual(projectAfter.stage, 2)
        // templateName ОСТАЁТСЯ stage1 — миграция отказана из-за role mismatch.
        XCTAssertEqual(projectAfter.templateName, stage1Tmpl,
            "Migration must be skipped when unit role incompatible with template slot")
    }

    /// AC4: replay второго engine на тех же событиях даёт то же templateName.
    func testMigrationIsReplayable() throws {
        let dir = makeTempDir()
        let e1 = makeEngine(at: dir)
        let base = Date().addingTimeInterval(-86_400 * 60)
        ingestN(e1, project: "proj-R", count: 10, baseDate: base)
        let templateNameLive = e1.state.projects["proj-R"]?.templateName
        let stageLive = e1.state.projects["proj-R"]?.stage
        // Второй engine на том же dir → должен auto-replay (как в TASK-048c).
        let e2 = makeEngine(at: dir)
        let templateNameReplay = e2.state.projects["proj-R"]?.templateName
        let stageReplay = e2.state.projects["proj-R"]?.stage
        XCTAssertNotNil(templateNameLive)
        XCTAssertEqual(templateNameLive, templateNameReplay,
            "Template after replay must match live")
        XCTAssertEqual(stageLive, stageReplay)
    }
}
