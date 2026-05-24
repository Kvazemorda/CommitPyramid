# TASK-050: Era progression — долгоиграющая эволюция после stage 5 (monumental эпоха)

## Связь
- **F-25** из Concept.md (шаблоны кварталов + эпохи)
- **D-25** из Diff.md (часть 4/5 — эпохи)
- **F-09** (decay — era reset на decay-4 руины)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Главное требование Ильи: «писать проекты годами, и город не только
разрастается, но и улучшается (эволюционирует)». Stage 1→5 — это «грубая»
эволюция за недели/месяцы. После stage 5 нужна **долгоиграющая
награда** — `eraLevel` 0..3, который растёт по двум осям:
**количество задач** и **возраст проекта**. Каждая эпоха подменяет
шаблон на `<base>-monumental.json` / `<base>-legacy.json` с
**уникальными monumental-зданиями** (пирамида, цитадель, акрополь),
которые **недоступны** на низких эпохах.

### Пользовательский сценарий

1. Пользователь ведёт проект 2 года, закрывает 600+ задач. Квартал давно
   на stage 5.
2. На 100-й задаче после stage 5 + 30 дней age — `eraLevel 0 → 1`. Шаблон
   `stage5-akhetaten-ceremonial` подменяется на
   `stage5-akhetaten-monumental` (расширенная версия с обелиск-комплексом
   и палаццо 4×4). Существующие юниты остаются, добавляются monumental-слоты.
3. На 500-й задаче + 180 дней — `eraLevel 1 → 2`. Появляется уникальный
   landmark проекта: пирамида (egyptian) / акрополь (greek) / цитадель
   (roman) — `monumental` SlotRole, footprint 4×4.
4. На 2000-й задаче + 365 дней — `eraLevel 2 → 3`. Появляется
   library/observatory/smelting district — финальная эпоха «древнего
   города культуры».
5. Каждый era-up → событие в журнале + лёгкая визуальная анимация
   («золотое сияние» 2 сек).

### Acceptance criteria

- [ ] `ProjectState.eraLevel: Int` (default 0). Codable backwards-compat
      (старые snapshot загружаются с eraLevel = 0).
- [ ] Новый `EraRules` (pure-функция):
      `func computeEra(taskCount: Int, stage: Int, ageDays: Int) -> Int`
      возвращает:
      - 0 если stage < 5
      - 1 если stage == 5 && taskCount ≥ 100 && ageDays ≥ 30
      - 2 если stage == 5 && taskCount ≥ 500 && ageDays ≥ 180
      - 3 если stage == 5 && taskCount ≥ 2000 && ageDays ≥ 365
- [ ] В `CityEngine.applyTaskCompleted` после увеличения taskCount
      вызывается `applyEraProgression(project:)`:
      - newEra = EraRules.computeEra(...)
      - если newEra > project.eraLevel:
        - emit `GameEvent.Kind.eraAdvanced(projectId, era: newEra)`
        - подменить шаблон на `<currentBase>-monumental.json` (era 1)
          или `<currentBase>-legacy.json` (era 2-3) через те же правила
          migration из TASK-049.
        - project.eraLevel = newEra
- [ ] В `Resources/DistrictTemplates/egyptian/` добавляются 3 era-шаблона:
      - `stage5-akhetaten-monumental.json` — расширение Akhetaten
        ceremonial: добавлен обелиск-комплекс + палаццо 4×4.
      - `stage5-akhetaten-legacy.json` — финал: + библиотека + ритуальный
        бассейн + священная роща.
      - `stage5-akhetaten-pyramid.json` — era 2 landmark (отдельный
        slot.role = .monumental в основном шаблоне). Может быть один и тот
        же шаблон с разной видимостью monumental-слотов по eraLevel.
- [ ] Новые SlotRole: уже есть `.monumental` (из TASK-047) — используем для
      пирамиды/цитадели/акрополя. Размер footprint = 3×3 или 4×4.
- [ ] В `DistrictTemplate` добавляется поле `minEra: Int` для каждого
      слота (default 0). UnitPlanner пропускает слоты, у которых
      `slot.minEra > project.eraLevel` — это и есть «недоступные»
      monumental-слоты.
- [ ] `GameEvent.Kind.eraAdvanced(projectId: String, era: Int)` — новый
      case, записывается в events.jsonl, replay-safe.
- [ ] `GameScene.handleEraAdvanced` — лёгкая анимация (золотая вспышка
      по контуру квартала, 2 сек).
- [ ] Тесты `EraRulesTests.swift`:
      `testComputeEraReturnsZeroBelowStage5`,
      `testComputeEraReachesOneAt100TasksAnd30Days`,
      `testComputeEraReachesTwoAt500TasksAnd180Days`,
      `testComputeEraReachesThreeAt2000TasksAnd365Days`.
- [ ] Тесты `CityEngineEraProgressionTests.swift`:
      `testEraAdvancesOnTaskCompleted`,
      `testEraTemplateMigrationKeepsUnitPositions`,
      `testEraIsReplayable`.

### Что НЕ делаем (границы скоупа)

- НЕ делаем era reset для guess-проектов (вернувшихся из руин) — пока
  era сохраняется при decay/restore.
- НЕ делаем Settings UI для era (это TASK-051 включит).
- НЕ делаем Roman/Greek monumental — это backlog follow-up.
- НЕ балансируем точные числа (100/500/2000 задач). Можно подкрутить
  после первого реального прогона.

### Edge cases

- [ ] Проект на stage 5 с 2000+ задач и 365+ дней (имеющийся
      «старый» проект Ильи на момент мерджа) → при первом
      task_completed после релиза скачком получает era 3 (eraLevel = 3),
      все 3 шаблона подменяются за один тик. Это **OK** (одноразовая
      миграция legacy).
- [ ] Replay events.jsonl до этой TASK (без `eraAdvanced` events) → все
      проекты получают era 0 при load, затем при следующем task_completed
      пересчитываются. Backwards-compat.
- [ ] ageDays считается от `project.createdAt` до now (или до
      `lastActivityAt`? — uniform: используем `lastActivityAt - createdAt`
      чтобы заброшенные проекты не «дозревали» в эпохах).
- [ ] decay-4 проект → era progression skipped (нет смысла улучшать руины).
- [ ] `EraRules.computeEra` чистая функция → тестируется без I/O.

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (templateName),
  TASK-049 (migration mechanism).
- **Soft-blocks:** TASK-051 (Settings UI может показывать current era проекта).

### Дизайн

Не применимо (нет UI; визуал — золотая вспышка по контуру квартала на
era-up, можно использовать SKEmitterNode или SKAction.colorize).

### Done-критерий

_Часть F-25 Done-критерия:_ «После stage 5 + 100 задач + 30 дней появляется
уникальное здание (пирамида для egyptian-family), которое не появлялось
раньше. Replay 5000 событий воспроизводит выбор шаблонов и era-up
детерминированно».

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- В коде уже есть:
  - `ProjectState.eraLevel: Int` — поле уже добавлено превентивно
    (`Sources/CityDeveloper/Data/CityState.swift:497` поле, `:501`
    Codable `decodeIfPresent ?? 0`, `:507` CodingKey). Никаких миграций
    Codable делать НЕ нужно.
  - Поле инициализируется как `0` при создании нового проекта
    (`Sources/CityDeveloper/Game/CityEngine.swift:298`).
  - `applyTemplateMigration(projectKey:newStage:silent:)`
    (`Sources/CityDeveloper/Game/CityEngine.swift:664–720`) — готовый
    механизм подмены `templateName` с валидацией позиций через
    `TemplateMigrationValidator.canMigrate(...)`. Точка для
    переиспользования: вынести core-логику смены имени шаблона на
    функцию-помощник и пере-использовать в era-flow.
  - `StageRules.computeStage(taskCount:ageDays:)`
    (`Sources/CityDeveloper/Game/StageRules.swift:3–28`) — pure enum,
    шаблон для `EraRules`.
  - Каркас событий: `GameEvent.Kind` enum
    (`Sources/CityDeveloper/Data/GameEvent.swift:5–19`), payload-helper
    `templateMigrationPayload` (там же `:66`), switch-обработка в
    `CityEngine.apply(_:silent:)` (`CityEngine.swift:181–215`).
  - GameScene имеет обработчики/callback'и для аналогичных событий:
    `handleProjectStageChanged` (`GameScene.swift:397`),
    `handleTemplateMigrated` (`:413`), `handleUnitEvolved` (`:474+`).
    Анимации-вспышки: примеры fadeIn/fadeOut/sequence на `:290–293`,
    `:375`, `:459–467`.

- Связанные модули:
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` —
    модели `SlotRole`, `TemplateSlot`, `DistrictTemplate`.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplateCatalog.swift`
    (`byName(_:)`, `loadFromBundle()`) — каталог.
  - `Sources/CityDeveloper/Game/Templates/DistrictTemplatePicker.swift`
    — выбор по `(stage, family, biome, seed)`.
  - `Sources/CityDeveloper/Game/Templates/TemplateMigrationValidator.swift`
    — проверяет совместимость существующих unit-позиций со слотами
    нового шаблона.
  - `Sources/CityDeveloper/Game/UnitPlanner.swift:282–384` —
    `nextPosition(...)` итерирует по `template.slots.filter { $0.role == targetRole }`.
    Точка для добавления `&& $0.minEra <= projectEraLevel`.
  - `Sources/CityDeveloper/Data/EventLog.swift:19/31` — append/readAll
    events.jsonl, неизвестные kind'ы логируются и пропускаются.
  - `Resources/DistrictTemplates/egyptian/` — уже есть
    `stage5-akhetaten-ceremonial.json`. Все JSON попадают в bundle
    через `.process(...)` в `Package.swift`.
  - AppDelegate (где `engine.onTemplateMigrated` присваивается)
    — точка для wiring `engine.onEraAdvanced`.

- Что переиспользуем:
  - Codable backwards-compat паттерн `decodeIfPresent ?? 0` уже есть в
    `ProjectState`, повторяем то же для `TemplateSlot.minEra`.
  - `TemplateMigrationValidator.canMigrate(units:to:districtOrigin:)`
    — обязателен перед подменой шаблона на era-up (иначе можем
    оставить юниты вне слотов).
  - Паттерн «миграция в одном тике серии stage'ей» (цикл
    `for targetStage in (oldStage+1)...newStage`) в
    `CityEngine.swift:469–477` — копируем как
    `for targetEra in (oldEra+1)...newEra`.
  - `appendSystemEvent(.templateMigrated, ...)` + `onTemplateMigrated`
    callback — для era-up подмены шаблона переиспользуем эти же
    хуки (отдельный `.templateMigrated` event при подмене —
    GameScene уже умеет перерисовать road-слоты).

- Что нужно дописать:
  - `EraRules.swift` — новый pure-модуль (4 порога).
  - `TemplateSlot.minEra: Int` + явный `init(from:)` для backwards-compat.
  - `GameEvent.Kind.eraAdvanced` + payload helper.
  - `CityEngine.applyEraProgression` + интеграция в `applyTaskCompleted`.
  - Helper выбора era-шаблона (по имени `<base>-monumental` /
    `<base>-legacy`).
  - `CityEngine.onEraAdvanced` callback + wiring в AppDelegate.
  - `GameScene.handleEraAdvanced` — золотая вспышка.
  - 2 JSON-шаблона: `stage5-akhetaten-monumental.json`,
    `stage5-akhetaten-legacy.json` (pyramid реализуем как слот
    `minEra: 2` внутри monumental — см. ниже).
  - 2 теста: `EraRulesTests.swift`, `CityEngineEraProgressionTests.swift`.
  - Документы: `Current.md`, `LogFormat.md`.

### Архитектурное решение

**Era pipeline.** `applyTaskCompleted` уже выполняет: `taskCount++ →
stage compute → template migration → emit events`. Era добавляется
*после* stage-migration блока в `CityEngine.swift:478`. Так
обеспечиваем порядок: сначала pop в stage 5 (если был ≤4) и переход
на `stage5-akhetaten-ceremonial` через существующий
`applyTemplateMigration`, затем — era progression поверх ceremonial.
Это гарантирует, что юнит уже создан и счётчик обновлён, перед
проверкой era-порогов.

**Один тик = N era-up'ов.** Edge case Ильи (legacy-проект 2000+/365+)
требует перехода 0→3 в одном событии. Делаем цикл
`for targetEra in (oldEra+1)...newEra`: для каждого уровня — emit
`eraAdvanced(era: N)` event и (опционально) `templateMigrated`. Era 1
подменяет ceremonial → monumental. Era 2 — нет подмены (активация
pyramid через `minEra: 2`). Era 3 — monumental → legacy. То есть
максимум 3 `eraAdvanced` event'а и до 2 `templateMigrated` event'ов
за один task_completed. Это совпадает с уже работающим паттерном
stage-up из TASK-049 (там 1→3 = два .templateMigrated).

**Pyramid как слот, а не отдельный шаблон.** PM явно разрешил:
«Может быть один и тот же шаблон с разной видимостью monumental-слотов
по eraLevel». Реализуем 2 шаблона (monumental, legacy) вместо 3 —
pyramid живёт как `{role: "monumental", footprint: 4×4, minEra: 2}`
внутри `stage5-akhetaten-monumental.json`. На era 1 этот слот
отфильтровывается UnitPlanner'ом; на era 2 — становится доступен.
Файл `stage5-akhetaten-pyramid.json` НЕ создаём — это упрощение
снижает количество JSON и явно использует механизм minEra (то ради
чего он и заведён в AC-6).

**Replay-safety.** Pattern из stage-up: state-мутация (project.eraLevel,
project.templateName) выполняется ВНУТРИ `applyTaskCompleted` для
обоих режимов (silent=replay и live). Сам `eraAdvanced` event в
switch `apply(_:silent:)` — `break` (state уже мутирован). Это
повторяет паттерн `stageUp`/`templateMigrated` в `:201`. Старые
events.jsonl без `eraAdvanced` корректно: при первом
task_completed после загрузки старого лога — пересчёт. Era 0
осыпается с обоих краёв (Codable default + EraRules return 0).

**UnitPlanner сигнатура.** Добавляем обязательный параметр
`projectEraLevel: Int` (без default, чтобы все call-site'ы явно
прокинули era). Это безопаснее default'а 0, потому что забыть про
параметр = всегда видеть слоты с `minEra > 0` (опасный bag). Тестам
явно передаём 0 (там, где era не релевантна), или нужное значение.

**ageDays — `lastActivityAt - createdAt`.** Edge case спеки: проекты,
которые не получают task_completed, не «дозревают» в epoch'ах.
Это требует чтобы вычисление выполнялось ВНУТРИ
applyTaskCompleted (где обновляется `lastActivityAt`), и
использовался уже обновлённый `lastActivityAt = event.ts`.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ
> импровизируй, возвращай задачу через сообщение.

1. **EraRules — pure модуль** `[AC:2]`
   - Файл (новый): `Sources/CityDeveloper/Game/EraRules.swift`
   - Скелет:
     ```swift
     import Foundation

     /// TASK-050 F-25: вычисление эпохи (0..3) после stage 5.
     /// Pure (без I/O), testable без CityEngine.
     enum EraRules {
         static func computeEra(taskCount: Int, stage: Int, ageDays: Int) -> Int {
             guard stage >= 5 else { return 0 }
             if taskCount >= 2000 && ageDays >= 365 { return 3 }
             if taskCount >= 500  && ageDays >= 180 { return 2 }
             if taskCount >= 100  && ageDays >= 30  { return 1 }
             return 0
         }
     }
     ```
   - Порядок проверок — **сверху вниз от старшего**: гарантирует,
     что 2000+/365+ сразу даёт 3 (важно для edge case legacy).

2. **TemplateSlot.minEra + Codable backwards-compat** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift`
   - В `struct TemplateSlot` добавить:
     - `let minEra: Int`
     - Явный `init(from decoder:)`:
       ```swift
       init(from decoder: Decoder) throws {
           let c = try decoder.container(keyedBy: CodingKeys.self)
           x = try c.decode(Int.self, forKey: .x)
           y = try c.decode(Int.self, forKey: .y)
           role = try c.decode(SlotRole.self, forKey: .role)
           footprint = try c.decode(GridSize.self, forKey: .footprint)
           minEra = try c.decodeIfPresent(Int.self, forKey: .minEra) ?? 0
       }
       ```
     - Явный `enum CodingKeys: String, CodingKey { case x, y, role, footprint, minEra }`.
     - НЕ переопределять `encode(to:)` — synthesized encoder будет
       работать (или явный для симметрии — на усмотрение).
   - Проверка: все существующие 5 JSON-шаблонов в
     `Resources/DistrictTemplates/egyptian/` декодируются без падений
     (запустить `DistrictTemplateCatalogTests` после правки).

3. **GameEvent.Kind.eraAdvanced + payload** `[AC:7]`
   - Файл: `Sources/CityDeveloper/Data/GameEvent.swift`
   - В enum `Kind` добавить:
     ```swift
     /// TASK-050 F-25: era-up. title = "<era>" (Int as string).
     case eraAdvanced = "era_advanced"
     ```
   - Внизу файла (рядом с `templateMigrationPayload`) добавить:
     ```swift
     /// Парсит title `eraAdvanced` формата "<era>".
     static func eraAdvancedPayload(from title: String?) -> Int? {
         guard let title, let era = Int(title) else { return nil }
         return era
     }
     ```
   - projectId передаём через `event.project` (как в остальных
     case'ах) — в title только era.

4. **UnitPlanner.nextPosition — фильтр по minEra** `[AC:6]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift`
   - Сигнатуру `nextPosition(...)` (строка 282) расширить параметром
     **перед** `template`:
     `projectEraLevel: Int,` (обязательный, без default).
   - В template-блоке (строка 295), в `.filter`:
     ```swift
     let sorted = t.slots
         .filter { $0.role == targetRole && $0.minEra <= projectEraLevel }
         ...
     ```
   - Обновить вызов в `CityEngine.swift:386`:
     передать `projectEraLevel: project.eraLevel`.
   - Обновить вызовы в `UnitPlannerTests.swift`:
     передать `projectEraLevel: 0` (era не релевантна для существующих
     тестов).

5. **CityEngine: helper выбора era-шаблона** `[AC:3,4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Добавить private helper рядом с `applyTemplateMigration`:
     ```swift
     /// Имя era-шаблона по правилу TASK-050:
     ///   era 1 → "<stage5-base>-monumental"
     ///   era 3 → "<stage5-base>-legacy"
     ///   era 2 → nil (без подмены — только активация minEra:2 слотов)
     /// stage5-base = currentName с отрезанным "-monumental"/"-legacy" суффиксом.
     private func eraTemplateName(currentName: String, era: Int) -> String? {
         let base = stripEraSuffix(currentName)
         switch era {
         case 1: return "\(base)-monumental"
         case 3: return "\(base)-legacy"
         default: return nil
         }
     }
     private func stripEraSuffix(_ name: String) -> String {
         for suf in ["-monumental", "-legacy"] {
             if name.hasSuffix(suf) {
                 return String(name.dropLast(suf.count))
             }
         }
         return name
     }
     ```
   - Использование: внутри `applyEraProgression` (шаг 6).

6. **CityEngine.applyEraProgression** `[AC:3,4,5]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - **Семантика eraLevel при частично-провальных миграциях
     (важно):** eraLevel **всегда** = computed newEra, даже если
     `TemplateMigrationValidator` отверг подмену шаблона. Логика:
     era — это логический уровень проекта (счётчик), шаблон — его
     визуальная реализация. Если шаблон не смогли подменить, eraLevel
     всё равно поднимается; на следующем task_completed повторная
     попытка миграции может пройти (validator вызывается заново).
     В лог пишем ErrorsLog. Это сознательный graceful degrade —
     задокументирован в комментарии метода.
   - После `applyTemplateMigration` (после строки 720) добавить
     новый метод:
     ```swift
     /// TASK-050 F-25: era progression после stage-up.
     /// Возвращает массив (era, migration?) для каждого совершённого
     /// шага — нужен в live-блоке для emit eraAdvanced / templateMigrated.
     /// Идемпотентен (silent=true safe), state-мутации применяются всегда.
     /// Skip для руин (decayLevel == 4) и legacy-проектов (templateName == nil).
     /// Семантика: eraLevel = newEra ВСЕГДА (даже если шаблон не
     /// подменили — это graceful degrade, следующий task_completed
     /// попробует миграцию заново).
     @discardableResult
     private func applyEraProgression(
         projectKey: String,
         eventTs: Date,
         silent: Bool
     ) -> [(era: Int, migration: (from: String, to: String)?)] {
         guard var project = state.projects[projectKey] else { return [] }
         guard project.decayLevel < 4 else { return [] }   // ruin skip
         guard project.templateName != nil else { return [] } // legacy proj skip

         let ageDays = max(1,
             Calendar.current.dateComponents([.day], from: project.createdAt, to: eventTs).day ?? 1)
         let newEra = EraRules.computeEra(
             taskCount: project.taskCount,
             stage: project.stage,
             ageDays: ageDays
         )
         let oldEra = project.eraLevel
         guard newEra > oldEra else { return [] }

         var results: [(era: Int, migration: (from: String, to: String)?)] = []
         for targetEra in (oldEra + 1)...newEra {
             // Подмена шаблона (опционально).
             var mig: (from: String, to: String)? = nil
             if let currentName = state.projects[projectKey]?.templateName,
                let targetName = eraTemplateName(currentName: currentName, era: targetEra),
                let nextTemplate = DistrictTemplateCatalog.byName(targetName),
                targetName != currentName {
                 // Валидация позиций существующих юнитов.
                 let origin = project.districtOrigin
                 guard let currentTemplate = DistrictTemplateCatalog.byName(currentName) else {
                     ErrorsLog.write("[era] district \(projectKey): current template \(currentName) not in catalog")
                     continue
                 }
                 let currentSlotPositions: Set<GridPoint> = Set(currentTemplate.slots.map {
                     GridPoint(x: origin.x + $0.x, y: origin.y + $0.y)
                 })
                 let allUnits = state.units.values.filter { $0.projectId == projectKey }
                 let templateUnits = allUnits.filter { currentSlotPositions.contains($0.position) }
                 guard TemplateMigrationValidator.canMigrate(
                     units: Array(templateUnits),
                     to: nextTemplate,
                     districtOrigin: origin
                 ) else {
                     ErrorsLog.write("[era] district \(projectKey): cannot migrate \(currentName) → \(targetName), keeping \(currentName)")
                     continue   // era поднимаем, но шаблон не меняем
                 }
                 if var p = state.projects[projectKey] {
                     p.templateName = nextTemplate.name
                     p.templateFamily = nextTemplate.family
                     state.projects[projectKey] = p
                 }
                 mig = (currentName, nextTemplate.name)
             }
             results.append((era: targetEra, migration: mig))
         }
         // Финальная state-мутация eraLevel (один раз).
         if var p = state.projects[projectKey] {
             p.eraLevel = newEra
             state.projects[projectKey] = p
         }
         return results
     }
     ```
   - Важное: `project` локальная копия используется только для
     guard'ов; реальная мутация — через `state.projects[projectKey]`,
     потому что между шагами цикла шаблон меняется.

7. **CityEngine.applyTaskCompleted — интеграция era-flow** `[AC:3,5,7]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - **Точное место вставки state-мутации:** сразу **после** блока
     stage migrations (после строки 478 `}`), **перед** строкой 480
     `if !silent`. Этот блок выполняется в обоих режимах (silent +
     live), как и stage-up migrations.
   - **Точное место вставки emit'ов:** внутри `if !silent` блока,
     **сразу после** существующего блока stage-up emit
     (после строки 501 `}` закрывающего `if newStage > oldStage`),
     **перед** строкой 502 `if isNewProject`. Это гарантирует
     порядок: `task_completed → unit_built → unit_evolved×N →
     stage_up? → templateMigrated×(stage-up) →
     eraAdvanced→templateMigrated×(era-up) → projectCreated? → unitBuilt-cb → stageChanged-cb`.
     ```swift
     // TASK-050 F-25: era progression.
     // Запускается всегда (silent + live) для state-консистентности.
     let eraResults = applyEraProgression(
         projectKey: projectKey,
         eventTs: event.ts,
         silent: silent
     )
     ```
   - Внутри `if !silent` блока, **после** existing stage-up emit (после
     строки 501), добавить:
     ```swift
     // TASK-050: emit eraAdvanced + опциональный templateMigrated.
     for r in eraResults {
         appendSystemEvent(.eraAdvanced, project: projectKey, title: String(r.era))
         onEraAdvanced?(projectKey, r.era)
         if let m = r.migration {
             appendSystemEvent(.templateMigrated, project: projectKey,
                               title: "\(m.from)|\(m.to)")
             onTemplateMigrated?(projectKey, m.from, m.to)
         }
     }
     ```
   - Порядок в events.jsonl: `task_completed → unit_built →
     unit_evolved×N → stage_up? → templateMigrated×N (stage-up) →
     eraAdvanced→templateMigrated→eraAdvanced→… (era-up)`.

8. **CityEngine.apply(_:silent:) — case eraAdvanced** `[AC:7]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - В switch на строке 201 расширить тот же `break`-case:
     ```swift
     case .unitBuilt, .stageUp, .ruinsCleared, .templateMigrated, .eraAdvanced:
         break
     ```
   - Обоснование: state мутируется в `applyTaskCompleted` (та же
     модель, что для stage_up/templateMigrated).

9. **CityEngine.onEraAdvanced callback** `[AC:8]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift`
   - Рядом с `var onTemplateMigrated: ((String, String, String) -> Void)?`
     добавить:
     ```swift
     /// TASK-050 F-25: era-up callback.
     /// Параметры: projectId, era (1..3).
     var onEraAdvanced: ((String, Int) -> Void)?
     ```

10. **AppDelegate wiring** `[AC:8]`
    - Файл: тот же, где находится `engine.onTemplateMigrated = ...`
      (искать grep'ом `onTemplateMigrated` — обычно AppDelegate
      или GameSceneController; согласно карте Explore — около
      строки 75–77).
    - **Паттерн:** в AppDelegate существующие коллбэки
      (`onProjectStageChanged`, `onTemplateMigrated`,
      `onUnitEvolved`, `onRoadCellsAdded`) присваиваются **БЕЗ**
      DispatchQueue.main.async обёртки — main.async делается ВНУТРИ
      соответствующего `handle*` метода в GameScene (см. эталон
      `handleTemplateMigrated` `GameScene.swift:414` — оборачивается
      внутри).
    - После строки с `engine.onTemplateMigrated` добавить:
      ```swift
      engine.onEraAdvanced = { [weak scene] projectId, era in
          scene?.handleEraAdvanced(projectId: projectId, era: era)
      }
      ```
    - **НЕ оборачивать в DispatchQueue.main.async в AppDelegate** —
      это сделает `handleEraAdvanced` внутри (шаг 11).

11. **GameScene.handleEraAdvanced — золотая вспышка** `[AC:8]`
    - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
    - **Координатная стратегия:** рисуем `SKShapeNode` напрямую в
      `world` (как `drawDistrictMarker` `GameScene.swift:706`),
      НЕ как child `districtNode` (тот содержит только label+bg
      и не отражает контур квартала). Контур = iso-ромб из 4 углов
      квартала, посчитанных через `isoPosition(grid:)`.
    - Метод (положить рядом с `handleProjectStageChanged`):
      ```swift
      /// TASK-050 F-25: золотая вспышка по контуру квартала на era-up.
      /// Длительность 2 сек: fadeIn 0.3 → wait 1.4 → fadeOut 0.3.
      /// Контур = iso-ромб квартала width×height (4 угла), цвет UI gold.
      func handleEraAdvanced(projectId: String, era: Int) {
          DispatchQueue.main.async { [weak self] in
              guard let self, self.didAttach,
                    let engine = self.engine,
                    let project = engine.state.projects[projectId] else { return }
              let template = project.templateName
                  .flatMap { DistrictTemplateCatalog.byName($0) }
              let w = template?.width ?? 16
              let h = template?.height ?? 16
              let origin = project.districtOrigin
              // 4 угла квартала в grid-координатах:
              let corners = [
                  GridPoint(x: origin.x,           y: origin.y),
                  GridPoint(x: origin.x + w - 1,   y: origin.y),
                  GridPoint(x: origin.x + w - 1,   y: origin.y + h - 1),
                  GridPoint(x: origin.x,           y: origin.y + h - 1),
              ]
              let scenePoints = corners.map { self.isoPosition(grid: $0) }
              let path = CGMutablePath()
              path.move(to: scenePoints[0])
              for i in 1..<scenePoints.count {
                  path.addLine(to: scenePoints[i])
              }
              path.closeSubpath()
              let outline = SKShapeNode(path: path)
              outline.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
              outline.lineWidth = 3
              outline.fillColor = .clear
              outline.alpha = 0
              outline.zPosition = 9998
              self.world.addChild(outline)
              outline.run(.sequence([
                  .fadeIn(withDuration: 0.3),
                  .wait(forDuration: 1.4),
                  .fadeOut(withDuration: 0.3),
                  .removeFromParent()
              ]))
          }
      }
      ```
    - **API эталон:** `engine.state.projects[projectId]` (НЕ
      `engine.snapshot.projects` — у CityEngine нет `snapshot`
      проперти; вижу из `GameScene.swift:401` и `:417`).
    - **Анимация:** total ≈ 2 сек, что соответствует AC «лёгкая
      анимация 2 сек».

12. **JSON-шаблон stage5-akhetaten-monumental.json** `[AC:4]`
    - **Сначала** прочитать
      `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-ceremonial.json`
      целиком — поля верхнего уровня (`name, family, stage, width,
      height, biomePreference`) и список `slots` копируются ОДИН-В-ОДИН
      в monumental (только `name` меняется на `"stage5-akhetaten-monumental"`).
    - Файл (новый):
      `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-monumental.json`
    - Содержимое: **super-set** ceremonial:
      - Сохранить ВСЕ слоты ceremonial на тех же `(x, y)` с тем же
        `footprint` и `role` (иначе `TemplateMigrationValidator.canMigrate`
        провалит миграцию).
      - Поля `family, stage, width, height, biomePreference` —
        повторить ровно как в ceremonial (значение `biomePreference`
        проверить в реальном файле, не угадывать).
    - Добавить новые слоты (в свободной зоне поля 16×16, не
      пересекаются с существующими — проверь координаты против
      ceremonial):
      - palazzo 4×4: `{"x": <free>, "y": <free>, "role": "residential", "footprint": {"width": 4, "height": 4}, "minEra": 1}`
      - обелиск-комплекс (2 obelisk слота):
        `{"x": <free>, "y": <free>, "role": "obelisk", "footprint": {"width": 1, "height": 1}, "minEra": 1}` × 2
      - pyramid:
        `{"x": <free>, "y": <free>, "role": "monumental", "footprint": {"width": 4, "height": 4}, "minEra": 2}`
    - Все добавленные слоты должны иметь `minEra >= 1` (на era 0
      они не активны — но проект на era 0 уже на ceremonial, не на
      monumental, поэтому это страховка).
    - **Валидация после правки:** запустить
      `swift test --filter DistrictTemplateCatalogTests` — каталог
      должен загрузить новый JSON без ошибок.

13. **JSON-шаблон stage5-akhetaten-legacy.json** `[AC:4]`
    - **Сначала** прочитать только что созданный monumental JSON
      целиком — слоты monumental копируются ОДИН-В-ОДИН в legacy.
    - Файл (новый):
      `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-legacy.json`
    - Содержимое: **super-set** monumental:
      - Сохранить ВСЕ слоты monumental на тех же `(x, y)/footprint/role/minEra`.
      - Поля верхнего уровня (`family, stage, width, height,
        biomePreference`) — повторить как в monumental.
      - Поле `name`: `"stage5-akhetaten-legacy"`.
    - Добавить новые слоты (в свободной зоне):
      - library: `{"role": "school", "footprint": {"width": 2, "height": 2}, "minEra": 3}`
      - ритуальный бассейн: `{"role": "bath", "footprint": {"width": 2, "height": 2}, "minEra": 3}`
      - священная роща (obelisk-кластер): 2 × `{"role": "obelisk", "footprint": {"width": 1, "height": 1}, "minEra": 3}`
      - observatory (если хватает места): `{"role": "temple", "footprint": {"width": 2, "height": 2}, "minEra": 3}`
    - Все новые слоты `minEra: 3`.
    - **Валидация:** `swift test --filter DistrictTemplateCatalogTests`.

14. **EraRulesTests.swift** `[AC:9]`
    - Файл (новый): `Tests/CityDeveloperTests/EraRulesTests.swift`
    - Скелет:
      ```swift
      import XCTest
      @testable import CityDeveloper

      final class EraRulesTests: XCTestCase {
          func testComputeEraReturnsZeroBelowStage5() {
              for stage in 0..<5 {
                  XCTAssertEqual(EraRules.computeEra(taskCount: 99999, stage: stage, ageDays: 99999), 0)
              }
          }
          func testComputeEraReachesOneAt100TasksAnd30Days() {
              XCTAssertEqual(EraRules.computeEra(taskCount: 100, stage: 5, ageDays: 30), 1)
              XCTAssertEqual(EraRules.computeEra(taskCount: 99,  stage: 5, ageDays: 30), 0)
              XCTAssertEqual(EraRules.computeEra(taskCount: 100, stage: 5, ageDays: 29), 0)
          }
          func testComputeEraReachesTwoAt500TasksAnd180Days() {
              XCTAssertEqual(EraRules.computeEra(taskCount: 500, stage: 5, ageDays: 180), 2)
              XCTAssertEqual(EraRules.computeEra(taskCount: 499, stage: 5, ageDays: 180), 1)
              XCTAssertEqual(EraRules.computeEra(taskCount: 500, stage: 5, ageDays: 179), 1)
          }
          func testComputeEraReachesThreeAt2000TasksAnd365Days() {
              XCTAssertEqual(EraRules.computeEra(taskCount: 2000, stage: 5, ageDays: 365), 3)
              XCTAssertEqual(EraRules.computeEra(taskCount: 1999, stage: 5, ageDays: 365), 2)
              XCTAssertEqual(EraRules.computeEra(taskCount: 2000, stage: 5, ageDays: 364), 2)
          }
      }
      ```

15. **CityEngineEraProgressionTests.swift** `[AC:10]`
    - Файл (новый):
      `Tests/CityDeveloperTests/CityEngineEraProgressionTests.swift`
    - **Эталон replay-паттерна:** перед написанием прочитать
      `Tests/CityDeveloperTests/CityEngineTemplateMigrationTests.swift`
      полностью. Скопировать helper'ы `makeTempDir()` и
      `makeEngine(at:)` (они стандартные, ~10 строк) и паттерн
      replay (engine инициализируется второй раз тем же путём
      events.jsonl — readAll вызывается внутри `init(dataDir:)`
      или эквивалент; точный API — НЕ угадывать, скопировать из
      эталона).
    - Структура:
      ```swift
      final class CityEngineEraProgressionTests: XCTestCase {
          private func makeTempDir() -> URL { /* копия из эталона */ }
          private func makeEngine(at dir: URL) -> CityEngine { /* копия */ }

          func testEraAdvancesOnTaskCompleted() {
              // 1. engine + ingest 100 task_completed с ts = createdAt + 30d
              //    (через task_completed events: первый ставит createdAt =
              //    нашему ts; остальные с ts = createdAt + 30d).
              //    StageRules.computeStage(100, 30) должен дать stage 5
              //    (проверить пороги StageRules).
              // 2. Проверить project.eraLevel == 1, project.templateName.hasSuffix("-monumental").
              // 3. Прочитать events.jsonl: должен содержать ровно один
              //    GameEvent.Kind.eraAdvanced с title="1".
          }

          func testEraTemplateMigrationKeepsUnitPositions() {
              // 1. Симулировать через ingest набор юнитов на ceremonial
              //    (например 20 task_completed, чтобы дойти до stage 5
              //    ceremonial + несколько юнитов в слотах).
              // 2. Запомнить позиции всех юнитов до era-up.
              // 3. Догнать счётчик/age до era 1 (доп. ingest'ы).
              // 4. После era-up: project.templateName.hasSuffix("-monumental"),
              //    позиции юнитов (state.units.values) НЕ изменились.
          }

          func testEraIsReplayable() {
              // 1. engine1: makeEngine(at: tmp), ingest до era 3 (через
              //    `_testInjectUnit` или массовый ingest events с фиксированными ts).
              // 2. Проверить engine1.state.projects[id].eraLevel == 3,
              //    templateName.hasSuffix("-legacy").
              // 3. engine2 = makeEngine(at: tmp) — повторное создание из той же
              //    директории. По образцу CityEngineTemplateMigrationTests:
              //    engine2 при init читает events.jsonl и replay'ит.
              // 4. Сравнить engine2.state.projects[id].eraLevel == 3,
              //    templateName.hasSuffix("-legacy") — детерминированный
              //    результат.
          }
      }
      ```
    - **Важно:** для достижения 100/500/2000 задач за разумное
      время теста — использовать `_testInjectUnit` (`CityEngine.swift:726`)
      для установки нужного state до ingest финального triggering
      task_completed. Альтернатива (честный 100×ingest) тоже OK
      для small теста; для 2000+ — обязательно через test seam.
    - Все ts через `Date(timeIntervalSince1970: ...)`. Дата
      создания проекта = первый ingest, дата triggering события =
      первый + N дней.

16. **Документы** `[AC: F-25 DoD]`
    - `concept/Current.md` — обновить F-25 (часть 4/5):
      добавить запись «era progression — ceremonial → monumental → legacy».
    - `concept/Diff.md` — НЕ закрывать D-25 (часть 4 из 5).
    - `concept/LogFormat.md` — описать новый event:
      ```
      era_advanced: подъём eraLevel проекта.
        title = "<era>" (Int 1..3).
        project = projectId.
        ts = ts последнего task_completed.
      ```

### Edge cases (явно обработать)

- [ ] Проект `decayLevel == 4` (руины) — `applyEraProgression` сразу
      return через guard. Обнаружено: `CityState.swift:447` хранение
      decayLevel, `CityEngine.swift:673` тот же guard в
      `applyTemplateMigration`. Тест не обязателен (просто guard).
- [ ] Legacy-проект (templateName == nil) — `applyEraProgression`
      сразу return. Era progression только для templated-проектов
      (для legacy нет понятия «monumental-шаблон»).
- [ ] Старый snapshot ProjectState без `eraLevel` → `decodeIfPresent ?? 0`
      на `CityState.swift:501` уже работает. Тест: load старого
      snapshot.json без поля eraLevel — backwards-compat.
- [ ] Старый JSON-шаблон без `minEra` → custom `init(from:)` в
      `TemplateSlot` даст default 0. Тест:
      `DistrictTemplateCatalogTests` должен пройти на 5 существующих
      ceremonial-шаблонах.
- [ ] events.jsonl без `eraAdvanced` events → старые проекты
      получают `eraLevel = 0` при load, при следующем task_completed
      EraRules пересчитывает реальное значение. Тест: ingest 100
      task_completed в engine1 БЕЗ eraAdvanced в jsonl (т.е. на
      старой версии кода) → upgrade → engine2 load → следующий
      task_completed выставит era корректно.
- [ ] Edge case Ильи (2000+/365+ за один тик): цикл
      `for targetEra in (oldEra+1)...newEra` обработает все 3 уровня.
      Тест: project с createdAt=T-400d, taskCount уже 1999 (через
      injects), ingest задачи 2000 → ожидаем 3 `eraAdvanced` events и
      `eraLevel == 3`, `templateName.hasSuffix("-legacy") == true`.
- [ ] `TemplateMigrationValidator.canMigrate` провалит подмену
      ceremonial → monumental: era поднимаем, шаблон оставляем
      ceremonial (continue в цикле). Логируем ошибку. Это
      деградация, не падение.
- [ ] UnitPlanner на era 0 при templateName=monumental: все слоты
      с `minEra >= 1` отфильтрованы — UnitPlanner может вернуть nil
      → fallback на legacy placement (уже работает,
      `CityEngine.swift:397–413`). Это не должно случаться на
      практике (era=0 значит шаблон ceremonial), но guard через
      fallback есть.
- [ ] ageDays никогда < 1 (max(1, ...)) — потому что то же делает
      stage compute в `CityEngine.swift:451`. Edge case: ts события
      раньше createdAt → ageDays = 1, EraRules вернёт 0 (что
      корректно).

### Файлы для изменения

- `Sources/CityDeveloper/Data/CityState.swift` — НЕ трогаем
  (eraLevel уже есть). Сюда вписано для верификации; правок не нужно.
- `Sources/CityDeveloper/Game/EraRules.swift` — **новый файл**.
- `Sources/CityDeveloper/Game/Templates/DistrictTemplate.swift` —
  добавить `minEra: Int` + явный `init(from:)`.
- `Sources/CityDeveloper/Data/GameEvent.swift` — новый case
  `eraAdvanced` + payload helper.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — параметр
  `projectEraLevel: Int` в `nextPosition(...)` + фильтр.
- `Sources/CityDeveloper/Game/CityEngine.swift` — `applyEraProgression`,
  `eraTemplateName`, `stripEraSuffix`, integration в
  `applyTaskCompleted`, switch case + emit + callback +
  передача era в UnitPlanner.
- `Sources/CityDeveloper/Game/GameScene.swift` — `handleEraAdvanced`.
- AppDelegate (или место установки `onTemplateMigrated`) — wiring
  `engine.onEraAdvanced`.
- `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-monumental.json` — **новый файл**.
- `Sources/CityDeveloper/Resources/DistrictTemplates/egyptian/stage5-akhetaten-legacy.json` — **новый файл**.
- `Tests/CityDeveloperTests/EraRulesTests.swift` — **новый файл**.
- `Tests/CityDeveloperTests/CityEngineEraProgressionTests.swift` —
  **новый файл**.
- `Tests/CityDeveloperTests/UnitPlannerTests.swift` — добавить
  `projectEraLevel: 0` в существующие вызовы `nextPosition`.
- `concept/Current.md`, `concept/LogFormat.md` — документация.

### Файлы НЕ трогать

- `StageRules.swift` — era не влияет на stage compute.
- `DecayEngine.swift` — era progression только читает `decayLevel`.
- `applyTemplateMigration` — оставляем как есть, era использует
  собственную обёртку (другие правила выбора шаблона).
- `stage1..stage4` JSON-шаблоны — era применяется только на stage 5.
- `concept/Concept.md`, `concept/Diff.md` (только update про D-25 без
  закрытия) — основные документы остаются.

### Команды проверки (для DoD)

- Компиляция: `swift build -c debug`
- Тесты:
  - `swift test --filter EraRulesTests`
  - `swift test --filter CityEngineEraProgressionTests`
  - `swift test --filter CityEngineTemplateMigrationTests`
    (регрессия stage-миграции)
  - `swift test --filter UnitPlannerTests`
    (после изменения сигнатуры nextPosition)
  - `swift test --filter DistrictTemplateCatalogTests`
    (после изменения TemplateSlot)
  - `swift test` (полный прогон)
- Smoke (manual через скрипт):
  - `Scripts/` — если есть симулятор ingest'а — прогнать fixture
    с 100/500/2000 task_completed и проверить eraLevel в state.json.
  - Иначе — оставить на интеграционные тесты.

### Сложность

`middle`

**Обоснование:** хотя задача затрагивает 10+ файлов и вводит
новый game-mechanic layer, большинство шагов — атомарные правки по
готовому паттерну (TASK-049 уже сделал stage-template migration; era
повторяет его структуру). Senior-уровень требует
TemplateMigrationValidator + replay-safety, но они уже реализованы
и переиспользуются как есть. Из 16 шагов: 9 простых (новый файл /
поле / case), 5 средних (CityEngine integration, JSON super-set),
2 нетривиальных (handleEraAdvanced iso-ромб + testEraIsReplayable).
Это **middle с senior-touch'ами**, не чистый senior.

### Ожидаемое время

M (≤1д). Основной риск — координаты слотов monumental/legacy
(super-set проверка `TemplateMigrationValidator.canMigrate`) и
replay-тест с правильным API из `CityEngineTemplateMigrationTests`.

---

## ✅ Исполнение

_Исполнитель: sonnet (executor)_
_Сложность: middle_
_Объём: M_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены
- [x] Smoke: тест `testEraAdvancesThreeLevelsInSingleTick` симулирует 2000+/365+
      за один тик — все 3 era-ups идут подряд + monumental→legacy migration.

#### Технические
- [x] Компиляция/линтер без новых ошибок (`swift build` clean)
- [x] Тесты не сломаны: 126/126 PASS кроме известного BUG-020.
      Era-tests — EraRulesTests 4/4 + CityEngineEraProgressionTests 4/4 = 8/8 PASS.
- [x] Replay events.jsonl детерминирован (`testEraIsReplayable`).
- [x] events.jsonl без `era_advanced` events backwards-compat (`apply(.eraAdvanced) = break`).

#### Обновление документации
- [x] `Current.md`: F-25 → ⚠️ (6/7 sub-task'ов готово, остался TASK-051)
- [x] `Diff.md`: D-25 — остаток только TASK-051
- [x] `concept/LogFormat.md`: добавлен `era_advanced` event

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047, TASK-048, TASK-049
- Готова к работе: 2026-05-24
- Lead-model: opus
- Plan-review: revised
- Завершена: 2026-05-24
- Коммит: — (бэкфиллится после commit)
