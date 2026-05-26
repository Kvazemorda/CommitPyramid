import XCTest
@testable import CommitPyramid

/// TASK-059 BUG-025: property-тест для pre-mainRoad cross-project overlap инварианта.
/// Проверяет, что legacyRingPosition (fallback при пустых roadCells) не допускает
/// пересечения footprint'ов разных проектов.
///
/// Паттерн — CityEngine-level ingest (аналогично DistrictNoOverlapPropertyTests),
/// с roadNetwork=nil → roadCells=[] → запускает legacy path в UnitPlanner.nextPosition.
///
/// Два теста:
///   1. NoOverlap: 5 проектов × 1 задача, без магистрали → 0 overlap клеток.
///   2. DeterministicReplay: два прогона с теми же входными данными → идентичный state.
final class UnitPlannerLegacyRingOverlapTests: XCTestCase {

    // MARK: - Mock

    /// Минимальный BiomeReader (meadow-only) — активирует cross-project skip
    /// в DistrictPlanner.allocateNextOrigin. Без него spiralPoint возвращается
    /// напрямую без проверки биома, что достаточно для нашего теста, но с mock
    /// поведение точнее воспроизводит production сценарий.
    private final class MockBiomeReader: BiomeMapReader {
        let width: Int = 256
        let height: Int = 256
        func biome(atX x: Int, y: Int) -> BiomeKind { .meadow }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-ring-overlap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Создаёт CityEngine без roadNetwork (nil) — гарантирует, что
    /// roadCells=[] и nextPosition пойдёт по legacy-кольцу.
    private func makeEngine(at dir: URL) -> CityEngine {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)
        // roadNetwork НЕ устанавливаем → engine.roadNetwork == nil → roadCells=[]
        engine.biomeReader = MockBiomeReader()
        return engine
    }

    /// Ingest N проектов × tasksPerProject задач в порядке round-robin
    /// (project-0 task-0, project-1 task-0, ..., project-N task-0, project-0 task-1, ...)
    /// чтобы первые юниты каждого проекта попали в pre-mainRoad сценарий
    /// (каждый проект получает первую задачу раньше, чем появится магистраль).
    private func ingestRoundRobin(_ engine: CityEngine,
                                  projects: [String],
                                  tasksPerProject: Int) {
        for tIdx in 0..<tasksPerProject {
            for (pIdx, project) in projects.enumerated() {
                let ts = Date(timeIntervalSince1970:
                    TimeInterval(tIdx * projects.count + pIdx) * 3600)
                engine.ingestTaskCompletion(
                    project: project,
                    title: "task-\(tIdx)",
                    taskId: nil,
                    source: "test:\(project):\(tIdx)",
                    ts: ts
                )
            }
        }
    }

    // MARK: - AC:4 — Zero cross-project overlap (pre-mainRoad)

    /// 5 проектов × 1 задача каждый (round-robin ingest без магистрали) →
    /// ни одна клетка не содержит юнитов разных проектов (footprint-aware).
    func test_PreMainRoadScenario_NoOverlapBetweenProjects() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = makeEngine(at: dir)
        let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]
        ingestRoundRobin(engine, projects: projects, tasksPerProject: 1)

        var cellToProject: [GridPoint: String] = [:]
        for unit in engine.state.units.values {
            // Пропускаем fully-decayed руины (decayLevel == 4 исключены по AC1).
            guard unit.decayLevel < 4 else { continue }
            let size = unit.kind.size
            for dx in 0..<size.width {
                for dy in 0..<size.height {
                    let cell = GridPoint(
                        x: unit.position.x + dx,
                        y: unit.position.y + dy)
                    if let existing = cellToProject[cell] {
                        XCTAssertEqual(existing, unit.projectId,
                            "Cross-project overlap at \(cell): " +
                            "existing=\(existing), new=\(unit.projectId)")
                    } else {
                        cellToProject[cell] = unit.projectId
                    }
                }
            }
        }
    }

    // MARK: - AC:5 — Deterministic replay (pre-mainRoad)

    /// Тот же ввод (5 проектов × 1 задача, round-robin) на двух свежих движках
    /// даёт идентичный финальный state (детерминизм replay-инварианта).
    func test_PreMainRoadScenario_DeterministicReplay() {
        let dir1 = makeTempDir()
        let dir2 = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }
        let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]

        let engine1 = makeEngine(at: dir1)
        ingestRoundRobin(engine1, projects: projects, tasksPerProject: 1)

        let engine2 = makeEngine(at: dir2)
        ingestRoundRobin(engine2, projects: projects, tasksPerProject: 1)

        XCTAssertEqual(engine1.state.units.count,
                       engine2.state.units.count,
                       "Unit counts diverge between replays")

        for project in projects {
            let p1 = engine1.state.projects[project]
            let p2 = engine2.state.projects[project]
            XCTAssertEqual(p1?.districtOrigin, p2?.districtOrigin,
                           "districtOrigin diverges for \(project)")
            XCTAssertEqual(p1?.taskCount, p2?.taskCount,
                           "taskCount diverges for \(project)")
        }

        // Проверяем детерминизм позиций юнитов: множество (projectId, position) совпадает.
        // UUID-ключи разные (генерятся при создании), поэтому сравниваем по содержанию.
        let positions1 = Set(engine1.state.units.values.map { "\($0.projectId):\($0.position.x),\($0.position.y)" })
        let positions2 = Set(engine2.state.units.values.map { "\($0.projectId):\($0.position.x),\($0.position.y)" })
        XCTAssertEqual(positions1, positions2, "Unit (projectId, position) sets diverge between replays")
    }
}
