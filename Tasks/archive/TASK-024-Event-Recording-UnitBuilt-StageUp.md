# TASK-024: Запись системных событий `unit_built` и `stage_up` в `events.jsonl`

## Связь
- **F-03** Event sourcing (расширение состава событий лога)
- **F-09** Decay и руины (паттерн уже применён: `appendSystemEvent` пишет `decay_tick/fire/restore`)
- **F-11** Инспектор / журнал (TASK-015 фильтр зависит от наличия этих событий)
- **P2 (Current.md) → закрывается:** «Системные события (`unit_built`, `stage_up`) определены в `GameEvent.Kind`, но пока не пишутся в `events.jsonl` отдельно»
- **Приоритет:** P1
- **Pre-requisite для:** TASK-015 (UI-фильтр)

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Сейчас в `events.jsonl` пишутся:
- `task_completed` — из `ingestTaskCompletion` (live и через TasksJsonlWatcher);
- `decay_tick` / `fire` / `restore` — из DecayEngine и `applyTaskCompleted` через
  `appendSystemEvent` (F-09 ✅).

Не пишутся:
- `unit_built` — каждый новый юнит как отдельное событие (для журнала и фильтра);
- `stage_up` — повышение стадии квартала 0→5 (для журнала и фильтра).

При этом обе ветки уже подготовлены в коде:
- `GameEvent.Kind` содержит `.unitBuilt`, `.stageUp` (`Data/GameEvent.swift:7,8`);
- `CityEngine.apply` имеет no-op-ветку `case .unitBuilt, .stageUp, .ruinsCleared: break`
  (`Game/CityEngine.swift:150`).

Цель: начать **писать** эти события из `applyTaskCompleted` (live-тик, `!silent`).
**Не вводить миграцию формата `events.jsonl` v1 → v2.** Идемпотентность apply
гарантирует, что:

- старые логи (без `unit_built/stage_up`) реплеятся как раньше — state
  восстанавливается из `task_completed` (внутри `applyTaskCompleted` уже строится
  и `UnitState`, и `stage`);
- новые логи (с `unit_built/stage_up`) реплеятся идемпотентно — `apply`
  для этих kind'ов = `break` (state не меняется), события используются только
  для журнала / фильтра / истории.

### Пользовательский сценарий

1. Юзер закрывает задачу → `applyTaskCompleted` строит `UnitState`,
   инкрементирует `taskCount`, считает `newStage`.
2. В `events.jsonl` после `task_completed` появляется строка
   `{"kind":"unit_built", "project":"<id>", "title":"<UnitKind.label>"}`.
3. Если stage поднялся → ещё одна строка `{"kind":"stage_up", "project":"<id>",
   "title":"S<old>→S<new>"}`.
4. Журнал (TASK-015) видит все три типа и может фильтровать.
5. Перезапуск приложения → replay snapshot+tail отрабатывает идентично: state
   восстановлен корректно, в `engine.events` теперь есть все три типа.

### Acceptance criteria

- [ ] **Расширение `appendSystemEvent`** опциональным `title`:
      `func appendSystemEvent(_ kind: GameEvent.Kind, project: String, title: String? = nil)`.
      Сохраняет обратную совместимость с DecayEngine (он зовёт без `title`).
- [ ] **Запись `unit_built` в `applyTaskCompleted`** (только при `!silent`,
      после `state.units[unit.id] = unit` и `state.projects[projectKey] = project`):
      `appendSystemEvent(.unitBuilt, project: projectKey, title: unit.kind.label)`.
      `unit.kind.label` — русское название юнита («Лачуга», «Дом», ...). Если в
      `UnitKind` нет `label`, лид определит точное место получения строки.
- [ ] **Запись `stage_up` в `applyTaskCompleted`** (только при `!silent`,
      после `state.units[uid]?.tier = newStage`, до `onProjectStageChanged?`):
      `appendSystemEvent(.stageUp, project: projectKey, title: "S\(oldStage) → S\(newStage)")`.
- [ ] **`apply(.unitBuilt)` и `apply(.stageUp)` остаются no-op** — state-агрегаты
      выводятся из `task_completed`. Это обеспечивает идемпотентность при replay
      смешанных логов (старые без новых событий + новые с ними).
- [ ] **`silent: true` ветка** (replay из лога / snapshot tail) **не пишет**
      ни `unit_built`, ни `stage_up` — события уже в логе, повторная запись
      создала бы дубликаты при каждом запуске.
- [ ] **Replay-проверка:** запустить приложение на свежей `events.jsonl`,
      закрыть 6 задач (3 разных проекта) → перезапустить. До и после перезапуска
      `state.projects` и `state.units` идентичны (юнит-тест: serialize до/после).
- [ ] **Backwards-compat проверка:** взять `events.jsonl` от старого билда
      (только `task_completed`/decay-события), запустить новый билд → replay
      успешен без warning'ов, state восстановлен.
- [ ] **Snapshot+tail:** счётчик `eventsSinceSnapshot` корректно растёт на
      запись `unit_built`/`stage_up` (сейчас уже растёт в `appendSystemEvent`).
      Триггер snapshot на 500 событий продолжает работать.
- [ ] **Порядок событий в логе для одной задачи** (нормативный):
      `task_completed` → `unit_built` → опц. `stage_up`. Внутри одного тика
      `applyTaskCompleted`. Этот порядок документируется в `LogFormat.md`.
- [ ] **Поле `id` у системного события** — генерируется UUID, как сейчас в
      `appendSystemEvent` (`GameEvent.init` default).
- [ ] **Юнит-тесты:**
      1. После одного `ingestTaskCompletion` в чистом state — в логе 2 события
         (`task_completed`, `unit_built`); если stage поднялся — 3.
      2. `replayFromLog` на смешанном логе из 50 событий (`task_completed` +
         `unit_built` + `stage_up`) даёт тот же state, что live-исполнение.

### Что НЕ делаем

- **Не вводим версию формата** (`version: 2`) в `events.jsonl`. Если в будущем
  понадобится поле `from_version`/`to_version` — отдельная задача с миграцией.
- Не вводим события «при стартовом проекте» — `onProjectCreated` остаётся
  callback'ом без своего kind (если потребуется — отдельная задача).
- Не вводим `unit_built` в инспектор-карточке (визуал юнита) — это уже работает
  через `onUnitBuilt` callback (отдельный канал, не event log).
- Не пишем `stage_up` при `silent: true` даже если логика хочет — это сломает
  replay (двойная запись).
- Не меняем `apply(.ruinsCleared)` — это отдельная история (F-06), здесь
  оставляем `break`.

### Edge cases

- [ ] **Replay-tail после миграции:** юзер обновляет билд с v1 (только
      task_completed) на новый. Snapshot существует, но `lastEventIndex`
      указывает на старое событие. `apply(e, silent: true)` на tail работает
      корректно (никаких новых событий не пишется — `silent` это блокирует).
- [ ] **Stage-up при создании квартала (taskCount=1):** `oldStage=0`,
      `newStage = StageRules.computeStage(taskCount: 1, ...)` — обычно 0, но
      на свежесозданном квартале с `createdAt = event.ts` (`ageDays = 1`)
      возможен 0. Если совпало → `if newStage > oldStage` не сработает,
      `stage_up` не пишется. Это правильно.
- [ ] **Restore-кольцо:** `applyTaskCompleted` рекурсивно вызывает
      `appendSystemEvent(.restore, ...)` до основной логики. `restore`
      пишет → `apply(.restore)` обнуляет decay → `onDecayChanged` колбэк.
      Только после этого продолжается основной поток построения юнита и
      записи `unit_built`. Порядок в логе: `task_completed → restore → unit_built`.
      Документируется.
- [ ] **Несколько задач в одном тике батчем** (например, watcher прочитал 5
      строк): каждая идёт через `ingestTaskCompletion` отдельно, события
      пишутся последовательно. Порядок в логе соответствует порядку
      обработки строк.
- [ ] **Stage falls back at decay 4 → restore (decay 3→0):** при возврате к
      decay-3 проекту `applyTaskCompleted` пишет `restore`, потом строит юнит
      и **может** поднять stage. Все три события — `task_completed`, `restore`,
      `unit_built`, опционально `stage_up` — в правильном порядке.
- [ ] **Replay из v1 лога на v2-коде:** все события v1 — корректны (v1 не
      содержит unknown kinds). `applyTaskCompleted(silent: true)` строит
      юнит и stage из `task_completed` так же, как раньше. State идентичен.

### Зависимости

- **F-03** Event sourcing — закрыт, расширяем.
- **F-09** Decay — закрыт, эталонный паттерн `appendSystemEvent`.
- **F-12** Snapshots — закрыт. Новые события включаются в snapshot+tail без
  изменений в `StateSnapshot` (формат не меняется).
- Нет миграций, нет внешних сервисов.

### Дизайн

UI здесь нет — это backend-задача. Документация:
- **`concept/LogFormat.md`** — расширить раздел «Системные события»:
  - `unit_built`: пишется на каждый закрытый task, рядом с `task_completed`.
    `title` = label типа юнита.
  - `stage_up`: пишется при повышении стадии. `title` = `"S<old> → S<new>"`.
  - Гарантия порядка в одной задаче: `task_completed → (restore?) → unit_built → (stage_up?)`.
- **`concept/Current.md`** — снять P2 пункт «Системные события не пишутся».

### Done-критерий

> После закрытия одной задачи в `events.jsonl` появляются строки `task_completed`
> и `unit_built` (порядок — в указанном выше). При повышении стадии — ещё
> `stage_up`. Replay приложения восстанавливает идентичный state как из
> v1-лога, так и из нового лога со смешанными событиями. TASK-015 (UI-фильтр)
> может фильтровать журнал по `unit_built` / `stage_up` без доработок в
> backend'е.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `Sources/CityDeveloper/Data/GameEvent.swift` — `GameEvent.Kind` уже содержит `unitBuilt` ("unit_built", стр. 7) и `stageUp` ("stage_up", стр. 8). Поле `title: String?` уже опционально в самой `struct GameEvent` (стр. 19) — модель расширять **не нужно**.
- `Sources/CityDeveloper/Game/CityEngine.swift`:
  - `@Published private(set) var events: [GameEvent]` (стр. 7).
  - `appendSystemEvent(_:project:)` (стр. 50–59): пишет в `eventLog`, делает `apply(silent: false)`, инкрементирует счётчики, опционально снапшот. **НЕ** пушит в `events` — асимметрия с `ingestTaskCompletion` (стр. 71 пушит). Декей-события сейчас видны в `events` только после рестарта через `replayFromLog` (стр. 95 — `events = eventLog.readAll()`).
  - `ingestTaskCompletion` (стр. 61–76) — образец «и в лог, и в `events`».
  - `applyTaskCompleted` (стр. 155–296):
    - `restore`-ветка: `appendSystemEvent(.restore, project: projectKey)` при `!silent && decay 1..3` (стр. 166–172).
    - юнит создаётся: `state.units[unit.id] = unit` (стр. 255), `project.unitIds.append(unit.id)` (стр. 256).
    - `oldStage` / `newStage` (стр. 258–265).
    - `state.projects[projectKey] = project` (стр. 267).
    - tier-апдейт при stage-up (стр. 271–275).
    - блок `if !silent { … }` с callback'ами `onProjectCreated/onProjectRuinsCleared/onUnitBuilt/onProjectStageChanged` (стр. 277–295).
  - `apply(_:silent:)` для `.unitBuilt/.stageUp/.ruinsCleared` = `break` (стр. ~150) — **не трогаем**, это гарантирует идемпотентность.
- `Sources/CityDeveloper/Data/CityState.swift` (стр. 16–29) — `enum UnitKind: String, Codable, CaseIterable` (12 case'ов: shack/house/villa/well/road/warehouse/workshop/raw/market/forum/temple/obelisk). Свойства `label` сейчас **нет**. Русские названия дублируются в `InspectorPanel.swift` и `InspectorOverlayCard.swift` (приватный `russianKind`).
- `Sources/CityDeveloper/Data/EventLog.swift` — `init(fileURL: URL = AppPaths.eventsJsonl)` (стр. 9), `append(_:)` (стр. 19–29) — построчный JSONL, fsync через FileHandle. URL **injectable** — пригодно для тестов с tmpdir.
- `Sources/CityDeveloper/Data/SnapshotStore.swift` — тоже injectable URL (см. `relocateSnapshotStore`).
- `Sources/CityDeveloper/Game/StageRules.swift` — `computeStage(taskCount:ageDays:) -> Int` (используется в applyTaskCompleted стр. 259–262).
- `Sources/CityDeveloper/Game/DecayEngine.swift` — эталонный паттерн: `engine.appendSystemEvent(.decayTick, project: …)` без `title`. **Сохраняет совместимость** через дефолт `title: String? = nil`.
- `Package.swift` — `.executableTarget` без тестов (см. также TASK-014, которая тоже добавляет `.testTarget`).
- `concept/LogFormat.md` — описывает входной `tasks.jsonl`, **нет** раздела про выходной `events.jsonl` и системные события.
- `concept/Current.md:88-92` — P2-пункт «Системные события (`unit_built`, `stage_up`, …) определены в `GameEvent.Kind`, но пока не пишутся».

**Что переиспользуем:** `appendSystemEvent` как единая точка записи; готовое поле `title: String?`; injection в `CityEngine.init(eventLog:snapshotStore:)`; готовые `EventLog`/`SnapshotStore` URL-параметризации; ветка `apply` с `break` для новых kind'ов.

**Что нужно дописать:** `title` параметр в `appendSystemEvent`; симметрия с `ingestTaskCompletion` (`events.append`); две точки записи в `applyTaskCompleted`; `UnitKind.label`; раздел в `LogFormat.md`; снятие P2 в `Current.md`; test target; два юнит-теста.

### Архитектурное решение

**Один поток записи — `appendSystemEvent` расширяется опциональным `title`** (`func appendSystemEvent(_ kind: GameEvent.Kind, project: String, title: String? = nil)`). Дефолт `nil` сохраняет backwards-compat для существующих вызовов из `DecayEngine` и `applyTaskCompleted`. `unitBuilt` и `stageUp` записываются той же функцией, той же логикой (eventLog + apply + counters + snapshot trigger).

**Симметрия с `ingestTaskCompletion` (фикс асимметрии).** Сейчас `appendSystemEvent` пишет в `eventLog`, но **не** в `@Published events`. Это означает, что во время текущей сессии decay/restore/unit_built/stage_up не появляются в `engine.events` и недоступны UI-журналу (TASK-015). После рестарта `replayFromLog` восстанавливает `events` целиком — поэтому баг проявляется только до первого перезапуска. AC TASK-024 явно требует, чтобы Done-критерий закрывал «TASK-015 (UI-фильтр) может фильтровать без доработок в backend'е». Поэтому добавляем `events.append(e)` сразу после `eventLog.append(e)` внутри `appendSystemEvent` — это симметрирует поведение и закрывает требование. Side-effect: decay-события начнут показываться в UI-журнале мгновенно (TASK-015 ожидает этого — пресет «Decay-события» подразумевает наличие в `events`). Это в пределах AC #8 «`eventsSinceSnapshot` корректно растёт» — не противоречит.

**Точка записи `unit_built` и `stage_up`.** Внутри существующего блока `if !silent { … }` (стр. 277), **перед** существующими callback'ами `onProjectCreated/onUnitBuilt/onProjectStageChanged`. Это гарантирует порядок в файле: `task_completed → (restore?) → unit_built → (stage_up?)` и при этом события уже в `eventLog`/`events` до того, как сцена реагирует через callback'и. Никакой новой `!silent`-ветки — переиспользуем существующую (стр. 277–295).

**`UnitKind.label`.** Добавляем `extension UnitKind { var label: String { … } }` в `Sources/CityDeveloper/Data/CityState.swift` (там же, где `enum`). Это устраняет необходимость дублирования таблицы в third месте. **Существующие `russianKind` в `InspectorPanel`/`InspectorOverlayCard` оставляем как есть** — их refactor out of scope (запишется в Backlog). Так план остаётся атомарным, и не вмешивается в файлы UI.

**Тесты.** Создаём `Tests/CityDeveloperTests/CityEngineTests.swift` (директория совпадает с TASK-014). `Package.swift` нужен `.testTarget` — добавляем idempotent (если TASK-014 уже запущен раньше, секция уже есть; если нет — добавим). Два кейса:
1. **Live-flow:** один `ingestTaskCompletion` → в логе 2 события (`task_completed`, `unit_built`). Шесть `ingestTaskCompletion` подряд для одного проекта так, чтобы поднялся stage 0→1 → в логе появляется `stage_up`.
2. **Replay-equivalence:** «прогнать» live-engine с N событий → захватить `state` через JSON-encode; создать второй engine с теми же EventLog/SnapshotStore путями (имитация рестарта) → encode его `state`; сравнить байты. Идемпотентность гарантирована, потому что `apply(.unitBuilt/.stageUp) = break`.

**Backwards-compat (v1-логи).** Сценарий явно перечислен в AC. Покрытие — без отдельного теста (через replay-equivalence в комбинации с тем, что новые kind'ы no-op): «v1-лог не содержит `unit_built/stage_up`, новые kind'ы там просто отсутствуют, state восстановится из `task_completed`-событий — как раньше». Документируется в плане; смоук — DoD-ручная проверка.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.

1. **Расширить `appendSystemEvent`: `title` + симметрия с `ingestTaskCompletion`** `[AC:1,8]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Блок: метод `appendSystemEvent` (стр. 50–59).
   - Что меняем: добавить опциональный `title: String? = nil`; передать в конструктор `GameEvent`; добавить `events.append(e)` сразу после `eventLog.append(e)` (для симметрии с `ingestTaskCompletion` стр. 70–71).
   - Финальный вид метода:
     ```swift
     /// Записывает системное событие в лог, применяет к state и триггерит визуальные колбэки.
     /// Вызывается из DecayEngine на main queue и из applyTaskCompleted.
     /// `title` — человекочитаемое описание (имя юнита, "S<old> → S<new>" и т.п.).
     func appendSystemEvent(_ kind: GameEvent.Kind, project: String, title: String? = nil) {
         let e = GameEvent(ts: Date(), kind: kind, project: project, title: title)
         eventLog.append(e)
         events.append(e)
         apply(e, silent: false)
         lastSnapshotEventIndex += 1
         eventsSinceSnapshot += 1
         if eventsSinceSnapshot >= 500 { saveSnapshot() }
     }
     ```
   - Существующие вызовы из `DecayEngine.swift` (`.decayTick`, `.fire`) и текущий вызов `.restore` в `applyTaskCompleted` (стр. 167) **не меняем** — дефолт `nil` сохраняет совместимость.

2. **Добавить `extension UnitKind { var label: String }`** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`
   - Блок: **сразу после** закрывающей `}` `enum UnitKind` (≈ стр. 29; найти `case obelisk` + закрывающий `}`).
   - Что меняем: добавить extension с computed property:
     ```swift
     extension UnitKind {
         /// Русское название юнита для UI и для `title` системных событий.
         var label: String {
             switch self {
             case .shack:     return "Лачуга"
             case .house:     return "Дом"
             case .villa:     return "Вилла"
             case .well:      return "Колодец"
             case .road:      return "Дорога"
             case .warehouse: return "Склад"
             case .workshop:  return "Мастерская"
             case .raw:       return "Сырьевая яма"
             case .market:    return "Рынок"
             case .forum:     return "Форум"
             case .temple:    return "Храм"
             case .obelisk:   return "Обелиск"
             }
         }
     }
     ```
   - Строки взяты из существующих `russianKind` в `InspectorPanel.swift:83-98` и `InspectorOverlayCard.swift:53-68` — таблица идентична.
   - **Не трогать** `russianKind`-приватные функции в Inspector*.swift (out of scope; их dedup → Backlog после задачи).

3. **Записать `unit_built` и `stage_up` в `applyTaskCompleted`** `[AC:2,3,5,9]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Блок: внутри `if !silent { … }` блока `applyTaskCompleted` (стр. 277–295). **Самым первым** действием внутри блока — до `if isNewProject { … }` (стр. 278).
   - Что меняем: вставить две записи, переменные `unit`, `oldStage`, `newStage`, `projectKey` уже в скоупе.
     ```swift
     if !silent {
         // Order in events.jsonl: task_completed → (restore?) → unit_built → (stage_up?).
         appendSystemEvent(.unitBuilt, project: projectKey, title: unit.kind.label)
         if newStage > oldStage {
             appendSystemEvent(.stageUp, project: projectKey, title: "S\(oldStage) → S\(newStage)")
         }
         // ↓ существующий код callback'ов (НЕ менять):
         if isNewProject {
             if let oldId = ruinsClearedFrom { … }
             else { onProjectCreated?(project) }
         }
         onUnitBuilt?(unit, project)
         if newStage > oldStage {
             onProjectStageChanged?(projectKey, oldStage, newStage)
         }
     }
     ```
   - Никаких других изменений в `applyTaskCompleted`. `apply(.unitBuilt)` и `apply(.stageUp)` остаются `break` — не трогаем switch.

4. **Расширить `concept/LogFormat.md`** `[AC:9]`
   - Файл: `concept/LogFormat.md`
   - Блок: добавить новый раздел `## События в events.jsonl (системные)` **в конце файла**.
   - Что меняем: дописать (полное содержание раздела):
     ```markdown
     ## События в events.jsonl (системные)

     Помимо `task_completed`, движок пишет системные события из `applyTaskCompleted`
     и `DecayEngine`. Все используют структуру `GameEvent` (см. `Data/GameEvent.swift`).

     ### Типы

     | Kind            | Когда пишется                                            | Поле `title`              |
     |-----------------|----------------------------------------------------------|---------------------------|
     | `task_completed`| ingest live и из watcher                                 | заголовок задачи          |
     | `unit_built`    | каждый закрытый task → построен новый юнит (`!silent`)   | `UnitKind.label`          |
     | `stage_up`      | повышение стадии квартала 0→…→5 (`!silent`)              | `S<old> → S<new>`         |
     | `restore`       | возврат к проекту с `decayLevel 1..3` (`!silent`)        | nil                       |
     | `decay_tick`    | `DecayEngine` тик подъёма уровня decay                   | nil                       |
     | `fire`          | переход decay 2→3 (визуализация горения)                 | nil                       |
     | `ruins_cleared` | (зарезервирован; пока не пишется отдельно)               | nil                       |

     ### Порядок для одной задачи (нормативный)

     `task_completed` → (`restore` опц.) → `unit_built` → (`stage_up` опц.)

     Все четыре события пишутся в рамках одного вызова `applyTaskCompleted` (live-тик).
     В `silent: true`-ветке (replay из лога / snapshot tail) **новых записей не делается**:
     события уже на диске. Идемпотентность гарантирована тем, что
     `apply(.unitBuilt) = apply(.stageUp) = break`.

     ### Backwards-compat v1 → текущий

     Старый лог (только `task_completed` + decay-серия) реплеится без изменений:
     state-агрегаты (`taskCount`, `stage`, `unitIds`) выводятся из `task_completed`-веток.
     Новый лог содержит `unit_built/stage_up`, но они no-op при apply — state идентичен.
     Версия формата НЕ повышается (нет поля `version` в `GameEvent`).

     ### Поведение при неизвестных `kind`

     `GameEvent.Kind` — закрытое `Codable enum` без `@unknown default`. Строка
     `events.jsonl` с неизвестным `kind` пропускается: `EventLog.readAll` ловит
     ошибку декодирования через `try?` и пишет в `ErrorsLog`
     (`EventLog.swift:42-45`). Это значит:
     - старый бинарь, читающий лог с новым `kind`, не падает, но теряет такие строки;
     - при добавлении нового `kind` авторы обязаны обновлять `LogFormat.md` и
       выдерживать совместимость через `apply = break` либо отдельную no-op-ветку.
     ```

5. **Снять P2 в `concept/Current.md`** `[AC:9]`
   - Файл: `concept/Current.md`
   - Блок: строки 88–92 (раздел «### P2 — Технический долг»). Найти точный текст:
     ```
     1. Системные события (`unit_built`, `stage_up`, и т.д.) определены в `GameEvent.Kind`,
        но пока не пишутся в `events.jsonl` отдельно — все апдейты state выводятся из
        `task_completed`. Это упрощение MVP; для проигрывания decay/restore-анимаций
        потребуется писать системные события.
     ```
   - Что меняем: удалить этот пункт целиком. Если в P2 он был единственным — оставить заголовок раздела и пустой markdown-список (или удалить всю секцию). Перенумеровать остальные пункты в P2, если есть.

6. **Добавить test target в Package.swift (idempotent)** `[AC:10]`
   - Файл: `Package.swift`
   - Что меняем: если `.testTarget(name: "CityDeveloperTests", …)` **уже добавлен** TASK-014 — этот шаг пропустить. Иначе расширить `targets`:
     ```swift
     targets: [
         .executableTarget(
             name: "CityDeveloper",
             path: "Sources/CityDeveloper"
         ),
         .testTarget(
             name: "CityDeveloperTests",
             dependencies: ["CityDeveloper"],
             path: "Tests/CityDeveloperTests"
         )
     ]
     ```
   - Создать директорию: `mkdir -p Tests/CityDeveloperTests` (если ещё нет).

7. **Юнит-тесты `CityEngineTests.swift`** `[AC:10]`
   - Файл: новый — `Tests/CityDeveloperTests/CityEngineTests.swift`. Если файл уже создан TASK-014 (например `CitizenManagerTests.swift`) — создаём отдельный файл рядом.
   - Что меняем: создать со следующим содержимым:
     ```swift
     import XCTest
     @testable import CityDeveloper

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
         /// Сравнение **структурное**: побайтовое сравнение JSON ненадёжно для словарей
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
     ```
   - **Внимание:** `SnapshotStore(url:)` — конструктор. Если в `SnapshotStore.swift` инициализатор другой (например, `init()` + property `url`), исполнитель адаптирует под фактическую сигнатуру (см. файл). Это единственное место, требующее «понимания контекста» — но `relocateSnapshotStore` в `CityEngine.swift:46-48` уже показывает, что `snapshotStore.url` — публичный setter, значит конструктор-инжектор либо принимает `url`, либо есть default-init с последующим `.url = …`. Скорее всего работает любой из двух вариантов:
     ```swift
     // Вариант A — если есть init(url:)
     let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
     // Вариант B — если только default init + url-сеттер
     let snap = SnapshotStore()
     snap.url = dir.appendingPathComponent("state.json")
     ```
     Исполнителю: проверить `SnapshotStore.swift`, выбрать правильный паттерн.

### Edge cases (явно обработать)

- [x] **Replay-tail после миграции v1 → новый билд** — `silent: true` блокирует запись `unit_built`/`stage_up` на старых событиях (`apply` для них = `break`, в `applyTaskCompleted` гард `!silent` стр. 277). State восстанавливается через `task_completed`-ветку как раньше. Тестируется `testReplayEquivalence` + `testReplayDoesNotDuplicateEvents`.
- [x] **Stage-up при taskCount=1** — `oldStage=0`, `newStage` через `computeStage(taskCount: 1, ageDays: 1)` обычно тоже 0; `if newStage > oldStage` = false → `stage_up` не пишется. Корректно.
- [x] **Restore-кольцо** — `appendSystemEvent(.restore, ...)` в начале `applyTaskCompleted` стр. 167 завершает рекурсивный apply ДО основного потока. Порядок в логе: `task_completed → restore → unit_built → (stage_up?)`. Гарантировано.
- [x] **Несколько задач в одном тике** — каждая идёт через `ingestTaskCompletion` отдельно, на main-queue. События последовательны.
- [x] **decay 3→0 (restore) + stage-up в одном тике** — порядок: `task_completed → restore → unit_built → stage_up`. Покрывается общей логикой шага 3.
- [x] **v1-лог без новых событий** — в логе старых билдов `unit_built/stage_up` отсутствуют. `replayFromLog` читает их через `readAll`/`readSince`, проходит через `apply(silent: true)`; для отсутствующих kind'ов проблем нет — их в логе нет.

### Файлы для изменения

- `Sources/CityDeveloper/Game/CityEngine.swift` — расширить `appendSystemEvent` (signature + `events.append`); вставка двух `appendSystemEvent` в `applyTaskCompleted` (внутри `!silent` блока, перед callback'ами).
- `Sources/CityDeveloper/Data/CityState.swift` — `extension UnitKind { var label: String }`.
- `concept/LogFormat.md` — новый раздел «События в events.jsonl (системные)» в конце файла.
- `concept/Current.md` — снять P2-пункт про системные события (стр. 88–92).
- `Package.swift` — `.testTarget` (idempotent с TASK-014).
- `Tests/CityDeveloperTests/CityEngineTests.swift` — новый файл, 4 XCTest-кейса.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/CityEngine.swift:apply` (switch по kind'ам) — `case .unitBuilt, .stageUp, .ruinsCleared: break` обязан остаться, это якорь идемпотентности replay.
- `Sources/CityDeveloper/Game/CityEngine.swift:replayFromLog` — без изменений; снапшот-логика стабильна.
- `Sources/CityDeveloper/Game/DecayEngine.swift` — существующие вызовы `appendSystemEvent(.decayTick/.fire, project:)` совместимы через дефолт `title: nil`.
- `Sources/CityDeveloper/Data/GameEvent.swift` — поле `title: String?` уже есть, модель **не** трогаем.
- `Sources/CityDeveloper/UI/InspectorPanel.swift` и `InspectorOverlayCard.swift` — `russianKind` дубли оставляем (refactor вынести в Backlog).
- `Sources/CityDeveloper/Game/UnitSprites.swift` — визуальные настройки юнитов вне scope.

### Команды проверки (для DoD)

- Компиляция: `swift build` из `<repo-root>`. Ожидание: 0 ошибок, 0 новых warning'ов.
- Тесты: `swift test --filter CityEngineTests`. Ожидание: 4 пройдены.
- Полный smoke `[AC:6,7]`:
  1. Удалить `events.jsonl` и `state.json` (см. `AppPaths`) для чистого старта.
  2. Запустить `swift run CityDeveloper` (или Xcode).
  3. Закрыть 8 задач в журнале (3 разных projectId, минимум 1 stage-up).
  4. Открыть `events.jsonl` — убедиться, что:
     - На каждый `task_completed` идёт `unit_built` сразу после.
     - Где-то встречается `stage_up` с `title: "S0 → S1"` (или выше).
  5. Закрыть приложение, запустить заново.
  6. Открыть инспектор — `state.projects` и `state.units` визуально идентичны до и после рестарта (тот же набор кварталов, юнитов, стадий).
- v1 backwards-compat `[AC:7]`:
  1. Взять старый `events.jsonl` (только `task_completed/decay_*`) от предыдущей версии — можно сохранить копию `events.jsonl` ДО реализации задачи.
  2. Запустить новый билд на этом логе.
  3. Убедиться: в `ErrorsLog` нет undecodable-warning'ов; `state` совпадает с тем, что был в старом билде (визуально город идентичен).

### Сложность

`middle`

**Обоснование:** event sourcing core, P1, расширение формата журнала. 6 файлов в Game/Data/concept/Package/Tests — без архитектурных рисков (используем существующий `appendSystemEvent`-паттерн), но требует аккуратности в порядке записи и тестов на идемпотентность. Не junior — backend, формат события, тесты с tmpdir. Не senior — нет миграции формата, нет переписывания replay'а.

### Ожидаемое время

M (≤1д) — 2 правки в одном файле, extension, два markdown-документа, test target, 4 теста с tmpdir / JSON-сравнением state. Реалистично 3–5 часов.

---

## ✅ Исполнение

_Исполнитель: sonnet (executor)_
_Сложность: middle_

### Definition of Done

#### Функциональные
- [x] AC1–AC5, AC8–AC11 — structural pass (verify Sonnet)
- [ ] AC6 (Replay-эквивалентность), AC7 (v1 backwards-compat) — manual: код тестов корректен, но `swift test` в окружении без Xcode.app не запускается

#### Технические
- [x] Компиляция Swift без новых ошибок/варнингов (`swift build` clean)
- [ ] `swift test --filter CityEngineTests` — n/a (нет Xcode.app/XCTest framework). Структура 4 тестов корректна.

#### Обновление документации
- [x] `Current.md`: P2-пункт «Системные события не пишутся» удалён
- [x] `LogFormat.md`: дополнен раздел «События в events.jsonl (системные)» с таблицей, нормативным порядком и backwards-compat
- [x] `Diff.md`: D-11 строка дополнена — TASK-024 в Done

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: implicit-approved (PM-блок полный: Done, AC, сценарий, «не делаем», edge cases, зависимости)
- Lead-model: opus
- Plan-review: revised (sonnet, 2 круга → approved)
- Code-review: approved (opus, 1 круг)
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Коммит: 1093693
