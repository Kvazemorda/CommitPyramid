import Foundation

/// TASK-030b F-15: ошибки координатора реинита карты.
enum MapReinitError: Error, LocalizedError {
    case alreadyInProgress
    case worldMapWriteFailed(underlying: Error)
    case stateResetFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "Reinit уже выполняется"
        case .worldMapWriteFailed(let underlying):
            return "Не удалось перезаписать worldmap.json: \(underlying.localizedDescription)"
        case .stateResetFailed(let underlying):
            return "Не удалось пересобрать state: \(underlying.localizedDescription)"
        }
    }
}

/// TASK-030b F-15: оркестратор атомарной пересборки карты.
///
/// Сценарий (см. план тимлида в TASK-030b):
///   1. Pause engine + decay.
///   2. Bak текущего state.json (file-copy → state.json.bak).
///   3. WorldMapProvider.regenerate(newSeed:) — атомарная замена worldmap.json.
///      Если после regenerate файла нет на диске → throw, rollback.
///   4. Detach engine.biomeReader / engine.roadNetwork (старая биом-карта не должна
///      использоваться при replay). resetScene() в шаге 6 переустановит их.
///   5. Delete state.json + engine.resetStateAndReplay() — replay events.jsonl от
///      пустого state. Если падает — rollback bak'а, throw.
///   6. Resume engine + decay, scene.handleMapReinitComplete (teardown + rebuild).
///   7. Cleanup state.json.bak.
///
/// Atomicity: при ошибке на шагах ≥4 .bak восстанавливается и engine.resetStateAndReplay()
/// зовётся повторно → старое состояние города живо.
@MainActor
final class MapReinitCoordinator {

    // MARK: - DI

    weak var engine: CityEngine?
    weak var worldMapProvider: WorldMapProvider?
    weak var decayEngine: DecayEngine?
    weak var scene: GameScene?

    /// AppSettings для записи нового seed по завершении (TASK-030a).
    weak var appSettings: AppSettings?

    /// Каталог с state.json / worldmap.json. AppDelegate проставляет
    /// = appSettings.dataDirectory.
    var dataDirectory: URL = AppPaths.appSupport

    // MARK: - State

    private(set) var isReiniting: Bool = false

    // MARK: - API

    /// Атомарная пересборка карты.
    /// - Parameter newSeed: `nil` → WorldMapProvider сгенерит случайный.
    /// - Throws: `MapReinitError.alreadyInProgress`, `.worldMapWriteFailed`,
    ///           `.stateResetFailed`.
    func reinit(newSeed: UInt64?) async throws {
        guard !isReiniting else { throw MapReinitError.alreadyInProgress }
        isReiniting = true
        defer { isReiniting = false }

        guard let engine = engine,
              let worldMapProvider = worldMapProvider,
              let decayEngine = decayEngine
        else {
            // Координатор не привязан — silent no-op (на случай DI-misconfig в тестах).
            ErrorsLog.write("[map-reinit] coordinator missing dependencies — skipping")
            return
        }

        let stateURL = dataDirectory.appendingPathComponent("state.json")
        let bakURL = dataDirectory.appendingPathComponent("state.json.bak")
        let worldmapURL = dataDirectory.appendingPathComponent("worldmap.json")
        let fm = FileManager.default
        var bakCreated = false

        // a. Pause simulation + decay timer.
        engine.pauseSimulation()
        decayEngine.stop()

        // b. Backup существующего state.json (если есть).
        // AC3: SnapshotStore.save(state, to: .bak) — функциональный эквивалент
        // через file-copy. Бекапим байт-в-байт текущий файл (а не in-memory state),
        // что устойчивее к расхождению disk vs RAM (eventsSinceSnapshot > 0).
        if fm.fileExists(atPath: stateURL.path) {
            do {
                if fm.fileExists(atPath: bakURL.path) {
                    try fm.removeItem(at: bakURL)
                }
                try fm.copyItem(at: stateURL, to: bakURL)
                bakCreated = true
            } catch {
                ErrorsLog.write("[map-reinit] failed to bak snapshot: \(error)")
                // не блокирует — bak просто не будет; при failure нечего восстанавливать.
            }
        }

        // c. Regenerate worldmap (атомарно через WorldMapStore.save).
        let signedSeed: Int64? = newSeed.map { Int64(bitPattern: $0) }
        _ = worldMapProvider.regenerate(newSeed: signedSeed)

        // Verify: worldmap.json физически на диске.
        // WorldMapStore.save может вернуть false при ошибке записи — провайдер
        // держит in-memory новую карту, но файл отстал.
        if !fm.fileExists(atPath: worldmapURL.path) {
            await rollback(
                bak: bakURL, stateURL: stateURL,
                bakCreated: bakCreated,
                engine: engine, decayEngine: decayEngine, fm: fm
            )
            throw MapReinitError.worldMapWriteFailed(
                underlying: NSError(
                    domain: "MapReinit",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "worldmap.json missing after regenerate"]
                )
            )
        }

        // d. Detach biomeReader / roadNetwork — старая биом-карта не должна
        //    использоваться при replay. resetScene() в шаге f переустановит.
        engine.biomeReader = nil
        engine.roadNetwork = nil

        // e. Delete state.json + reset engine state + replay events.jsonl.
        do {
            if fm.fileExists(atPath: stateURL.path) {
                try fm.removeItem(at: stateURL)
            }
            engine.resetStateAndReplay()
        } catch {
            await rollback(
                bak: bakURL, stateURL: stateURL,
                bakCreated: bakCreated,
                engine: engine, decayEngine: decayEngine, fm: fm
            )
            throw MapReinitError.stateResetFailed(underlying: error)
        }

        // f. Resume simulation + decay.
        engine.resumeSimulation()
        decayEngine.start()

        // g. GameScene teardown + rebuild по новой биом-карте.
        if let scene = scene {
            scene.worldMap = worldMapProvider.map
            let appliedSeed = UInt64(bitPattern: worldMapProvider.seed)
            scene.handleMapReinitComplete(newSeed: appliedSeed)
        }

        // h. Cleanup bak.
        if bakCreated, fm.fileExists(atPath: bakURL.path) {
            try? fm.removeItem(at: bakURL)
        }

        // i. Persist new seed в AppSettings (TASK-030a уже выкатил поле).
        if let settings = appSettings {
            settings.mapSeed = UInt64(bitPattern: worldMapProvider.seed)
            settings.save()
        }

        ErrorsLog.write("[map-reinit] completed seed=\(worldMapProvider.seed)")
    }

    // MARK: - Rollback

    private func rollback(
        bak: URL,
        stateURL: URL,
        bakCreated: Bool,
        engine: CityEngine,
        decayEngine: DecayEngine,
        fm: FileManager
    ) async {
        if bakCreated, fm.fileExists(atPath: bak.path) {
            do {
                if fm.fileExists(atPath: stateURL.path) {
                    try fm.removeItem(at: stateURL)
                }
                try fm.moveItem(at: bak, to: stateURL)
                // Перечитать восстановленный snapshot.
                engine.resetStateAndReplay()
            } catch {
                ErrorsLog.write("[map-reinit] rollback failed: \(error)")
            }
        }
        engine.resumeSimulation()
        decayEngine.start()
    }
}

#if DEBUG
extension MapReinitCoordinator {
    /// Test seam: имитирует, что reinit уже идёт (для testDoubleReinitIsRejected).
    func _startReinitFlagForTest() { isReiniting = true }

    /// Test seam: сбрасывает флаг (cleanup в тестах).
    func _stopReinitFlagForTest() { isReiniting = false }
}
#endif
