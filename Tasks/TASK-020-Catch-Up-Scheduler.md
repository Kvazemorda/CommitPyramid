# TASK-020: Catch-up Scheduler — единый планировщик источников событий (F-20)

## Связь
- **F-20** Catch-up watcher (5-мин poll)
- **D-20** из diff.md
- **Приоритет:** P1
- **Pre-requisite для:** F-18 (notes watcher), F-19 (git watcher).

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Сейчас источник событий один — `tasks.jsonl` через `DispatchSource` (F-04). Это
работает только в живом режиме: если игра была закрыта, новые `[x]` в файле
после её закрытия не попадают на карту (хотя F-04 действительно читает offset
при старте). Для будущих источников (F-18 notes watcher, F-19 git watcher)
нужен **единый механизм**: периодический опрос всех источников + догон при
старте после простоя + сохранение `last_check_ts` per-source.

В этой задаче реализуем **infrastructure-слой** — `CatchUpScheduler`-сервис с
протоколом для источников. Конкретных источников (F-18, F-19) ещё нет — TASK-020
закрывает только фундамент. Проверка done-критерия через mock-источник в
smoke-тесте.

### Пользовательский сценарий

1. Пользователь настраивает источники в Settings (когда F-18/F-19 будут готовы —
   пока через mock в smoke).
2. Приложение запускается. После загрузки snapshot+tail (F-12) `CatchUpScheduler`
   делает **immediate scan**: для каждого зарегистрированного источника
   вызывает `scan(since: source.lastCheckTs)`.
3. Источник возвращает новые события (либо пишет напрямую в `events.jsonl`
   через `engine.ingestSystemEvent` — точную интеграцию определит лид).
4. После scan `lastCheckTs` источника обновляется на текущий момент,
   сохраняется в Application Support.
5. Через 5 минут Timer срабатывает → новый poll всех источников.
6. Если пользователь меняет интервал в Settings (3–60 мин) — Timer
   перезапускается с новым значением, без перезапуска приложения.

### Acceptance criteria

- [ ] **Протокол `EventSource`** определён: имеет метод `scan(since: Date) async
      throws -> Date` (возвращает новый `lastCheckTs` после успешного скана),
      идентификатор `id: String`, и getter/setter для `lastCheckTs`.
- [ ] **`CatchUpScheduler`-сервис** реализован: регистрация источников через
      `register(_ source: EventSource)`, отмена через `unregister(id: String)`,
      запуск/останов Timer.
- [ ] **Immediate scan при старте:** после `replayFromLog()` (F-12) и до запуска
      Timer выполняется один проход всех зарегистрированных источников
      последовательно.
- [ ] **Periodic poll по Timer** запускается раз в `interval` секунд
      (`DispatchSourceTimer` или `Timer.scheduledTimer` на main-thread). По
      умолчанию `interval = 300` (5 мин).
- [ ] **Settings: интервал** — новое поле `catchUpIntervalMinutes: Int` в
      `AppSettings` (default 5). Допустимый диапазон 3..60, clamp при вводе
      вне диапазона. Изменение значения автоматически перезапускает Timer
      (через `onChange` или эквивалент).
- [ ] **Per-source `last_check_ts` persistence:** хранится в новом файле
      `Application Support/CityDeveloper/catchup-state.json` в виде словаря
      `[sourceId: ISO8601Date]`. Читается при `register()`, пишется после
      каждого успешного `scan()`.
- [ ] **Smoke-тест с mock-источником:** скрипт `Scripts/smoke-catchup.sh`
      запускает приложение с зарегистрированным `MockEventSource` (генерирует
      одно событие в `events.jsonl` при scan). Проверяет:
      - immediate scan при старте создал событие → юнит на карте;
      - повторный запуск (без новых событий) не дублирует юнит (`lastCheckTs`
        корректно сохранился);
      - изменение `catchUpIntervalMinutes` в `UserDefaults` → Timer
        перезапускается с новым значением (логируется в errors-log).
- [ ] **Done-критерий F-20:** см. блок ниже.

### Что НЕ делаем (границы скоупа)

- Не реализуем сами источники F-18 (notes watcher) и F-19 (git watcher) — это
  отдельные задачи TASK-021/022.
- Не трогаем F-04 (`TasksJsonlWatcher`) — он продолжает работать через свой
  `DispatchSource`. Миграция F-04 в `EventSource`-протокол — отдельная
  refactor-итерация (или часть TASK-021 при необходимости).
- Не вводим UI для управления per-source состоянием (только глобальный
  интервал в Settings). Полноценный UI добавится с F-18/F-19.
- Не реализуем concurrent scan нескольких источников — последовательный
  обход, чтобы избежать race conditions при записи в `events.jsonl`.
- Не вводим персональные интервалы per-source (общий интервал на все).
- Не делаем фоновую активность когда приложение закрыто (это macOS, можно
  через `LaunchAgent`, но это отдельная фича — здесь не входит).

### Edge cases

- [ ] **Нет зарегистрированных источников** при старте → Timer работает,
      scan'ы вызывают пустой цикл, ничего не пишется. Не считается ошибкой.
- [ ] **`scan()` источника бросает ошибку** → ошибка пишется в `ErrorsLog`
      (`Data/ErrorsLog.swift`), `lastCheckTs` НЕ обновляется (ретрай в
      следующем poll), остальные источники продолжают.
- [ ] **`catchUpIntervalMinutes` вне диапазона 3..60** (например, юзер
      руками поменял UserDefaults) → clamp в коде, в errors-log warning.
- [ ] **Quit во время scan** → scan атомарен per-source (await завершится
      или будет отменён через task cancellation). `lastCheckTs`
      обновляется только после успешного завершения, так что повтор при
      следующем старте не вредит.
- [ ] **Concurrent timer fire** (если предыдущий scan ещё идёт): использовать
      флаг `isScanning` — пропустить новый Timer-tick если scan уже выполняется
      (skip-if-busy).
- [ ] **Файл `catchup-state.json` отсутствует или повреждён** → при чтении
      возвращается пустой словарь, при первом scan каждого источника
      `lastCheckTs = .distantPast`, scan получит «всё что есть».
- [ ] **Часы системы переведены назад** (rare) → `lastCheckTs > now` → scan
      получит since в будущем, ничего не найдёт, обновит lastCheckTs на now
      (clamp). Не валится.
- [ ] **Регистрация источника после старта приложения** (горячая регистрация
      из Settings UI) → `register()` сразу выполняет immediate scan для
      нового источника без ожидания следующего Timer-tick.

### Зависимости

- **F-12** Snapshots — закрыт. `replayFromLog()` отрабатывает до
  `CatchUpScheduler.start()`.
- **F-14** AppSettings — закрыт. Добавляем поле `catchUpIntervalMinutes` через
  существующий механизм.
- **Data/ErrorsLog.swift** — существующий компонент для записи ошибок.
- Нет внешних сервисов, секретов, миграций state (только новый файл
  `catchup-state.json` рядом с `state.json`).

### Дизайн

В Settings UI (F-14) добавляется одно новое поле:

```
Catch-up интервал: [    5    ] мин (3–60)
```

С подписью: «Как часто проверять источники задач (notes, git). Меньше —
быстрее реагирует, больше — экономит ресурсы.»

Никакого другого UI в этой задаче не добавляется.

### Done-критерий

_Из concept.md F-20 (дословно):_

> При старте приложения после ≥1 дня простоя все коммиты в настроенных репо
> + все новые `[x]` в notes-папках детектируются и попадают на карту в течение
> 30 сек. Periodic poll каждые 5 мин ловит изменения в живом режиме (новые
> коммиты, новые `[x]` в открытом .md-файле). Per-source `last_check_ts`
> сохраняется между запусками. Интервал 5 мин может быть переопределён в
> Settings (3–60 мин).

Примечание: первая часть Done («коммиты в репо + новые [x]») будет
проверяться полноценно при наличии F-18/F-19. В TASK-020 проверяется через
mock-источник — что **механизм** работает.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

В коде уже есть:
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — образец livewatcher
  на `DispatchSource.makeFileSystemObjectSource`, использует `IngestionState`
  (persistence через `AppPaths.ingestionState`) и `ErrorsLog.write(_:)` для
  ошибок. `engine.ingestTaskCompletion(project:title:taskId:source:ts:)` —
  единственная публичная точка приёма событий извне.
- `Sources/CityDeveloper/App/AppDelegate.swift:21–114` — инициализация
  приложения. `engine.replayFromLog()` отрабатывает внутри `CityEngine.init`
  (вызывается в `init` около строки 33 — см. `CityEngine.swift:78–107`).
  Текущая последовательность стартов: `watcher.start()` (`AppDelegate.swift:103`)
  → `decayEngine.start()` (`AppDelegate.swift:113`).
- `Sources/CityDeveloper/Data/AppPaths.swift:5–18` — `appSupport` директория
  и константы путей (`tasksJsonl`, `eventsJsonl`, `stateJson`,
  `ingestionState`, `errorsLog`). Создание директории при первом обращении.
- `Sources/CityDeveloper/Data/AppSettings.swift` — `ObservableObject` с
  `@Published` полями, `Persisted` struct + UserDefaults, версия `1`.
- `Sources/CityDeveloper/Game/CityEngine.swift:35–39` — образец
  `DispatchSource.makeTimerSource(queue: .main)` с `[weak self]`. Аналогично
  в `Game/DecayEngine.swift:16–19`.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — `static func write(_ message: String)`,
  thread-safe, non-blocking, append к `~/Library/Application Support/CityDeveloper/errors.log`.
- `Sources/CityDeveloper/Data/IngestionState.swift` — образец persistence:
  Codable + `load()`/`save()` через `JSONEncoder`/`JSONDecoder` + atomic write.

Переиспользуем:
- Паттерн `DispatchSource.makeTimerSource(queue: .main)` + weak self.
- `ErrorsLog.write(_:)` для всех логов нашего сервиса.
- `engine.ingestTaskCompletion(...)` — единственный API записи событий
  (mock-source в smoke использует его же).
- Codable + JSONEncoder/JSONDecoder + atomic write — стиль `IngestionState`.
- Стиль `AppSettings.Persisted` для миграции версий через `version` поле.

Что нужно дописать:
- `EventSource` протокол + `MockEventSource` (для smoke).
- `CatchUpState` Codable + load/save.
- `CatchUpScheduler` сервис.
- `AppPaths.catchupState` константа.
- `AppSettings.catchUpIntervalMinutes` поле + миграция.
- `SettingsView` — одно новое поле в UI.
- `AppDelegate` — инициализация и старт сервиса.
- Smoke-скрипт `Scripts/smoke-catchup.sh` (ручной, документация).

### Архитектурное решение

`CatchUpScheduler` живёт как самостоятельный сервис рядом с `DecayEngine` и
`TasksJsonlWatcher`. Источники регистрируются через протокол `EventSource`,
сервис ничего не знает про их внутренности — только `id` и `scan(since:)
async throws -> Date`. Возвращаемое значение `scan` — **новый `lastCheckTs`,
источник сам решает** (max ts события или `Date()` для пустого scan'а).
Scheduler хранит per-source `lastCheckTs` в `catchup-state.json` и не
зависит от persistence источников.

Timer — `DispatchSource.makeTimerSource(queue: .main)` (паттерн проекта).
При старте — immediate scan последовательно для всех зарегистрированных
источников, затем Timer на `interval` секунд. Concurrent fire защищён
флагом `isScanning: Bool` (skip-if-busy). При смене интервала в Settings —
Timer пересоздаётся (cancel + новый).

Init order в `AppDelegate`:
1. `engine.replayFromLog()` (внутри `CityEngine.init`) — снапшот+tail
   восстанавливают state.
2. `watcher.start()` — F-04 продолжает работать как есть (не в `EventSource`-
   протоколе для этой задачи; миграция в отдельной refactor-задаче).
3. **NEW:** `catchUpScheduler = CatchUpScheduler(engine: engine,
   appSettings: appSettings)` + `catchUpScheduler.start()`. В TASK-020
   источников ещё нет (F-18/F-19 не реализованы), но если есть
   `MockEventSource` (smoke-режим, например, через env-флаг) —
   регистрируется и срабатывает.
4. `decayEngine.start()`.

`AppSettings.catchUpIntervalMinutes` хранится через ObservableObject
(`@Published`) — сервис подписывается через Combine `$catchUpIntervalMinutes`
или KVO и пересоздаёт Timer на изменение.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **EventSource protocol + mock** `[AC:1,7]`
   - Файл: `Sources/CityDeveloper/Data/EventSource.swift` (новый).
   - Действие: объявить публичный протокол + mock-реализацию для smoke.
   - Скелет:
     ```swift
     import Foundation

     protocol EventSource: AnyObject {
         var id: String { get }
         func scan(since: Date) async throws -> Date  // returns new lastCheckTs
     }

     // Mock для smoke и dev: при scan генерирует одно событие через engine.
     final class MockEventSource: EventSource {
         let id: String
         let projectId: String
         let titlePrefix: String
         private weak var engine: CityEngine?
         private var counter = 0

         init(id: String = "mock", projectId: String = "mock-project",
              titlePrefix: String = "Mock task", engine: CityEngine) {
             self.id = id; self.projectId = projectId
             self.titlePrefix = titlePrefix; self.engine = engine
         }

         func scan(since: Date) async throws -> Date {
             let now = Date()
             counter += 1
             await MainActor.run {
                 engine?.ingestTaskCompletion(
                     project: projectId,
                     title: "\(titlePrefix) #\(counter)",
                     taskId: nil,
                     source: "mock:\(id):\(counter)",
                     ts: now
                 )
             }
             return now
         }
     }
     ```

2. **CatchUpState persistence** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Data/CatchUpState.swift` (новый).
   - Действие: Codable + load/save (стиль `IngestionState`).
   - Скелет:
     ```swift
     struct CatchUpState: Codable {
         var version: Int
         var sources: [String: SourceState]

         struct SourceState: Codable {
             var lastCheckTs: Date
         }

         static let currentVersion = 1

         static func load() -> CatchUpState {
             guard let data = try? Data(contentsOf: AppPaths.catchupState),
                   let decoded = try? JSONDecoder.event.decode(CatchUpState.self, from: data)
             else { return CatchUpState(version: currentVersion, sources: [:]) }
             return decoded
         }

         func save() {
             // Pretty-print отдельным encoder'ом — не нужен в hot-path, но
             // полезен для ручного отлада через jq/grep.
             let encoder = JSONEncoder()
             encoder.dateEncodingStrategy = .iso8601
             encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
             guard let data = try? encoder.encode(self) else { return }
             try? data.write(to: AppPaths.catchupState, options: .atomic)
         }
     }
     ```
   - **Важно:** используем существующие `JSONDecoder.event` / `JSONEncoder.event`
     из `GameEvent.swift` (уже настроены на ISO8601). Pretty-print в `save()`
     задаётся локально (для удобства чтения файла глазами), без нового
     extension'а.

3. **AppPaths.catchupState** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Data/AppPaths.swift`, после строки 18.
   - Действие: добавить
     ```swift
     static var catchupState: URL { appSupport.appendingPathComponent("catchup-state.json") }
     ```

4. **AppSettings.catchUpIntervalMinutes + миграция** `[AC:5]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift`.
   - Действие:
     1. Добавить `@Published var catchUpIntervalMinutes: Int` (default 5).
     2. В `init(...)` — параметр + clamp в диапазон 3...60.
     3. В `Persisted` struct — поле `catchUpIntervalMinutes: Int?`
        (Optional для миграции с v1).
     4. Bump `currentVersion` (или эквивалент) до 2.
     5. В `.load()` — **явная миграция, НЕ возврат к defaults при `version >= 1`**:
        ```swift
        // Старая проверка `decoded.version == 1` ломала миграцию: при v2
        // в файле load() возвращал defaults и стирал tasksJsonlPath / hotkey.
        // Делаем: принимаем любую version >= 1, для v1 заполняем
        // catchUpIntervalMinutes дефолтом.
        if decoded.version >= 1 {
            let interval = max(3, min(60, decoded.catchUpIntervalMinutes ?? 5))
            return AppSettings(
                tasksJsonlPath: decoded.tasksJsonlPath,
                dataDirectory: decoded.dataDirectory,
                hotkeyKeyCode: decoded.hotkeyKeyCode,
                hotkeyModifiers: decoded.hotkeyModifiers,
                catchUpIntervalMinutes: interval
            )
        }
        // Если version < 1 (неожиданное) — defaults.
        return AppSettings(...)
        ```
        После первого save() файл получит версию 2 и новое поле.
     6. В `save()` — записать новое поле, clamp перед сохранением (didSet это
        делает в runtime, но дополнительно clamp перед записью на диск
        не повредит).
   - Скелет clamp в @Published:
     ```swift
     @Published var catchUpIntervalMinutes: Int = 5 {
         didSet {
             if catchUpIntervalMinutes < 3 || catchUpIntervalMinutes > 60 {
                 catchUpIntervalMinutes = min(max(catchUpIntervalMinutes, 3), 60)
                 ErrorsLog.write("AppSettings: catchUpIntervalMinutes clamped to \(catchUpIntervalMinutes)")
             }
         }
     }
     ```
   - **Важно:** регрессия F-14 (сброс существующих настроек) — реальный
     риск если миграция написана неверно. Исполнитель должен проверить
     после load() из старого v1-файла: tasksJsonlPath/dataDir/hotkey
     совпадают с тем, что было сохранено в v1.

5. **CatchUpScheduler сервис** `[AC:2,3,4,5,6,7]`
   - Файл: `Sources/CityDeveloper/App/CatchUpScheduler.swift` (новый).
   - Действие: реализовать сервис с регистрацией источников, Timer,
     immediate scan, persistence.
   - Скелет:
     ```swift
     import Foundation
     import Combine

     @MainActor
     final class CatchUpScheduler {
         private weak var engine: CityEngine?
         private weak var appSettings: AppSettings?
         private var sources: [String: EventSource] = [:]
         private var state: CatchUpState = .load()
         private var timer: DispatchSourceTimer?
         private var isScanning: Bool = false
         private var settingsSub: AnyCancellable?

         init(engine: CityEngine, appSettings: AppSettings) {
             self.engine = engine
             self.appSettings = appSettings
         }

         func register(_ source: EventSource) {
             sources[source.id] = source
             // Immediate scan для нового источника (вне общего immediate-scan
             // при start()).
             Task { [weak self] in await self?.scanOne(source) }
         }

         func unregister(id: String) {
             sources.removeValue(forKey: id)
         }

         func start() {
             // 1. Immediate scan всех зарегистрированных источников.
             Task { [weak self] in
                 guard let self else { return }
                 for src in self.sources.values { await self.scanOne(src) }
             }
             // 2. Подписка на изменение интервала.
             if let settings = appSettings {
                 settingsSub = settings.$catchUpIntervalMinutes.sink { [weak self] _ in
                     self?.rescheduleTimer()
                 }
             }
             // 3. Запуск Timer.
             rescheduleTimer()
         }

         func stop() {
             timer?.cancel()
             timer = nil
             settingsSub?.cancel()
         }

         private func rescheduleTimer() {
             timer?.cancel()
             let interval = (appSettings?.catchUpIntervalMinutes ?? 5) * 60
             let t = DispatchSource.makeTimerSource(queue: .main)
             t.schedule(deadline: .now() + .seconds(interval),
                        repeating: .seconds(interval))
             t.setEventHandler { [weak self] in self?.onTimerFire() }
             t.resume()
             timer = t
         }

         private func onTimerFire() {
             guard !isScanning else {
                 ErrorsLog.write("CatchUpScheduler: skip — previous scan still running")
                 return
             }
             Task { [weak self] in
                 guard let self else { return }
                 self.isScanning = true
                 defer { self.isScanning = false }
                 for src in self.sources.values { await self.scanOne(src) }
             }
         }

         private func scanOne(_ source: EventSource) async {
             let now = Date()
             let since = state.sources[source.id]?.lastCheckTs ?? .distantPast
             // Clamp на случай часов назад.
             let effectiveSince = min(since, now)
             do {
                 let newTs = try await source.scan(since: effectiveSince)
                 // Clamp: lastCheckTs не должен быть в будущем.
                 let safeTs = min(newTs, Date())
                 state.sources[source.id] = .init(lastCheckTs: safeTs)
                 state.save()
             } catch {
                 ErrorsLog.write("CatchUpScheduler: scan \(source.id) failed: \(error)")
                 // lastCheckTs не обновляется, ретрай в следующий tick.
             }
         }
     }
     ```

6. **AppDelegate: инициализация и старт** `[AC:2,3]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`.
   - Действие: между `watcher.start()` (~строка 103) и `decayEngine.start()`
     (~строка 113) добавить:
     ```swift
     catchUpScheduler = CatchUpScheduler(engine: engine, appSettings: appSettings)
     // В smoke-режиме (env CITY_SMOKE_CATCHUP=1) регистрируем mock-источник:
     if ProcessInfo.processInfo.environment["CITY_SMOKE_CATCHUP"] == "1" {
         let mock = MockEventSource(engine: engine)
         catchUpScheduler.register(mock)
     }
     catchUpScheduler.start()
     ```
   - Объявить свойство `catchUpScheduler: CatchUpScheduler?` рядом с другими
     свойствами класса.
   - В `applicationWillTerminate(_:)` (~строка 136) добавить
     `catchUpScheduler?.stop()` рядом с другими `.stop()`.

7. **SettingsView: UI поле для интервала** `[AC:5]`
   - Файл: `Sources/CityDeveloper/UI/SettingsView.swift`.
   - Действие: добавить новую секцию или строку в существующую `Form`:
     ```swift
     Section("Catch-up") {
         HStack {
             Text("Интервал, мин:")
             // Live-binding (НЕ через draft-State). Это intentional: didSet
             // в AppSettings делает clamp + ErrorsLog, изменение цены не имеет
             // (Timer пересоздаётся через Combine-sink в шаге 5). Для пути
             // tasks.jsonl / hotkey draft нужен (тяжёлые операции / valid
             // path check), для int-stepper'а — нет.
             Stepper(value: $settings.catchUpIntervalMinutes, in: 3...60) {
                 Text("\(settings.catchUpIntervalMinutes)")
                     .monospacedDigit()
                     .frame(width: 40, alignment: .trailing)
             }
         }
         Text("Как часто проверять источники задач (notes, git). Меньше — быстрее реагирует, больше — экономит ресурсы.")
             .font(.caption)
             .foregroundColor(.secondary)
     }
     ```
   - Сохранение Settings (которое уже привязано к `AppSettings.save()` на
     каком-то onChange — лид-исполнитель проверит существующий механизм)
     должно подхватить новое поле автоматически.
   - **Замечание для исполнителя:** существующие поля (tasksPath, dataDir,
     hotkey) используют draft-паттерн с явной кнопкой «Сохранить». Для
     `catchUpIntervalMinutes` мы сознательно НЕ используем draft — Stepper
     уже сам ограничивает диапазон визуально, плюс `didSet` clamp'ит, и
     Timer-reschedule через Combine стоит копейки.

8. **Smoke-скрипт** `[AC:7]`
   - Файл: `Scripts/smoke-catchup.sh` (новый).
   - Действие: shell-скрипт (ручной прогон, CLI-replay в Package.swift нет):
     ```bash
     #!/usr/bin/env bash
     # Manual smoke for TASK-020 (F-20 Catch-up Scheduler).
     # Requires app to be runnable: swift run CityDeveloper.
     #
     # Setup:
     #   1. Clean state: rm -f ~/Library/Application\ Support/CityDeveloper/{events.jsonl,state.json,catchup-state.json}
     #   2. Run with mock source: CITY_SMOKE_CATCHUP=1 swift run CityDeveloper
     #
     # Expected:
     #   - On start: immediate scan creates one mock event → unit appears on map within ~1 sec.
     #   - After ~5 min (or whatever interval set in Settings): second mock event → second unit.
     #   - On restart without CITY_SMOKE_CATCHUP=1: no new mock events (source not registered).
     #   - catchup-state.json contains "mock" key with lastCheckTs.
     #
     # Check after first run:
     #   cat ~/Library/Application\ Support/CityDeveloper/catchup-state.json | jq .
     #   → should show {"version":1,"sources":{"mock":{"lastCheckTs":"<ISO>"}}}
     #
     # Check that Settings interval change reschedules Timer:
     #   1. Set catchUpIntervalMinutes = 3 in Settings UI.
     #   2. Wait < 3 min — mock event shouldn't fire (just timer reschedule).
     #   3. After 3 min — mock event fires.
     ```
   - `chmod +x Scripts/smoke-catchup.sh`.

### Edge cases (явно обработать)

- [ ] **Нет зарегистрированных источников** — `sources` пуст, `for src in
      sources.values` no-op, Timer работает без events. Не считается ошибкой.
- [ ] **`scan()` источника бросает ошибку** — обработано в `scanOne`:
      `ErrorsLog.write(...)`, `lastCheckTs` НЕ обновляется. Реализовано в
      шаге 5.
- [ ] **`catchUpIntervalMinutes` вне 3..60** — `didSet` в шаге 4 делает clamp +
      warning. Реализовано в шаге 4.
- [ ] **Quit во время scan** — `Task` отменяется при terminate (по `stop()`
      из `applicationWillTerminate`). `lastCheckTs` обновляется только после
      успешного await — повтор при следующем старте безвреден.
- [ ] **Concurrent timer fire** — `isScanning` флаг + early return в
      `onTimerFire`. Реализовано в шаге 5.
- [ ] **`catchup-state.json` отсутствует/повреждён** — `CatchUpState.load`
      возвращает пустой словарь (`sources: [:]`), при первом scan'е каждый
      источник получит `since = .distantPast`. Реализовано в шаге 2.
- [ ] **Часы переведены назад** — `effectiveSince = min(since, now)` в
      `scanOne` + clamp `safeTs = min(newTs, Date())`. Реализовано в шаге 5.
- [ ] **`register()` после старта** — immediate scan нового источника через
      `Task { await scanOne(...) }` сразу при регистрации. Реализовано в шаге 5.
- [ ] **Mock-source при отсутствии env-флага** — не регистрируется,
      приложение работает как обычно (только F-04 watcher). Шаг 6.
- [ ] **Свежий запуск (нет файла catchup-state.json)** — `.load()` возвращает
      пустой `CatchUpState`, файл создаётся при первом `.save()` после
      успешного scan'а.

### Файлы для изменения

- `Sources/CityDeveloper/Data/EventSource.swift` — новый: протокол + Mock.
- `Sources/CityDeveloper/Data/CatchUpState.swift` — новый: Codable + persistence.
- `Sources/CityDeveloper/App/CatchUpScheduler.swift` — новый: сервис.
- `Sources/CityDeveloper/Data/AppPaths.swift` — добавить `catchupState`.
- `Sources/CityDeveloper/Data/AppSettings.swift` — добавить
  `catchUpIntervalMinutes`, миграция `Persisted` v1 → v2.
- `Sources/CityDeveloper/App/AppDelegate.swift` — свойство + старт + stop.
- `Sources/CityDeveloper/UI/SettingsView.swift` — секция «Catch-up» со Stepper.
- `Scripts/smoke-catchup.sh` — новый, ручной smoke.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — F-04, остаётся
  параллельно как есть. Миграция в `EventSource` — отдельная задача.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `ingestTaskCompletion` уже
  существует, используем как есть. `replayFromLog` отрабатывает в `init`
  — порядок не меняем.
- `Sources/CityDeveloper/Game/DecayEngine.swift` — F-09 закрыт.
- `Sources/CityDeveloper/Data/IngestionState.swift` — старый формат для F-04.
- `Sources/CityDeveloper/Data/SnapshotStore.swift`, `StateSnapshot.swift` —
  F-12 закрыт.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — используем `write(_:)` как
  есть.

### Команды проверки (для DoD)

- Компиляция: `swift build` из корня проекта, без новых ошибок/warnings.
- Smoke (ручной):
  1. `rm -f ~/Library/Application\ Support/CityDeveloper/catchup-state.json`
  2. `CITY_SMOKE_CATCHUP=1 swift run CityDeveloper`
  3. Подождать ~1 сек после старта — на карте появляется юнит проекта
     `mock-project` (immediate scan).
  4. Закрыть приложение (Cmd+Q). Проверить:
     `jq . ~/Library/Application\ Support/CityDeveloper/catchup-state.json` —
     должен показать `{"version":1,"sources":{"mock":{"lastCheckTs":"<ISO>"}}}`.
  5. Снова `CITY_SMOKE_CATCHUP=1 swift run CityDeveloper` — mock зарегается
     ещё раз, immediate scan сделает ещё одно событие. lastCheckTs обновится.
  6. Изменить `catchUpIntervalMinutes` в Settings UI с 5 на 3 → Timer должен
     перезапуститься (логирование в errors.log опционально).
- Ручная проверка нормального режима (без env): `swift run CityDeveloper` —
  приложение запускается, mock не регистрируется, F-04 watcher работает как
  обычно. catchup-state.json остаётся пустым (`sources: {}`).

### Сложность

`middle`

**Обоснование:** 8 файлов в нескольких слоях (Data + App + UI), async/await
+ Combine + DispatchSource + Codable persistence + миграция Settings v1→v2,
race conditions через `isScanning`. Не junior — джун легко забудет clamp
часов / migration / weak self / skip-if-busy. Не senior — нет архитектурного
рефактора, нет security/perf-рисков (Timer на 5 мин — околонулевая нагрузка).

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Mock-источник в smoke-тесте подтверждает все ключевые поведения
      (immediate scan, dedup через lastCheckTs, Timer-перезапуск при смене
      интервала)

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-04 / F-12 / F-14 не сломаны
- [ ] `catchup-state.json` пишется атомарно (`write(to:options:.atomic)`)

#### Обновление документации
- [ ] `Current.md`: F-20 → ✅
- [ ] `Diff.md`: D-20 удалён
- [ ] Новые идеи → `Backlog.md`, баги → `Bugs.md`

---

## Статус

`[x] ready`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: approved-with-notes (3 minor revisions applied → resolved)
- Lead-trigger: opus (priority P1, multi-module)
- Завершена: —
- Коммит: —
