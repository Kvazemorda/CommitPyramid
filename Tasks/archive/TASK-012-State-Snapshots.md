# TASK-012: Снэпшоты состояния (быстрый старт при больших логах)

## Связь
- **F-12** Снэпшоты состояния
- **D-12**
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Защитить старт игры от деградации производительности при росте `events.jsonl`.
Сейчас replay лога O(N) при каждом запуске; при 10k+ событий это уже секунды.
Решение — периодически сериализовать `CityState` в `state.json` и при следующем
запуске грузить снэпшот + replay только хвоста после него. Снэпшот не источник
истины — лог остаётся.

### Пользовательский сценарий

1. Игра запущена несколько месяцев, в `events.jsonl` накопилось 10000+ строк.
2. Перезапускаю приложение — старт занимает менее 1 сек (раньше было ≥ 3 сек).
3. Удаляю `state.json` вручную → следующий запуск восстанавливает всё из лога
   и заново сохраняет `state.json` (без потери данных).
4. Снэпшоты обновляются автоматически: каждые N событий ИЛИ раз в сутки.

### Acceptance criteria

- [ ] `Data/StateSnapshot.swift` — фабрика сериализации `CityState` в
      `state.json` через `JSONEncoder`:
  - `cityState: CityState`
  - `lastEventIndex: Int` (порядковый номер события в `events.jsonl`,
    после которого снэпшот сделан)
  - `lastEventId: UUID` (для верификации)
  - `version: Int = 1` (для будущих миграций формата)
  - `snapshotTs: Date`
- [ ] `CityEngine.replayFromLog()` модифицирован: если есть валидный
      `state.json`, загружает его как стартовое состояние, далее реплеит
      только события с `index > lastEventIndex`.
- [ ] **Триггер сохранения снэпшота:**
  - Каждые 500 примененных событий (`taskCompleted` + системные).
  - И раз в сутки в полночь по системному времени (`DispatchSourceTimer`).
  - При quit (`applicationWillTerminate`): принудительный сохранение, если
    с момента последнего снэпшота применено ≥ 50 событий.
- [ ] **Валидация снэпшота:**
  - Если `state.json` повреждён (parse fail) → fallback: replay полного лога
    + перезапись `state.json`.
  - Если `lastEventId` снэпшота не соответствует событию по индексу в логе
    (например, лог был обрезан вручную) → fallback: replay полного лога.
  - Если `version` неизвестен → fallback: replay полного лога с предупреждением
    в `errors.log`.
- [ ] **Производительность:** лог 10000 событий + актуальный снэпшот → старт
      ≤ 1 сек на M-серии Mac.
- [ ] Удаление `state.json` (`rm`) между запусками не теряет данные —
      следующий старт восстанавливает state из полного лога и пересоздаёт
      снэпшот.
- [ ] `CityState`, `ProjectState`, `UnitState` уже `Codable` → дополнительная
      работа не нужна; убедиться, что новые поля при появлении сразу
      добавляются в Codable.

### Что НЕ делаем (границы скоупа)

- Не делаем сжатие снэпшота (gzip, msgpack) — JSON достаточно для текущих
  объёмов.
- Не делаем инкрементальные снэпшоты (только полные).
- Не делаем «версии» снэпшотов с откатами / истории — только последний.
- Не делаем backup в облако / sync между устройствами.
- Не обрезаем `events.jsonl` после снэпшота — лог всегда полный (требование
  Ильи из концепта).
- Не делаем миграции формата (если `version != 1` — fallback, не
  миграция); миграции — отдельная задача когда понадобится.
- Не делаем UI для управления снэпшотами — настройки в F-14.

### Edge cases

- [ ] **Поврежденный `state.json`:** parse fail → fallback на полный replay +
      перезапись. Событие в `errors.log`: «State snapshot invalid, falling
      back to full replay».
- [ ] **`events.jsonl` обрезан после снэпшота** (например, пользователь
      редактировал руками): `lastEventId` не находится → fallback на полный
      replay.
- [ ] **`events.jsonl` пуст, но `state.json` есть:** загрузить state из
      снэпшота, replay 0 событий, продолжить работу. При следующем event —
      обычный flow.
- [ ] **`state.json` есть, `events.jsonl` нет** (странная ситуация): replay
      хвоста = 0 событий, всё ок. Если позже придёт `taskCompleted` через
      watcher — события пишутся в (новый) `events.jsonl`.
- [ ] **Гонка при quit:** `applicationWillTerminate` пишет снэпшот; если
      приложение крашится до завершения записи — `state.json` остаётся в
      предыдущей версии (atomic write через `URL.replaceItem` или write в tmp
      + rename).
- [ ] **Длительный quit (write blocked):** не блокировать termination более
      2 сек — если не успели, оставить старый снэпшот.
- [ ] **Конкурентная запись:** параллельный watcher не должен мешать
      сохранению снэпшота — снэпшот делается на `state` snapshot (struct copy),
      не на live reference.

### Зависимости

- **F-03** (event log) — `EventLog.readAll()` уже даёт упорядоченный список;
  добавить `EventLog.readSince(index: Int) -> [GameEvent]` для tail-read.
- **F-04** (watcher) — продолжает работать как раньше; снэпшот не влияет
  на watch-логику.
- **Существующая модель:** `CityState`, `ProjectState`, `UnitState`,
  `GameEvent` уже `Codable`.
- **AppPaths:** добавить `AppPaths.stateJson` (уже зарезервировано в
  `Current.md`).

### Дизайн

Не применимо (нет UI).

### Done-критерий

_Из `Concept.md` F-12 (дословно):_ Лог 10000 событий грузится менее 1 секунды
при наличии снэпшота. Удаление снэпшотов не теряет данные — следующий запуск
восстанавливает всё из лога и создаёт новый снэпшот.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `Data/CityState.swift` — `CityState`, `ProjectState`, `UnitState`, `GameEvent` все `Codable`. Готовы к сериализации.
- `Data/EventLog.swift` — `readAll() -> [GameEvent]`. Метод `readSince(index:)` не существует — добавим.
- `Data/AppPaths.swift` — нужно добавить `stateJson: URL`.
- `Game/CityEngine.swift` — `replayFromLog()` в init: `let events = eventLog.readAll(); for e in events { apply(e, silent: true) }`. Будем модифицировать.

### Архитектурное решение
Новый `Data/StateSnapshot.swift` — `Codable struct` со state + lastEventIndex (0-based по readAll()) + lastEventId (UUID для верификации) + version + snapshotTs. Чтение/запись через `JSONEncoder`/`JSONDecoder` + atomic write через `URL.replaceItem` (или `Data.write(to:options: .atomic)` — наиболее простой и надёжный путь).

`CityEngine.replayFromLog()` модифицируется: try `loadSnapshot()`, если есть валидный — `state = snapshot.cityState`, реплеить только `events[lastEventIndex+1...]`. Если нет — replay full + создать снэпшот после.

Trigger сохранения:
1. После каждого applied события — счётчик `eventsSinceSnapshot` ++; если ≥ 500 → `saveSnapshot()`.
2. Раз в 24 часа — `DispatchSourceTimer` на main, через `60 * 60 * 1000` ms; при tick проверяет «прошло ли ≥ 24 ч с `snapshotTs`».
3. `applicationWillTerminate` → если `eventsSinceSnapshot >= 1` → `saveSnapshot(timeout: 2s)`.

«В полночь» заменено на «≥ 24 часа с последнего» (см. REVISIONS из spec-review).

Atomic write — через `Data.write(to: tmpURL); FileManager.replaceItem(at: stateURL, withItemAt: tmpURL, ...)`.

### Пошаговая декомпозиция

1. **AppPaths.stateJson** `[AC:setup]`
   - Файл: `Sources/CityDeveloper/Data/AppPaths.swift`
   - Добавить `static let stateJson: URL = appSupport.appendingPathComponent("state.json")`.

2. **StateSnapshot модель** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Data/StateSnapshot.swift` (новый)
   - Структура:
     ```swift
     struct StateSnapshot: Codable {
         let version: Int
         let snapshotTs: Date
         let lastEventIndex: Int      // 0-based; -1 если в логе ещё ничего нет
         let lastEventId: UUID?       // nil если lastEventIndex == -1
         let cityState: CityState
         static let currentVersion = 1
     }
     ```

3. **SnapshotStore — load/save** `[AC:1,7,9,10]`
   - Файл: `Sources/CityDeveloper/Data/SnapshotStore.swift` (новый)
   - Скелет:
     ```swift
     final class SnapshotStore {
         let url: URL
         init(url: URL = AppPaths.stateJson) { self.url = url }
         func load() -> StateSnapshot? {
             guard let data = try? Data(contentsOf: url) else { return nil }
             let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
             guard let snap = try? decoder.decode(StateSnapshot.self, from: data),
                   snap.version == StateSnapshot.currentVersion else {
                 ErrorsLog.write("State snapshot invalid or unsupported version, falling back to full replay")
                 return nil
             }
             return snap
         }
         func save(_ snapshot: StateSnapshot, timeoutMs: Int = 2000) -> Bool {
             let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
             guard let data = try? encoder.encode(snapshot) else { return false }
             let tmpURL = url.appendingPathExtension("tmp")
             do {
                 try data.write(to: tmpURL, options: .atomic)
                 _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
                 return true
             } catch {
                 ErrorsLog.write("Snapshot save failed: \(error)")
                 try? FileManager.default.removeItem(at: tmpURL)
                 return false
             }
         }
     }
     ```

4. **EventLog.readSince(index:)** `[AC:новый API]`
   - Файл: `Sources/CityDeveloper/Data/EventLog.swift`
   - Добавить:
     ```swift
     func readSince(index: Int) -> [GameEvent] {
         let all = readAll()
         guard index >= 0 && index < all.count else { return all }  // out-of-range → весь лог
         return Array(all.suffix(from: index + 1))
     }
     ```

5. **CityEngine: интеграция snapshot** `[AC:2,8]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Добавить:
     ```swift
     private let snapshotStore = SnapshotStore()
     private var eventsSinceSnapshot: Int = 0
     private var lastEventIndex: Int = -1
     ```
   - `replayFromLog()` модифицировать:
     ```swift
     private func replayFromLog() {
         if let snap = snapshotStore.load() {
             let all = eventLog.readAll()
             // Верифицируем: lastEventId соответствует событию по индексу
             if snap.lastEventIndex >= 0 && snap.lastEventIndex < all.count
                && all[snap.lastEventIndex].id == snap.lastEventId {
                 state = snap.cityState
                 lastEventIndex = snap.lastEventIndex
                 let tail = eventLog.readSince(index: snap.lastEventIndex)
                 for e in tail { apply(e, silent: true) }
                 lastEventIndex = all.count - 1
                 return
             } else {
                 ErrorsLog.write("Snapshot event mismatch, falling back to full replay")
             }
         }
         // Fallback: full replay
         let events = eventLog.readAll()
         for e in events { apply(e, silent: true) }
         lastEventIndex = events.count - 1
     }
     ```
   - В `ingestTaskCompletion` (и в новом `appendSystemEvent` из TASK-008): после `eventLog.append(event)` + `apply(event)` → `lastEventIndex += 1; eventsSinceSnapshot += 1; if eventsSinceSnapshot >= 500 { saveSnapshot() }`.

6. **saveSnapshot helper** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Метод:
     ```swift
     func saveSnapshot() {
         let all = eventLog.readAll()  // дешёво на M1+ при < 100k событий; оптимизация позже
         let lastId = (lastEventIndex >= 0 && lastEventIndex < all.count) ? all[lastEventIndex].id : nil
         let snap = StateSnapshot(version: StateSnapshot.currentVersion, snapshotTs: Date(),
             lastEventIndex: lastEventIndex, lastEventId: lastId, cityState: state)
         if snapshotStore.save(snap) { eventsSinceSnapshot = 0 }
     }
     ```

7. **Daily timer (24h check)** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - В init после `replayFromLog()`:
     ```swift
     let timer = DispatchSource.makeTimerSource(queue: .main)
     timer.schedule(deadline: .now() + 3600, repeating: 3600)
     timer.setEventHandler { [weak self] in
         self?.checkDailySnapshot()
     }
     timer.resume()
     self.dailyTimer = timer
     ```
   - Метод:
     ```swift
     private func checkDailySnapshot() {
         guard let snap = snapshotStore.load() else { saveSnapshot(); return }
         if Date().timeIntervalSince(snap.snapshotTs) >= 86400 && eventsSinceSnapshot > 0 {
             saveSnapshot()
         }
     }
     ```

8. **Quit-snapshot в AppDelegate** `[AC:3]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - В `applicationWillTerminate`: `if engine.eventsSinceSnapshot >= 1 { engine.saveSnapshot() }`. Свойство `eventsSinceSnapshot` сделать `internal` (или метод-getter).

9. **Bench (10000 событий) — DoD** `[AC:perf]`
   - Скрипт `Scripts/snapshot-bench.sh` (новый, опциональный):
     ```bash
     # Заполнить tasks.jsonl 10000 строками синтетических задач
     for i in $(seq 1 10000); do
       echo "{\"ts\":\"2025-01-01T00:00:00Z\",\"project\":\"BenchProj\",\"title\":\"Task $i\"}" >> ~/Library/Application\ Support/CityDeveloper/tasks.jsonl
     done
     # Дождаться обработки (watcher + apply)
     # Замерить старт времени replay
     ```
   - Альтернатива: unit-тест в `Tests/CityDeveloperTests/CityEngineSnapshotTests.swift` (если структура поддерживает) — но в проекте Tests пока нет → отложим до появления.

### Edge cases (явно обработать)
- [ ] **Поврежденный state.json:** `JSONDecoder.decode` бросает → `load()` возвращает `nil`, `ErrorsLog.write(...)`, replay full.
- [ ] **events.jsonl обрезан после снэпшота** (`lastEventId` не совпадает): запись в errors.log, full replay.
- [ ] **events.jsonl пуст + state.json есть:** `all.count == 0`, `snap.lastEventIndex >= 0` → mismatch → full replay (загрузит пустой state). Альтернатива: специальный case "snap with empty log" — если `snap.lastEventIndex == -1`, считать валидным; в нашей логике snap создаётся только при `eventsSinceSnapshot >= 1`, так что edge не возникает практически.
- [ ] **state.json есть, events.jsonl нет:** `eventLog.readAll()` возвращает `[]` → mismatch → full replay → state остаётся пустой.
- [ ] **Гонка при quit:** `Data.write(to:options:.atomic)` гарантирует atomicity; tmp-файл удаляется через `replaceItemAt`. Краш во время `write` — атомарность не гарантирует завершения, но прерванный tmp-файл не затронет основной `state.json`.
- [ ] **Длительный quit:** `save` блокирует main thread ≤ ~1 сек для типичного state (несколько KB). Hard-timeout 2 сек реализуется через `DispatchQueue.global().async + group.wait(timeout:)` — если важно. Для MVP — синхронный вызов (state.json < 100 KB при типичной нагрузке).
- [ ] **Конкурентная запись:** snapshot делается на копию `state` (struct copy at value semantics) — concurrent watcher не повредит.

### Файлы для изменения
- `Sources/CityDeveloper/Data/AppPaths.swift` — добавить `stateJson`
- `Sources/CityDeveloper/Data/EventLog.swift` — добавить `readSince(index:)`
- `Sources/CityDeveloper/Game/CityEngine.swift` — snapshot интеграция
- `Sources/CityDeveloper/App/AppDelegate.swift` — quit snapshot

### Файлы НЕ трогать
- `Data/CityState.swift`, `GameEvent.swift` — модель Codable готова
- `Data/TasksJsonlWatcher.swift` — watcher не зависит от снэпшотов
- `Data/IngestionState.swift` — отдельная сущность (offset в tasks.jsonl)

### Новые файлы
- `Sources/CityDeveloper/Data/StateSnapshot.swift`
- `Sources/CityDeveloper/Data/SnapshotStore.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- Тест: добавить 600+ задач, дождаться `eventsSinceSnapshot >= 500` → проверить, что `state.json` создан и содержит state.
- Тест fallback: повредить state.json (echo "garbage" >) → следующий старт должен пройти полный replay (см. лог).
- Тест perf: bench-скрипт + измерение времени старта.

### Сложность
`middle`

**Обоснование:** 2 новых файла + 3 правки. Логика валидации snapshot, atomic write, fallback требует внимания. Без UI и без архитектурного риска.

### Ожидаемое время
S (≤ 2 часа), возможно M если bench-скрипт реализовать аккуратно.

### Plan-review правки (round 1 → applied)

1. **CRITICAL — `SnapshotStore.save()`: упрощение через `Data.write(.atomic)`** (foundation сама делает write-to-tmp + rename, без требования pre-existing файла):
   ```swift
   func save(_ snapshot: StateSnapshot) -> Bool {
       let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
       guard let data = try? encoder.encode(snapshot) else { return false }
       do { try data.write(to: url, options: .atomic); return true }
       catch { ErrorsLog.write("Snapshot save failed: \(error)"); return false }
   }
   ```
   Это и atomic, и работает при первом запуске (`url` не существует).

2. **CRITICAL — после full fallback-replay сохранять снэпшот:**
   ```swift
   // В replayFromLog() в конце fallback-ветки:
   let events = eventLog.readAll()
   for e in events { apply(e, silent: true) }
   lastEventIndex = events.count - 1
   if !events.isEmpty { saveSnapshot() }  // ← добавлено
   ```
   Это нужно для Done-критерия «следующий запуск восстанавливает всё из лога и создаёт новый снэпшот».

3. **`readSince(index:)` — раздельная обработка границ:**
   ```swift
   func readSince(index: Int) -> [GameEvent] {
       let all = readAll()
       if index < 0 { return all }
       if index >= all.count { return [] }
       return Array(all[(index + 1)...])
   }
   ```

4. **Edge case «пустой лог + валидный snap с lastEventIndex == -1»:**
   ```swift
   if all.isEmpty && snap.lastEventIndex == -1 {
       state = snap.cityState
       lastEventIndex = -1
       return  // успех, replay 0 событий
   }
   ```

5. **Переименование:** `dailyTimer` → `periodicSnapshotTimer`; `checkDailySnapshot` → `checkPeriodicSnapshot` (раз в час, проверяет ≥ 24 ч).

6. **Quit-threshold:** в плане шага 8 написано `>= 1`. AC говорит `>= 50`. Принимаем `>= 1` (лида) — это либеральнее, меньше рисков потерять немного данных при крашах. Зафиксировать в `applicationWillTerminate`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен: bench с 10000 событий и снэпшотом

#### Технические
- [ ] `swift build` без новых ошибок
- [ ] Atomic write (write-to-tmp + rename) для `state.json`
- [ ] Поврежденный `state.json` → fallback без падения

#### Обновление документации
- [ ] `current.md`: F-12 ❌ → ✅
- [ ] `diff.md`: D-12 удалён

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Lead-model: opus
- Plan-review: needs-revision → applied (round 1)
- Сложность: middle
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Исполнитель: sonnet
- Code-review: approved (opus)
- Коммит: —
