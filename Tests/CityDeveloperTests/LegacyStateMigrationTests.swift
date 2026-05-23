import XCTest
@testable import CityDeveloper

/// Тесты backwards-compat: старый 12-юнитный state.json / events.jsonl
/// должен без ошибок читаться новым 50-юнитным кодом (TASK-037).
final class LegacyStateMigrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("citydev-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ content: String, to url: URL) {
        try? content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - 1. rawValue stability for the original 12 kinds

    /// Защита от случайного переименования rawValue в TASK-031 или последующих задачах.
    func testRawValuesStable12() {
        XCTAssertEqual(UnitKind.shack.rawValue,     "shack")
        XCTAssertEqual(UnitKind.house.rawValue,     "house")
        XCTAssertEqual(UnitKind.villa.rawValue,     "villa")
        XCTAssertEqual(UnitKind.well.rawValue,      "well")
        XCTAssertEqual(UnitKind.road.rawValue,      "road")
        XCTAssertEqual(UnitKind.warehouse.rawValue, "warehouse")
        XCTAssertEqual(UnitKind.workshop.rawValue,  "workshop")
        XCTAssertEqual(UnitKind.raw.rawValue,       "raw")
        XCTAssertEqual(UnitKind.market.rawValue,    "market")
        XCTAssertEqual(UnitKind.forum.rawValue,     "forum")
        XCTAssertEqual(UnitKind.temple.rawValue,    "temple")
        XCTAssertEqual(UnitKind.obelisk.rawValue,   "obelisk")
    }

    /// temple и obelisk должны оставаться в категории .social (legacy совместимость,
    /// до TASK-035 они не переносятся в .religious).
    func testTempleObeliskRemainSocial() {
        XCTAssertEqual(UnitKind.temple.category, .social,
                       "temple должен оставаться .social до TASK-035")
        XCTAssertEqual(UnitKind.obelisk.category, .social,
                       "obelisk должен оставаться .social до TASK-035")
    }

    // MARK: - 2. Old state.json loads without crash

    /// Фикстура: minimal state.json, сохранённый до TASK-031 (только 12 старых rawValue).
    /// SnapshotStore.load() должен вернуть non-nil и корректно восстановить юниты.
    func testOldStateJsonLoadsCleanly() throws {
        let dir = makeTempDir()
        let stateURL = dir.appendingPathComponent("state.json")

        // Минимальный state.json с 3 юнитами в формате до TASK-031.
        // Используем rawValue из 12 legacy kinds: shack, temple, obelisk.
        let unitId1 = UUID()
        let unitId2 = UUID()
        let unitId3 = UUID()
        let projectId = "TestProject"

        let fixtureJSON = """
        {
          "version": 1,
          "snapshotTs": "2026-01-01T00:00:00Z",
          "lastEventIndex": 2,
          "lastEventId": "\(UUID().uuidString)",
          "cityState": {
            "nextDistrictIndex": 1,
            "projects": {
              "\(projectId)": {
                "id": "\(projectId)",
                "name": "\(projectId)",
                "createdAt": "2026-01-01T00:00:00Z",
                "lastActivityAt": "2026-01-02T00:00:00Z",
                "taskCount": 3,
                "stage": 0,
                "decayLevel": 0,
                "lastDecayLogged": 0,
                "districtOrigin": {"x": 0, "y": 0},
                "unitIds": [
                  "\(unitId1.uuidString)",
                  "\(unitId2.uuidString)",
                  "\(unitId3.uuidString)"
                ]
              }
            },
            "units": {
              "\(unitId1.uuidString)": {
                "id": "\(unitId1.uuidString)",
                "projectId": "\(projectId)",
                "kind": "shack",
                "position": {"x": 0, "y": 0},
                "tier": 0,
                "decayLevel": 0,
                "taskTitle": "Первая задача",
                "taskTs": "2026-01-01T00:00:00Z",
                "taskSource": null
              },
              "\(unitId2.uuidString)": {
                "id": "\(unitId2.uuidString)",
                "projectId": "\(projectId)",
                "kind": "temple",
                "position": {"x": 1, "y": 0},
                "tier": 0,
                "decayLevel": 0,
                "taskTitle": "Вторая задача",
                "taskTs": "2026-01-01T00:00:00Z",
                "taskSource": null
              },
              "\(unitId3.uuidString)": {
                "id": "\(unitId3.uuidString)",
                "projectId": "\(projectId)",
                "kind": "obelisk",
                "position": {"x": 2, "y": 0},
                "tier": 0,
                "decayLevel": 0,
                "taskTitle": "Третья задача",
                "taskTs": "2026-01-01T00:00:00Z",
                "taskSource": null
              }
            }
          }
        }
        """
        writeFile(fixtureJSON, to: stateURL)

        let store = SnapshotStore(url: stateURL)
        let snap = store.load()

        XCTAssertNotNil(snap, "Старый state.json с legacy rawValue должен загружаться без ошибок")
        XCTAssertEqual(snap?.cityState.units.count, 3,
                       "Все 3 legacy-юнита должны быть восстановлены")
        XCTAssertEqual(snap?.cityState.projects.count, 1,
                       "Проект должен быть восстановлен")

        // Проверяем, что kind'ы сохранились правильно
        let kinds = snap?.cityState.units.values.map(\.kind).sorted(by: { $0.rawValue < $1.rawValue })
        XCTAssertTrue(kinds?.contains(.shack)   == true, "shack должен декодироваться корректно")
        XCTAssertTrue(kinds?.contains(.temple)  == true, "temple должен декодироваться корректно")
        XCTAssertTrue(kinds?.contains(.obelisk) == true, "obelisk должен декодироваться корректно")
    }

    // MARK: - 3. Old events.jsonl replays correctly

    /// Фикстура: events.jsonl со старыми task_completed / unit_built / decay_tick событиями.
    /// UnitKind в лог НЕ пишется (только label в title), поэтому лог всегда совместим.
    /// Проверяем: после удаления state.json engine поднимается и восстанавливает проекты.
    func testOldEventsJsonlReplays() {
        let dir = makeTempDir()
        let eventsURL = dir.appendingPathComponent("events.jsonl")

        // 3 task_completed события для 2 разных проектов (legacy-style лог до TASK-024).
        let fixtureLines = [
            #"{"id":"\#(UUID().uuidString)","ts":"2026-01-01T00:00:00Z","kind":"task_completed","project":"ProjA","title":"Task 1"}"#,
            #"{"id":"\#(UUID().uuidString)","ts":"2026-01-02T00:00:00Z","kind":"task_completed","project":"ProjA","title":"Task 2"}"#,
            #"{"id":"\#(UUID().uuidString)","ts":"2026-01-03T00:00:00Z","kind":"task_completed","project":"ProjB","title":"Task 3"}"#,
        ]
        writeFile(fixtureLines.joined(separator: "\n") + "\n", to: eventsURL)

        // state.json намеренно отсутствует → engine пойдёт по full-replay ветке.
        let log = EventLog(fileURL: eventsURL)
        let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
        let engine = CityEngine(eventLog: log, snapshotStore: snap)

        XCTAssertEqual(engine.state.projects.count, 2,
                       "Full replay должен восстановить оба проекта из старых событий")
        XCTAssertNotNil(engine.state.projects["ProjA"])
        XCTAssertNotNil(engine.state.projects["ProjB"])
        XCTAssertEqual(engine.state.projects["ProjA"]?.taskCount, 2)
        XCTAssertEqual(engine.state.projects["ProjB"]?.taskCount, 1)
    }

    // MARK: - 4. Unknown event kind is skipped (forward-compat)

    /// Фикстура: events.jsonl содержит строку с неизвестным kind "unit_evolved"
    /// (из будущего TASK-034). EventLog.readAll() должен пропустить её без паники
    /// и вернуть только те события, которые распознаёт.
    func testUnknownEventKindSkipped() {
        let dir = makeTempDir()
        let eventsURL = dir.appendingPathComponent("events.jsonl")

        let knownId = UUID().uuidString
        let fixtureLines = [
            // Известное событие
            #"{"id":"\#(knownId)","ts":"2026-01-01T00:00:00Z","kind":"task_completed","project":"P1","title":"Known"}"#,
            // Неизвестное событие (из будущего / из ручного редактирования)
            #"{"id":"\#(UUID().uuidString)","ts":"2026-01-01T01:00:00Z","kind":"unit_evolved","project":"P1","unitId":"\#(UUID().uuidString)"}"#,
            // Ещё одно известное
            #"{"id":"\#(UUID().uuidString)","ts":"2026-01-01T02:00:00Z","kind":"decay_tick","project":"P1"}"#,
        ]
        writeFile(fixtureLines.joined(separator: "\n") + "\n", to: eventsURL)

        let log = EventLog(fileURL: eventsURL)
        let events = log.readAll()

        XCTAssertEqual(events.count, 2,
                       "Только 2 известных события должны быть возвращены; unit_evolved — пропущен")
        XCTAssertEqual(events[0].kind, .taskCompleted)
        XCTAssertEqual(events[1].kind, .decayTick)
    }

    // MARK: - 5. Corrupted snapshot falls back to full replay

    /// Фикстура: state.json содержит юнит с INVALID_KIND — синтетически невалидный rawValue.
    /// Engine не должен падать; должен откатиться на full replay из events.jsonl.
    func testCorruptedSnapshotFallbackToReplay() {
        let dir = makeTempDir()
        let stateURL  = dir.appendingPathComponent("state.json")
        let eventsURL = dir.appendingPathComponent("events.jsonl")

        // Повреждённый snapshot (kind = "INVALID_KIND" не декодируется в UnitKind).
        let badSnapshot = """
        {
          "version": 1,
          "snapshotTs": "2026-01-01T00:00:00Z",
          "lastEventIndex": 0,
          "lastEventId": "\(UUID().uuidString)",
          "cityState": {
            "nextDistrictIndex": 1,
            "projects": {},
            "units": {
              "\(UUID().uuidString)": {
                "id": "\(UUID().uuidString)",
                "projectId": "P1",
                "kind": "INVALID_KIND",
                "position": {"x": 0, "y": 0},
                "tier": 0,
                "decayLevel": 0,
                "taskTitle": null,
                "taskTs": "2026-01-01T00:00:00Z",
                "taskSource": null
              }
            }
          }
        }
        """
        writeFile(badSnapshot, to: stateURL)

        // events.jsonl с одной задачей — именно по нему должен восстановиться state.
        let eventsLine = #"{"id":"\#(UUID().uuidString)","ts":"2026-01-01T00:00:00Z","kind":"task_completed","project":"P1","title":"Recovery task"}"#
        writeFile(eventsLine + "\n", to: eventsURL)

        let log    = EventLog(fileURL: eventsURL)
        let store  = SnapshotStore(url: stateURL)
        let engine = CityEngine(eventLog: log, snapshotStore: store)

        // Engine запустился без краша и восстановил state из events.jsonl.
        XCTAssertEqual(engine.state.projects.count, 1,
                       "После fallback на full replay проект P1 должен быть восстановлен из events.jsonl")
        XCTAssertNotNil(engine.state.projects["P1"])
    }

    // MARK: - 6. Round-trip identity

    /// Записываем snapshot новым кодом → загружаем его обратно → state идентичен.
    /// Гарантирует, что encode/decode нового формата без потерь.
    func testRoundTripIdentity() throws {
        let dir = makeTempDir()
        let eventsURL = dir.appendingPathComponent("events.jsonl")
        let stateURL  = dir.appendingPathComponent("state.json")

        let log    = EventLog(fileURL: eventsURL)
        let store  = SnapshotStore(url: stateURL)
        let engine = CityEngine(eventLog: log, snapshotStore: store)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<5 {
            engine.ingestTaskCompletion(
                project: "p\(i % 2)", title: "t\(i)",
                taskId: nil, source: nil,
                ts: base.addingTimeInterval(TimeInterval(i) * 86_400)
            )
        }
        engine.saveSnapshot()

        let liveProjects = engine.state.projects
        let liveUnits    = engine.state.units
        let liveDI       = engine.state.nextDistrictIndex

        // Перезапуск: читаем тот же snapshot.
        let store2  = SnapshotStore(url: stateURL)
        let snap2   = try XCTUnwrap(store2.load(), "Round-trip: snapshot должен загружаться")

        XCTAssertEqual(snap2.cityState.projects.count, liveProjects.count,
                       "Round-trip: количество проектов должно совпадать")
        XCTAssertEqual(snap2.cityState.units.count, liveUnits.count,
                       "Round-trip: количество юнитов должно совпадать")
        XCTAssertEqual(snap2.cityState.nextDistrictIndex, liveDI,
                       "Round-trip: nextDistrictIndex должен совпадать")

        for (id, lp) in liveProjects {
            let rp = try XCTUnwrap(snap2.cityState.projects[id],
                                   "Round-trip: проект \(id) должен быть в snapshot")
            XCTAssertEqual(lp.taskCount, rp.taskCount, "taskCount mismatch для \(id)")
            XCTAssertEqual(lp.stage,     rp.stage,     "stage mismatch для \(id)")
        }

        for (uid, lu) in liveUnits {
            let ru = try XCTUnwrap(snap2.cityState.units[uid],
                                   "Round-trip: unit \(uid) должен быть в snapshot")
            XCTAssertEqual(lu.kind, ru.kind, "kind mismatch для unit \(uid)")
            XCTAssertEqual(lu.projectId, ru.projectId, "projectId mismatch для unit \(uid)")
        }
    }
}
