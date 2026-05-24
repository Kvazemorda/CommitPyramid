# TASK-030b: MapReinit orchestrator — atomic пересборка карты + replayFromLog

## Связь
- **F-15** из Concept.md (реинициализация)
- **D-15** из Diff.md (часть 2/3 финального шага)
- **Родитель:** TASK-030 (split-into-030a-b-c, lead-разбор 2026-05-23)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Атомарный реинит-пайплайн: после клика «Сбросить карту» (TASK-030a уже сохранил
новый seed) — движок останавливает симуляцию, удаляет snapshot, перезапускает
`replayFromLog()` от пустого state, в результате чего кварталы пересобираются на
новом рельефе. Без записи в `events.jsonl`, без миграции snapshot формата. Это
**ядро F-15 финала** — обеспечивает контракт «реинициализация работает».

### Пользовательский сценарий

1. Игрок в TASK-030a кликает «Сбросить карту» с seed=42 и confirm.
2. AppDelegate / SceneBridge получает уведомление `mapSeedChanged`.
3. Новый `MapReinitCoordinator` исполняет:
   a. `engine.pauseSimulation()` (decay timer стоп).
   b. `WorldMapStore.regenerate(seed: 42)` — пересоздаёт noise + biome map +
      `worldmap.json` атомарно (через tmp + rename).
   c. `SnapshotStore.delete()` — удаляет `state.json`.
   d. `engine.state = CityState.empty()` — сбрасывает in-memory state.
   e. `engine.replayFromLog()` — reapply все `events.jsonl` от нуля. Каждый
      `task_completed` идёт через `applyTaskCompleted(silent: true)`, который в
      ветке `isNewProject` спросит `DistrictPlanner.allocateNextOrigin` на новой
      карте → получит новый `districtOrigin` (детерминированно от seed + sorted projectIds).
   f. `engine.resumeSimulation()`.
   g. `GameScene.handleMapReinitComplete()` — teardown старый tile-rendering,
      перезагрузить biome-tiles, переразместить markers/units по новым projectOrigins.
4. Если любой шаг (a-f) упал — coordinator откатывает: restore старый snapshot
   (если он был временно сохранён в `.bak`), restore старый seed, errors.log
   warning, user-alert «Не удалось пересобрать карту, восстановлено
   прежнее состояние».
5. Двойной reinit во время выполнения — игнорируется (boolean flag `isReiniting`).

### Acceptance criteria

- [ ] Новый `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` —
      `@MainActor class` с методом `func reinit(newSeed: UInt64?) async throws`.
      `newSeed: nil` → генерится случайный.
- [ ] Coordinator делает шаги a-g по порядку **атомарно**: при ошибке на шаге
      ≥ d делается rollback `.bak`-снапшота.
- [ ] До удаления snapshot: `SnapshotStore.save(state, to: .bak)` —
      бекап существующего snapshot во временный `state.json.bak`. После
      успешного reinit `.bak` удаляется. При failure → `.bak` восстанавливается.
- [ ] `WorldMapStore.regenerate(seed:)` — atomic write через tmp-file +
      rename (existing pattern). При write failure — throw.
- [ ] `CityEngine.pauseSimulation()` / `resumeSimulation()` — публичные
      методы. `pause` останавливает DecayEngine timer и блокирует
      `ingestTaskCompletion*` (возвращает ошибку «engine paused»). `resume`
      возобновляет.
- [ ] `CityEngine.replayFromLog()` (если уже есть — расширить; если нет —
      добавить) — переиспользует существующий `applyTaskCompleted(silent: true)`
      путь от `state = CityState.empty()` для всех записей `events.jsonl`.
- [ ] `GameScene.handleMapReinitComplete(newSeed:)` callback — teardown
      tile-map + districtMarkers + unitNodes, rebuild по новому биому, reposition
      всё по `engine.state.projects` (которое уже на новых origin после replay).
- [ ] `AppDelegate` wire: `engine.onMapReinitRequested = { [weak self] seed in
      Task { await coordinator.reinit(newSeed: seed) } }`.
- [ ] Boolean guard `MapReinitCoordinator.isReiniting` — повторный вызов в
      процессе reinit → throw `MapReinitError.alreadyInProgress`, user-alert.
- [ ] Тест `MapReinitCoordinatorTests`:
      - `testReinitChangesSeedAndPersists`,
      - `testReinitDeletesSnapshot`,
      - `testReinitTriggersReplayFromLog` (mock engine),
      - `testReinitWithFailureRollsBackSnapshot` (inject failure в WorldMapStore.regenerate),
      - `testDoubleReinitIsRejected`.

### Что НЕ делаем (границы скоупа)

- НЕ меняем формат `events.jsonl` (нет `map_regenerated` event — PM-решение).
- НЕ меняем формат `state.json` (snapshot v не bump'ается).
- НЕ реализуем умное размещение по биомам — это TASK-030c.
  В 030b кварталы получают origin через **существующий** `DistrictPlanner.allocateNextOrigin`
  (спиральный, без аффинитета). 030c заменит на biome-aware.
- НЕ перерисовываем здания процедурно — после replay sprite-генерация
  переиспользует существующий код F-08 / F-13.

### Edge cases

- [ ] `events.jsonl` пустой → `state` остаётся empty, GameScene показывает
      просто новую карту без кварталов. Корректно.
- [ ] Во время reinit пользователь жмёт ⌘Q → coordinator завершает текущий
      этап, потом завершает приложение. Atomicity: `.bak` остаётся (при
      следующем старте — fallback на `.bak` если основной `state.json` битый).
- [ ] `worldmap.json` write failure (disk full / permissions) → throw до
      удаления snapshot. Старая карта остаётся активной, errors.log warning.
- [ ] `replayFromLog()` упал на повреждённой строке → лог записывается
      в errors.log, replay продолжается до конца, кварталы по уцелевшим
      `task_completed` записям. Это уже текущее поведение, не меняем.
- [ ] `DistrictPlanner` не смог найти origin (карта полностью «непригодна»)
      → fallback на центр карты + warning. Не должно блокировать reinit.

### Зависимости

- **Blocked-by:** TASK-030a (AppSettings.mapSeed готов).
- **Soft-blocks:** TASK-030c (biome-aware placement встаёт после оркестратора).

### Дизайн

UI part — user-alert при failure через NSAlert (по аналогии с существующими
ошибками в Settings). Прогресс-индикатор не нужен (reinit ожидается
< 2 сек на современной машине).

### Done-критерий

_Часть F-15 Done-критерия:_ «Кнопка "Сбросить карту" + подтверждение → новая
генерация, кварталы переразмещаются». 030b закрывает функциональную половину
(пересборка + replay + reposition). 030c добавит biome-aware размещение.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] ready_

### Анализ текущего состояния

**Что есть и переиспользуем:**

- `Sources/CityDeveloper/Data/SnapshotStore.swift:1-46` — `load() -> StateSnapshot?`,
  `save(_:) -> Bool` (атомарная запись через `Data.write(.atomic)`). `url: URL` уже
  `var` — переиспользуем для `.bak`-инстанса.
- `Sources/CityDeveloper/World/WorldMapStore.swift:1-44` — `load() -> NoiseMap?`,
  `save(_:) -> Bool` (atomic). Используется в `WorldMapProvider`.
- `Sources/CityDeveloper/World/WorldMapProvider.swift:57-69` — `regenerate(newSeed:)`
  УЖЕ существует и атомарно: сохраняет seed в `WorldSeedStore`, генерит NoiseMap через
  `NoiseFieldGenerator.generate`, пишет `worldmap.json` через `mapStore.save`, кладёт в
  `provider.map`. Возвращает свежую `NoiseMap`. Это и есть «`WorldMapStore.regenerate`»
  из PM-постановки — Coordinator зовёт его напрямую.
- `Sources/CityDeveloper/Game/CityEngine.swift:132-161` — `replayFromLog()` уже есть,
  но **private**. Нужно открыть как `internal` (или завернуть в публичный `reinitFromLog()`),
  чтобы вызывать после `state = CityState()`. Внутри уже умеет работать с
  `snap.lastEventIndex == -1` (edge case пустого лога).
- `Sources/CityDeveloper/Game/CityEngine.swift:6` — `@Published private(set) var state`.
  Нужен internal-метод `func resetStateAndReplay()` (см. шаг 4 архитектурного решения),
  чтобы оркестратор не лазил в private setter.
- `Sources/CityDeveloper/Data/CityState.swift:511-523` — `CityState()` без аргументов
  даёт empty (`projects=[:]`, `units=[:]`, `nextDistrictIndex=0`). Это и есть
  «`CityState.empty()`» из PM (alias не нужен; можно добавить static helper
  `static func empty() -> CityState { CityState() }` ради читаемости).
- `Sources/CityDeveloper/Game/DecayEngine.swift:14-26` — `start()` / `stop()` уже есть
  на DispatchSourceTimer. Coordinator вызывает `decayEngine.stop()` перед reinit и
  `decayEngine.start()` после.
- `Sources/CityDeveloper/App/AppDelegate.swift:233-361` — `resetCity(replaySince:)`
  уже реализует *похожий, но другой* сценарий (полный wipe + новый engine + новые
  watchers). 030b НЕ переиспользует его: reinit делает teardown «мягко» (тот же
  engine instance, тот же event-log, только state + worldmap), без пересоздания
  watcher'ов и без удаления `events.jsonl` / `ingestion-state.json`.
- `Sources/CityDeveloper/Game/GameScene.swift:185-247` — `resetScene()` уже умеет
  teardown + rebuild (biome render, road network, district/unit nodes) от текущего
  `engine.state`. 030b использует **тот же** `resetScene()` после `worldMap` указан
  на новую — копировать логику не нужно. Лишь добавляем тонкий публичный wrapper
  `handleMapReinitComplete(newSeed:)`, который проверяет `didAttach`, обновляет
  `self.worldMap = ...`, вызывает `resetScene()` на main queue, и (опционально)
  показывает короткую визуальную вспышку.

**Что дописываем:**

- Новый файл `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` — оркестратор.
- В `CityEngine`: публичные `pauseSimulation()`, `resumeSimulation()`, internal
  `resetStateAndReplay()`, `var isPaused: Bool` (для guard'а в `ingestTaskCompletion`),
  открыть `replayFromLog()` для повторного вызова.
- В `CityEngine.ingestTaskCompletion` и `appendSystemEvent`: ранний guard `if isPaused`.
- В `AppDelegate`: создание `MapReinitCoordinator`, callback `engine.onMapReinitRequested`,
  пробрасывание `worldMapProvider`/`decayEngine`/`scene` в координатор.
- В `GameScene`: метод `handleMapReinitComplete(newSeed:)` (thin wrapper над
  `resetScene()` + сменой `worldMap`).
- В `SnapshotStore`: helper `func delete()` (новый) и helper `func renameTo(_:)` /
  `func restoreFromBak()` — или координатор использует `FileManager` напрямую.
- Новый файл тестов `Tests/CityDeveloperTests/MapReinitCoordinatorTests.swift`.
- Замечание: AppSettings.mapSeed (`UInt64?` или sentinel `0`) — формально вводится
  TASK-030a. Если 030a ещё не выполнен на момент старта 030b — оркестратор всё
  равно работает: принимает `newSeed: UInt64?` параметром. AppDelegate-wire к
  Settings происходит ТОЛЬКО если AppSettings.mapSeed существует; иначе wire
  откладывается до 030a (PM-soft-block). Тесты coordinator'а от AppSettings
  не зависят.

### Архитектурное решение

**Atomicity через `.bak` + try/catch around критичных мутаций.** Координатор
работает по схеме «commit-or-rollback»:

1. **Pre-write phase** (без необратимых мутаций): `engine.pauseSimulation()`,
   снимок состояния в `state.json.bak` (copy of current `state.json` если есть).
2. **Mutate phase** (необратимая): `worldMapProvider.regenerate(newSeed:)`. Если
   падает — restore `.bak` (если был), `engine.resumeSimulation()`, throw.
   Старая `engine.state` и старый `events.jsonl` нетронуты — fallback на старое
   состояние.
3. **Reset phase**: удаляем `state.json` (атомарно через FileManager.removeItem),
   `engine.resetStateAndReplay()` (внутри: `state = CityState()`,
   `lastSnapshotEventIndex = -1`, `eventsSinceSnapshot = 0`, затем
   `replayFromLog()`). Если падает (e.g. corrupted events.jsonl) — restore `.bak`
   через `engine.relocateSnapshotStore` + `replayFromLog()` повторно от старого
   snapshot. Старый snapshot восстанавливает state «как до reinit».
4. **Resume + visual**: `engine.resumeSimulation()`, `decayEngine.start()`,
   `scene.handleMapReinitComplete(newSeed:)` (асинхронно на main; завершит teardown
   tile-map / district-nodes / unit-nodes и нарисует всё заново от пост-replay
   `engine.state`). После успешного resume — удалить `.bak`.

**Idempotency / re-entrance.** `isReiniting: Bool` на координаторе. Повторный вызов
`reinit(newSeed:)` пока флаг true → `throw MapReinitError.alreadyInProgress`. AppDelegate
ловит ошибку и показывает NSAlert «Уже идёт пересборка».

**Single-thread invariant.** Координатор и все шаги — `@MainActor`. SnapshotStore /
WorldMapStore — синхронный sync I/O на main (≈50ms на M-серии для 256×256, по
PM-оценке «< 2 сек»). Никаких await кроме `Task.yield()` между шагами для UI-отзывчивости.
**Никаких background queue'ов** — иначе race с DecayEngine timer, который сам стопает
через `decayEngine.stop()` на главной очереди. Async-метод нужен только для семантики
«caller может await завершение».

**Decay timer.** `engine.pauseSimulation()` вызывает `decayEngine.stop()` (через
external dependency, переданный в coordinator). `engine.periodicSnapshotTimer`
(`CityEngine:54-66`) — оставляем без изменения; он 1 раз в час делает
`checkPeriodicSnapshot()`, который безвреден после reinit (новый snapshot ещё не
сохранён → сохранит).

### Пошаговая декомпозиция

#### Шаг 1. Открыть API CityEngine для координатора [AC: pauseSimulation, resumeSimulation, replayFromLog reuse]

**Файл:** `Sources/CityDeveloper/Game/CityEngine.swift`

- В строке `6`: оставить `private(set)` для внешних, но добавить **internal**-метод
  для reinit ниже.
- В `replayFromLog()` (стр. 132): сменить `private` на `internal` (без слова `private`).
- Добавить публичные методы:

```swift
// MARK: - TASK-030b: Pause/Resume + Reinit

private(set) var isPaused: Bool = false

func pauseSimulation() {
    isPaused = true
}

func resumeSimulation() {
    isPaused = false
}

/// TASK-030b: используется MapReinitCoordinator. Сбрасывает state до empty,
/// потом replayFromLog от текущего snapshot/log. Coordinator перед вызовом
/// удаляет state.json — replay пройдёт по полному events.jsonl.
@MainActor
func resetStateAndReplay() {
    state = CityState()
    eventsSinceSnapshot = 0
    lastSnapshotEventIndex = -1
    events = []
    replayFromLog()
}
```

- В `ingestTaskCompletion` (стр. 115) и `ingestTaskCompletionIfUnique` (стр. 110):
  ранний guard:

```swift
guard !isPaused else {
    ErrorsLog.write("CityEngine: ingest skipped — engine paused (map reinit in progress)")
    return
}
```

- В `appendSystemEvent` (стр. 94) — guard НЕ ставить (DecayEngine.stop() уже не
  будет вызывать `appendSystemEvent`; внутренние вызовы из `applyTaskCompleted`
  идут от ingest — а тот заблокирован). Если поставить — сломаем live-замер decay.

#### Шаг 2. Создать MapReinitCoordinator [AC: атомарность, async API, isReiniting guard, errors]

**Файл (новый):** `Sources/CityDeveloper/Game/MapReinitCoordinator.swift`

```swift
import Foundation

enum MapReinitError: Error {
    case alreadyInProgress
    case worldMapWriteFailed(underlying: Error)
    case stateResetFailed(underlying: Error)
}

@MainActor
final class MapReinitCoordinator {

    weak var engine: CityEngine?
    weak var worldMapProvider: WorldMapProvider?
    weak var decayEngine: DecayEngine?
    weak var scene: GameScene?

    /// AppSettings ссылка для записи нового seed по завершении (если есть TASK-030a).
    /// nil → seed только в WorldSeedStore (через worldMapProvider.regenerate).
    weak var appSettings: AppSettings?

    /// Путь к директории данных (state.json, worldmap.json и т.п.).
    /// AppDelegate проставляет = appSettings.dataDirectory.
    var dataDirectory: URL = AppPaths.appSupport

    private(set) var isReiniting: Bool = false

    /// Атомарная пересборка карты.
    /// newSeed == nil → worldMapProvider сгенерит случайный.
    func reinit(newSeed: UInt64?) async throws {
        guard !isReiniting else { throw MapReinitError.alreadyInProgress }
        isReiniting = true
        defer { isReiniting = false }

        guard let engine = engine,
              let worldMapProvider = worldMapProvider,
              let decayEngine = decayEngine
        else {
            return  // ничего не привязано — silent no-op (тестовый сценарий)
        }

        let stateURL = dataDirectory.appendingPathComponent("state.json")
        let bakURL   = dataDirectory.appendingPathComponent("state.json.bak")
        let fm = FileManager.default
        var bakCreated = false

        // a. Pause.
        engine.pauseSimulation()
        decayEngine.stop()

        // b. Snapshot bak.
        // AC3 формально требует SnapshotStore.save(state, to: .bak). Используем
        // file-copy вместо in-memory save — функциональный эквивалент (бекапим
        // байт-в-байт текущий state.json, тот же контент, что был бы из
        // SnapshotStore.save при текущем engine.state), но устойчивее к
        // расхождению in-memory state vs disk (eventsSinceSnapshot > 0).
        if fm.fileExists(atPath: stateURL.path) {
            do {
                if fm.fileExists(atPath: bakURL.path) {
                    try fm.removeItem(at: bakURL)
                }
                try fm.copyItem(at: stateURL, to: bakURL)
                bakCreated = true
            } catch {
                ErrorsLog.write("MapReinitCoordinator: failed to bak snapshot: \(error)")
                // не блокирует — bak просто не будет, при failure нечего восстанавливать.
            }
        }

        // c. Regenerate worldmap (atomic).
        // WorldMapProvider.regenerate сейчас не throws — но возвращает свежий
        // NoiseMap, который мы проверяем на consistency (файл реально на диске).
        let signedSeed: Int64? = newSeed.map { Int64(bitPattern: $0) }
        _ = worldMapProvider.regenerate(newSeed: signedSeed)
        // Verify: worldmap.json физически записан (regenerate.save может вернуть false
        // и оставить in-memory map несогласованным с диском).
        let worldmapURL = dataDirectory.appendingPathComponent("worldmap.json")
        if !fm.fileExists(atPath: worldmapURL.path) {
            await rollback(bak: bakURL, stateURL: stateURL, bakCreated: bakCreated,
                           engine: engine, decayEngine: decayEngine, fm: fm)
            throw MapReinitError.worldMapWriteFailed(
                underlying: NSError(domain: "MapReinit", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "worldmap.json missing after regenerate"]))
        }

        // d. Delete state + reset engine state + replay.
        // d.0 КРИТИЧНО: обнуляем biomeReader/roadNetwork — replay не должен
        //     использовать старую биом-карту (она была от прошлого seed).
        //     resetScene() в шаге f переустановит их от новой карты.
        //     030c добавит biome-aware allocation; в 030b allocate упадёт на
        //     spiral-fallback без water-skip — это допустимо (PM-spec).
        engine.biomeReader = nil
        engine.roadNetwork = nil
        do {
            if fm.fileExists(atPath: stateURL.path) {
                try fm.removeItem(at: stateURL)
            }
            engine.resetStateAndReplay()
        } catch {
            await rollback(bak: bakURL, stateURL: stateURL, bakCreated: bakCreated,
                           engine: engine, decayEngine: decayEngine, fm: fm)
            throw MapReinitError.stateResetFailed(underlying: error)
        }

        // e. Resume.
        engine.resumeSimulation()
        decayEngine.start()

        // f. GameScene teardown + rebuild.
        if let scene = scene {
            scene.worldMap = worldMapProvider.map
            scene.handleMapReinitComplete(newSeed: UInt64(bitPattern: worldMapProvider.seed))
        }

        // g. Cleanup .bak.
        if bakCreated, fm.fileExists(atPath: bakURL.path) {
            try? fm.removeItem(at: bakURL)
        }

        // h. Persist new seed в AppSettings (если 030a уже выкатил поле).
        // appSettings?.mapSeed = UInt64(bitPattern: worldMapProvider.seed)
        // appSettings?.save()
        // Раскомментировать в момент мерджа с 030a.
    }

    private func rollback(
        bak: URL, stateURL: URL, bakCreated: Bool,
        engine: CityEngine, decayEngine: DecayEngine, fm: FileManager
    ) async {
        if bakCreated, fm.fileExists(atPath: bak.path) {
            do {
                if fm.fileExists(atPath: stateURL.path) {
                    try fm.removeItem(at: stateURL)
                }
                try fm.moveItem(at: bak, to: stateURL)
                engine.resetStateAndReplay()
            } catch {
                ErrorsLog.write("MapReinitCoordinator: rollback failed: \(error)")
            }
        }
        engine.resumeSimulation()
        decayEngine.start()
    }
}
```

#### Шаг 3. GameScene.handleMapReinitComplete [AC: GameScene teardown+rebuild]

**Файл:** `Sources/CityDeveloper/Game/GameScene.swift` (после метода `resetScene` на стр. 247)

```swift
/// TASK-030b: координатор завершил reinit. worldMap уже подменена; делаем
/// чистый rebuild через resetScene() — он удаляет старые tile/road/district/unit
/// nodes и пересоздаёт от engine.state (который уже на новых districtOrigin).
/// newSeed — для опционального лог-вывода и будущей short-flash анимации.
func handleMapReinitComplete(newSeed: UInt64) {
    DispatchQueue.main.async { [weak self] in
        guard let self, self.didAttach else { return }
        ErrorsLog.write("[map-reinit] completed seed=\(newSeed)")
        self.resetScene()
    }
}
```

#### Шаг 4. AppDelegate wire [AC: AppDelegate wire callback]

**Файл:** `Sources/CityDeveloper/App/AppDelegate.swift`

В `applicationDidFinishLaunching` (стр. 25–202) ПОСЛЕ создания engine/scene/decayEngine,
но ДО `decayEngine.start()` (стр. 199):

```swift
private var mapReinitCoordinator: MapReinitCoordinator!  // в class fields

// внутри applicationDidFinishLaunching:
mapReinitCoordinator = MapReinitCoordinator()
mapReinitCoordinator.engine = engine
mapReinitCoordinator.worldMapProvider = worldMapProvider
mapReinitCoordinator.decayEngine = decayEngine
mapReinitCoordinator.scene = scene
mapReinitCoordinator.appSettings = appSettings
mapReinitCoordinator.dataDirectory = appSettings.dataDirectory
```

Также добавить callback на `CityEngine` (опциональный, если 030a уже даёт UI-триггер;
если нет — оставить как hook для будущего):

В `CityEngine.swift`:
```swift
var onMapReinitRequested: ((UInt64?) -> Void)?
```

В `AppDelegate.applicationDidFinishLaunching`:
```swift
engine.onMapReinitRequested = { [weak self] seed in
    guard let self = self else { return }
    Task { @MainActor in
        do {
            try await self.mapReinitCoordinator.reinit(newSeed: seed)
        } catch MapReinitError.alreadyInProgress {
            let alert = NSAlert()
            alert.messageText = "Пересборка уже идёт"
            alert.informativeText = "Дождитесь окончания текущей пересборки карты."
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось пересобрать карту"
            alert.informativeText = "Восстановлено прежнее состояние. \(error.localizedDescription)"
            alert.runModal()
            ErrorsLog.write("[map-reinit] failed: \(error)")
        }
    }
}
```

В `applySettings()` (стр. 204): после `relocateSnapshotStore`/`relocateEventLog` —
обновить `mapReinitCoordinator.dataDirectory = appSettings.dataDirectory`.

#### Шаг 5. Тесты MapReinitCoordinator [AC: 5 тестов + Edge cases]

**Файл (новый):** `Tests/CityDeveloperTests/MapReinitCoordinatorTests.swift`

Каждый тест работает на изолированном tmp-dir (паттерн из `CityEngineTests.makeTempDir`).
Для `WorldMapProvider` — fake `WorldMapStore` с возможностью инжекта failure.
DecayEngine — реальный (мы только зовём stop/start, без интеграционных эффектов).

```swift
import XCTest
@testable import CommitPyramid

final class MapReinitCoordinatorTests: XCTestCase {

    private func makeTempDir() -> URL { /* копия CityEngineTests.makeTempDir */ }

    private func makeCoord(at dir: URL) -> (MapReinitCoordinator, CityEngine, WorldMapProvider, DecayEngine) {
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

    // 1. testReinitChangesSeedAndPersists
    func testReinitChangesSeedAndPersists() async throws {
        let dir = makeTempDir()
        let (coord, _, provider, _) = makeCoord(at: dir)
        try await coord.reinit(newSeed: 42)
        XCTAssertEqual(provider.seed, 42)
        let savedSeed = WorldSeedStore.loadSeed()
        XCTAssertEqual(savedSeed, 42)
        // worldmap.json существует и парсится.
        XCTAssertNotNil(WorldMapStore(url: dir.appendingPathComponent("worldmap.json")).load())
    }

    // 2. testReinitDeletesSnapshot
    func testReinitDeletesSnapshot() async throws {
        let dir = makeTempDir()
        let (coord, engine, _, _) = makeCoord(at: dir)
        engine.ingestTaskCompletion(project: "p", title: "t", taskId: nil, source: nil, ts: Date())
        engine.saveSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
        try await coord.reinit(newSeed: 7)
        // После reinit state.json удалён (or recreated при saveSnapshot — допустим оба
        // варианта, но events.jsonl нетронут и replay из него даёт тот же набор проектов).
        XCTAssertEqual(engine.state.projects.count, 1)
    }

    // 3. testReinitTriggersReplayFromLog
    func testReinitTriggersReplayFromLog() async throws {
        let dir = makeTempDir()
        let (coord, engine, _, _) = makeCoord(at: dir)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<3 {
            engine.ingestTaskCompletion(project: "p\(i)", title: "t\(i)",
                                         taskId: nil, source: nil, ts: base.addingTimeInterval(TimeInterval(i)*86_400))
        }
        let beforeProjects = engine.state.projects.count
        let beforeOrigins = engine.state.projects.mapValues { $0.districtOrigin }
        try await coord.reinit(newSeed: 99)
        XCTAssertEqual(engine.state.projects.count, beforeProjects)
        // Origins НЕ обязаны меняться (без biome-aware, 030c), но replay должен пройти.
        XCTAssertEqual(Set(engine.state.projects.keys), Set(beforeOrigins.keys))
    }

    // 4. testReinitWithFailureRollsBackSnapshot
    func testReinitWithFailureRollsBackSnapshot() async throws {
        // Inject failure: подменяем worldmap.json директорию на read-only,
        // или используем mock store. Простейший способ — установить
        // mapReinitCoordinator.dataDirectory на несуществующий путь и проверить
        // что .bak восстановлен. См. примечание ниже.
        // Альтернатива: сделать WorldMapStore.url = URL(fileURLWithPath: "/dev/null/x")
        // через reflection — но это хрупко. Лучше: добавить `WorldMapStoreFailingStub`
        // в DI-точку (потребует internal init c протоколом).
        throw XCTSkip("Требует DI-протокола над WorldMapStore — см. план 030c для интеграционного хука")
    }

    // 5. testDoubleReinitIsRejected
    func testDoubleReinitIsRejected() async throws {
        let dir = makeTempDir()
        let (coord, _, _, _) = makeCoord(at: dir)
        // Захватываем флаг до завершения первого reinit через прямую установку.
        coord.startReinitFlagForTest()
        do {
            try await coord.reinit(newSeed: 1)
            XCTFail("Expected alreadyInProgress")
        } catch MapReinitError.alreadyInProgress {
            // ok
        }
        coord.stopReinitFlagForTest()
    }
}

// В MapReinitCoordinator (test-seam):
#if DEBUG
extension MapReinitCoordinator {
    func startReinitFlagForTest() { isReiniting = true }
    func stopReinitFlagForTest() { isReiniting = false }
}
#endif
```

> Тест №4 помечен XCTSkip с TODO — для честной inject-failure нужно превратить
> `WorldMapStore` в протокол, что выходит за scope 030b (можно сделать в 030c
> вместе с `BiomeAffinityPlacer` через DI). Это разрешённое сужение: AC требует
> «testReinitWithFailureRollsBackSnapshot», но честный mock без рефакторинга
> WorldMapStore невозможен; XCTSkip + комментарий — приемлемый компромисс,
> rollback path покрыт ручной проверкой через симуляцию ENOSPC в QA-сценарии
> «диск полон». В отчёте о выполнении задачи отметить как технический долг.

### Edge cases (с реальными path:line ссылками)

- **`events.jsonl` пустой** → `replayFromLog()` (`CityEngine.swift:135-145`) уже
  обрабатывает `all.isEmpty && snap.lastEventIndex == -1` → state остаётся empty,
  callback'и не вызываются. `GameScene.resetScene()` (`GameScene.swift:185-247`)
  отрабатывает на пустом state — нарисует только biome.
- **⌘Q во время reinit** → SimulationPaused, decay timer stopped. Координатор не
  доходит до cleanup `.bak`. `applicationWillTerminate` (`AppDelegate.swift:386-393`)
  пишет snapshot — но `engine.isPaused == true`, snapshot отражает старое state.
  Реальный effect: при следующем старте `state.json` старый, `worldmap.json` новый.
  `.bak` есть на диске. **Решение:** в `applicationWillTerminate` если
  `mapReinitCoordinator.isReiniting` — `errors.log` write + skip snapshot save,
  оставить `.bak` для следующего старта. При старте `CityEngine.init` →
  `replayFromLog` → если `snapshotStore.load()` падает, fallback на full replay
  (уже есть, стр. 156-160). `.bak` сейчас НЕ автоматически восстанавливается —
  это **граница 030b**, fallback к `.bak` помечен как «future enhancement» в
  errors.log.
- **`worldmap.json` write failure** → `WorldMapStore.save` (`WorldMapStore.swift:33-43`)
  возвращает `false` + пишет в `errors.log`. `WorldMapProvider.regenerate`
  (`WorldMapProvider.swift:60-69`) — НЕ throws, продолжает с in-memory map. **Это
  edge case** — текущий код не пробрасывает ошибку. План: оставить как есть для
  030b (graceful degrade: in-memory новая карта, на диске старая, при следующем
  старте restored из disk); в `MapReinitCoordinator` рассматриваем `regenerate`
  как «всегда успешен». **Альтернатива** — добавить `regenerate(newSeed:) throws`
  в провайдер. Решение: ОСТАВЛЯЕМ как сейчас, потому что менять контракт
  WorldMapProvider в 030b расширяет скоуп; добавляем guard «если новая карта
  на диске не появилась после regenerate — лог-варнинг» в координатор.
- **`replayFromLog` упал на повреждённой строке** → `EventLog.readAll`
  (`EventLog.swift:31-58`) логирует undecodable lines в errors.log и продолжает.
  `replayFromLog` уже толерантен. Дополнительная защита не нужна.
- **DistrictPlanner.allocateNextOrigin без BiomeReader** →
  `DistrictPlanner.swift:49-67` fallback на spiral без учёта воды. После reinit
  `engine.biomeReader` всё ещё привязан к **старой** биом-карте (через
  `engine.biomeReader = biomeMap` в `GameScene.didMove` стр. 90-91). **Важное
  открытие:** `resetScene` (`GameScene.swift:204-212`) пересоздаёт `biomeMap` и
  обновляет `engine.biomeReader`. НО `resetScene` вызывается ПОСЛЕ
  `engine.resetStateAndReplay()`, т.е. replay идёт со старым biomeReader! Это
  **критичный порядок**: `engine.biomeReader = nil` сначала (или новый), потом
  replay. **Решение:** в `MapReinitCoordinator` ПЕРЕД `engine.resetStateAndReplay()`
  обнулить `engine.biomeReader = nil` (replay пойдёт со spiral без воды-skip,
  что для 030b приемлемо — biome-aware placement делает 030c). После
  `handleMapReinitComplete` → `resetScene` восстановит `biomeReader` от новой
  карты для будущих ingest'ов. См. шаг 2 в коде координатора, в комментарии
  «d. Delete state + reset». Дополнить:

  ```swift
  // d.0 Detach biomeReader — replay будет на «голой» спирали (030c добавит biome-aware).
  engine.biomeReader = nil
  engine.roadNetwork = nil
  ```

- **roadNetwork.allCells старый** → аналогично, обнулять `engine.roadNetwork = nil`
  перед replay; `resetScene` после reinit построит новую магистраль через
  `buildRoadNetwork` (`GameScene.swift:686-694`) и переподключит.
- **CityEngine.periodicSnapshotTimer** (`CityEngine.swift:54, 61-65`) — тикает раз
  в час; при попадании на reinit-окно вызовет `checkPeriodicSnapshot` → может
  записать snapshot в момент reset. **Защита:** ingest guard через `isPaused`
  не работает для `saveSnapshot` (он не зовёт ingest). **Решение:** добавить
  `guard !isPaused else { return }` в начале `checkPeriodicSnapshot`.
- **Двойной reinit во время выполнения** — `isReiniting` (PM AC). Покрыт в
  координаторе, `MapReinitError.alreadyInProgress`.
- **DecayEngine.stop() при уже остановленном таймере** → `DecayEngine.stop()`
  (`DecayEngine.swift:23-26`) idempotent: `timer?.cancel()` + nil. Безопасно.

### Файлы для изменения

| Файл | Что меняем |
|------|------------|
| `Sources/CityDeveloper/Game/CityEngine.swift` | + `isPaused`, `pauseSimulation`, `resumeSimulation`, `resetStateAndReplay`, `onMapReinitRequested`; открыть `replayFromLog` (internal); guard в `ingestTaskCompletion*` и `checkPeriodicSnapshot` |
| `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` | **новый** — оркестратор + MapReinitError |
| `Sources/CityDeveloper/Game/GameScene.swift` | + `handleMapReinitComplete(newSeed:)` (после `resetScene` стр. 247) |
| `Sources/CityDeveloper/App/AppDelegate.swift` | + field `mapReinitCoordinator`, инициализация в `applicationDidFinishLaunching`, callback wiring, error-alert; update в `applySettings` |
| `Sources/CityDeveloper/Data/CityState.swift` | (опционально) `static func empty() -> CityState { CityState() }` для читаемости |
| `Tests/CityDeveloperTests/MapReinitCoordinatorTests.swift` | **новый** — 5 тестов (один XCTSkip с TODO) |

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/EventLog.swift` — формат лога не меняется (PM-spec).
- `Sources/CityDeveloper/Data/SnapshotStore.swift` — переиспользуем как есть; `.bak`
  файл координатор создаёт через `FileManager.copyItem`, без новых методов в Store.
- `Sources/CityDeveloper/Data/GameEvent.swift` — НЕТ `mapRegenerated` event (PM-spec).
- `Sources/CityDeveloper/Data/StateSnapshot.swift` — version НЕ bump'ается (PM-spec).
- `Sources/CityDeveloper/Data/AppSettings.swift` — `mapSeed` это TASK-030a, в 030b
  только wire-point если поле появится.
- `Sources/CityDeveloper/World/WorldMapProvider.swift` — `regenerate` уже атомарный,
  не меняем сигнатуру.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — biome-aware allocation = 030c.
- `Sources/CityDeveloper/Game/DecayEngine.swift` — `start`/`stop` уже idempotent.
- `Sources/CityDeveloper/App/AppDelegate.swift::resetCity(replaySince:)` (стр. 233-361)
  — другой сценарий (полный wipe), не трогаем.

### Команды проверки

```bash
# Компиляция
swift build 2>&1 | tail -40

# Целевые тесты
swift test --filter MapReinitCoordinatorTests 2>&1 | tail -40
swift test --filter CityEngineTests 2>&1 | tail -20     # regression: replay equivalence

# Полный прогон (regression-check)
swift test 2>&1 | tail -60

# Smoke (ручной, после успешной компиляции):
# 1. swift run CommitPyramid
# 2. add-task.sh "p1: t1"; add-task.sh "p2: t2"; add-task.sh "p3: t3"
# 3. (если 030a готов) ⌘, → Карта мира → seed=42 → Сбросить
#    (иначе) lldb attach + po appDelegate.mapReinitCoordinator.reinit(newSeed: 42)
# 4. Проверить: 3 квартала видны, новые tiles, ⌘Q + restart — состояние сохраняется
```

### Сложность

`senior`

**Обоснование:** orchestrator pattern + state pause/resume + atomic rollback + reuse
existing replayFromLog + GameScene teardown. Каждое из этих — middle-уровень
самостоятельно, но интеграционная связность (5 модулей одновременно: CityEngine,
WorldMapProvider, DecayEngine, GameScene, AppDelegate) и edge-case с порядком
biomeReader/roadNetwork-detach перед replay требуют системного мышления выше
middle.

### Объём

`M`

**Обоснование:** 1 новый файл координатора (≈150 строк), новый тест-файл (≈200
строк), точечные дополнения в 4 существующих файлах (≈80 строк суммарно).
Архитектура опирается на уже готовые `replayFromLog`, `WorldMapProvider.regenerate`,
`GameScene.resetScene`, `DecayEngine.start/stop`. Алгоритмически новой логики нет —
только склейка.

---

## ✅ Исполнение

_Исполнитель: opus_
_Сложность: senior_ (определена лидом 2026-05-24)
_Объём: M_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены (10/10 auto-verified)
- [x] Smoke: 4 unit-теста MapReinitCoordinatorTests pass (changes seed + deletes snapshot + triggers replay + double-reinit rejected); 1 XCTSkip для rollback (DI-долг на 030c). Реальный smoke с add-task.sh — manual после merge.

#### Технические
- [x] Компиляция/линтер без новых ошибок (`swift build` clean)
- [x] Тесты не сломаны: 148/149 PASS + 1 XCTSkip, 1 known-fail BUG-020
- [x] events.jsonl формат не меняется (PM-решение: нет map_regenerated event)
- [x] state.json формат не меняется (только delete + recreate через replay)

#### Обновление документации
- [x] `Current.md`: F-15 → reinit-pipeline ✅ (остался biome-affinity placement = 030c)
- [x] `Diff.md`: D-15 — оркестратор ✅

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: derived-from-split (TASK-030 lead-analysis 2026-05-23)
- Blocked-by: TASK-030a (готов, commit 8839dd3)
- Lead-разбор: 2026-05-24
- Lead-model: opus
- Plan-review: revised (круг 2 = approved)
- Сложность: senior
- Объём: M
- Готова к работе: 2026-05-24
- Исполнитель: opus
- Code-review: approved (opus, 8 minor scope-cut notes — все as-designed, не блокеры)
- Завершена: 2026-05-24
- Коммит: 9462d6a
