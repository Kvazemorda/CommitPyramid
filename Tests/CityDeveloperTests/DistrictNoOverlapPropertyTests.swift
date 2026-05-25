import XCTest
@testable import CommitPyramid

/// TASK-056 BUG-022: property-тест для cross-project overlap инварианта F-06.
/// Проверяет, что после ingest 5 проектов × 30 задач:
///   1. Никакая клетка `state.units` не содержит юнитов с разными `projectId`.
///   2. Replay одной и той же последовательности → один и тот же state (детерминизм).
///
/// MockBiomeReader (meadow-only) активирует cross-project skip logic в
/// DistrictPlanner.allocateNextOrigin (при nil reader ветка возвращает spiralPoint
/// напрямую без проверки, что для нашего теста не сработает).
final class DistrictNoOverlapPropertyTests: XCTestCase {

    // MARK: - Mock (скопировано из DistrictPlannerBiomeAwareTests)

    private final class MockBiomeReader: BiomeMapReader {
        let biomes: [GridPoint: BiomeKind]
        let defaultBiome: BiomeKind
        let width: Int
        let height: Int

        init(biomes: [GridPoint: BiomeKind] = [:],
             defaultBiome: BiomeKind = .meadow,
             width: Int = 256, height: Int = 256) {
            self.biomes = biomes
            self.defaultBiome = defaultBiome
            self.width = width
            self.height = height
        }

        func biome(atX x: Int, y: Int) -> BiomeKind {
            biomes[GridPoint(x: x, y: y)] ?? defaultBiome
        }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("districts-overlap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(at dir: URL) -> CityEngine {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)
        // meadow-only карта — гарантирует, что cross-project skip activates
        // (при nil biomeReader allocateNextOrigin отдаёт spiralPoint напрямую).
        engine.biomeReader = MockBiomeReader()
        return engine
    }

    private func ingestProjects(_ engine: CityEngine,
                                 projects: [String], tasksPerProject: Int) {
        for (pIdx, project) in projects.enumerated() {
            for tIdx in 0..<tasksPerProject {
                let ts = Date(timeIntervalSince1970:
                    TimeInterval(pIdx * 1000 + tIdx) * 3600)
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

    // MARK: - AC:5 — Zero cross-project overlap

    /// 5 проектов × 30 задач → ни одна клетка `state.units` не содержит юнитов
    /// разных проектов (footprint-aware: проверяем все клетки size×size).
    func test_FiveProjects_ThirtyTasks_ZeroOverlap() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = makeEngine(at: dir)
        let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]
        ingestProjects(engine, projects: projects, tasksPerProject: 30)

        var cellToProject: [GridPoint: String] = [:]
        for unit in engine.state.units.values {
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

    // MARK: - AC:7 — Deterministic replay

    /// Тот же ввод (5 проектов × 30 задач) на двух свежих движках даёт
    /// идентичный финальный state: same nextDistrictIndex, same districtOrigins,
    /// same taskCounts, same unit counts.
    func test_FiveProjects_ThirtyTasks_DeterministicReplay() {
        let dir1 = makeTempDir()
        let dir2 = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }
        let projects = ["alpha", "beta", "gamma", "delta", "epsilon"]

        let engine1 = makeEngine(at: dir1)
        ingestProjects(engine1, projects: projects, tasksPerProject: 30)

        let engine2 = makeEngine(at: dir2)
        ingestProjects(engine2, projects: projects, tasksPerProject: 30)

        // Сравнение state:
        XCTAssertEqual(engine1.state.units.count,
                       engine2.state.units.count,
                       "Unit counts diverge")
        XCTAssertEqual(engine1.state.nextDistrictIndex,
                       engine2.state.nextDistrictIndex,
                       "nextDistrictIndex diverge")
        for project in projects {
            let p1 = engine1.state.projects[project]
            let p2 = engine2.state.projects[project]
            XCTAssertEqual(p1?.districtOrigin, p2?.districtOrigin,
                           "districtOrigin diverge for \(project)")
            XCTAssertEqual(p1?.taskCount, p2?.taskCount,
                           "taskCount diverge for \(project)")
        }
    }
}
