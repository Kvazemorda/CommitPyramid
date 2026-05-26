import XCTest
@testable import CommitPyramid

/// TASK-063 BUG-026: property-тесты для branching-стратегии размещения кварталов.
///
/// AC4: После ingest 5 проектов на свежей карте 100×100 — ≥ 2 origin'а
///      находятся НЕ на самой магистрали (perpendicular offset ≥ minDistrictRadius=8).
///
/// AC5: Для каждого off-road origin'а (|dy| > loopDepth=5) есть валидное
///      road-ответвление — BFS по 4-cardinal от (origin.x, origin.y - sign(dy))
///      через rn.allCells достигает любой клетки rn.mainRoadCells.
final class DistrictBranchingPropertyTests: XCTestCase {

    // MARK: - Mock

    private final class MockBiomeReader: BiomeMapReader {
        let width: Int
        let height: Int
        let defaultBiome: BiomeKind

        init(width: Int = 256, height: Int = 256, defaultBiome: BiomeKind = .meadow) {
            self.width = width
            self.height = height
            self.defaultBiome = defaultBiome
        }

        func biome(atX x: Int, y: Int) -> BiomeKind { defaultBiome }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("district-branching-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Создаёт CityEngine с подключённой RoadNetwork и buildMainRoad.
    /// templateFamily = "none" → DistrictTemplatePicker вернёт nil → legacy path
    /// (branching MVP работает только на legacy проектах без template).
    private func makeEngine(at dir: URL, mapSize: Int = 256) -> (CityEngine, RoadNetwork) {
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)

        let reader = MockBiomeReader(width: mapSize, height: mapSize)
        engine.biomeReader = reader

        // Отключаем template assignment: family "none" не существует в catalog →
        // DistrictTemplatePicker.pick вернёт nil → project.templateName == nil →
        // RoadNetwork/branching путь активируется (legacy mode).
        engine.templateFamily = "none"

        let rn = RoadNetwork()
        rn.buildMainRoad(cols: mapSize, rows: mapSize, biomeReader: reader)
        engine.roadNetwork = rn
        engine.syncRoadNetworkPlans()

        return (engine, rn)
    }

    /// Ingest `count` проектов × 1 task_completed каждый.
    private func ingestProjects(_ engine: CityEngine, count: Int) {
        for i in 0..<count {
            let project = "proj-\(i)"
            let ts = Date(timeIntervalSince1970: TimeInterval(i) * 3600)
            engine.ingestTaskCompletion(
                project: project,
                title: "task-\(i)",
                taskId: nil,
                source: "test:\(project)",
                ts: ts
            )
        }
    }

    // MARK: - AC4: Branching origin'ы уходят перпендикулярно от магистрали

    /// Ingest 5 проектов × 1 task → ≥ 2 origin'а с |origin.y - midY| ≥ minDistrictRadius=8.
    func test_FiveProjects_AtLeastTwoOriginsPerpendicular() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mapSize = 256
        let (engine, _) = makeEngine(at: dir, mapSize: mapSize)

        ingestProjects(engine, count: 5)

        let midY = mapSize / 2
        let minDistrictRadius = 8

        // Считаем origin'ы, которые уходят перпендикулярно от магистрали
        // (|origin.y - midY| >= minDistrictRadius).
        let branchingOrigins = engine.state.projects.values.filter { project in
            abs(project.districtOrigin.y - midY) >= minDistrictRadius
        }

        XCTAssertGreaterThanOrEqual(
            branchingOrigins.count, 2,
            "После 5 проектов должны быть ≥ 2 branching origin'а с |origin.y - midY| ≥ \(minDistrictRadius). " +
            "Найдено: \(branchingOrigins.count). " +
            "Все origins: \(engine.state.projects.values.map { "\($0.id): \($0.districtOrigin)" }.joined(separator: ", "))"
        )
    }

    // MARK: - AC5: RoadNetwork.extendBranchToOrigin создаёт валидный road-path

    /// BFS по 4-cardinal от стартовой клетки branch через allCells до mainRoadCells.
    /// Лимит: 200 шагов.
    private func bfsReachesMainRoad(
        startCell: GridPoint,
        allCells: Set<GridPoint>,
        mainRoadCells: [GridPoint],
        limit: Int = 200
    ) -> Bool {
        let mainRoadSet = Set(mainRoadCells)
        // Стартовая клетка должна быть в allCells (road).
        guard allCells.contains(startCell) else { return false }
        if mainRoadSet.contains(startCell) { return true }

        var visited = Set<GridPoint>()
        var queue = [startCell]
        visited.insert(startCell)
        let directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        var steps = 0

        while !queue.isEmpty && steps < limit {
            var next: [GridPoint] = []
            for cell in queue {
                for (dx, dy) in directions {
                    let neighbor = GridPoint(x: cell.x + dx, y: cell.y + dy)
                    guard !visited.contains(neighbor) else { continue }
                    visited.insert(neighbor)
                    if mainRoadSet.contains(neighbor) { return true }
                    if allCells.contains(neighbor) {
                        next.append(neighbor)
                    }
                }
            }
            queue = next
            steps += 1
        }
        return false
    }

    /// Прямой тест extendBranchToOrigin на RoadNetwork (не через CityEngine).
    /// Для off-road origin'ов (|dy| > loopDepth) branch создаёт непрерывный road-path
    /// от origin до магистрали.
    ///
    /// Тест не идёт через CityEngine/templates, а напрямую вызывает RoadNetwork API —
    /// branching MVP работает на legacy path (templateName == nil), и тест это имитирует.
    func test_OffRoadOrigins_HaveValidBranchPath() {
        let mapSize = 256
        let reader = MockBiomeReader(width: mapSize, height: mapSize)

        let rn = RoadNetwork()
        rn.buildMainRoad(cols: mapSize, rows: mapSize, biomeReader: reader)

        let midY = mapSize / 2
        let loopDepth = RoadNetwork.loopDepth
        let minDistrictRadius = 8

        // Тестируемые off-road origin'ы (branching-формула для idx=3,4,5):
        // idx=3: i=0, layer=1, sub=0, uSide=1, vSide=1, magIdx=136, perpOffset=8
        //   origin=(136, 136), dy=8 > loopDepth=5 → branch needed
        // idx=4: i=1, layer=1, sub=1, uSide=1, vSide=-1, magIdx=136, perpOffset=8
        //   origin=(136, 120), dy=-8 → branch needed
        // idx=5: i=2, layer=1, sub=2, uSide=-1, vSide=1, magIdx=120, perpOffset=8
        //   origin=(120, 136), dy=8 → branch needed
        let testOrigins: [GridPoint] = [
            GridPoint(x: 136, y: 136),   // perpOffset=8 выше mag
            GridPoint(x: 136, y: 120),   // perpOffset=8 ниже mag
            GridPoint(x: 120, y: 136),   // другой столбец
        ]

        for origin in testOrigins {
            let dy = origin.y - midY
            XCTAssertGreaterThan(abs(dy), loopDepth,
                "Origin \(origin) должен быть off-road (|dy|=\(abs(dy)) > loopDepth=\(loopDepth))")

            // Вызов extendBranchToOrigin.
            let branchCells = rn.extendBranchToOrigin(
                projectId: "test-\(origin.x)-\(origin.y)",
                origin: origin,
                otherProjectsClaims: [],
                biomeReader: reader
            )

            XCTAssertFalse(branchCells.isEmpty,
                "extendBranchToOrigin должен вернуть непустой массив для origin \(origin) (dy=\(dy))")

            // Ожидаемое количество branch-клеток: |dy| - 1
            let expectedCount = abs(dy) - 1
            XCTAssertEqual(branchCells.count, expectedCount,
                "Branch для origin \(origin) должен содержать \(expectedCount) клеток, получено \(branchCells.count)")

            // BFS от (origin.x, origin.y - sign(dy)) через allCells до mainRoadCells.
            let vSide = dy > 0 ? 1 : -1
            let startCell = GridPoint(x: origin.x, y: origin.y - vSide)

            let reached = bfsReachesMainRoad(
                startCell: startCell,
                allCells: rn.allCells,
                mainRoadCells: rn.mainRoadCells
            )

            XCTAssertTrue(
                reached,
                "Off-road origin \(origin) (dy=\(dy)) не имеет валидного road-пути до магистрали. " +
                "BFS от startCell \(startCell) в allCells не достиг mainRoadCells. " +
                "Branch cells: \(branchCells.prefix(5))"
            )
        }
    }

    // MARK: - AC7: Детерминизм branching

    /// Два прогона с одинаковыми входными данными дают идентичный state.
    func test_Branching_DeterministicReplay() {
        let dir1 = makeTempDir()
        let dir2 = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        let (engine1, _) = makeEngine(at: dir1)
        ingestProjects(engine1, count: 5)

        let (engine2, _) = makeEngine(at: dir2)
        ingestProjects(engine2, count: 5)

        XCTAssertEqual(engine1.state.nextDistrictIndex,
                       engine2.state.nextDistrictIndex,
                       "nextDistrictIndex не совпадает между прогонами")

        for i in 0..<5 {
            let projId = "proj-\(i)"
            let p1 = engine1.state.projects[projId]
            let p2 = engine2.state.projects[projId]
            XCTAssertEqual(p1?.districtOrigin, p2?.districtOrigin,
                           "districtOrigin для \(projId) не совпадает: \(String(describing: p1?.districtOrigin)) vs \(String(describing: p2?.districtOrigin))")
        }
    }
}
