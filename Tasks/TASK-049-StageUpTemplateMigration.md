# TASK-049: Template migration на stage-up (квартал «улучшается», юниты остаются)

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **D-25** из Diff.md (часть 3/5 — миграция формы при stage-up)
- **F-08** (стадии 0→5 — миграция должна работать на каждый stage++)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Сейчас при stage-up квартала (F-08) меняется только визуал юнитов (tier).
**Форма квартала остаётся та же** — шаблон stage 1 не превращается в
шаблон stage 2. Этого Илья хочет: чтобы квартал «улучшался годами», а не
только «обрастал юнитами в одной и той же форме».

Эта TASK: на каждом `applyProjectStageChange` (stage_up event) подменять
текущий `ProjectState.templateName` на новый шаблон stage+1 той же
family, **сохраняя позиции существующих юнитов**.

Инвариант дизайна шаблонов (заложен в TASK-047): для каждой пары
`(stage N, stage N+1)` в одной family bbox stage N ⊆ bbox stage N+1 и
роли слотов совместимы (slot (x,y) с role X в N → есть slot (x,y) с
role X в N+1, либо пустая клетка которая роль не блокирует).

### Пользовательский сценарий

1. Квартал «Foo» в stage 1 имеет шаблон Deir el-Medina (10 юнитов).
2. Stage 1 → 2 (formula StageRules) → CityEngine triggers
   `applyTemplateMigration`: новый шаблон = Kahun (stage 2 egyptian).
3. Все 10 существующих юнитов (хижины + колодец + дорога) **остаются на
   своих координатах**. Их позиции (3, 2), (4, 2), ... соответствуют слотам
   Kahun (потому что Deir el-Medina ⊆ Kahun bbox).
4. У Kahun добавились новые слоты по периметру (ферма, амбар, дом
   старосты) — они **свободны**, заполнятся следующими task_completed.
5. Визуально пользователь видит: квартал не «передёрнулся», а **раскрылся**
   — появились новые тайлы дорог и пустые слоты, готовые принять новые
   здания. Анимация: cross-fade новых тайлов земли + road-extension за
   ≤1 сек.
6. Если миграция невозможна (например, в catalog нет stage+1 шаблона той
   же family) → fallback: квартал остаётся со старым шаблоном, warning в
   errors.log: `[template-migration] no stage+1 template for family X,
   keeping stage N template`.

### Acceptance criteria

- [ ] В `CityEngine.applyProjectStageChange` (или эквивалент — найти точку
      через Explore) после изменения `project.stage` вызывается
      `applyTemplateMigration(project:)`.
- [ ] `applyTemplateMigration` алгоритм:
      a) Получить `currentTemplate` через `templateName`.
      b) Получить `nextTemplate` через Picker(stage: project.stage,
         family: project.templateFamily, biome: ..., seed: ...).
      c) Проверить инвариант: для каждого занятого слота currentTemplate
         (`projectUnits` имеют позицию = слот) в `nextTemplate` есть слот
         с **той же координатой** и **совместимой role**. Совместимость:
         residential ↔ residential (любого footprint), well ↔ well,
         road ↔ road; обновлять role для слотов с одной ролью точно
         можно, для разных — нет.
      d) Если инвариант нарушен (хоть один существующий юнит «выпадает»
         из nextTemplate) → НЕ мигрировать, warning, оставить currentTemplate.
      e) Если ОК — обновить `project.templateName` на `nextTemplate.name`,
         emit `GameEvent.Kind.templateMigrated(projectId, fromTemplate,
         toTemplate)`.
- [ ] Новый `GameEvent.Kind` case `templateMigrated(projectId: String,
      fromTemplate: String, toTemplate: String)` — записывается в events.jsonl,
      replay воспроизводит.
- [ ] `GameScene.handleProjectStageChanged` дорисовывает новые road-клетки
      и пустые тайлы земли через `drawAddedRoadCells` (уже есть в BUG-017
      инфраструктуре) + cross-fade ≤1 сек.
- [ ] Инвариант шаблонов проверяется в `DistrictTemplateCatalogTests`:
      `testStageNContainsStageNMinusOne(family: "egyptian")` для каждой
      пары (1→2, 2→3, 3→4, 4→5). Если падает — шаблоны нужно переделать.
- [ ] Тест `CityEngineTemplateMigrationTests.swift`:
      `testStageUpMigratesTemplate`, `testMigrationPreservesUnitPositions`,
      `testMigrationSkippedWhenIncompatible`, `testMigrationIsReplayable`.

### Что НЕ делаем (границы скоупа)

- НЕ делаем era progression (era 1-3 после stage 5) — это TASK-050.
- НЕ делаем Settings UI — это TASK-051.
- НЕ позволяем «перерасставить» юниты (это сломало бы replay) — только
  bbox-расширение шаблона.

### Edge cases

- [ ] Старый проект без `templateName` (legacy snapshot) → миграция
      пропускается, продолжает работать на legacy placement.
- [ ] `nextTemplate == nil` (для stage 5 нет stage 6 шаблона — это
      ожидаемо до TASK-050 era progression) → миграция пропускается без
      warning'а.
- [ ] Quick double stage-up (1→2→3 за один тик) → миграция применяется
      последовательно: 1→2, потом 2→3. Каждая отдельным
      `templateMigrated` event.
- [ ] Юнит в позиции, которая в nextTemplate занята слотом другой role
      (например, residential было, а в nextTemplate тут warehouse) →
      инвариант нарушен, миграция skipped. Это сигнал «шаблоны надо
      пересмотреть».
- [ ] decay-4 квартал (руины) → миграция skipped (нет смысла улучшать
      руины).
- [ ] Replay: при чтении старого `templateMigrated` event'а из
      events.jsonl шаблоны должны иметь те же `name` (иначе replay
      сломается). При смене формата шаблона нужна явная миграция
      `events.jsonl v2` (out-of-scope этой TASK).

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (templateName в ProjectState).
- **Soft-blocks:** TASK-050 (era progression — для stage 5 → era 1
  использует тот же mechanism).

### Дизайн

Не применимо (нет UI; визуал — расширение road-сети + новые пустые
тайлы, уже покрыто BUG-017 инфраструктурой).

### Done-критерий

_Часть F-25 Done-критерия:_ «При stage-up до 2 квартал визуально
превращается в Kahun-сетку, существующие хижины остаются на своих
местах + появляются новые слоты». Эта TASK закрывает это полностью.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- В коде уже есть:
  - `Sources/CityDeveloper/Game/StageRules.swift:5-27` — `computeStage(taskCount:ageDays:) -> Int` (0..5).
  - `Sources/CityDeveloper/Game/CityEngine.swift:444-461` — stage-up branch внутри `applyTaskCompleted`: вычисляет `newStage`, обновляет `project.stage` + `unit.tier` для всех unit'ов проекта.
  - `Sources/CityDeveloper/Game/CityEngine.swift:463-496` — live-блок `if !silent`: `appendSystemEvent(.unitBuilt)` → `applyEvolutionsIfReady` cascade → `appendSystemEvent(.stageUp)` → callbacks (`onProjectCreated`/`onUnitBuilt`/`onProjectStageChanged`).
  - `Sources/CityDeveloper/Game/CityEngine.swift:177-212` — `apply(event:silent:)` switch по `event.kind`: `.unitBuilt, .stageUp, .ruinsCleared: break` (no-op — state уже изменён в applyTaskCompleted; событие только для логирования).
  - `Sources/CityDeveloper/Game/CityEngine.swift:87-95` — `appendSystemEvent(_:project:title:)` — единая точка записи системных событий.
  - `Sources/CityDeveloper/Game/CityEngine.swift:298-309` — pick template для нового проекта (seed `fnv1a([projectKey])`).
  - `Sources/CityDeveloper/Game/CityEngine.swift:634-654` — `pickRuinForNewProject` использует `decayLevel == 4` как маркер руины.
  - `Sources/CityDeveloper/Data/GameEvent.swift:5-16` — `enum Kind: String, Codable` (8 case'ов). `unitEvolvedPayload(from:)` — пример парсинга composite title через `|`.
  - `Sources/CityDeveloper/Data/EventLog.swift:19-58` — JSONL append/read.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift:7-37` — `pick(stage:family:biome:seed:)`.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — `byStage`, `byName` (TASK-048c).
  - `Sources/CityDeveloper/Game/GameScene.swift:397-407` — `handleProjectStageChanged(projectId:oldStage:newStage:)` (TASK-019).
  - `Sources/CityDeveloper/Game/GameScene.swift:649-657` — `drawAddedRoadCells(_ cells: [GridPoint])` (BUG-017 инфра).
  - `Sources/CityDeveloper/App/AppDelegate.swift:70-72` — `engine.onProjectStageChanged` registered.
  - `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift:93-117` — `testStageProgressionPreservesSlots` — **гарантирует**, что для each pair (N, N+1) ALL slots stage N присутствуют в stage N+1 с тем же (x,y,role,footprint). Это значит: для egyptian-family миграция всегда compatible.
  - `Tests/CityDeveloperTests/CityEngineTemplateAssignmentTests.swift` — helper-pattern (`makeTempDir`, `makeEngine`).
  - 5 egyptian JSON: stage1 8×5/15 slots → stage5 16×16/60 slots, bbox монотонно растёт.

- Связанные модули:
  - `Sources/CityDeveloper/Data/CityState.swift:440-509` — `ProjectState.templateName/templateFamily/eraLevel`.
  - `Sources/CityDeveloper/Data/GameEvent.swift` — расширение enum.
  - `Sources/CityDeveloper/Game/DeterministicRNG.swift` — `fnv1a(combining:)`.
  - `Sources/CityDeveloper/Data/ErrorsLog.swift` — `write(_:)`.

- Что переиспользуем:
  - `DistrictTemplatePicker.pick`, `DistrictTemplateCatalog.byName`, `appendSystemEvent`, `fnv1a`, `ErrorsLog.write`, existing `apply` switch pattern (`.stageUp: break`).

- Что нужно дописать:
  - `GameEvent.Kind.templateMigrated` case + helper `templateMigrationPayload(from title:)` (по аналогии с `unitEvolvedPayload`).
  - `TemplateMigrationValidator` — pure static helper для проверки compatibility (новый файл для testability).
  - `CityEngine.applyTemplateMigration` — private метод, вызывается из applyTaskCompleted после tier-update.
  - `CityEngine.onTemplateMigrated` callback (optional, для GameScene; MVP — no-op).
  - 4 теста в `CityEngineTemplateMigrationTests.swift` + 1 unit-test в `TemplateMigrationValidatorTests.swift`.

### Архитектурное решение

**Главный паттерн:** template migration копирует семантику `.stageUp` — state-изменение в `applyTaskCompleted` (работает и в live, и в replay через silent), а `apply(.templateMigrated): break` (no-op, state уже применён). Это обеспечивает идемпотентность replay без дополнительной логики в `apply()` switch.

**Сидирование Picker для миграции:** `fnv1a(combining: [projectKey, "stage-\(newStage)"])`. Отличается от сидирования нового проекта (`fnv1a([projectKey])`), чтобы будущие версии могли иметь несколько кандидатов на каждый stage без коллизий. Family берётся из `project.templateFamily` (уже зафиксирован при создании проекта в TASK-048c — например, "egyptian" после resolve "auto"), поэтому миграция всегда внутри одной family — детерминизм гарантирован.

**Validator выносится в отдельный pure тип** `TemplateMigrationValidator.canMigrate(units:from:to:districtOrigin:) -> Bool` для testability с фикстурными templates (in-memory, не из Catalog). Логика: для каждого unit'а проверить, что `unit.position` лежит на одном из слотов `nextTemplate` (с учётом `districtOrigin`) И role этого слота совместим с `unit.kind.preferredSlotRole`. Compatible = `slot.role == unit.kind.preferredSlotRole`.

**Edge case quick double stage-up** (1→2→3 за один тик): мигрируем **пошагово** через `for s in (oldStage+1)...newStage { applyTemplateMigration(newStage: s, ...) }` — каждый шаг отдельным `.templateMigrated` event'ом в JSONL (по PM AC). Это гарантирует, что replay воспроизведёт ту же цепочку событий, что и live, независимо от формулы StageRules.

**Сидирование Picker для миграции:** `fnv1a(combining: [projectKey, "stage-\(targetStage)"])` где `targetStage` — каждый промежуточный stage в loop'е (не «final» newStage). Это значит, что миграция 1→2 использует seed `[projectKey, "stage-2"]`, миграция 2→3 — `[projectKey, "stage-3"]`, и т.д. Детерминизм при replay гарантирован.

**GameScene callback `onTemplateMigrated`** — **реализуем minimal road-extension** через переиспользование `drawAddedRoadCells` (BUG-017 инфра). Handler вычисляет diff: road-слоты `nextTemplate \ currentTemplate` (по абсолютным координатам с учётом `project.districtOrigin`) и передаёт их в `drawAddedRoadCells`. Это закрывает road-часть AC4. Cross-fade новых пустых тайлов земли оставляем для follow-up (Земля не рендерится отдельно — это часть SKTileMapNode, который не меняется при миграции; отдельный rendering empty slots — отдельная задача).

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Не меняй существующие методы без указания. Не трогай GameScene rendering — там только callback-регистрация (no-op handler).

1. **Добавить `GameEvent.Kind.templateMigrated` + payload helper** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Data/GameEvent.swift`
   - В `enum Kind: String, Codable, CaseIterable` (lines 5-16) добавить новый case в конец:
     ```swift
     case templateMigrated = "template_migrated"
     ```
   - Добавить static helper по аналогии с `unitEvolvedPayload(from:)` (внизу того же файла, в extension `GameEvent`):
     ```swift
     static func templateMigrationPayload(from title: String?) -> (from: String, to: String)? {
         guard let title else { return nil }
         let parts = title.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
         guard parts.count == 2 else { return nil }
         return (String(parts[0]), String(parts[1]))
     }
     ```

2. **`apply` switch: добавить no-op case для `.templateMigrated`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift` (lines 177-212).
   - В switch блоке найти строку `case .unitBuilt, .stageUp, .ruinsCleared:` и добавить `.templateMigrated`:
     ```swift
     case .unitBuilt, .stageUp, .ruinsCleared, .templateMigrated:
         break
     ```
   - **Обоснование:** state-изменение `project.templateName` уже применяется в `applyTaskCompleted` (live + replay через silent). Событие .templateMigrated — чисто логирующее, как `.stageUp`.

3. **Новый файл `TemplateMigrationValidator.swift`** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Game/Templates/TemplateMigrationValidator.swift` (НОВЫЙ).
   - Скелет:
     ```swift
     import Foundation

     enum TemplateMigrationValidator {
         /// Проверяет, что все existing units проекта попадают на slot'ы nextTemplate
         /// с совместимой role. Совместимость: slot.role == unit.kind.preferredSlotRole.
         /// districtOrigin — origin квартала (для расчёта абсолютной позиции slot'ов).
         static func canMigrate(
             units: [UnitState],
             to nextTemplate: DistrictTemplate,
             districtOrigin: GridPoint
         ) -> Bool {
             // Построить map: absolute slot position → slot.role
             var slotRoles: [GridPoint: SlotRole] = [:]
             for slot in nextTemplate.slots {
                 let abs = GridPoint(x: districtOrigin.x + slot.x, y: districtOrigin.y + slot.y)
                 slotRoles[abs] = slot.role
             }
             // Каждый unit'у проекта (исключая road — он на road-слотах,
             // которые тоже учтены): unit.position должна быть slot'ом
             // с slot.role == unit.kind.preferredSlotRole.
             for unit in units {
                 guard let role = slotRoles[unit.position] else { return false }
                 if role != unit.kind.preferredSlotRole { return false }
             }
             return true
         }
     }
     ```
   - **Не закладывать никакой compat-логики «residential ↔ resident-related»** — strict equality `role == preferredSlotRole`. Этот контракт уже соответствует `UnitKind.preferredSlotRole` (TASK-048b) и slot.role в template.

4. **`CityEngine.applyTemplateMigration` (private метод)** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift` (внизу класса, рядом с `resolveLegacyKindAndPosition`).
   - Скелет:
     ```swift
     /// TASK-049 F-25: миграция template при stage-up. Идемпотентна (silent=true safe).
     /// Изменяет project.templateName в state. В live (silent=false) emit'ит событие
     /// и вызывает callback.
     /// Возвращает (fromName, toName)? — нужно для appendSystemEvent в live-блоке.
     @discardableResult
     private func applyTemplateMigration(
         projectKey: String,
         newStage: Int,
         silent: Bool
     ) -> (from: String, to: String)? {
         guard var project = state.projects[projectKey] else { return nil }

         // Pre-checks
         guard let currentName = project.templateName else { return nil }      // legacy proj
         guard project.decayLevel < 4 else { return nil }                       // ruin
         guard let currentFamily = project.templateFamily else { return nil }   // safety

         // Pick next template (deterministic via fnv1a([projectKey, "stage-\(newStage)"])).
         let pickSeed = fnv1a(combining: [projectKey, "stage-\(newStage)"])
         let pickBiome = biomeReader?.biome(atX: project.districtOrigin.x, y: project.districtOrigin.y)
         guard let nextTemplate = DistrictTemplatePicker.pick(
             stage: newStage,
             family: currentFamily,
             biome: pickBiome,
             seed: pickSeed
         ) else {
             // No template for stage+1 (например stage 5 без stage 6) — silent skip
             return nil
         }
         // Same template (Picker иногда возвращает тот же, если family flat) — skip
         if nextTemplate.name == currentName { return nil }

         // Validate compatibility.
         let projectUnits = state.units.values.filter { $0.projectId == projectKey }
         guard TemplateMigrationValidator.canMigrate(
             units: Array(projectUnits),
             to: nextTemplate,
             districtOrigin: project.districtOrigin
         ) else {
             ErrorsLog.write("[template-migration] district \(projectKey): cannot migrate from \(currentName) to \(nextTemplate.name) — unit positions incompatible, keeping \(currentName)")
             return nil
         }

         // Apply state change (live + replay).
         project.templateName = nextTemplate.name
         project.templateFamily = nextTemplate.family  // обычно тот же, но safe
         state.projects[projectKey] = project

         return (currentName, nextTemplate.name)
     }
     ```

5. **Вызов миграции в `applyTaskCompleted` после tier-update (пошагово)** `[AC:1,3]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`.
   - **Точное место:** в outer scope objявить переменную `var migrations: [(from: String, to: String)] = []` ПЕРЕД блоком `if newStage > oldStage` (строка 458). Внутри блока, после `for uid in project.unitIds { ... }` (строки 459-461) добавить пошаговый loop миграций.
   - Финальный block (примерно строки 458-470 после правки):
     ```swift
     var migrations: [(from: String, to: String)] = []
     if newStage > oldStage {
         for uid in project.unitIds {
             state.units[uid.uuidString]?.tier = newStage
         }
         // TASK-049 F-25: пошаговая миграция template для каждого промежуточного
         // stage'а (1→2→3 даёт два .templateMigrated event'а). Идемпотентна
         // для replay через silent (state-изменение всегда, событие — только в
         // live ниже).
         for targetStage in (oldStage + 1)...newStage {
             if let m = applyTemplateMigration(
                 projectKey: projectKey,
                 newStage: targetStage,
                 silent: silent
             ) {
                 migrations.append(m)
             }
         }
     }
     ```

5a. **Emit `.templateMigrated` events в live-блоке** `[AC:3]`
   - Внутри `if !silent` блока (строки 463-496), **сразу после** `appendSystemEvent(.stageUp, ...)` (строка 477), добавить loop эмиссии (один event на каждую промежуточную миграцию):
     ```swift
     for m in migrations {
         appendSystemEvent(.templateMigrated, project: projectKey,
                           title: "\(m.from)|\(m.to)")
         onTemplateMigrated?(projectKey, m.from, m.to)
     }
     ```

6. **Добавить callback `onTemplateMigrated` в CityEngine** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`.
   - Найти существующий блок callbacks (внизу class declaration, после `onProjectStageChanged`):
     ```swift
     var onProjectStageChanged: ((String, Int, Int) -> Void)?
     ```
   - Добавить:
     ```swift
     /// TASK-049 F-25: callback при миграции template на stage-up.
     /// (projectId, fromTemplateName, toTemplateName). Вызывается только в live.
     /// AppDelegate wires в GameScene.handleTemplateMigrated.
     var onTemplateMigrated: ((String, String, String) -> Void)?
     ```

6a. **Тестовый seam в CityEngine для инжекции unit'а** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`.
   - **Точное место:** добавь internal helper рядом с private методами (внизу класса, после `resolveLegacyKindAndPosition`).
   - Скелет:
     ```swift
     /// TASK-049 test seam — позволяет интеграционным тестам инжектить
     /// unit на произвольную позицию (например, для проверки behavior'а
     /// applyTemplateMigration при incompatible state). НЕ использовать
     /// в production-коде — обходит event-sourcing.
     internal func _testInjectUnit(_ unit: UnitState, into projectKey: String) {
         state.units[unit.id.uuidString] = unit
         state.projects[projectKey]?.unitIds.append(unit.id)
     }
     ```
   - `internal` доступен через `@testable import CommitPyramid`. Внутри класса `state` (даже private(set)) доступен для записи. Нет production-каллеров, никаких регрессов.

7. **Регистрация callback в AppDelegate + road-extension handler в GameScene** `[AC:4]`
   - Файл `Sources/CityDeveloper/App/AppDelegate.swift`: после строк 70-72 (`engine.onProjectStageChanged = ...`) добавить:
     ```swift
     engine.onTemplateMigrated = { [weak self] projectId, from, to in
         self?.scene?.handleTemplateMigrated(projectId: projectId, fromTemplate: from, toTemplate: to)
     }
     ```
   - Файл `Sources/CityDeveloper/Game/GameScene.swift`: рядом с `handleProjectStageChanged` (строки 397-407) добавить:
     ```swift
     /// TASK-049 F-25: при миграции template — дорисовать новые road-слоты
     /// (slot.role == .road, которые есть в nextTemplate, но не было в currentTemplate).
     /// Пустые тайлы земли других role'ов рендерятся естественно при заполнении
     /// последующими task_completed (через slot-placement в UnitPlanner).
     func handleTemplateMigrated(projectId: String, fromTemplate: String, toTemplate: String) {
         DispatchQueue.main.async { [weak self] in
             guard let self, self.didAttach,
                   let engine = self.engine,
                   let project = engine.state.projects[projectId],
                   let current = DistrictTemplateCatalog.byName(fromTemplate),
                   let next = DistrictTemplateCatalog.byName(toTemplate) else { return }
             let origin = project.districtOrigin
             // Абсолютные координаты road-слотов в каждом template.
             let currentRoadCells: Set<GridPoint> = Set(current.slots
                 .filter { $0.role == .road }
                 .map { GridPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
             let nextRoadCells: Set<GridPoint> = Set(next.slots
                 .filter { $0.role == .road }
                 .map { GridPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
             // Diff: новые road-слоты, которых не было раньше.
             let added = Array(nextRoadCells.subtracting(currentRoadCells))
             if !added.isEmpty {
                 self.drawRoadCells(added)  // SKAction.fadeIn ≤0.5 уже внутри
             }
         }
     }
     ```
   - **Примечание исполнителю:** `drawRoadCells(_:)` — внутренний метод, который уже имеет fade-in анимацию (см. `drawAddedRoadCells` обёртка). Если drawRoadCells private — переиспользуй `self.drawAddedRoadCells(added)` (более внешний API).

9. **Unit-тесты `TemplateMigrationValidatorTests.swift`** `[AC:6]`
   - Файл: `Tests/CityDeveloperTests/TemplateMigrationValidatorTests.swift` (НОВЫЙ).
   - Скелет:
     ```swift
     import XCTest
     @testable import CommitPyramid

     final class TemplateMigrationValidatorTests: XCTestCase {

         private func makeTemplate(name: String, slots: [TemplateSlot]) -> DistrictTemplate {
             DistrictTemplate(
                 name: name, family: "test", stage: 1,
                 width: 10, height: 10,
                 biomePreference: [.meadow],
                 slots: slots
             )
         }

         private func makeUnit(kind: UnitKind, at: GridPoint, projectId: String = "p1") -> UnitState {
             UnitState(
                 id: UUID(), projectId: projectId, kind: kind,
                 position: at, tier: 0, decayLevel: 0,
                 taskTitle: nil, taskTs: Date(), taskSource: nil
             )
         }

         func testCanMigrateWhenAllPositionsMatchSlots() {
             let next = makeTemplate(name: "next", slots: [
                 TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1)),
                 TemplateSlot(x: 2, y: 2, role: .road,        footprint: GridSize(width: 1, height: 1))
             ])
             let units = [
                 makeUnit(kind: .shack, at: GridPoint(x: 1, y: 1)),  // residential
                 makeUnit(kind: .road,  at: GridPoint(x: 2, y: 2))   // road
             ]
             XCTAssertTrue(TemplateMigrationValidator.canMigrate(
                 units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
             ))
         }

         func testCannotMigrateWhenUnitPositionHasNoSlot() {
             let next = makeTemplate(name: "next", slots: [
                 TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1))
             ])
             let units = [makeUnit(kind: .shack, at: GridPoint(x: 5, y: 5))]
             XCTAssertFalse(TemplateMigrationValidator.canMigrate(
                 units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
             ))
         }

         func testCannotMigrateWhenSlotRoleIncompatible() {
             let next = makeTemplate(name: "next", slots: [
                 TemplateSlot(x: 1, y: 1, role: .warehouse, footprint: GridSize(width: 1, height: 1))
             ])
             let units = [makeUnit(kind: .shack, at: GridPoint(x: 1, y: 1))]  // shack → residential ≠ warehouse
             XCTAssertFalse(TemplateMigrationValidator.canMigrate(
                 units: units, to: next, districtOrigin: GridPoint(x: 0, y: 0)
             ))
         }

         func testRespectsDistrictOriginOffset() {
             let next = makeTemplate(name: "next", slots: [
                 TemplateSlot(x: 1, y: 1, role: .residential, footprint: GridSize(width: 1, height: 1))
             ])
             let units = [makeUnit(kind: .shack, at: GridPoint(x: 101, y: 51))]
             XCTAssertTrue(TemplateMigrationValidator.canMigrate(
                 units: units, to: next, districtOrigin: GridPoint(x: 100, y: 50)
             ))
         }
     }
     ```
   - 4 теста. (PM не требует точное число, спека требует `testStageNContainsStageNMinusOne` уже есть в TASK-047 как `testStageProgressionPreservesSlots`.)

10. **Integration-тесты `CityEngineTemplateMigrationTests.swift`** `[AC:6]`
    - Файл: `Tests/CityDeveloperTests/CityEngineTemplateMigrationTests.swift` (НОВЫЙ).
    - Скелет (4 теста — точно по PM AC):
      ```swift
      import XCTest
      @testable import CommitPyramid

      final class CityEngineTemplateMigrationTests: XCTestCase {

          private func makeTempDir() -> URL {
              let dir = FileManager.default.temporaryDirectory
                  .appendingPathComponent("ce-mig-\(UUID().uuidString)")
              try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
              return dir
          }

          private func makeEngine(at dir: URL) -> CityEngine {
              let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
              let snap = SnapshotStore(url: dir.appendingPathComponent("state.json"))
              let e = CityEngine(eventLog: log, snapshotStore: snap)
              e.templateFamily = "egyptian"
              return e
          }

          /// Создаёт ProjectState с stage=N и нужным числом задач, последовательно
          /// ingestТaskCompletion. ageDays достигается ts далеко в прошлое.
          private func ingestN(_ engine: CityEngine, project: String, count: Int, baseDate: Date) {
              for i in 0..<count {
                  // Шагаем по дням, чтобы ageDays > 1 для stage progression.
                  let ts = baseDate.addingTimeInterval(TimeInterval(i) * 86_400)
                  engine.ingestTaskCompletion(project: project, title: "t\(i)",
                      taskId: nil, source: nil, ts: ts)
              }
          }

          /// Имена шаблонов берутся динамически из Catalog — устойчивы к
          /// переименованию JSON-файлов.
          private func stage1Name() throws -> String {
              let t = try XCTUnwrap(
                  DistrictTemplateCatalog.byStage(1, family: "egyptian").first)
              return t.name
          }
          private func stage5Name() throws -> String {
              let t = try XCTUnwrap(
                  DistrictTemplateCatalog.byStage(5, family: "egyptian").first)
              return t.name
          }

          func testStageUpMigratesTemplate() throws {
              let dir = makeTempDir()
              let engine = makeEngine(at: dir)
              // base = 60 дней назад — гарантирует ageDays ≥ 60 независимо от Calendar
              // edge cases (TZ, DST). По StageRules: byAge при 60d ≥ 4-5.
              // count=10 → byCount ≥ 2. Итог: stage = min(byCount, byAge) ≥ 2.
              let base = Date().addingTimeInterval(-86_400 * 60)
              ingestN(engine, project: "proj-A", count: 10, baseDate: base)
              let project = engine.state.projects["proj-A"]
              XCTAssertNotNil(project)
              XCTAssertGreaterThanOrEqual(project!.stage, 2, "Expected stage progression")
              // templateName должен измениться от stage1.
              let initialName = try stage1Name()
              XCTAssertNotEqual(project!.templateName, initialName,
                  "Template should have migrated from \(initialName)")
          }

          func testMigrationPreservesUnitPositions() throws {
              let dir = makeTempDir()
              let engine = makeEngine(at: dir)
              let base = Date().addingTimeInterval(-86_400 * 60)
              // Несколько задач до stage 1 (юниты в slot'ах stage1).
              ingestN(engine, project: "proj-B", count: 4, baseDate: base)
              let snapshotBeforeMigration = engine.state.units.values
                  .filter { $0.projectId == "proj-B" }
                  .map { ($0.id, $0.position) }
              // Ещё задач до stage 2.
              ingestN(engine, project: "proj-B", count: 6, baseDate: base.addingTimeInterval(86_400 * 5))
              let projectAfter = try XCTUnwrap(engine.state.projects["proj-B"])
              XCTAssertGreaterThanOrEqual(projectAfter.stage, 2)
              // Все existing units на тех же позициях.
              for (id, oldPos) in snapshotBeforeMigration {
                  let unit = try XCTUnwrap(engine.state.units[id.uuidString],
                      "Unit \(id) disappeared after migration")
                  XCTAssertEqual(unit.position, oldPos,
                      "Unit \(id) moved from \(oldPos) to \(unit.position)")
              }
          }

          func testMigrationSkippedWhenIncompatible() throws {
              // Engine-level test для AC «миграция skipped при несовместимости».
              // Сетап: создаём project на stage 1, вручную инжектим unit на
              // позицию вне ВСЕХ slot'ов любого template (например, далеко
              // за template bbox). При следующем stage-up applyTemplateMigration
              // вызовет Validator.canMigrate → false → templateName НЕ меняется
              // + warning в errors.log.
              let dir = makeTempDir()
              let engine = makeEngine(at: dir)
              let base = Date().addingTimeInterval(-86_400 * 60)
              // Один task → создаётся project + stage1 template + первый road unit.
              engine.ingestTaskCompletion(project: "proj-X", title: "init",
                  taskId: nil, source: nil, ts: base)
              guard var project = engine.state.projects["proj-X"] else {
                  XCTFail("Project not created"); return
              }
              let stage1Tmpl = try stage1Name()
              XCTAssertEqual(project.templateName, stage1Tmpl)
              // Инжектим "сломанный" unit вне любых slot'ов (далеко за bbox)
              // через internal test seam (см. шаг 6a в плане).
              let brokenUnit = UnitState(
                  id: UUID(), projectId: "proj-X", kind: .shack,
                  position: GridPoint(x: project.districtOrigin.x + 100,
                                       y: project.districtOrigin.y + 100),
                  tier: 0, decayLevel: 0,
                  taskTitle: nil, taskTs: Date(), taskSource: nil
              )
              engine._testInjectUnit(brokenUnit, into: "proj-X")
              // Ещё задач → stage up попытка.
              ingestN(engine, project: "proj-X", count: 9, baseDate: base)
              let projectAfter = try XCTUnwrap(engine.state.projects["proj-X"])
              XCTAssertGreaterThanOrEqual(projectAfter.stage, 2)
              // templateName ОСТАЁТСЯ stage1 — миграция отказана.
              XCTAssertEqual(projectAfter.templateName, stage1Tmpl,
                  "Migration must be skipped when units incompatible")
          }

          func testMigrationIsReplayable() throws {
              let dir = makeTempDir()
              let e1 = makeEngine(at: dir)
              let base = Date().addingTimeInterval(-86_400 * 60)
              ingestN(e1, project: "proj-R", count: 10, baseDate: base)
              let templateNameLive = e1.state.projects["proj-R"]?.templateName
              let stageLive = e1.state.projects["proj-R"]?.stage
              // Второй engine на том же dir → должен auto-replay (как в TASK-048c).
              let e2 = makeEngine(at: dir)
              let templateNameReplay = e2.state.projects["proj-R"]?.templateName
              let stageReplay = e2.state.projects["proj-R"]?.stage
              XCTAssertNotNil(templateNameLive)
              XCTAssertEqual(templateNameLive, templateNameReplay,
                  "Template after replay must match live")
              XCTAssertEqual(stageLive, stageReplay)
          }
      }
      ```
    - **Исполнителю:** seam `_testInjectUnit(_:into:)` уже добавлен в шаге 6a — никакого write через `engine.state` напрямую (т.к. `private(set)` блокирует). Если StageRules formula требует другого числа задач для stage 2 — подкорректируй `count` в ingestN. **Сначала прочитай StageRules.swift**, потом подбери. Не наугад.

### Edge cases (явно обработать)

- [ ] `project.templateName == nil` (legacy) → `applyTemplateMigration` возвращает nil сразу (guard в шаге 4 кода). Миграция не запускается, никаких side-effects. **Покрыто guard'ом `guard let currentName = project.templateName else { return nil }`.**
- [ ] `nextTemplate == nil` (stage 5 → нет stage 6) → silent skip, no warning. **Покрыто `guard let nextTemplate = ...` без ErrorsLog.**
- [ ] Quick double stage-up (taskCount/age дают переход 1→3 за один тик) → миграция применяется **пошагово** через `for s in (oldStage+1)...newStage` (по PM AC). Один `.templateMigrated` event на каждый промежуточный stage. Replay воспроизводит ту же цепочку.
- [ ] **Семья проекта при миграции:** в `applyTemplateMigration` после успешного pick'а присваивается `project.templateFamily = nextTemplate.family`. Обычно family та же (Picker зовётся с `family: project.templateFamily`), но при resolve "mixed" Picker может вернуть шаблон другой family. Сейчас это безопасно (для MVP — только egyptian), но семантически означает «семья проекта может смениться при миграции». В followup можно зафиксировать family строго и пропустить миграцию если family меняется.
- [ ] Юнит на позиции с другой role в nextTemplate (например, residential было, а в nextTemplate тут warehouse) → `TemplateMigrationValidator.canMigrate` вернёт false → migration skipped + ErrorsLog warning. **Покрыто шагом 4.**
- [ ] `decayLevel == 4` (руины) → migration skipped (guard в шаге 4: `guard project.decayLevel < 4 else { return nil }`).
- [ ] Replay: `applyTaskCompleted(silent: true)` rerunит миграцию (state-изменение), event `.templateMigrated` не записывается (внутри `if !silent`), `onTemplateMigrated` callback не вызывается. После replay state идентичен live. **Покрыто `silent`-гейтингом в шаге 6.**
- [ ] Старый events.jsonl без `.templateMigrated` (legacy log) → projects без templateName грузятся как раньше; новый событие enum-case в `Kind` обратносовместим (старые logs не содержат — не падают; новые logs со старым decoder упадут, но мы не downgrade'им version).
- [ ] `nextTemplate.name == currentName` (если Picker вернул тот же шаблон, например family flat) → skip без emit'а event'а (избегаем no-op JSONL entries). **Покрыто `if nextTemplate.name == currentName { return nil }` в шаге 4.**
- [ ] templateFamily nil (broken state из старой версии) → guard в шаге 4: `guard let currentFamily = project.templateFamily else { return nil }`. Скорее не случится, т.к. TASK-048c всегда устанавливает family вместе с name.

### Файлы для изменения

- `Sources/CityDeveloper/Data/GameEvent.swift` — +1 case + helper (~10 строк).
- `Sources/CityDeveloper/Game/CityEngine.swift` — +1 line в switch, +callback declaration, +step-wise migration loop в applyTaskCompleted, +emit loop в if !silent, +private method `applyTemplateMigration` (~50 строк), +internal `_testInjectUnit` seam (~6 строк).
- `Sources/CityDeveloper/App/AppDelegate.swift` — +3 строки (callback wiring).
- `Sources/CityDeveloper/Game/GameScene.swift` — +5 строк (no-op `handleTemplateMigrated`).
- `Sources/CityDeveloper/Game/Templates/TemplateMigrationValidator.swift` — НОВЫЙ файл (~30 строк).
- `Tests/CityDeveloperTests/TemplateMigrationValidatorTests.swift` — НОВЫЙ, 4 теста (~80 строк).
- `Tests/CityDeveloperTests/CityEngineTemplateMigrationTests.swift` — НОВЫЙ, 4 теста (~120 строк).

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/StageRules.swift` — формула стабильна, миграция её не меняет.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` — структура неизменна.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift` — `byStage`/`byName` уже есть.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift` — переиспользуется как есть.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — slot-placement не меняется (TASK-048c).
- `Sources/CityDeveloper/Data/CityState.swift` — `ProjectState` уже имеет templateName/Family (TASK-048a).
- 5 egyptian JSON в `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/` — инвариант preservation уже выполнен (тест зелёный).
- `Sources/CityDeveloper/Data/EventLog.swift` — JSONL формат стабилен.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — используется как есть.
- `Tests/CityDeveloperTests/DistrictTemplateCatalogTests.swift` — `testStageProgressionPreservesSlots` уже проверяет инвариант.
- `concept/LogFormat.md` — обновит `/sync` или вручную при docs-update в `/run`.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Все тесты: `swift test`
- Целевые тесты:
  - `swift test --filter TemplateMigrationValidatorTests` (4/4 PASS)
  - `swift test --filter CityEngineTemplateMigrationTests` (4/4 PASS)
- Регресс:
  - `swift test --filter UnitPlannerTests` (9/9 PASS)
  - `swift test --filter CityEngineTests` (existing PASS)
  - `swift test --filter CityEngineTemplateAssignmentTests` (4/4 PASS — не сломан)
  - `swift test --filter DistrictTemplateCatalogTests` (PASS — `testStageProgressionPreservesSlots` гарантирует инвариант миграции)
- Full suite: 109+ PASS, 1 known-fail (BUG-020).

### Сложность

`middle`

**Обоснование:** Несколько файлов (7), новый event type + миграционная логика + валидатор + интеграционные тесты. Без архитектурной развилки (паттерн `.stageUp: break` уже есть для копирования). Логика валидатора простая (lookup + role compare). Тесты middle-сложности — требуют понимания StageRules для подбора `count`.

### Ожидаемое время

M (≤1д)

---

## ✅ Исполнение

_Исполнитель: sonnet_
_Сложность: —_ (определит лид)
_Объём: M_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: создать проект, закрыть 10 задач (stage 1 → 2 через
      StageRules) — визуально на карте квартал «раскрылся», старые
      юниты на своих местах, новые слоты доступны для следующих задач.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны (включая UnitPlannerTests, DistrictTemplateCatalogTests,
      DistrictTemplatePickerTests)
- [ ] Replay 500 events детерминирован (templateMigrated порядок и
      результат)
- [ ] events.jsonl v1 backwards-compat (старые logs без templateMigrated
      грузятся, миграция пропускается)

#### Обновление документации
- [ ] `Current.md`: F-25 → ⚠️ (часть 3/5)
- [ ] `Diff.md`: D-25 не закрывать
- [ ] `concept/LogFormat.md`: добавить описание `templateMigrated`
      event'а

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047 ✅, TASK-048a ✅, TASK-048b ✅, TASK-048c ✅
- Готова к работе: 2026-05-24
- Lead-model: opus
- Plan-review: revised (3 круга: round1 needs-revision на step-wise migration + AC4 visual + engine-level incompat test → round2 needs-revision на private(set) блокер для test seam → round3 approved)
- Исполнитель: sonnet
- Verify: pass (4/4 + 4/4 новых, 9/9 регресс TASK-038, 4/4 регресс CityEngineTests, 4/4 регресс TASK-048c, 7/7 регресс DistrictTemplateCatalogTests, full suite 117/118 с 1 known-fail BUG-020)
- Code-review: approved (opus, 3 non-blocking notes: log forging теор., templateUnits filter архитектурное уточнение, tag `[template-migration]` отдельная подсистема)
- Завершена: 2026-05-24
- Коммит: —
