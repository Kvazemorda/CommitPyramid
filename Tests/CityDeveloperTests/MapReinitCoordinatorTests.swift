import XCTest
@testable import CommitPyramid

@MainActor
final class MapReinitCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("citydev-mapreinit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStack(at dir: URL) -> (
        coord: MapReinitCoordinator,
        engine: CityEngine,
        provider: WorldMapProvider,
        decay: DecayEngine
    ) {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)
        let provider = WorldMapProvider(
            seedStore: WorldSeedStore.self,
            mapStore: WorldMapStore(url: dir.appendingPathComponent("worldmap.json"))
        )
        let decay = DecayEngine()
        decay.cityEngine = engine
        let coord = MapReinitCoordinator()
        coord.engine = engine
        coord.worldMapProvider = provider
        coord.decayEngine = decay
        coord.dataDirectory = dir
        return (coord, engine, provider, decay)
    }

    // MARK: - Tests

    /// AC: reinit меняет seed в провайдере и сохраняет его в WorldSeedStore.
    func testReinitChangesSeedAndPersists() async throws {
        let dir = makeTempDir()
        let stack = makeStack(at: dir)
        let targetSeedRaw: UInt64 = 42
        try await stack.coord.reinit(newSeed: targetSeedRaw)
        // provider.seed — Int64(bitPattern: UInt64).
        XCTAssertEqual(stack.provider.seed, Int64(bitPattern: targetSeedRaw))
        // worldmap.json существует и парсится.
        let loaded = WorldMapStore(url: dir.appendingPathComponent("worldmap.json")).load()
        XCTAssertNotNil(loaded, "worldmap.json must exist after reinit")
        XCTAssertEqual(loaded?.seed, Int64(bitPattern: targetSeedRaw))
    }

    /// AC: state.json удаляется при reinit; events.jsonl нетронут → replay
    /// восстанавливает количество проектов.
    func testReinitDeletesSnapshot() async throws {
        let dir = makeTempDir()
        let stack = makeStack(at: dir)
        stack.engine.ingestTaskCompletion(
            project: "p1", title: "t1",
            taskId: nil, source: nil, ts: Date()
        )
        stack.engine.saveSnapshot()
        let stateURL = dir.appendingPathComponent("state.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path),
                      "state.json must exist after saveSnapshot")

        try await stack.coord.reinit(newSeed: 7)

        // После reinit движок прошёл replay из events.jsonl → проект всё ещё есть.
        XCTAssertEqual(stack.engine.state.projects.count, 1,
                       "Replay must restore 1 project from events.jsonl")
        // events.jsonl нетронут.
        let eventsURL = dir.appendingPathComponent("events.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsURL.path),
                      "events.jsonl must be preserved")
    }

    /// AC: replayFromLog вызывается после reset → набор projectId совпадает.
    func testReinitTriggersReplayFromLog() async throws {
        let dir = makeTempDir()
        let stack = makeStack(at: dir)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<3 {
            stack.engine.ingestTaskCompletion(
                project: "p\(i)", title: "t\(i)",
                taskId: nil, source: nil,
                ts: base.addingTimeInterval(TimeInterval(i) * 86_400)
            )
        }
        let beforeProjects = Set(stack.engine.state.projects.keys)
        XCTAssertEqual(beforeProjects.count, 3)

        try await stack.coord.reinit(newSeed: 99)

        let afterProjects = Set(stack.engine.state.projects.keys)
        XCTAssertEqual(afterProjects, beforeProjects,
                       "Replay must restore the same set of projects")
    }

    /// AC: при failure в worldmap-фазе .bak восстанавливается.
    /// TODO: требует DI-протокола над WorldMapStore для honest inject-failure
    /// (текущий WorldMapStore — concrete final class). XCTSkip до 030c, где
    /// будет вводиться `BiomeAffinityPlacer` через DI и переезд WorldMapStore
    /// на протокол станет естественным. Rollback-path покрыт ручным QA-сценарием
    /// «диск полон» / chmod -w на dataDirectory.
    func testReinitWithFailureRollsBackSnapshot() async throws {
        throw XCTSkip("Требует DI-протокола над WorldMapStore — см. план 030c")
    }

    /// AC: двойной reinit во время выполнения → throw alreadyInProgress.
    func testDoubleReinitIsRejected() async throws {
        let dir = makeTempDir()
        let stack = makeStack(at: dir)
        // Имитируем «reinit уже идёт» через test seam — иначе пришлось бы
        // ловить race с уже стартующей таской и тест был бы flaky.
        stack.coord._startReinitFlagForTest()
        defer { stack.coord._stopReinitFlagForTest() }

        do {
            try await stack.coord.reinit(newSeed: 1)
            XCTFail("Expected MapReinitError.alreadyInProgress")
        } catch MapReinitError.alreadyInProgress {
            // ok
        }
    }
}
