import XCTest
@testable import CommitPyramid

final class CityEngineTests: XCTestCase {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("citydev-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(at dir: URL) -> CityEngine {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        return CityEngine(eventLog: log, snapshotStore: snap)
    }

    /// AC: один task → 2 события (`task_completed`, `unit_built`).
    func testSingleIngestProducesTwoEvents() {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        engine.ingestTaskCompletion(
            project: "p1", title: "t1",
            taskId: nil, source: nil,
            ts: Date()
        )
        let kinds = engine.events.map(\.kind)
        XCTAssertEqual(kinds, [.taskCompleted, .unitBuilt],
                       "Expected task_completed then unit_built")
    }

    /// AC: при stage-up — 3 события подряд для одной ингестии,
    /// либо stage-up появляется на той ингестии, где сработала формула.
    func testStageUpAppendsThirdEvent() {
        let dir = makeTempDir()
        let engine = makeEngine(at: dir)
        // Закрываем 6 задач в одном проекте, спред по дате чтобы ageDays > 1.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<6 {
            engine.ingestTaskCompletion(
                project: "p1", title: "t\(i)",
                taskId: nil, source: nil,
                ts: base.addingTimeInterval(TimeInterval(i) * 86_400)
            )
        }
        let stageUpCount = engine.events.filter { $0.kind == .stageUp }.count
        XCTAssertGreaterThan(stageUpCount, 0,
                             "Expected at least one stage_up across 6 ingestions")
        // task_completed = 6, unit_built = 6.
        XCTAssertEqual(engine.events.filter { $0.kind == .taskCompleted }.count, 6)
        XCTAssertEqual(engine.events.filter { $0.kind == .unitBuilt }.count, 6)
    }

    /// AC: replay из лога даёт тот же state, что live-исполнение.
    /// Сравнение структурное: побайтовое сравнение JSON ненадёжно для словарей
    /// (`[String: ProjectState]`, `[UUID: UnitState]`) — `JSONEncoder` не гарантирует
    /// порядок ключей. Проходим по словарям и сравниваем поля проектов/юнитов.
    func testReplayEquivalence() throws {
        let dir = makeTempDir()
        let engineLive = makeEngine(at: dir)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<10 {
            engineLive.ingestTaskCompletion(
                project: "p\(i % 3)", title: "t\(i)",
                taskId: nil, source: nil,
                ts: base.addingTimeInterval(TimeInterval(i) * 86_400)
            )
        }
        let liveState = engineLive.state

        // "Перезапуск": новый engine читает тот же лог/снапшот.
        let engineReplay = makeEngine(at: dir)
        let replayState = engineReplay.state

        XCTAssertEqual(liveState.projects.count, replayState.projects.count,
                       "Replay must restore the same set of projects")
        XCTAssertEqual(liveState.units.count, replayState.units.count,
                       "Replay must restore the same set of units")
        XCTAssertEqual(liveState.nextDistrictIndex, replayState.nextDistrictIndex,
                       "District spiral counter must be preserved")
        for (id, lp) in liveState.projects {
            let rp = try XCTUnwrap(replayState.projects[id],
                                   "Project \(id) missing after replay")
            XCTAssertEqual(lp.taskCount, rp.taskCount, "taskCount mismatch for \(id)")
            XCTAssertEqual(lp.stage, rp.stage, "stage mismatch for \(id)")
            XCTAssertEqual(lp.decayLevel, rp.decayLevel, "decay mismatch for \(id)")
            XCTAssertEqual(lp.unitIds.count, rp.unitIds.count,
                           "unitIds count mismatch for \(id)")
        }
    }

    /// AC: silent: true не дублирует события.
    /// Эмулируется через два инстанса CityEngine на одном файле — второй replay'ит
    /// первый, и `events.jsonl` не должен расти.
    func testReplayDoesNotDuplicateEvents() {
        let dir = makeTempDir()
        let engineLive = makeEngine(at: dir)
        engineLive.ingestTaskCompletion(
            project: "p1", title: "t1",
            taskId: nil, source: nil, ts: Date()
        )
        let countAfterLive = engineLive.events.count

        let engineReplay = makeEngine(at: dir)
        XCTAssertEqual(engineReplay.events.count, countAfterLive,
                       "Replay must not append duplicates")
    }
}
